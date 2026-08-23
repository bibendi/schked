# frozen_string_literal: true

require "spec_helper"
require "uri"
require "mysql2"

# End-to-end integration tests for the database-backed coordination store.
# These exercise actual SQL semantics — UNIQUE constraint enforcement,
# INSERT ... ON DUPLICATE KEY UPDATE, concurrent inserts, and the cleanup
# sweep — against a live MySQL instance. Loaded only in the +mysql+
# Appraisal gemfile (see the +default_args+ in dip.yml).
#
# Each example creates the +schked_job_runs+ table with the production DDL
# (printed by `schked generate-migration`) and drops it on teardown.
describe Schked::DatabaseJobRunStore do
  def mysql_connection
    return @mysql_connection if defined?(@mysql_connection)

    uri = URI.parse(ENV.fetch("SCHKED_MYSQL_URL"))
    @mysql_connection = Mysql2::Client.new(
      host: uri.host,
      port: uri.port,
      username: uri.user,
      password: uri.password,
      database: uri.path.sub(%r{\A/}, "")
    )
  end

  def with_mysql_table
    mysql_connection.query("DROP TABLE IF EXISTS schked_job_runs")
    mysql_connection.query(<<~SQL)
      CREATE TABLE schked_job_runs (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        job_name VARCHAR(255) NOT NULL,
        window_start BIGINT NOT NULL,
        run_at DOUBLE NOT NULL,
        UNIQUE KEY schked_job_runs_unique (job_name, window_start)
      )
    SQL
    yield
  ensure
    begin
      mysql_connection.query("DROP TABLE IF EXISTS schked_job_runs")
    rescue Mysql2::Error
      # connection may already be closed
    end
  end

  describe "MySQL integration" do
    let(:logger) { Logger.new(File::NULL) }
    let(:adapter) { Schked::DatabaseAdapters::Mysql2.new(mysql_connection) }
    let(:store) { described_class.new(adapter: adapter, flavor: :mysql, logger: logger) }

    def claim_in_thread(name:, window:)
      Thread.new do
        uri = URI.parse(ENV.fetch("SCHKED_MYSQL_URL"))
        client = Mysql2::Client.new(
          host: uri.host,
          port: uri.port,
          username: uri.user,
          password: uri.password,
          database: uri.path.sub(%r{\A/}, "")
        )
        Schked::DatabaseJobRunStore.new(
          adapter: Schked::DatabaseAdapters::Mysql2.new(client),
          flavor: :mysql,
          logger: Logger.new(File::NULL)
        ).claim(name, window)
      ensure
        client&.close
      end
    end

    around { |ex| with_mysql_table(&ex) }

    it_behaves_like "a job run store"

    it "persists rows that win the claim" do
      expect(store.claim("job_a", Time.now.to_i)).to be true
      rows = mysql_connection.query("SELECT job_name FROM schked_job_runs").to_a
      expect(rows.map { |r| r["job_name"] }).to eq ["job_a"]
    end

    it "does not insert rows that lose the claim (UNIQUE constraint enforced by ON DUPLICATE KEY UPDATE)" do
      window = Time.now.to_i
      store.claim("job_a", window)
      expect(store.claim("job_a", window)).to be false

      count = mysql_connection.query("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
      expect(count.to_i).to eq 1
    end

    it "lets exactly one claim win when many concurrent callers race for the same (job, window)" do
      window = Time.now.to_i
      threads = 20.times.map { claim_in_thread(name: "racey", window: window) }
      results = threads.map(&:value)
      expect(results.count(true)).to eq 1
      expect(results.count(false)).to eq 19

      count = mysql_connection.query("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
      expect(count.to_i).to eq 1
    end

    describe "#cleanup" do
      it "deletes rows whose window_start is older than the cutoff" do
        store.claim("old", Time.now.to_i - 3600)
        store.claim("new", Time.now.to_i)

        store.cleanup(Time.now.to_i - 60)

        job_names = mysql_connection.query("SELECT job_name FROM schked_job_runs").to_a.map { |r| r["job_name"] }
        expect(job_names).to contain_exactly("new")
      end
    end
  end

  describe "auto flavor detection" do
    let(:logger) { Logger.new(File::NULL) }

    it "detects MySQL via the mysql2 adapter" do
      adapter = Schked::DatabaseAdapters::Mysql2.new(mysql_connection)
      store = described_class.new(adapter: adapter, logger: logger)
      expect(store.flavor).to eq :mysql
    end
  end
end
