# frozen_string_literal: true

require "logger"

module Schked
  class Config
    attr_writer :logger

    def paths
      @paths ||= []
    end

    def logger?
      !!@logger
    end

    def logger
      @logger ||= Logger.new(STDOUT).tap { |l| l.level = Logger::INFO }
    end

    def register_callback(name, &block)
      callbacks[name] << block
    end

    def fire_callback(name, *args)
      callbacks[name].each do |callback|
        callback.call(*args)
      end
    end

    private

    def callbacks
      @callbacks ||= Hash.new { |hsh, key| hsh[key] = [] }
    end
  end
end
