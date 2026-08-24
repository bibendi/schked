# frozen_string_literal: true

module Schked
  # Auto-detects which +Schked::Adapters::*+ class to use for a given
  # database connection. Returns a concrete +JobRunStore+ instance — the
  # caller should not need to know which backend is in play.
  #
  # Resolution order:
  # 1. An explicit connection if provided.
  # 2. +ActiveRecord::Base.connection+ when ActiveRecord is loaded and
  #    connected.
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
      when Adapters::Pg, Adapters::Mysql2, Adapters::Sequel, Adapters::ActiveRecord
        raw
      else
        build_for(raw, logger: logger)
      end
    end

    def build_for(raw, logger:)
      if defined?(::PG::Connection) && raw.is_a?(::PG::Connection)
        Adapters::Pg.new(raw, logger: logger)
      elsif defined?(::Mysql2::Client) && raw.is_a?(::Mysql2::Client)
        Adapters::Mysql2.new(raw, logger: logger)
      elsif defined?(::Sequel::Database) && raw.is_a?(::Sequel::Database)
        Adapters::Sequel.new(raw, logger: logger)
      elsif defined?(::ActiveRecord::ConnectionAdapters::AbstractAdapter) &&
          raw.is_a?(::ActiveRecord::ConnectionAdapters::AbstractAdapter)
        Adapters::ActiveRecord.new(raw, logger: logger)
      else
        raise NotFoundError,
          "Schked could not detect an adapter for: #{raw.class}. " \
          "Provide a PG::Connection, Mysql2::Client, Sequel::Database, or an " \
          "ActiveRecord adapter."
      end
    end

    def auto_detect_connection
      if defined?(ActiveRecord) && ActiveRecord.const_defined?(:Base) &&
          ActiveRecord::Base.respond_to?(:connected?) && ActiveRecord::Base.connected?
        return ActiveRecord::Base.connection
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
