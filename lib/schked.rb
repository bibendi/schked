# frozen_string_literal: true

require "redlock"

require "schked/version"
require "schked/config"
require "schked/worker"
require "schked/redis_locker"
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
