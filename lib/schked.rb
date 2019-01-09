# frozen_string_literal: true

require "rufus/scheduler"

require "schked/version"
require "schked/railtie" if defined?(Rails)

module Schked
  module_function

  def paths
    @paths ||= []
  end

  def schedule
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
