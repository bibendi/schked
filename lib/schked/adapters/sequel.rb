# frozen_string_literal: true

module Schked
  # Adapter for Sequel (Postgres or MySQL via +Sequel::Database+).
  # Implements the +Schked::JobRunStore+ contract using Sequel's Dataset
  # API — +insert_conflict+ compiles to the right SQL for the underlying
  # adapter (Postgres uses +ON CONFLICT DO NOTHING+; MySQL uses
  # +ON DUPLICATE KEY UPDATE id = id+).
  class Adapters
    class Sequel
      include JobRunStore

      attr_reader :logger

      def initialize(database, logger: Logger.new($stdout))
        @database = database
        @logger = logger
      end

      def claim(job_name, window_start)
        validate!(job_name, window_start)

        job_name, window_start, run_at = normalize_values(job_name, window_start)
        result = dataset
          .insert_conflict(target: UNIQUE_COLUMNS)
          .insert(job_name: job_name, window_start: window_start, run_at: run_at)
        # Sequel returns the new PK on success and +nil+ on conflict.
        !result.nil?
      rescue ArgumentError
        raise
      rescue => e
        logger.error("Failed to claim sequel job run with error: #{e.message}")
        raise
      end

      def cleanup(older_than)
        cutoff = older_than.is_a?(Time) ? older_than.to_i : Integer(older_than)
        dataset.where { window_start < cutoff }.delete
        nil
      rescue => e
        logger.error("Failed to clean up sequel job runs with error: #{e.message}")
        raise
      end

      def adapter_name
        @database.adapter_scheme.to_s
      end

      private

      TABLE = :schked_job_runs
      UNIQUE_COLUMNS = %i[job_name window_start].freeze

      def dataset
        @database[TABLE]
      end

      def normalize_values(job_name, window_start)
        ts = window_start.is_a?(Time) ? window_start.to_i : Integer(window_start)
        run_at = Time.now.to_f
        [job_name, ts, run_at]
      end

      def validate!(job_name, window_start)
        raise ArgumentError, "job_name must be a non-empty String" if job_name.to_s.empty?
        raise ArgumentError, "window_start must not be nil" if window_start.nil?
      end
    end
  end
end
