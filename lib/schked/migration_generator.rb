# frozen_string_literal: true

module Schked
  # Generates the DDL for the +schked_job_runs+ table used by the
  # database-backed coordination store. Operators copy the SQL into their own
  # migration; schked does not write migration files or run DDL on its own.
  module MigrationGenerator
    module_function

    DDL_POSTGRES = <<~SQL
      CREATE TABLE schked_job_runs (
        id BIGSERIAL PRIMARY KEY,
        job_name TEXT NOT NULL,
        window_start BIGINT NOT NULL,
        run_at DOUBLE PRECISION NOT NULL,
        claimer TEXT NOT NULL,
        CONSTRAINT schked_job_runs_unique UNIQUE (job_name, window_start)
      );

      CREATE INDEX schked_job_runs_window_start_idx ON schked_job_runs (window_start);
    SQL

    DDL_MYSQL = <<~SQL
      CREATE TABLE schked_job_runs (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        job_name VARCHAR(255) NOT NULL,
        window_start BIGINT NOT NULL,
        run_at DOUBLE NOT NULL,
        claimer VARCHAR(255) NOT NULL,
        UNIQUE KEY schked_job_runs_unique (job_name, window_start),
        KEY schked_job_runs_window_start_idx (window_start)
      );
    SQL

    def sql(flavor = "postgres")
      case flavor.to_s.downcase
      when "mysql" then DDL_MYSQL
      else DDL_POSTGRES
      end
    end
  end
end
