# frozen_string_literal: true

module Schked
  # Auto-detects which +Schked::Adapters::*+ class to use for the
  # database-backed coordination store. Returns a concrete +JobRunStore+
  # instance — the caller should not need to know which backend is in play.
  #
  # Resolution order:
  # 1. An explicit connection/pool if provided.
  # 2. +ActiveRecord::Base.connection_pool+ when ActiveRecord is loaded
  #    and configured (the pool, not a single connection, so the adapter
  #    can check out per operation).
  # 3. Sequel's first available +Sequel::DATABASES+ database.
  # 4. Otherwise raises a clear +NotFoundError+ telling the operator to
  #    set +database_connection+ explicitly.
  module DatabaseConnection
    class NotFoundError < StandardError; end

    module_function

    def detect(connection: nil, logger: Logger.new($stdout))
      raw = connection || auto_detect_connection
      wrap(raw, logger: logger)
    end

    def wrap(raw, logger: Logger.new($stdout))
      case raw
      when Adapters::Sequel, Adapters::ActiveRecord
        raw
      else
        build_for(raw, logger: logger)
      end
    end

    def build_for(raw, logger: Logger.new($stdout))
      if defined?(::Sequel::Database) && raw.is_a?(::Sequel::Database)
        Adapters::Sequel.new(raw, logger: logger)
      elsif raw.respond_to?(:with_connection)
        # An ActiveRecord connection pool.
        Adapters::ActiveRecord.new(raw, logger: logger)
      elsif raw.respond_to?(:pool) && raw.respond_to?(:adapter_name)
        # A concrete ActiveRecord adapter connection — normalize to its pool.
        Adapters::ActiveRecord.new(raw.pool, logger: logger)
      elsif raw.respond_to?(:claim) && raw.respond_to?(:cleanup)
        # Already a store: a pre-built adapter or a custom object.
        raw
      else
        raise NotFoundError,
          "Schked could not detect an adapter for: #{raw.class}. " \
          "Provide a Sequel::Database, an ActiveRecord connection pool, " \
          "or an ActiveRecord connection (PostgreSQL, Mysql2, or Trilogy)."
      end
    end

    def auto_detect_connection
      if defined?(ActiveRecord) && ActiveRecord.const_defined?(:Base)
        begin
          return ActiveRecord::Base.connection_pool
        rescue
          # ActiveRecord is loaded but not configured (or the pool cannot
          # be resolved) — fall through to Sequel detection below.
        end
      end

      if defined?(Sequel) && Sequel.respond_to?(:DATABASES) && Sequel::DATABASES.any?
        return Sequel::DATABASES.first
      end

      raise NotFoundError,
        "Schked could not detect a database connection for the database-backed " \
        "job run store. Load ActiveRecord or Sequel, or set `Schked.config.database_connection` " \
        "explicitly."
    end
  end
end
