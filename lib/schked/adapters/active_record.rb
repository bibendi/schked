# frozen_string_literal: true

require "securerandom"

module Schked
  # Adapter for ActiveRecord connection pools (PostgreSQL, Mysql2,
  # Trilogy). Implements the +Schked::JobRunStore+ contract.
  #
  # The adapter wraps a connection *pool*, not a single connection: every
  # operation checks a connection out via +with_connection+ and returns it
  # afterwards. The lease guarantees exclusive use of the checked-out
  # connection, so claims (scheduler thread) and the cleanup sweep (work
  # threads) can safely share the pool, and the pool transparently
  # replaces dead connections after a database restart or failover.
  class Adapters
    class ActiveRecord
      include JobRunStore

      SUPPORTED_ADAPTERS = %w[PostgreSQL Mysql2 Trilogy].freeze

      attr_reader :adapter_name
      attr_reader :logger

      def initialize(pool, logger: Logger.new($stdout))
        # Accept either a ConnectionPool or a concrete adapter connection
        # (+ActiveRecord::Base.connection+) and normalize to the pool.
        @pool = pool.respond_to?(:with_connection) ? pool : pool.pool
        @logger = logger
        validate_adapter!
      end

      def claim(job_name, window_start)
        validate!(job_name, window_start)

        ts = window_start.is_a?(Time) ? window_start.to_i : Integer(window_start)
        run_at = Time.now.to_f
        claimer = SecureRandom.uuid

        @pool.with_connection do |connection|
          if postgres?
            postgres_claim(connection, job_name, ts, run_at, claimer)
          else
            mysql_claim(connection, job_name, ts, run_at, claimer)
          end
        end
      rescue ArgumentError
        raise
      rescue => e
        logger.error("Failed to claim AR job run with error: #{e.message}")
        raise
      end

      def cleanup(older_than)
        cutoff = older_than.is_a?(Time) ? older_than.to_i : Integer(older_than)
        @pool.with_connection do |connection|
          connection.execute("DELETE FROM #{TABLE} WHERE window_start < #{connection.quote(cutoff)}")
        end
        nil
      rescue => e
        logger.error("Failed to clean up AR job runs with error: #{e.message}")
        raise
      end

      private

      TABLE = "schked_job_runs"

      def validate_adapter!
        name = @pool.with_connection do |connection|
          connection.respond_to?(:adapter_name) ? connection.adapter_name.to_s : ""
        end
        unless SUPPORTED_ADAPTERS.any? { |supported| supported.casecmp?(name) }
          raise ArgumentError,
            "Schked::Adapters::ActiveRecord supports #{SUPPORTED_ADAPTERS.join(", ")} " \
            "connections only, got: #{name.inspect}"
        end

        # Cached: claim/cleanup dispatch on the dialect without extra
        # adapter_name round-trips on every firing.
        @adapter_name = name
      end

      def postgres?
        adapter_name.include?("Postgre") || adapter_name.include?("Postgres")
      end

      # Postgres can decide atomically in a single statement: INSERT ...
      # ON CONFLICT DO NOTHING RETURNING yields a row only for the winner.
      def postgres_claim(connection, job_name, ts, run_at, claimer)
        sql = "INSERT INTO #{TABLE} (job_name, window_start, run_at, claimer) " \
          "VALUES (#{connection.quote(job_name)}, #{connection.quote(ts)}, " \
          "#{connection.quote(run_at)}, #{connection.quote(claimer)}) " \
          "ON CONFLICT (job_name, window_start) DO NOTHING RETURNING id"
        Integer(connection.exec_query(sql, "Schked CLAIM").length).positive?
      end

      # Rails' mysql2 and trilogy adapters both connect with the
      # CLIENT_FOUND_ROWS capability set unconditionally (see
      # mysql2_adapter.rb / trilogy_adapter.rb), so affected_rows cannot
      # distinguish a fresh insert from a matched duplicate. Instead every
      # claimer writes a unique token and reads it back: the
      # UNIQUE (job_name, window_start) constraint guarantees exactly one
      # row survives, so only the claimer whose token is stored in that
      # row won the window.
      def mysql_claim(connection, job_name, ts, run_at, claimer)
        insert = "INSERT IGNORE INTO #{TABLE} (job_name, window_start, run_at, claimer) " \
          "VALUES (#{connection.quote(job_name)}, #{connection.quote(ts)}, " \
          "#{connection.quote(run_at)}, #{connection.quote(claimer)})"
        connection.execute(insert)

        select = "SELECT claimer FROM #{TABLE} " \
          "WHERE job_name = #{connection.quote(job_name)} AND window_start = #{connection.quote(ts)}"
        row = connection.exec_query(select, "Schked CLAIM").first
        !row.nil? && row["claimer"] == claimer
      end

      def validate!(job_name, window_start)
        raise ArgumentError, "job_name must be a non-empty String" if job_name.to_s.empty?
        raise ArgumentError, "window_start must not be nil" if window_start.nil?
      end
    end
  end
end
