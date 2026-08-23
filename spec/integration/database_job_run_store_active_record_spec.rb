# frozen_string_literal: true

require "spec_helper"

# ActiveRecord integration tests for the database-backed coordination store.
# Exercises the +Schked::DatabaseAdapters::ActiveRecord+ adapter path against
# a real ActiveRecord::Base.connection to Postgres. Loaded only via the
# +rails+ dip subcommand (any Rails appraisal gemfile), where ActiveRecord
# is on the load path. In non-Rails gemfiles the file loads but defines no
# examples, so the suite stays clean.
ar_loaded =
  begin
    require "active_record"
    true
  rescue LoadError
    false
  end

if ar_loaded
  describe Schked::DatabaseJobRunStore do
    def with_active_record_connection
      url = ENV.fetch("SCHKED_POSTGRES_URL")
      ActiveRecord::Base.establish_connection(url)
      @ar_connection = ActiveRecord::Base.connection
      yield
    ensure
      ActiveRecord::Base.connection_pool&.disconnect!
    end

    def ar_table_defined?
      ActiveRecord::Base.connection.tables.include?("schked_job_runs")
    end

    def define_ar_table
      table_exists = ar_table_defined?
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

    describe "ActiveRecord integration" do
      let(:logger) { Logger.new(File::NULL) }
      let(:ar_connection) { ActiveRecord::Base.connection }
      let(:adapter) { Schked::DatabaseAdapters::ActiveRecord.new(ar_connection) }
      let(:store) { described_class.new(adapter: adapter, flavor: :postgres, logger: logger) }

      around do |ex|
        with_active_record_connection do
          define_ar_table
          ex.run
        end
      end

      # Each concurrent caller opens its own connection — the shared AR
      # connection_pool is not safe across threads.
      def claim_in_thread(name:, window:)
        result = nil
        Thread.new do
          url = ENV.fetch("SCHKED_POSTGRES_URL")
          ActiveRecord::Base.establish_connection(url)
          conn = ActiveRecord::Base.connection
          result = Schked::DatabaseJobRunStore.new(
            adapter: Schked::DatabaseAdapters::ActiveRecord.new(conn),
            flavor: :postgres,
            logger: Logger.new(File::NULL)
          ).claim(name, window)
        ensure
          ActiveRecord::Base.connection_pool&.disconnect!
        end.join
        result
      end

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
        results = 20.times.map { claim_in_thread(name: "racey", window: window) }
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

      describe "auto flavor detection" do
        it "detects Postgres via the AR adapter" do
          store = described_class.new(adapter: adapter, logger: logger)
          expect(store.flavor).to eq :postgres
        end
      end
    end
  end
end
