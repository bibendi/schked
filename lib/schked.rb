# frozen_string_literal: true

require "rufus/scheduler"

require "schked/config"
require "schked/version"
require "schked/railtie" if defined?(Rails)

module Schked
  module_function

  def config
    @config ||= Config.new
  end

  def schedule
    config.
      paths.
      map { |path| File.read(path) }.
      join("\n")
  end

  def start
    scheduler = Rufus::Scheduler.new
    scheduler.instance_eval(schedule)
    scheduler.join
  end
end
