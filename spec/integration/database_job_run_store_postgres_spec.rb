# frozen_string_literal: true

require "spec_helper"
require "active_record"
require "pg"

# Real Postgres integration tests for the pool-based
# +Schked::Adapters::ActiveRecord+. Loaded only under the +postgres+
# Appraisal gemfile.
describe Schked::Adapters::ActiveRecord do
  around { |ex| SchkedSpec::ARJobRunTable.with_table(ENV.fetch("SCHKED_POSTGRES_URL"), &ex) }

  let(:logger) { Logger.new(File::NULL) }
  subject(:store) { described_class.new(ActiveRecord::Base.connection_pool, logger: logger) }

  it_behaves_like "a job run store"

  it "persists rows that win the claim" do
    expect(store.claim("job_a", Time.now.to_i)).to be true
    rows = ActiveRecord::Base.connection.exec_query("SELECT job_name, claimer FROM schked_job_runs").to_a
    expect(rows.map { |r| r["job_name"] }).to eq ["job_a"]
    expect(rows.first["claimer"]).to be_a(String)
    expect(store.adapter_name).to eq "PostgreSQL"
  end

  it "does not insert rows that lose the claim (UNIQUE constraint enforced by ON CONFLICT DO NOTHING)" do
    window = Time.now.to_i
    store.claim("job_a", window)
    expect(store.claim("job_a", window)).to be false

    count = ActiveRecord::Base.connection.exec_query("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
    expect(count.to_i).to eq 1
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
