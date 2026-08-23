# frozen_string_literal: true

require "spec_helper"

# Unit tests for the database-backed coordination store. These use the
# +FakeDatabaseAdapter+ (in spec/support) to exercise claim/cleanup logic
# without an actual database. End-to-end behavior against a live Postgres or
# MySQL is covered by spec/lib/schked/database_job_run_store_integration_spec.rb,
# which runs only in the +postgres+ and +mysql+ Appraisal gemfiles.
describe Schked::DatabaseJobRunStore do
  let(:logger) { Logger.new(File::NULL) }

  describe "Postgres semantics" do
    let(:adapter) { FakeDatabaseAdapter.new(adapter_name: "PostgreSQL") }
    let(:store) { described_class.new(adapter: adapter, flavor: :postgres, logger: logger) }

    it_behaves_like "a job run store"

    describe "#claim" do
      it "issues INSERT ... ON CONFLICT DO NOTHING RETURNING id" do
        store.claim("job_a", Time.now.to_i)
        insert = adapter.queries.find { |q| q[:sql].include?("INSERT INTO schked_job_runs") }
        expect(insert[:sql]).to include("ON CONFLICT")
        expect(insert[:sql]).to include("RETURNING id")
      end

      it "returns true on the first insert" do
        expect(store.claim("job_a", Time.now.to_i)).to be true
      end

      it "returns false when the same (job_name, window_start) is re-claimed" do
        window = Time.now.to_i
        allow(adapter).to receive(:execute).and_return([{id: 1}], [])

        expect(store.claim("job_a", window)).to be true
        expect(store.claim("job_a", window)).to be false
      end

      it "stores window_start as an integer epoch" do
        window = Time.now.to_i
        store.claim("job_a", window)
        insert = adapter.queries.find { |q| q[:sql].include?("INSERT INTO schked_job_runs") }
        expect(insert[:params][1]).to eq window
      end
    end

    describe "#cleanup" do
      it "issues DELETE FROM schked_job_runs WHERE window_start < ?" do
        store.cleanup(Time.now.to_i - 60)
        delete = adapter.queries.find { |q| q[:sql].include?("DELETE FROM schked_job_runs") }
        expect(delete[:sql]).to include("WHERE window_start < ?")
      end
    end
  end

  describe "MySQL semantics" do
    let(:adapter) { FakeDatabaseAdapter.new(adapter_name: "Mysql2") }
    let(:store) { described_class.new(adapter: adapter, flavor: :mysql, logger: logger) }

    it_behaves_like "a job run store"

    it "issues INSERT ... ON DUPLICATE KEY UPDATE id = id" do
      store.claim("job_a", Time.now.to_i)
      insert = adapter.queries.find { |q| q[:sql].include?("INSERT INTO schked_job_runs") }
      expect(insert[:sql]).to include("ON DUPLICATE KEY UPDATE id = id")
    end

    it "treats affected_rows == 1 as a successful claim" do
      allow(adapter).to receive(:execute).and_return(1)
      expect(store.claim("job_a", Time.now.to_i)).to be true
    end

    it "treats affected_rows == 0 as a conflicting claim" do
      allow(adapter).to receive(:execute).and_return(0)
      expect(store.claim("job_a", Time.now.to_i)).to be false
    end
  end

  describe "auto flavor detection" do
    it "defaults to postgres when adapter_name is unknown" do
      adapter = FakeDatabaseAdapter.new(adapter_name: "MysteryDB")
      store = described_class.new(adapter: adapter, logger: logger)
      expect(store.flavor).to eq :postgres
    end

    it "detects MySQL via adapter_name" do
      adapter = FakeDatabaseAdapter.new(adapter_name: "Mysql2")
      store = described_class.new(adapter: adapter, logger: logger)
      expect(store.flavor).to eq :mysql
    end
  end
end
