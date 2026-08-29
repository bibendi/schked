# frozen_string_literal: true

require "connection_pool"
require "redlock"

require "schked/version"
require "schked/liveness_probe"
require "schked/config"
require "schked/job_run_store"
require "schked/redis_job_run_store"
require "schked/adapters/sequel"
require "schked/adapters/active_record"
require "schked/database_connection"
require "schked/schedule_dsl"
require "schked/callbacks"
require "schked/migration_generator"
require "schked/worker"
require "schked/redis_locker"
require "schked/redis_client_factory"
require "schked/railtie" if defined?(Rails)

module Schked
  module_function

  def config
    @config ||= Config.new
  end

  def worker
    @worker ||= Worker.new(config: config)
  end
end
