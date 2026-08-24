# frozen_string_literal: true

require "spec_helper"
require "pg"

# Real Postgres integration tests for the +Schked::Adapters::Pg+ adapter.
# Loaded only under the +postgres+ Appraisal gemfile.
describe Schked::Adapters::Pg do
  def pg_connection
    @pg_connection ||= PG.connect(ENV.fetch("SCHKED_POSTGRES_URL"))
  end

  def with_postgres_table
    pg_connection.exec("DROP TABLE IF EXISTS schked_job_runs")
    pg_connection.exec(<<~SQL)
      CREATE TABLE schked_job_runs (
        id BIGSERIAL PRIMARY KEY,
        job_name TEXT NOT NULL,
        window_start BIGINT NOT NULL,
        run_at DOUBLE PRECISION NOT NULL,
        CONSTRAINT schked_job_runs_unique UNIQUE (job_name, window_start)
      )
    SQL
    yield
  ensure
    pg_connection.exec("DROP TABLE IF EXISTS schked_job_runs") unless pg_connection.finished?
  end

  let(:logger) { Logger.new(File::NULL) }
  subject(:store) { described_class.new(pg_connection, logger: logger) }

  around { |ex| with_postgres_table(&ex) }

  # Each concurrent caller opens its own connection — +PG::Connection+ is
  # not safe to share across threads.
  def claim_in_thread(name:, window:)
    result = nil
    Thread.new do
      conn = PG.connect(ENV.fetch("SCHKED_POSTGRES_URL"))
      result = described_class.new(conn, logger: Logger.new(File::NULL)).claim(name, window)
    ensure
      conn&.close
    end.join
    result
  end

  it_behaves_like "a job run store"

  it "persists rows that win the claim" do
    expect(store.claim("job_a", Time.now.to_i)).to be true
    rows = pg_connection.exec("SELECT job_name FROM schked_job_runs").to_a
    expect(rows.map { |r| r["job_name"] }).to eq ["job_a"]
    expect(store.adapter_name).to eq "PostgreSQL"
  end

  it "does not insert rows that lose the claim (UNIQUE constraint enforced by ON CONFLICT DO NOTHING)" do
    window = Time.now.to_i
    store.claim("job_a", window)
    expect(store.claim("job_a", window)).to be false

    count = pg_connection.exec("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
    expect(count.to_i).to eq 1
  end

  it "lets exactly one claim win when many concurrent callers race for the same (job, window)" do
    window = Time.now.to_i
    results = 20.times.map { claim_in_thread(name: "racey", window: window) }
    expect(results.count(true)).to eq 1
    expect(results.count(false)).to eq 19

    count = pg_connection.exec("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
    expect(count.to_i).to eq 1
  end

  describe "#cleanup" do
    it "deletes rows whose window_start is older than the cutoff" do
      store.claim("old", Time.now.to_i - 3600)
      store.claim("new", Time.now.to_i)

      store.cleanup(Time.now.to_i - 60)

      job_names = pg_connection.exec("SELECT job_name FROM schked_job_runs").map { |r| r["job_name"] }
      expect(job_names).to contain_exactly("new")
    end
  end
end
