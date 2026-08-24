# frozen_string_literal: true

require "spec_helper"
require "sequel"

# Sequel integration tests for +Schked::Adapters::Sequel+. Loaded only
# under the +sequel+ Appraisal gemfile.
describe Schked::Adapters::Sequel do
  def sequel_db
    @sequel_db ||= Sequel.connect(ENV.fetch("SCHKED_POSTGRES_URL"))
  end

  def with_table
    sequel_db.drop_table?(:schked_job_runs)
    sequel_db.create_table(:schked_job_runs) do
      primary_key :id, type: :Bignum
      String :job_name, null: false
      Bignum :window_start, null: false
      Float :run_at, null: false
      index %i[job_name window_start], unique: true, name: :schked_job_runs_unique
      index :window_start, name: :schked_job_runs_window_start_idx
    end
    yield
  ensure
    sequel_db&.disconnect
  end

  let(:logger) { Logger.new(File::NULL) }
  subject(:store) { described_class.new(sequel_db, logger: logger) }

  around { |ex| with_table(&ex) }

  it_behaves_like "a job run store"

  it "returns true on the first claim" do
    expect(store.claim("job_a", Time.now.to_i)).to be true
    expect(store.adapter_name).to eq "postgres"
  end

  it "returns false on a duplicate claim" do
    window = Time.now.to_i
    expect(store.claim("job_a", window)).to be true
    expect(store.claim("job_a", window)).to be false
  end

  it "lets only one claim win under concurrent contention" do
    window = Time.now.to_i
    threads = 20.times.map do
      Thread.new do
        conn = Sequel.connect(ENV.fetch("SCHKED_POSTGRES_URL"))
        described_class.new(conn, logger: Logger.new(File::NULL)).claim("racey", window)
      ensure
        conn&.disconnect
      end
    end
    results = threads.map(&:value)
    expect(results.count(true)).to eq 1
    expect(results.count(false)).to eq 19

    count = sequel_db[:schked_job_runs].count
    expect(count).to eq 1
  end

  describe "#cleanup" do
    it "deletes rows older than the cutoff" do
      store.claim("old", Time.now.to_i - 3600)
      store.claim("new", Time.now.to_i)

      store.cleanup(Time.now.to_i - 60)

      names = sequel_db[:schked_job_runs].select_map(:job_name)
      expect(names).to contain_exactly("new")
    end
  end
end
