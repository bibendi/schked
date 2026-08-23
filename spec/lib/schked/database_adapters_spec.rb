# frozen_string_literal: true

require "spec_helper"

describe Schked::DatabaseAdapters do
  describe ".wrap" do
    it "returns an existing Base wrapper unchanged" do
      adapter = Schked::DatabaseAdapters::Pg.new(double("conn"))
      expect(described_class.wrap(adapter)).to be adapter
    end

    it "wraps an unknown object via Passthrough when it responds to execute" do
      conn = double("conn", execute: [])
      expect(described_class.wrap(conn)).to be_a(Schked::DatabaseAdapters::Passthrough)
    end

    it "raises NotFoundError for an unsupported connection" do
      expect { described_class.wrap(Object.new) }.to raise_error(Schked::DatabaseConnection::NotFoundError, /could not detect/)
    end
  end

  describe Schked::DatabaseAdapters::Pg do
    it "rewrites ? placeholders to pg's $1, $2, ... positional binds" do
      conn = double("PG::Connection")
      adapter = described_class.new(conn)

      expect(conn).to receive(:exec_params) do |sql, params|
        expect(sql).to eq("INSERT INTO schked_job_runs (job_name, window_start) VALUES ($1, $2) ON CONFLICT DO NOTHING")
        expect(params).to eq(["job_a", 1234])
        []
      end

      adapter.execute("INSERT INTO schked_job_runs (job_name, window_start) VALUES (?, ?) ON CONFLICT DO NOTHING", ["job_a", 1234])
    end

    it "reports its adapter_name as PostgreSQL" do
      adapter = described_class.new(double("PG::Connection"))
      expect(adapter.adapter_name).to eq "PostgreSQL"
    end
  end

  describe Schked::DatabaseAdapters::Mysql2 do
    it "uses the prepared statement's affected_rows (not the connection's)" do
      conn = double("Mysql2::Client")
      stmt = double("Mysql2::Statement", affected_rows: 1)
      allow(conn).to receive(:prepare).with(anything).and_return(stmt)
      allow(stmt).to receive(:execute).with("job_a", 1234)

      adapter = described_class.new(conn)
      result = adapter.execute("INSERT INTO foo (a, b) VALUES (?, ?)", ["job_a", 1234])

      expect(result).to eq 1
    end

    it "reports its adapter_name as Mysql2" do
      adapter = described_class.new(double("Mysql2::Client"))
      expect(adapter.adapter_name).to eq "Mysql2"
    end
  end

  describe Schked::DatabaseAdapters::Sequel do
    let(:db) { double("Sequel::Database", adapter_scheme: "postgres") }
    let(:ds) { double("Sequel::Dataset") }
    let(:insert_ds) { double("Sequel::Dataset") }

    before do
      allow(db).to receive(:[]).with(:schked_job_runs).and_return(ds)
      allow(ds).to receive(:insert_conflict).and_return(insert_ds)
    end

    it "delegates DELETE to the dataset's delete method" do
      expect(ds).to receive(:where).and_return(double(delete: 1))
      adapter = described_class.new(db)
      adapter.execute("DELETE FROM schked_job_runs WHERE window_start < ?", [100])
    end

    it "uses insert_conflict for Postgres" do
      expect(insert_ds).to receive(:insert).with(job_name: "job_a", window_start: 1234, run_at: 1.5).and_return(1)
      adapter = described_class.new(db)
      expect(adapter.execute(
        "INSERT INTO schked_job_runs (job_name, window_start, run_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING RETURNING id",
        ["job_a", 1234, 1.5]
      )).to eq 1
    end

    it "returns 0 on Sequel conflict (insert returns nil)" do
      expect(insert_ds).to receive(:insert).with(job_name: "job_a", window_start: 1234, run_at: 1.5).and_return(nil)
      adapter = described_class.new(db)
      expect(adapter.execute(
        "INSERT INTO schked_job_runs (job_name, window_start, run_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING RETURNING id",
        ["job_a", 1234, 1.5]
      )).to eq 0
    end

    it "raises on unknown SQL" do
      adapter = described_class.new(db)
      expect { adapter.execute("SELECT 1", []) }.to raise_error(ArgumentError, /INSERT\/DELETE/)
    end
  end
end
