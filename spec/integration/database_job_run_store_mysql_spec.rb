# frozen_string_literal: true

require "spec_helper"
require "uri"
require "active_record"
require "mysql2"

# Real MySQL integration tests for the pool-based
# +Schked::Adapters::ActiveRecord+ — the mysql2 driver and, when the
# trilogy gem is available, the trilogy driver (Rails 7.1+/8 default for
# MySQL). Loaded only under the +mysql+ Appraisal gemfile.
describe Schked::Adapters::ActiveRecord do
  def mysql_url(adapter:)
    url = ENV.fetch("SCHKED_MYSQL_URL")
    return url if adapter == "mysql2"

    url.sub(/\Amysql2?:/, "#{adapter}:")
  end

  describe "via the mysql2 driver" do
    around { |ex| SchkedSpec::ARJobRunTable.with_table(mysql_url(adapter: "mysql2"), &ex) }

    let(:logger) { Logger.new(File::NULL) }
    subject(:store) { described_class.new(ActiveRecord::Base.connection_pool, logger: logger) }

    it_behaves_like "a job run store"

    it "decides claims by token read-back, not affected_rows (Rails sets CLIENT_FOUND_ROWS)" do
      window = Time.now.to_i
      expect(store.claim("job_a", window)).to be true
      expect(store.claim("job_a", window)).to be false

      rows = ActiveRecord::Base.connection.exec_query("SELECT claimer FROM schked_job_runs").to_a
      expect(rows.size).to eq 1
      expect(store.adapter_name).to eq "Mysql2"
    end

    it "lets exactly one claim win when many threads race through the shared pool" do
      window = Time.now.to_i
      results = 20.times.map { Thread.new { store.claim("racey", window) } }.map(&:value)

      expect(results.count(true)).to eq 1
      expect(results.count(false)).to eq 19

      count = ActiveRecord::Base.connection.exec_query("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
      expect(count.to_i).to eq 1
    end

    describe "#cleanup" do
      it "deletes rows whose window_start is older than the cutoff" do
        store.claim("old", Time.now.to_i - 3600)
        store.claim("new", Time.now.to_i)

        store.cleanup(Time.now.to_i - 60)

        names = ActiveRecord::Base.connection.exec_query("SELECT job_name FROM schked_job_runs").to_a.map { |r| r["job_name"] }
        expect(names).to contain_exactly("new")
      end
    end
  end

  trilogy_available =
    begin
      require "trilogy"
      true
    rescue LoadError
      false
    end

  if trilogy_available
    describe "via the trilogy driver" do
      around { |ex| SchkedSpec::ARJobRunTable.with_table(mysql_url(adapter: "trilogy"), &ex) }

      let(:logger) { Logger.new(File::NULL) }
      subject(:store) { described_class.new(ActiveRecord::Base.connection_pool, logger: logger) }

      it_behaves_like "a job run store"

      it "reports the Trilogy adapter name" do
        expect(store.adapter_name).to eq "Trilogy"
      end

      it "lets exactly one claim win when many threads race through the shared pool" do
        window = Time.now.to_i
        results = 20.times.map { Thread.new { store.claim("racey", window) } }.map(&:value)

        expect(results.count(true)).to eq 1
        expect(results.count(false)).to eq 19
      end
    end
  end
end
