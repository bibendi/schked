# frozen_string_literal: true

require "spec_helper"
require "pg"

# End-to-end integration tests for the database-backed coordination store.
# These exercise actual SQL semantics — UNIQUE constraint enforcement,
# INSERT ... ON CONFLICT DO NOTHING, concurrent inserts, and the cleanup
# sweep — against a live Postgres instance. Loaded only in the +postgres+
# Appraisal gemfile (see the +default_args+ in dip.yml).
#
# Each example creates the +schked_job_runs+ table with the production DDL
# (printed by `schked generate-migration`) and drops it on teardown.
describe Schked::DatabaseJobRunStore do
  def postgres_connection
    return @postgres_connection if defined?(@postgres_connection)

    @postgres_connection = PG.connect(ENV.fetch("SCHKED_POSTGRES_URL"))
  end

  def with_postgres_table
    postgres_connection.exec("DROP TABLE IF EXISTS schked_job_runs")
    postgres_connection.exec(<<~SQL)
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
    postgres_connection.exec("DROP TABLE IF EXISTS schked_job_runs") unless postgres_connection.finished?
  end

  describe "Postgres integration" do
    let(:logger) { Logger.new(File::NULL) }
    let(:adapter) { Schked::DatabaseAdapters::Pg.new(postgres_connection) }
    let(:store) { described_class.new(adapter: adapter, flavor: :postgres, logger: logger) }

    # Each concurrent caller opens its own connection — PG::Connection is
    # not safe to share across threads.
    def claim_in_thread(name:, window:)
      Thread.new do
        conn = PG.connect(ENV.fetch("SCHKED_POSTGRES_URL"))
        Schked::DatabaseJobRunStore.new(
          adapter: Schked::DatabaseAdapters::Pg.new(conn),
          flavor: :postgres,
          logger: Logger.new(File::NULL)
        ).claim(name, window)
      ensure
        conn&.close
      end
    end

    around { |ex| with_postgres_table(&ex) }

    it_behaves_like "a job run store"

    it "persists rows that win the claim" do
      expect(store.claim("job_a", Time.now.to_i)).to be true
      rows = postgres_connection.exec("SELECT job_name FROM schked_job_runs").to_a
      expect(rows.map { |r| r["job_name"] }).to eq ["job_a"]
    end

    it "does not insert rows that lose the claim (UNIQUE constraint enforced by ON CONFLICT DO NOTHING)" do
      window = Time.now.to_i
      store.claim("job_a", window)
      expect(store.claim("job_a", window)).to be false

      count = postgres_connection.exec("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
      expect(count.to_i).to eq 1
    end

    it "allows two different jobs to claim the same window concurrently" do
      window = Time.now.to_i
      threads = 10.times.map { |i| claim_in_thread(name: "job_#{i}", window: window) }
      expect(threads.map(&:value)).to all(be true)
      count = postgres_connection.exec("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
      expect(count.to_i).to eq 10
    end

    it "lets exactly one claim win when many concurrent callers race for the same (job, window)" do
      window = Time.now.to_i
      threads = 20.times.map { claim_in_thread(name: "racey", window: window) }
      results = threads.map(&:value)
      expect(results.count(true)).to eq 1
      expect(results.count(false)).to eq 19

      count = postgres_connection.exec("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
      expect(count.to_i).to eq 1
    end

    describe "#cleanup" do
      it "deletes rows whose window_start is older than the cutoff" do
        store.claim("old", Time.now.to_i - 3600)
        store.claim("new", Time.now.to_i)

        store.cleanup(Time.now.to_i - 60)

        job_names = postgres_connection.exec("SELECT job_name FROM schked_job_runs").map { |r| r["job_name"] }
        expect(job_names).to contain_exactly("new")
      end
    end
  end

  describe "auto flavor detection" do
    let(:logger) { Logger.new(File::NULL) }

    it "detects Postgres via the pg adapter" do
      adapter = Schked::DatabaseAdapters::Pg.new(postgres_connection)
      store = described_class.new(adapter: adapter, logger: logger)
      expect(store.flavor).to eq :postgres
    end
  end
end
