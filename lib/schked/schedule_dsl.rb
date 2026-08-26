# frozen_string_literal: true

require "rufus/scheduler"

module Schked
  # Wraps the rufus-scheduler DSL so deduplication mode (+job_run_store+ is
  # configured) makes +every+ jobs grid-aligned (via injected +first_at+) and
  # rejects +interval+ jobs (their phase drifts with job duration and cannot
  # be deduplicated).
  #
  # In the default (non-dedup) mode the wrapper is transparent and forwards
  # every call to the underlying scheduler.
  class ScheduleDSL
    class IntervalNotSupportedError < StandardError; end

    attr_reader :scheduler

    def initialize(scheduler:, dedup_enabled:, max_skew_seconds: 60)
      @scheduler = scheduler
      @dedup_enabled = dedup_enabled
      @max_skew_seconds = Integer(max_skew_seconds)
    end

    def respond_to_missing?(name, include_private = false)
      @scheduler.respond_to?(name, include_private) || super
    end

    def method_missing(name, *args, **kwargs, &block)
      case name
      when :every
        every_with_alignment(*args, **kwargs, &block)
      when :interval
        raise IntervalNotSupportedError, interval_error_message if @dedup_enabled

        @scheduler.interval(*args, **kwargs, &block)
      else
        @scheduler.public_send(name, *args, **kwargs, &block)
      end
    end

    private

    def every_with_alignment(duration, *args, **kwargs, &block)
      if @dedup_enabled
        seconds = Rufus::Scheduler.parse_duration(duration)
        # Shift "now" backward by +max_skew+ so that two instances whose
        # clocks differ by up to +max_skew+ still land on the same grid
        # point. Without this shift, an instance that is half a skew
        # ahead could pick a different slot than one that is half a skew
        # behind, and both would claim the job.
        first_at = Time.at(next_grid_point_epoch(seconds, Time.now.to_f - @max_skew_seconds))
        # In dedup mode any user-supplied +first_at:+ is intentionally
        # overridden — the grid alignment is required for exactly-once.
        kwargs = kwargs.merge(first_at: first_at)
      end

      @scheduler.every(duration, *args, **kwargs, &block)
    end

    def next_grid_point_epoch(seconds, shifted_now)
      grid_point = (shifted_now / seconds).ceil * seconds
      # When the interval is comparable to or smaller than +max_skew+, the
      # grid point closest to "now − max_skew" may still lie in the past,
      # and rufus-scheduler rejects a past +first_at+. Advance by whole
      # periods until the slot is strictly in the future: every step keeps
      # the value on the absolute (epoch-multiple) grid, so all instances
      # stay phase-aligned regardless of how many steps they take.
      grid_point += seconds while grid_point <= Time.now.to_f
      grid_point
    end

    def interval_error_message
      "`interval` jobs are not supported when `Schked.config.job_run_store` is configured. " \
        "Their phase depends on job duration and cannot be aligned to a stable grid. " \
        "Use `every` or `cron` instead."
    end
  end
end
