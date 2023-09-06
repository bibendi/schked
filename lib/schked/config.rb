# frozen_string_literal: true

require "logger"

module Schked
  class Config
    attr_writer :logger,
      :do_not_load_root_schedule,
      :redis,
      :standalone

    def paths
      @paths ||= []
    end

    def logger?
      !!@logger
    end

    def logger
      @logger ||= Logger.new($stdout).tap { |l| l.level = Logger::INFO }
    end

    def do_not_load_root_schedule?
      !!@do_not_load_root_schedule
    end

    def register_callback(name, &block)
      callbacks[name] << block
    end

    def fire_callback(name, *args)
      callbacks[name].each do |callback|
        callback.call(*args)
      end
    end

    def fire_around_callback(name, job, calls = callbacks[name], &block)
      return yield if calls.none?

      calls.first.call(job) do
        calls = calls.drop(1)
        if calls.any?
          fire_around_callback(name, job, calls, &block)
        else
          yield
        end
      end
    end

    def redis
      @redis ||= {url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379")}
    end

    def redis_servers=(val)
      val = val.first

      if val.is_a?(String)
        self.redis = {url: val}
      elsif val.respond_to?(:_client)
        conf = val._client.config
        self.redis = {url: conf.server_url, username: conf.username, password: conf.password}
      else
        raise ArgumentError, "Schked `redis_servers=` config option is deprecated. Please use `redis=` with a Hash"
      end

      warn "🔥 Schked `redis_servers=` config option is deprecated. Please use `redis=` with a Hash. Called from #{caller(1..1).first}"
    end

    def standalone?
      @standalone = ENV["RAILS_ENV"] == "test" || ENV["RACK_ENV"] == "test" if @standalone.nil?

      !!@standalone
    end

    private

    def callbacks
      @callbacks ||= Hash.new { |hsh, key| hsh[key] = [] }
    end
  end
end
