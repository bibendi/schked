# frozen_string_literal: true

require "securerandom"

module Schked
  # Adapter for Sequel (Postgres or MySQL via +Sequel::Database+).
  # Implements the +Schked::JobRunStore+ contract. Both operations go
  # through Sequel's thread-safe connection pool, so claims (scheduler
  # thread) and the cleanup sweep (work threads) can overlap freely.
  class Adapters
    class Sequel
      include JobRunStore

      SUPPORTED_DATABASE_TYPES = %w[postgres mysql].freeze

      attr_reader :logger

      def initialize(database, logger: Logger.new($stdout))
        @database = database
        @logger = logger
        type = database.database_type.to_s
        unless SUPPORTED_DATABASE_TYPES.include?(type)
          raise ArgumentError,
            "Schked::Adapters::Sequel supports Postgres and MySQL databases only, got: #{type.inspect}"
        end
      end

      def claim(job_name, window_start)
        validate!(job_name, window_start)

        ts = window_start.is_a?(Time) ? window_start.to_i : Integer(window_start)
        run_at = Time.now.to_f
        claimer = SecureRandom.uuid

        if postgres?
          # Sequel's +insert_conflict+ is a PostgreSQL-only dataset method;
          # it returns the new PK on success and +nil+ on conflict, so the
          # winner is decided atomically in a single statement.
          id = dataset
            .insert_conflict(target: UNIQUE_COLUMNS)
            .insert(job_name: job_name, window_start: ts, run_at: run_at, claimer: claimer)
          !id.nil?
        else
          mysql_claim(job_name, ts, run_at, claimer)
        end
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

      def postgres?
        @database.database_type == :postgres
      end

      # MySQL has no +RETURNING+, and affected-rows semantics depend on the
      # CLIENT_FOUND_ROWS connection flag, so the winner cannot be derived
      # from the insert alone. Instead every claimer writes a unique token
      # and reads it back: the UNIQUE (job_name, window_start) constraint
      # guarantees exactly one row survives, so only the claimer whose
      # token is stored in that row won the window. +insert_ignore+ is a
      # MySQL dataset method (+INSERT IGNORE+).
      def mysql_claim(job_name, ts, run_at, claimer)
        sql = dataset
          .insert_ignore
          .insert_sql(job_name: job_name, window_start: ts, run_at: run_at, claimer: claimer)

        @database.synchronize do |conn|
          conn.query(sql)
        end

        row = @database[TABLE]
          .where(job_name: job_name, window_start: ts)
          .select(:claimer)
          .first
        !row.nil? && row[:claimer] == claimer
      end

      def dataset
        @database[TABLE]
      end

      def validate!(job_name, window_start)
        raise ArgumentError, "job_name must be a non-empty String" if job_name.to_s.empty?
        raise ArgumentError, "window_start must not be nil" if window_start.nil?
      end
    end
  end
end
