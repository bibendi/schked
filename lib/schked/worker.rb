# frozen_string_literal: true

require "rufus/scheduler"

module Schked
  class Worker
    def initialize(config:)
      @config = config

      @scheduler = Rufus::Scheduler.new

      define_callbacks
      load_schedule
    end

    def wait
      scheduler.join
    end

    def stop
      scheduler.stop
    end

    def schedule
      config.
        paths.
        map { |path| File.read(path) }.
        join("\n")
    end

    private

    attr_reader :config, :scheduler

    def define_callbacks
      cfg = config

      scheduler.define_singleton_method(:on_error) do |job, error|
        cfg.logger.fatal("Task #{job.opts[:as] || job.job_id} failed with error: #{error.message}")
        cfg.logger.error(error.backtrace.join("\n")) if error.backtrace

        cfg.fire_callback(:on_error, job, error)
      end

      scheduler.define_singleton_method(:on_pre_trigger) do |job, time|
        cfg.logger.info("Started task: #{job.opts[:as] || job.job_id}")

        cfg.fire_callback(:before_start, job, time)
      end

      scheduler.define_singleton_method(:on_post_trigger) do |job, time|
        cfg.logger.info("Finished task: #{job.opts[:as] || job.job_id}")

        cfg.fire_callback(:after_finish, job, time)
      end
    end

    def load_schedule
      scheduler.instance_eval(schedule)
    end
  end
end
