# frozen_string_literal: true

require "logger"

module Schked
  class Config
    VALID_JOB_RUN_STORES = %i[redis database].freeze

    attr_writer :logger,
      :do_not_load_root_schedule,
      :redis,
      :standalone,
      :job_run_store,
      :max_skew,
      :database_connection

    def liveness_probe
      @liveness_probe ||= LivenessProbeConfig.new
    end

    def liveness_probe=(value)
      @liveness_probe = value.is_a?(LivenessProbeConfig) ? value : LivenessProbeConfig.new(value)
    end

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

    attr_reader :job_run_store

    def max_skew
      @max_skew ||= 60
    end

    attr_reader :database_connection

    def dedup_enabled?
      !@job_run_store.nil?
    end

    # Validates all configuration options. Called by the worker during
    # initialization so the worker can remain agnostic about which options
    # exist and which combinations are legal.
    def validate!
      validate_job_run_store!
    end

    private

    def validate_job_run_store!
      return if @job_run_store.nil?

      message = "Schked `job_run_store` must be one of #{VALID_JOB_RUN_STORES.inspect}, " \
        "a Symbol, or an object responding to #claim and #cleanup; got: #{@job_run_store.inspect}"

      valid = if @job_run_store.is_a?(Symbol)
        VALID_JOB_RUN_STORES.include?(@job_run_store)
      else
        @job_run_store.respond_to?(:claim) && @job_run_store.respond_to?(:cleanup)
      end

      raise ArgumentError, message unless valid
    end

    def callbacks
      @callbacks ||= Hash.new { |hsh, key| hsh[key] = [] }
    end
  end
end
