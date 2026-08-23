# frozen_string_literal: true

module Schked
  # Installs rufus-scheduler callbacks that translate rufus events into
  # schked semantics: per-job deduplication claims via the configured
  # +JobRunStore+, logging, and user-registered +Schked.config+ callbacks
  # (+:before_start+, +:after_finish+, +:on_error+, +:around_job+).
  #
  # Extracted from +Schked::Worker+ so the worker stays focused on
  # lifecycle and the callback wiring remains independently testable.
  class Callbacks
    # Marker prefix for schked's own internal jobs (cleanup, liveness
    # heartbeat). These are exempt from dedup claims.
    INTERNAL_JOB_PREFIX = "Schked::Worker#"

    def initialize(config:, job_run_store: nil)
      @config = config
      @job_run_store = job_run_store
    end

    def install(scheduler)
      cfg = @config
      store = @job_run_store
      internal = method(:internal_job?)

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
        job_name = extract_job_name(job).to_s

        if store && internal.call(job_name)
          # Internal schked jobs (cleanup sweep, liveness heartbeat) skip
          # the dedup claim entirely so they always run on every instance.
        elsif store
          unless job.opts[:as]
            # Without an explicit +as:+, the dedup key falls back to
            # +job.job_id+, which encodes the Ruby +object_id+ of the
            # +Rufus::Scheduler::Job+ and is unique per process. Claiming
            # with that key would silently duplicate every run across the
            # cluster. Refuse to claim; the operator must add +as:+ to
            # their schedule for dedup to be correct.
            cfg.logger.error(
              "Task #{job_name} has no `as:` label and cannot be deduplicated " \
              "(each process generates a unique job_id). Add `as: \"my_job\"` to " \
              "the schedule entry. Skipping this firing."
            )
            next false
          end

          window_start = job.previous_time || job.scheduled_at
          claimed = store.claim(job_name, window_start)
          unless claimed
            cfg.logger.info("Skipped task: #{job_name} (already claimed for window_start=#{window_start.to_i})")
            next false
          end
        end

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

      scheduler
    end

    def internal_job?(job_name)
      job_name.start_with?(INTERNAL_JOB_PREFIX)
    end
  end
end
