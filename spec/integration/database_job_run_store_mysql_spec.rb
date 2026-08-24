# frozen_string_literal: true

require "spec_helper"
require "uri"
require "mysql2"

# Real MySQL integration tests for the +Schked::Adapters::Mysql2+ adapter.
# Loaded only under the +mysql+ Appraisal gemfile.
describe Schked::Adapters::Mysql2 do
  def mysql_client
    @mysql_client ||= begin
      uri = URI.parse(ENV.fetch("SCHKED_MYSQL_URL"))
      Mysql2::Client.new(
        host: uri.host,
        port: uri.port,
        username: uri.user,
        password: uri.password,
        database: uri.path.sub(%r{\A/}, "")
      )
    end
  end

  def with_mysql_table
    mysql_client.query("DROP TABLE IF EXISTS schked_job_runs")
    mysql_client.query(<<~SQL)
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
      mysql_client.query("DROP TABLE IF EXISTS schked_job_runs")
    rescue Mysql2::Error
      # connection may already be closed
    end
  end

  let(:logger) { Logger.new(File::NULL) }
  subject(:store) { described_class.new(mysql_client, logger: logger) }

  around { |ex| with_mysql_table(&ex) }

  def claim_in_thread(name:, window:)
    result = nil
    Thread.new do
      uri = URI.parse(ENV.fetch("SCHKED_MYSQL_URL"))
      client = Mysql2::Client.new(
        host: uri.host, port: uri.port,
        username: uri.user, password: uri.password,
        database: uri.path.sub(%r{\A/}, "")
      )
      result = described_class.new(client, logger: Logger.new(File::NULL)).claim(name, window)
    ensure
      client&.close
    end.join
    result
  end

  it_behaves_like "a job run store"

  it "persists rows that win the claim" do
    expect(store.claim("job_a", Time.now.to_i)).to be true
    rows = mysql_client.query("SELECT job_name FROM schked_job_runs").to_a
    expect(rows.map { |r| r["job_name"] }).to eq ["job_a"]
    expect(store.adapter_name).to eq "Mysql2"
  end

  it "does not insert rows that lose the claim (UNIQUE constraint enforced by ON DUPLICATE KEY UPDATE)" do
    window = Time.now.to_i
    store.claim("job_a", window)
    expect(store.claim("job_a", window)).to be false

    count = mysql_client.query("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
    expect(count.to_i).to eq 1
  end

  it "lets exactly one claim win when many concurrent callers race for the same (job, window)" do
    window = Time.now.to_i
    results = 20.times.map { claim_in_thread(name: "racey", window: window) }
    expect(results.count(true)).to eq 1
    expect(results.count(false)).to eq 19

    count = mysql_client.query("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
    expect(count.to_i).to eq 1
  end

  describe "#cleanup" do
    it "deletes rows whose window_start is older than the cutoff" do
      store.claim("old", Time.now.to_i - 3600)
      store.claim("new", Time.now.to_i)

      store.cleanup(Time.now.to_i - 60)

      job_names = mysql_client.query("SELECT job_name FROM schked_job_runs").to_a.map { |r| r["job_name"] }
      expect(job_names).to contain_exactly("new")
    end
  end
end
