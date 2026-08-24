# frozen_string_literal: true

module Schked
  # Adapter for MySQL via the +mysql2+ gem (+Mysql2::Client+).
  # Implements the +Schked::JobRunStore+ contract directly.
  class Adapters
    class Mysql2
      include JobRunStore

      attr_reader :logger

      def initialize(client, logger: Logger.new($stdout))
        @client = client
        @logger = logger
      end

      def claim(job_name, window_start)
        validate!(job_name, window_start)

        ts = window_start.is_a?(Time) ? window_start.to_i : Integer(window_start)
        run_at = Time.now.to_f

        stmt = @client.prepare(
          "INSERT INTO #{TABLE} (job_name, window_start, run_at) VALUES (?, ?, ?) " \
          "ON DUPLICATE KEY UPDATE id = id"
        )
        stmt.execute(job_name, ts, run_at)
        # Note: +@client.affected_rows+ is NOT updated by prepared-statement
        # execution (libmysqlclient design quirk). The connection's value
        # reflects the last *direct* +query+ call, not the prepared
        # statement's, so we MUST read from the statement itself.
        Integer(stmt.affected_rows) == 1
      rescue ArgumentError
        raise
      rescue => e
        logger.error("Failed to claim mysql job run with error: #{e.message}")
        raise
      end

      def cleanup(older_than)
        cutoff = older_than.is_a?(Time) ? older_than.to_i : Integer(older_than)
        stmt = @client.prepare("DELETE FROM #{TABLE} WHERE window_start < ?")
        stmt.execute(cutoff)
        nil
      rescue => e
        logger.error("Failed to clean up mysql job runs with error: #{e.message}")
        raise
      end

      def adapter_name
        "Mysql2"
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
