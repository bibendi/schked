# frozen_string_literal: true

require "spec_helper"

# Unit tests for the per-backend coordination store adapters. These use
# mocks/spies because the agnostic gemfile does not pull in sequel or
# activerecord; real-database coverage lives in
# spec/integration/database_job_run_store_*_spec.rb (run via
# `dip rspec postgres|mysql|sequel|rails`).
describe Schked::Adapters do
  let(:logger) { Logger.new(File::NULL) }

  describe Schked::Adapters::Sequel do
    describe "on a Postgres database" do
      let(:database) { double("Sequel::Database", adapter_scheme: "postgres", database_type: :postgres) }
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

      it "uses insert_conflict targeting (job_name, window_start) and stores the claimer token" do
        expect(dataset).to receive(:insert_conflict)
          .with(target: %i[job_name window_start])
          .and_return(insert_ds)
        allow(insert_ds).to receive(:insert) do |hash|
          expect(hash).to match(job_name: "job_a", window_start: Integer, run_at: Float, claimer: String)
          1
        end

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

    describe "on a MySQL database" do
      let(:database) { double("Sequel::Database", adapter_scheme: "mysql", database_type: :mysql) }
      let(:dataset) { double("Sequel::Dataset") }
      let(:ignore_ds) { double("Sequel::Dataset") }
      let(:conn) { double("Mysql2::Client") }
      subject(:store) { described_class.new(database, logger: logger) }

      before do
        @_mysql_rows = {}
        allow(database).to receive(:[]).with(:schked_job_runs).and_return(dataset)
        allow(dataset).to receive(:insert_ignore).and_return(ignore_ds)
        allow(ignore_ds).to receive(:insert_sql) do |hash|
          key = [hash[:job_name], hash[:window_start]]
          @_mysql_rows[key] ||= hash[:claimer] # first writer wins
          "INSERT IGNORE INTO schked_job_runs (job_name, window_start, run_at, claimer) VALUES (...)"
        end
        allow(database).to receive(:synchronize).and_yield(conn)
        allow(conn).to receive(:query)
        allow(dataset).to receive(:where) do |conditions|
          key = [conditions[:job_name], conditions[:window_start]]
          where_ds = double("where dataset")
          allow(where_ds).to receive(:select).with(:claimer) do
            select_ds = double("select dataset")
            allow(select_ds).to receive(:first) { {claimer: @_mysql_rows[key]} }
            select_ds
          end
          where_ds
        end
      end

      it_behaves_like "a job run store"

      it "reads back the claimer token to decide the winner" do
        expect(store.claim("job_a", 1234)).to be true
        expect(store.claim("job_a", 1234)).to be false
      end

      it "runs the INSERT inside #synchronize (pool checkout)" do
        expect(database).to receive(:synchronize).and_yield(conn)
        expect(conn).to receive(:query).with(/INSERT IGNORE INTO schked_job_runs/)

        store.claim("job_a", 1234)
      end
    end

    describe "construction" do
      it "refuses unsupported databases loudly" do
        database = double("Sequel::Database", database_type: :sqlite)
        expect {
          described_class.new(database, logger: logger)
        }.to raise_error(ArgumentError, /supports Postgres and MySQL.*sqlite/m)
      end
    end
  end

  describe Schked::Adapters::ActiveRecord do
    let(:connection) { double("AR::Connection") }
    let(:pool) do
      double("AR::ConnectionPool").tap do |p|
        allow(p).to receive(:with_connection) { |&block| block.call(connection) }
      end
    end
    subject(:store) { described_class.new(pool, logger: logger) }

    before do
      allow(connection).to receive(:quote) { |v| v.is_a?(String) ? "'#{v}'" : v.to_s }
    end

    describe "connection validation" do
      %w[PostgreSQL Mysql2 Trilogy].each do |name|
        it "accepts #{name} connections" do
          allow(connection).to receive(:adapter_name).and_return(name)
          expect { store }.not_to raise_error
        end
      end

      it "refuses unsupported connections loudly at construction" do
        # A silent fallback would mean every later firing fails per-job;
        # failing fast forces operators to pick a supported backend.
        allow(connection).to receive(:adapter_name).and_return("SQLite")
        expect {
          store
        }.to raise_error(ArgumentError, /supports PostgreSQL, Mysql2, Trilogy.*SQLite/m)
      end

      it "handles connections without adapter_name" do
        expect {
          store
        }.to raise_error(ArgumentError, /got: ""/)
      end
    end

    describe "on a PostgreSQL connection" do
      before do
        allow(connection).to receive(:adapter_name).and_return("PostgreSQL")
      end

      it "decides atomically via INSERT ... ON CONFLICT DO NOTHING RETURNING" do
        result = double("AR::Result", length: 1)
        expect(connection).to receive(:exec_query) do |sql, name|
          expect(sql).to include("ON CONFLICT (job_name, window_start) DO NOTHING RETURNING id")
          expect(sql).to include("claimer")
          expect(name).to eq "Schked CLAIM"
          result
        end

        expect(store.claim("job_a", 1234)).to be true
      end

      it "returns false when RETURNING yields no row (conflict)" do
        allow(connection).to receive(:exec_query).and_return(double("AR::Result", length: 0))
        expect(store.claim("job_a", 1234)).to be false
      end

      it "checks the connection out of the pool for the claim" do
        expect(pool).to receive(:with_connection).and_yield(connection)
        allow(connection).to receive(:exec_query).and_return(double("AR::Result", length: 1))

        store.claim("job_a", 1234)
      end
    end

    describe "on a Mysql2 connection" do
      before do
        allow(connection).to receive(:adapter_name).and_return("Mysql2")
      end

      it "writes a unique token and reads it back (CLIENT_FOUND_ROWS-safe)" do
        tokens = []
        allow(connection).to receive(:execute) do |sql|
          expect(sql).to match(/\AINSERT IGNORE INTO schked_job_runs/)
          tokens << sql[/VALUES \('job_a', 1234, [0-9.]+, '([0-9a-f-]+)'\)/, 1]
        end
        allow(connection).to receive(:exec_query) do |sql, _name|
          expect(sql).to include("SELECT claimer FROM schked_job_runs")
          double("AR::Result", first: {"claimer" => tokens.first})
        end

        expect(store.claim("job_a", 1234)).to be true
      end

      it "loses the claim when another token is stored" do
        allow(connection).to receive(:execute)
        allow(connection).to receive(:exec_query)
          .and_return(double("AR::Result", first: {"claimer" => "someone-else"}))

        expect(store.claim("job_a", 1234)).to be false
      end
    end

    describe "#cleanup" do
      before do
        allow(connection).to receive(:adapter_name).and_return("PostgreSQL")
      end

      it "issues DELETE with a quoted cutoff inside a pool checkout" do
        expect(pool).to receive(:with_connection).and_yield(connection)
        expect(connection).to receive(:execute).with("DELETE FROM schked_job_runs WHERE window_start < 1234")

        store.cleanup(1234)
      end
    end

    it "reports the cached adapter_name" do
      allow(connection).to receive(:adapter_name).and_return("Trilogy")
      expect(store.adapter_name).to eq "Trilogy"
    end
  end
end
