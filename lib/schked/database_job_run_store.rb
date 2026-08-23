# frozen_string_literal: true

module Schked
  # Database-backed implementation of the per-job coordination store.
  # Executes pure SQL through a +DatabaseAdapters::*+ adapter that satisfies
  # the +execute(sql, params)+ contract. No ORM models or adapter classes
  # are required from the operator.
  #
  # The +schked_job_runs+ table is expected to have a unique index on
  # +(job_name, window_start)+ so the atomic insert guarantees a single winner.
  class DatabaseJobRunStore
    include JobRunStore

    TABLE = "schked_job_runs"

    attr_reader :adapter, :flavor, :logger

    def initialize(adapter:, flavor: nil, logger: Logger.new($stdout))
      @adapter = adapter
      @flavor = flavor || DatabaseConnection::KNOWN_ADAPTERS.fetch(adapter.adapter_name.to_s, :postgres)
      @logger = logger
    end

    def claim(job_name, window_start)
      validate!(job_name, window_start)

      ts = window_start.is_a?(Time) ? window_start.to_i : Integer(window_start)
      run_at = Time.now.to_f

      case @flavor
      when :mysql
        affected = @adapter.execute(
          "INSERT INTO #{TABLE} (job_name, window_start, run_at) VALUES (?, ?, ?) " \
          "ON DUPLICATE KEY UPDATE id = id",
          [job_name, ts, run_at]
        )
        # +affected_rows+ 1 = inserted (claim won), 0 = duplicate key (conflict).
        # Connection / SQL errors raise out of the adapter so the caller can
        # tell the difference between "lost the race" and "store unreachable".
        Integer(affected) == 1
      else
        result = @adapter.execute(
          "INSERT INTO #{TABLE} (job_name, window_start, run_at) VALUES (?, ?, ?) " \
          "ON CONFLICT (job_name, window_start) DO NOTHING RETURNING id",
          [job_name, ts, run_at]
        )
        # Empty result = conflict (lost the race); otherwise the claim won.
        # Connection / SQL errors raise out of the adapter.
        row_count(result).positive?
      end
    end

    def cleanup(older_than)
      cutoff = older_than.is_a?(Time) ? older_than.to_i : Integer(older_than)
      @adapter.execute(
        "DELETE FROM #{TABLE} WHERE window_start < ?",
        [cutoff]
      )
      nil
    end

    private

    def validate!(job_name, window_start)
      raise ArgumentError, "job_name must be a non-empty String" if job_name.to_s.empty?
      raise ArgumentError, "window_start must not be nil" if window_start.nil?
    end

    def row_count(result)
      if result.respond_to?(:cmd_tuples)
        Integer(result.cmd_tuples)
      elsif result.respond_to?(:affected_rows)
        Integer(result.affected_rows)
      elsif result.respond_to?(:length)
        Integer(result.length)
      elsif result.is_a?(Integer)
        result
      else
        0
      end
    end
  end
end
