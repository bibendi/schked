# frozen_string_literal: true

module Schked
  # Auto-detects a database connection for the database-backed coordination
  # store and wraps it in a +DatabaseAdapters::*+ adapter that satisfies the
  # +execute(sql, params)+ contract.
  #
  # Connection resolution order:
  # 1. +database_connection+ if explicitly configured.
  # 2. +ActiveRecord::Base.connection+ when ActiveRecord is loaded and connected.
  # 3. Sequel's first available +Sequel::DATABASES+ database when Sequel is loaded.
  # 4. Otherwise raises a clear startup error telling the operator to set
  #    +database_connection+ explicitly.
  #
  # Flavor resolution:
  # 1. +database_flavor+ if explicitly configured (:postgres / :mysql).
  # 2. The wrapped connection's adapter_name when it matches a known flavor.
  # 3. Defaults to +:postgres+.
  class DatabaseConnection
    DEFAULT_FLAVOR = :postgres
    KNOWN_ADAPTERS = {
      "PostgreSQL" => :postgres,
      "Postgres" => :postgres,
      "PG" => :postgres,
      "MySQL" => :mysql,
      "Mysql2" => :mysql,
      "Mysql2Adapter" => :mysql,
      "Trilogy" => :mysql,
      # Sequel reports its adapter via +adapter_scheme+ (e.g. "postgres",
      # "mysql2"). The wrappers normalize these to plain strings.
      "postgres" => :postgres,
      "mysql2" => :mysql
    }.freeze

    class NotFoundError < StandardError; end

    attr_reader :adapter, :flavor

    def initialize(connection: nil, flavor: nil)
      @explicit_connection = connection
      @explicit_flavor = flavor
      @adapter = resolve_adapter
      @flavor = resolve_flavor
    end

    def self.detect(connection: nil, flavor: nil)
      new(connection: connection, flavor: flavor)
    end

    private

    def resolve_adapter
      raw = @explicit_connection || auto_detect_connection
      DatabaseAdapters.wrap(raw)
    end

    def resolve_flavor
      return @explicit_flavor if @explicit_flavor
      return Config::VALID_DATABASE_FLAVORS.first unless @adapter

      name = @adapter.adapter_name
      KNOWN_ADAPTERS.fetch(name.to_s, DEFAULT_FLAVOR)
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
        "explicitly to an object that responds to `execute(sql, params)` (or pass " \
        "a PG::Connection, Mysql2::Client, Sequel::Database, or ActiveRecord adapter)."
    end
  end
end
