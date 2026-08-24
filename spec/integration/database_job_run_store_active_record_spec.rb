# frozen_string_literal: true

require "spec_helper"

# ActiveRecord integration tests for +Schked::Adapters::ActiveRecord+.
# Exercises the adapter path against a real ActiveRecord connection to
# Postgres. Loaded via the +rails+ dip subcommand; in non-Rails gemfiles
# the file loads but defines no examples.
ar_loaded =
  begin
    require "active_record"
    true
  rescue LoadError
    false
  end

if ar_loaded
  require "pg"

  describe Schked::Adapters::ActiveRecord do
    def ar_connection
      @ar_connection ||= ActiveRecord::Base.connection
    end

    def define_ar_table
      table_exists = ActiveRecord::Base.connection.tables.include?("schked_job_runs")
      ActiveRecord::Schema.define do
        drop_table(:schked_job_runs) if table_exists
        create_table(:schked_job_runs) do |t|
          t.bigint :window_start, null: false
          t.float :run_at, null: false
          t.string :job_name, null: false
        end
        add_index(:schked_job_runs, %i[job_name window_start], unique: true, name: :schked_job_runs_unique)
        add_index(:schked_job_runs, :window_start, name: :schked_job_runs_window_start_idx)
      end
    end

    def ar_adapter
      Schked::Adapters::ActiveRecord.new(ar_connection, logger: Logger.new(File::NULL))
    end

    before(:all) do
      url = ENV.fetch("SCHKED_POSTGRES_URL")
      ActiveRecord::Base.establish_connection(url)
      @_ar_setup_conn = ActiveRecord::Base.connection
      define_ar_table
    end

    before do
      # The table is created once via +before(:all)+ and accumulates rows
      # across examples. Truncate it before each test so the shared
      # contract (first claim wins, second loses on conflict) holds.
      ActiveRecord::Base.connection.execute("TRUNCATE TABLE schked_job_runs RESTART IDENTITY")
    end

    after(:all) do
      # The connection is closed by +disconnect!+; dropping the table
      # in another +before(:all)+ on a subsequent spec run is handled
      # by +define_ar_table+ via +drop_table if exists+.
      ActiveRecord::Base.connection_pool&.disconnect!
    end

    let(:logger) { Logger.new(File::NULL) }
    subject(:store) { ar_adapter }

    it_behaves_like "a job run store"

    it "persists rows that win the claim" do
      expect(store.claim("job_a", Time.now.to_i)).to be true
      rows = ar_connection.exec_query("SELECT job_name FROM schked_job_runs ORDER BY id").to_a
      expect(rows.map { |r| r["job_name"] }).to eq ["job_a"]
    end

    it "does not insert rows that lose the claim (UNIQUE constraint enforced by ON CONFLICT DO NOTHING)" do
      window = Time.now.to_i
      store.claim("job_a", window)
      expect(store.claim("job_a", window)).to be false

      count = ar_connection.exec_query("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
      expect(count.to_i).to eq 1
    end

    it "lets exactly one claim win when many concurrent callers race for the same (job, window)" do
      window = Time.now.to_i
      results = 20.times.map do
        result = nil
        Thread.new do
          url = ENV.fetch("SCHKED_POSTGRES_URL")
          ActiveRecord::Base.establish_connection(url)
          conn = ActiveRecord::Base.connection
          result = Schked::Adapters::ActiveRecord.new(conn, logger: Logger.new(File::NULL)).claim("racey", window)
        ensure
          ActiveRecord::Base.connection_pool&.disconnect!
        end.join
        result
      end
      expect(results.count(true)).to eq 1
      expect(results.count(false)).to eq 19

      count = ar_connection.exec_query("SELECT COUNT(*) AS n FROM schked_job_runs").first["n"]
      expect(count.to_i).to eq 1
    end

    describe "#cleanup" do
      it "deletes rows whose window_start is older than the cutoff" do
        store.claim("old", Time.now.to_i - 3600)
        store.claim("new", Time.now.to_i)

        store.cleanup(Time.now.to_i - 60)

        names = ar_connection.exec_query("SELECT job_name FROM schked_job_runs ORDER BY id").to_a.map { |r| r["job_name"] }
        expect(names).to contain_exactly("new")
      end
    end

    it "detects Postgres via the AR adapter" do
      expect(store.adapter_name).to eq "PostgreSQL"
    end
  end
end
