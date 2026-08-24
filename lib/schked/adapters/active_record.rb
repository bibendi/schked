# frozen_string_literal: true

module Schked
  # Adapter for ActiveRecord (+ActiveRecord::ConnectionAdapters::AbstractAdapter+).
  # Implements the +Schked::JobRunStore+ contract using the AR query
  # interface (+exec_query+ with +ActiveRecord::Relation::QueryAttribute+
  # bind objects). Translates +?+ placeholders to the appropriate form for
  # the underlying adapter (Postgres uses +$1, $2, ...+; MySQL accepts
  # +?+ directly).
  class Adapters
    class ActiveRecord
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

        sql = rewrite_placeholders(
          "INSERT INTO #{TABLE} (job_name, window_start, run_at) VALUES (?, ?, ?) " \
          "ON CONFLICT (job_name, window_start) DO NOTHING RETURNING id"
        )
        result = @connection.exec_query(sql, "Schked", [
          bind("job_name", job_name),
          bind("window_start", ts),
          bind("run_at", run_at)
        ])
        # +ActiveRecord::Result+ exposes +#length+ (number of rows).
        Integer(result.length).positive?
      rescue ArgumentError
        raise
      rescue => e
        logger.error("Failed to claim AR job run with error: #{e.message}")
        raise
      end

      def cleanup(older_than)
        cutoff = older_than.is_a?(Time) ? older_than.to_i : Integer(older_than)
        sql = rewrite_placeholders("DELETE FROM #{TABLE} WHERE window_start < ?")
        @connection.exec_query(sql, "Schked", [bind("cutoff", cutoff)])
        nil
      rescue => e
        logger.error("Failed to clean up AR job runs with error: #{e.message}")
        raise
      end

      def adapter_name
        @connection.adapter_name if @connection.respond_to?(:adapter_name)
      end

      private

      TABLE = "schked_job_runs"

      def bind(name, value)
        ::ActiveRecord::Relation::QueryAttribute.new(name, value, type_for(value))
      end

      def type_for(value)
        case value
        when Integer then ::ActiveRecord::Type::Integer.new
        when Float then ::ActiveRecord::Type::Float.new
        when true, false then ::ActiveRecord::Type::Boolean.new
        when nil then ::ActiveRecord::Type::Value.new
        else ::ActiveRecord::Type::String.new
        end
      end

      def rewrite_placeholders(sql)
        return sql unless postgres?
        i = 0
        sql.gsub("?") do
          i += 1
          "$#{i}"
        end
      end

      def postgres?
        adapter_name.to_s.include?("PostgreSQL") || adapter_name.to_s.include?("Postgres")
      end

      def validate!(job_name, window_start)
        raise ArgumentError, "job_name must be a non-empty String" if job_name.to_s.empty?
        raise ArgumentError, "window_start must not be nil" if window_start.nil?
      end
    end
  end
end
