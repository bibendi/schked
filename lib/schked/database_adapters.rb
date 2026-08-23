# frozen_string_literal: true

module Schked
  module DatabaseAdapters
    # Wraps an underlying database connection so it satisfies the
    # +execute(sql, params)+ contract used by +DatabaseJobRunStore+.
    #
    # Contract for the return value of +#execute+:
    # * For INSERT ... RETURNING (Postgres): an Array of result rows. An
    #   empty array means the INSERT lost the conflict; one row means it
    #   won. The wrapped connection's result object must therefore expose
    #   +#cmd_tuples+, +#length+, or +#first+ for the store to read the row
    #   count correctly.
    # * For INSERT ... ON DUPLICATE KEY UPDATE (MySQL): an Integer
    #   affected_rows count. 1 = inserted (won), 0 = duplicate (conflict).
    # * For DELETE: the result is ignored (cleanup is best-effort).
    #
    # Connection / SQL errors MUST raise out of +#execute+ so the worker can
    # distinguish "lost the race" (returned false) from "store unreachable"
    # (raised). Swallowing them silently would skip every job while the
    # database is down.
    class Base
      def initialize(connection)
        @connection = connection
      end

      attr_reader :connection

      def execute(_sql, _params = [])
        raise NotImplementedError
      end

      def adapter_name
        @connection.adapter_name if @connection.respond_to?(:adapter_name)
      end
    end

    # pg gem (libpq) — uses +exec_params(sql, params)+ and +PG::Result#cmd_tuples+.
    # Translates +?+ placeholders to pg's +$1, $2, ...+ positional binds.
    class Pg < Base
      def execute(sql, params = [])
        @connection.exec_params(rewrite_placeholders(sql), params)
      end

      def adapter_name
        "PostgreSQL"
      end

      private

      def rewrite_placeholders(sql)
        i = 0
        sql.gsub("?") do
          i += 1
          "$#{i}"
        end
      end
    end

    # mysql2 gem — uses +prepare(sql).execute(*params)+ and the statement's
    # +#affected_rows+. The connection's +#affected_rows+ is NOT updated by
    # prepared-statement execution, so we read it off the statement itself.
    class Mysql2 < Base
      def execute(sql, params = [])
        stmt = @connection.prepare(sql)
        stmt.execute(*params)
        Integer(stmt.affected_rows)
      end

      def adapter_name
        "Mysql2"
      end
    end

    # Sequel — uses the Dataset API so affected_rows semantics are honored
    # uniformly across Postgres and MySQL adapters. Postgres uses
    # +insert_conflict+ (which compiles to ON CONFLICT DO NOTHING); MySQL
    # uses +insert_conflict(multi: true)+ (which compiles to ON DUPLICATE
    # KEY UPDATE). The +window_start+ and +job_name+ columns must exist
    # with a UNIQUE index for the conflict path to fire.
    class Sequel < Base
      def execute(sql, params = [])
        if sql.start_with?("INSERT INTO #{::Schked::DatabaseJobRunStore::TABLE}")
          insert_conflict_insert(params)
        elsif sql.start_with?("DELETE FROM #{::Schked::DatabaseJobRunStore::TABLE}")
          cutoff = params[0]
          @connection[::Schked::DatabaseJobRunStore::TABLE.to_sym].where { window_start < cutoff }.delete
        else
          raise ArgumentError, "Schked::DatabaseAdapters::Sequel only supports INSERT/DELETE against #{::Schked::DatabaseJobRunStore::TABLE}"
        end
      end

      def adapter_name
        @connection.adapter_scheme.to_s
      end

      private

      def insert_conflict_insert(params)
        job_name, window_start, run_at = params
        target = %i[job_name window_start]
        ds = @connection[::Schked::DatabaseJobRunStore::TABLE.to_sym]
        ds = if @connection.adapter_scheme.to_s.include?("mysql")
          ds.insert_conflict(multi: true, target: target)
        else
          ds.insert_conflict(target: target)
        end
        # Sequel returns the inserted primary key on success and +nil+ on
        # conflict. Map to an Integer affected_rows-style count so the
        # store's row_count check works uniformly.
        result = ds.insert(job_name: job_name, window_start: window_start, run_at: run_at)
        result.nil? ? 0 : 1
      end
    end

    # ActiveRecord — uses +exec_query(sql, name, binds)+ with
    # +ActiveRecord::Relation::QueryAttribute+ bind objects. +sanitize_sql_array+
    # is only available on model classes, not on connection adapters, so we
    # build binds manually. PostgreSQL uses +$1, $2, ...+ positional binds;
    # MySQL uses +?+. The adapter rewrites +?+ to the appropriate form so
    # the store's +?+ SQL works uniformly. The connection returns an
    # +ActiveRecord::Result+ which exposes +#length+ so
    # +DatabaseJobRunStore#row_count+ works uniformly.
    class ActiveRecord < Base
      def execute(sql, params = [])
        return @connection.execute(sql) if params.empty?

        bound_sql = rewrite_placeholders(sql)
        binds = build_binds(params)
        @connection.exec_query(bound_sql, "Schked", binds)
      end

      def adapter_name
        @connection.adapter_name if @connection.respond_to?(:adapter_name)
      end

      private

      def rewrite_placeholders(sql)
        if mysql?
          sql
        else
          rewrite_placeholders_postgres(sql)
        end
      end

      def rewrite_placeholders_postgres(sql)
        i = 0
        sql.gsub("?") do
          i += 1
          "$#{i}"
        end
      end

      def build_binds(values)
        values.each_with_index.map do |value, idx|
          ::ActiveRecord::Relation::QueryAttribute.new(
            "schked_#{idx}",
            value,
            type_for(value)
          )
        end
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

      def mysql?
        adapter_name.to_s.include?("Mysql") || adapter_name.to_s.include?("Trilogy")
      end
    end

    # Auto-detect the right adapter for an arbitrary connection object.
    module_function

    def wrap(connection)
      if connection.is_a?(Base)
        connection
      elsif defined?(::PG::Connection) && connection.is_a?(::PG::Connection)
        Pg.new(connection)
      elsif defined?(::Mysql2::Client) && connection.is_a?(::Mysql2::Client)
        Mysql2.new(connection)
      elsif defined?(::Sequel::Database) && connection.is_a?(::Sequel::Database)
        Sequel.new(connection)
      elsif defined?(::ActiveRecord::ConnectionAdapters::AbstractAdapter) &&
          connection.is_a?(::ActiveRecord::ConnectionAdapters::AbstractAdapter)
        ActiveRecord.new(connection)
      elsif connection.respond_to?(:execute)
        # Assume the connection already satisfies the contract.
        Passthrough.new(connection)
      else
        raise DatabaseConnection::NotFoundError,
          "Schked could not detect a database adapter for: #{connection.class}. " \
          "Provide a connection of type PG::Connection, Mysql2::Client, " \
          "Sequel::Database, or ActiveRecord::ConnectionAdapters::AbstractAdapter."
      end
    end

    # Used when the connection already responds to +execute(sql, params)+.
    class Passthrough < Base
      def execute(sql, params = [])
        @connection.execute(sql, params)
      end
    end
  end
end
