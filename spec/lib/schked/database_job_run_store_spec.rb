# frozen_string_literal: true

require "spec_helper"

# Unit tests for the per-backend coordination store adapters. These use
# mocks/spies because the agnostic gemfile does not pull in pg, mysql2,
# sequel, or activerecord; real-database coverage lives in
# spec/integration/database_job_run_store_*_spec.rb (run via
# `dip rspec postgres|mysql|sequel|rails`).
describe Schked::Adapters do
  let(:logger) { Logger.new(File::NULL) }

  describe Schked::Adapters::Pg do
    let(:connection) { double("PG::Connection") }
    subject(:store) { described_class.new(connection, logger: logger) }

    before do
      # Shared contract: first claim wins, second loses on the same window.
      allow(connection).to receive(:exec_params) do |_sql, params|
        @_pg_inserts ||= {}
        key = [params[0], params[1]]
        if @_pg_inserts.key?(key)
          double("PG::Result", cmd_tuples: 0)
        else
          @_pg_inserts[key] = true
          double("PG::Result", cmd_tuples: 1)
        end
      end
      allow(connection).to receive(:exec_params).with(/DELETE/, anything).and_return(nil)
    end

    it_behaves_like "a job run store"

    describe "#claim" do
      it "issues INSERT ... ON CONFLICT DO NOTHING RETURNING id with $N binds" do
        result = double("PG::Result", cmd_tuples: 1)
        expect(connection).to receive(:exec_params) do |sql, params|
          expect(sql).to eq(
            "INSERT INTO schked_job_runs (job_name, window_start, run_at) " \
            "VALUES ($1, $2, $3) ON CONFLICT (job_name, window_start) DO NOTHING RETURNING id"
          )
          expect(params[0]).to eq "job_a"
          expect(params[1]).to be_a(Integer)
          expect(params[2]).to be_a(Float)
          result
        end

        expect(store.claim("job_a", Time.now.to_i)).to be true
      end

      it "returns false when no row is inserted (conflict)" do
        allow(connection).to receive(:exec_params).and_return(double("PG::Result", cmd_tuples: 0))
        expect(store.claim("job_a", Time.now.to_i)).to be false
      end
    end

    describe "#cleanup" do
      it "issues DELETE FROM schked_job_runs WHERE window_start < $1" do
        expect(connection).to receive(:exec_params) do |sql, params|
          expect(sql).to eq("DELETE FROM schked_job_runs WHERE window_start < $1")
          expect(params).to eq [1234]
          nil
        end

        store.cleanup(1234)
      end
    end

    it "reports adapter_name as PostgreSQL" do
      expect(store.adapter_name).to eq "PostgreSQL"
    end
  end

  describe Schked::Adapters::Mysql2 do
    let(:client) { double("Mysql2::Client") }
    let(:stmt) { double("Mysql2::Statement") }
    subject(:store) { described_class.new(client, logger: logger) }

    before do
      @_mysql_inserts = {}
      allow(client).to receive(:prepare).and_return(stmt)
      allow(stmt).to receive(:execute) do |*params|
        @_mysql_inserts[[params[0], params[1]]] ||= true
      end
      allow(stmt).to receive(:affected_rows) do |*|
        count = @_mysql_inserts.size
        # 1 on first call, 0 on subsequent calls to the same key.
        # The shared example calls claim twice with the same args; we
        # detect by counting entries since each call appends.
        if count == @_mysql_last_size
          0
        else
          @_mysql_last_size = count
          1
        end
      end
    end

    it_behaves_like "a job run store"

    describe "#claim" do
      it "issues INSERT ... ON DUPLICATE KEY UPDATE id = id via prepared statement" do
        allow(stmt).to receive(:affected_rows).and_return(1)
        expect(client).to receive(:prepare) do |sql|
          expect(sql).to include("ON DUPLICATE KEY UPDATE id = id")
          stmt
        end

        expect(store.claim("job_a", Time.now.to_i)).to be true
      end

      it "reads affected_rows from the statement (NOT the client)" do
        expect(stmt).to receive(:affected_rows).and_return(0)
        expect(client).not_to receive(:affected_rows)

        expect(store.claim("job_a", Time.now.to_i)).to be false
      end
    end

    it "reports adapter_name as Mysql2" do
      expect(store.adapter_name).to eq "Mysql2"
    end
  end

  describe Schked::Adapters::Sequel do
    let(:database) { double("Sequel::Database", adapter_scheme: "postgres") }
    let(:dataset) { double("Sequel::Dataset") }
    let(:insert_ds) { double("Sequel::Dataset") }
    subject(:store) { described_class.new(database, logger: logger) }

    before do
      @_sequel_inserts = {}
      allow(database).to receive(:[]).with(:schked_job_runs).and_return(dataset)
      allow(dataset).to receive(:insert_conflict).and_return(insert_ds)
      allow(insert_ds).to receive(:insert) do |hash|
        key = [hash[:job_name], hash[:window_start]]
        if @_sequel_inserts.key?(key)
          nil # conflict
        else
          @_sequel_inserts[key] = true
          1 # PK
        end
      end
    end

    it_behaves_like "a job run store"

    it "uses insert_conflict targeting (job_name, window_start)" do
      expect(dataset).to receive(:insert_conflict)
        .with(target: %i[job_name window_start])
        .and_return(insert_ds)
      allow(insert_ds).to receive(:insert).and_return(1)

      store.claim("job_a", Time.now.to_i)
    end

    it "returns false when Sequel returns nil for the insert (conflict)" do
      allow(insert_ds).to receive(:insert).and_return(nil)
      expect(store.claim("job_a", Time.now.to_i)).to be false
    end

    it "delegates #cleanup to the dataset's where + delete" do
      expect(dataset).to receive(:where).and_return(double(delete: 1))
      store.cleanup(1234)
    end

    it "reports adapter_name from adapter_scheme" do
      expect(store.adapter_name).to eq "postgres"
    end
  end

  describe Schked::Adapters::ActiveRecord do
    # ActiveRecord-dependent internals are exercised end-to-end in the rails
    # integration suite. The agnostic/redlock gemfiles do not pull in AR, so
    # these examples only exercise paths that never reference AR constants.
    describe "connection validation" do
      it "accepts PostgreSQL connections" do
        conn = double("AR::Connection", adapter_name: "PostgreSQL")
        expect { described_class.new(conn, logger: logger) }.not_to raise_error
      end

      it "accepts Mysql2 connections" do
        conn = double("AR::Connection", adapter_name: "Mysql2")
        expect { described_class.new(conn, logger: logger) }.not_to raise_error
      end

      it "refuses unsupported connections loudly at construction" do
        # A silent fallback would mean every later firing fails per-job;
        # failing fast forces operators to pick a supported backend.
        conn = double("AR::Connection", adapter_name: "SQLite")
        expect {
          described_class.new(conn, logger: logger)
        }.to raise_error(ArgumentError, /supports PostgreSQL and Mysql2.*SQLite/m)
      end

      it "handles connections without adapter_name" do
        conn = double("AR::Connection")
        expect {
          described_class.new(conn, logger: logger)
        }.to raise_error(ArgumentError, /got: ""/)
      end
    end

    describe "#claim on the Mysql2 flavor" do
      let(:raw_client) { double("Mysql2::Client") }
      let(:stmt) { double("Mysql2::Statement") }
      let(:conn) { double("AR::Connection", adapter_name: "Mysql2", raw_connection: raw_client) }

      subject(:store) { described_class.new(conn, logger: logger) }

      it "uses INSERT IGNORE through the underlying client" do
        allow(raw_client).to receive(:prepare) do |sql|
          expect(sql).to include("INSERT IGNORE INTO schked_job_runs")
          stmt
        end
        expect(stmt).to receive(:execute).with("job_a", anything, anything)
        allow(stmt).to receive(:close)

        # mysql2 sets CLIENT_FOUND_ROWS off by default, so affected_rows == 1
        # really means "row inserted" (vs matched).
        allow(stmt).to receive(:affected_rows).and_return(1)
        expect(store.claim("job_a", 1234)).to be true
      end

      it "returns false when the insert was IGNOREd (affected_rows == 0)" do
        allow(raw_client).to receive(:prepare).and_return(stmt)
        allow(stmt).to receive(:execute)
        allow(stmt).to receive(:close)
        allow(stmt).to receive(:affected_rows).and_return(0)
        expect(store.claim("job_a", 1234)).to be false
      end

      it "closes the prepared statement" do
        allow(raw_client).to receive(:prepare).and_return(stmt)
        allow(stmt).to receive(:execute)
        allow(stmt).to receive(:affected_rows).and_return(1)
        expect(stmt).to receive(:close)

        store.claim("job_a", 1234)
      end

      it "does not call exec_query (which would send Postgres-only SQL)" do
        allow(raw_client).to receive(:prepare).and_return(stmt)
        allow(stmt).to receive(:execute)
        allow(stmt).to receive(:affected_rows).and_return(1)
        allow(stmt).to receive(:close)
        expect(conn).not_to receive(:exec_query)

        store.claim("job_a", 1234)
      end
    end

    describe "#adapter_name" do
      it "reports adapter_name from the AR connection" do
        conn = double("AR::Connection", adapter_name: "PostgreSQL")
        store = described_class.new(conn, logger: logger)
        expect(store.adapter_name).to eq "PostgreSQL"
      end
    end
  end
end
