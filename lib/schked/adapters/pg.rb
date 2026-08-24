# frozen_string_literal: true

module Schked
  # Adapter for PostgreSQL via the +pg+ gem (+PG::Connection+).
  # Implements the +Schked::JobRunStore+ contract directly — no SQL
  # detail leaks past this class.
  class Adapters
    class Pg
      include JobRunStore

      attr_reader :logger

      def initialize(connection, logger: Logger.new($stdout))
        @connection = connection
        @logger = logger
      end

      def claim(job_name, window_start)
        validate!(job_name, window_start)

        ts = window_start.is_a?(Time) ? window_start.to_i : Integer(window_start)
        run_at = Time.now.to_f

        result = @connection.exec_params(
          "INSERT INTO #{TABLE} (job_name, window_start, run_at) VALUES ($1, $2, $3) " \
          "ON CONFLICT (job_name, window_start) DO NOTHING RETURNING id",
          [job_name, ts, run_at]
        )
        # +PG::Result+ responds to +#ntuples+ (rows) and +#cmd_tuples+ (affected).
        Integer(result.cmd_tuples).positive?
      rescue ArgumentError
        raise
      rescue => e
        logger.error("Failed to claim pg job run with error: #{e.message}")
        raise
      end

      def cleanup(older_than)
        cutoff = older_than.is_a?(Time) ? older_than.to_i : Integer(older_than)
        @connection.exec_params(
          "DELETE FROM #{TABLE} WHERE window_start < $1",
          [cutoff]
        )
        nil
      rescue => e
        logger.error("Failed to clean up pg job runs with error: #{e.message}")
        raise
      end

      def adapter_name
        "PostgreSQL"
      end

      private

      TABLE = "schked_job_runs"

      def validate!(job_name, window_start)
        raise ArgumentError, "job_name must be a non-empty String" if job_name.to_s.empty?
        raise ArgumentError, "window_start must not be nil" if window_start.nil?
      end
    end
  end
end
