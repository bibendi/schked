# frozen_string_literal: true

module SchkedSpec
  # Creates and drops the +schked_job_runs+ table through ActiveRecord for
  # the integration suites (postgres and mysql Appraisal gemfiles). Shared
  # by the ActiveRecord adapter specs; not loaded with ActiveRecord itself —
  # the requiring spec file is responsible for that.
  module ARJobRunTable
    module_function

    def with_table(url)
      ActiveRecord::Base.establish_connection(url)
      define_table
      yield
    ensure
      begin
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.execute("DROP TABLE IF EXISTS schked_job_runs")
        end
      rescue
        # The connection may already be gone; the next setup recreates the
        # table anyway (create drops it first when present).
      end
      ActiveRecord::Base.connection_pool&.disconnect!
    end

    def define_table
      table_exists = ActiveRecord::Base.connection.tables.include?("schked_job_runs")
      ActiveRecord::Schema.define do
        drop_table(:schked_job_runs) if table_exists
        create_table(:schked_job_runs) do |t|
          t.string :job_name, null: false
          t.bigint :window_start, null: false
          t.float :run_at, null: false
          t.string :claimer, null: false
        end
        add_index(:schked_job_runs, %i[job_name window_start], unique: true, name: :schked_job_runs_unique)
        add_index(:schked_job_runs, :window_start, name: :schked_job_runs_window_start_idx)
      end
    end
  end
end
