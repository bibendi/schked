# frozen_string_literal: true

require "rufus/scheduler"

module Schked
  class Worker
    DEFAULT_CLEANUP_INTERVAL = "60s"
    DEFAULT_CLEANUP_RETENTION = 24 * 60 * 60 # seconds before cutoff

    def initialize(config:)
      @config = config
      @liveness_probe = nil

      config.validate!
      @job_run_store = build_job_run_store
      @locker = build_locker

      scheduler_opts = {trigger_lock: locker}.compact
      @scheduler = Rufus::Scheduler.new(**scheduler_opts)

      watch_signals
      Callbacks.new(config: config, job_run_store: @job_run_store).install(@scheduler)
      define_extend_lock if locker
      define_cleanup_job if database_backed_store?
      load_schedule
      start_liveness_probe
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
      liveness_probe&.stop
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

    attr_reader :config, :scheduler, :locker, :liveness_probe, :job_run_store

    def build_job_run_store
      return nil unless config.dedup_enabled?

      case config.job_run_store
      when :redis
        RedisJobRunStore.new(
          redis_client: RedisClientFactory.build(config.redis),
          logger: config.logger,
          max_skew_seconds: config.max_skew
        )
      when :database
        DatabaseConnection.detect(
          connection: config.database_connection,
          logger: config.logger
        )
      else
        config.job_run_store
      end
    end

    def build_locker
      return nil if config.standalone?
      return nil if config.dedup_enabled?

      RedisLocker.new(config.redis, lock_ttl: 40_000, logger: config.logger)
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
          if @shutdown
            liveness_probe&.stop
            scheduler.shutdown(wait: 5)
          end
          sleep 1
        end
      end
    end

    def define_extend_lock
      scheduler.every("10s", as: "Schked::Worker#extend_lock", timeout: "5s", overlap: false) do
        locker.extend_lock
      end
    end

    def define_cleanup_job
      store = @job_run_store
      logger = config.logger

      scheduler.every(DEFAULT_CLEANUP_INTERVAL, as: "Schked::Worker#cleanup_job_runs", overlap: false) do
        cutoff = Time.now.to_i - (DEFAULT_CLEANUP_RETENTION + config.max_skew)
        logger.info("Cleaning up database job runs older than #{cutoff}")
        store.cleanup(cutoff)
      rescue => e
        logger.error("Failed to clean up database job runs: #{e.message}")
      end
    end

    # Only stores whose +#cleanup+ actually deletes rows need the sweep.
    # +RedisJobRunStore#cleanup+ is a no-op (native TTL handles retention),
    # so scheduling it would just log noise on every instance. Custom
    # stores keep the sweep because they implemented +#cleanup+ for it.
    def database_backed_store?
      !@job_run_store.is_a?(RedisJobRunStore)
    end

    def load_schedule
      dsl = ScheduleDSL.new(
        scheduler: scheduler,
        dedup_enabled: config.dedup_enabled?,
        max_skew_seconds: config.max_skew
      )
      dsl.instance_eval(schedule)
    end

    def start_liveness_probe
      return unless config.liveness_probe.enabled

      @liveness_probe = LivenessProbe.new(config: config.liveness_probe, logger: config.logger)
      @liveness_probe.start

      scheduler.every("#{config.liveness_probe.heartbeat_interval}s", as: "Schked::Worker#liveness_heartbeat", overlap: false) do
        @liveness_probe.heartbeat
      end

      @liveness_probe.heartbeat
    end
  end
end
