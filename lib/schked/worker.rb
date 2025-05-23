# frozen_string_literal: true

require "rufus/scheduler"

module Schked
  class Worker
    def initialize(config:)
      @config = config

      @locker = RedisLocker.new(config.redis, lock_ttl: 40_000, logger: config.logger) unless config.standalone?

      @scheduler = Rufus::Scheduler.new(trigger_lock: locker)

      watch_signals
      define_callbacks
      define_extend_lock unless config.standalone?
      load_schedule
    end

    def job(as)
      scheduler.jobs.find { |job| job.opts[:as] == as }
    end

    def pause
      scheduler.pause
    end

    def wait
      scheduler.join
    end

    def stop
      scheduler.stop
    end

    def schedule
      config
        .paths
        .map { |path| File.expand_path(path) }
        .uniq
        .map { |path| File.read(path) }
        .join("\n")
    end

    private

    attr_reader :config, :scheduler, :locker

    def define_callbacks
      cfg = config

      scheduler.define_singleton_method(:extract_job_name) do |job|
        if job
          job.opts[:as] || job.job_id
        else
          "unknown"
        end
      end

      scheduler.define_singleton_method(:on_error) do |job, error|
        cfg.logger.fatal("Task #{extract_job_name(job)} failed with error: #{error.message}")
        cfg.logger.error(error.backtrace.join("\n")) if error.backtrace

        cfg.fire_callback(:on_error, job, error)
      end

      scheduler.define_singleton_method(:on_pre_trigger) do |job, time|
        cfg.logger.info("Started task: #{extract_job_name(job)}")

        cfg.fire_callback(:before_start, job, time)
      end

      scheduler.define_singleton_method(:around_trigger) do |job, &block|
        cfg.fire_around_callback(:around_job, job, &block)
      end

      scheduler.define_singleton_method(:on_post_trigger) do |job, time|
        cfg.logger.info("Finished task: #{extract_job_name(job)}")

        cfg.fire_callback(:after_finish, job, time)
      end
    end

    def watch_signals
      Signal.trap("TERM") do
        config.logger.info("Going to shut down...")
        @shutdown = true
      end

      Signal.trap("INT") do
        config.logger.info("Going to shut down...")
        @shutdown = true
      end

      Thread.new do
        loop do
          scheduler.shutdown(wait: 5) if @shutdown
          sleep 1
        end
      end
    end

    def define_extend_lock
      scheduler.every("10s", as: "Schked::Worker#extend_lock", timeout: "5s", overlap: false) do
        locker.extend_lock
      end
    end

    def load_schedule
      scheduler.instance_eval(schedule)
    end
  end
end
