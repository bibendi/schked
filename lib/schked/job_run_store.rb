# frozen_string_literal: true

module Schked
  # Abstract interface for the per-job coordination store used by the
  # deduplication mode. A store records which `(job_name, window_start)` pairs
  # have been claimed, so two scheduler instances cannot execute the same job
  # in the same interval.
  #
  # Two built-in backends are provided: Redis (see +RedisJobRunStore+) and
  # database (see +DatabaseJobRunStore+). An operator may also supply any
  # custom object that responds to +#claim+ and +#cleanup+.
  module JobRunStore
    # Atomically records that +job_name+ was claimed for the interval starting
    # at +window_start+ (a Time/Integer epoch).
    #
    # Returns +true+ if this caller won the claim (the job may run) and +false+
    # if the interval is already claimed by another instance (the job must be
    # skipped). Raises +ArgumentError+ for invalid arguments.
    def claim(job_name, window_start)
      raise NotImplementedError, "#{self.class} must implement #claim(job_name, window_start)"
    end

    # Removes records whose window_start is older than +older_than+. The
    # Redis backend relies on native TTL and provides a no-op; the database
    # backend deletes matching rows.
    def cleanup(older_than)
      raise NotImplementedError, "#{self.class} must implement #cleanup(older_than)"
    end

    # Returns the natural TTL (in seconds) the backend should use for a job
    # with the given interval. Backends may override; defaults to
    # +interval + max_skew + buffer+.
    def ttl_for(interval_seconds, max_skew_seconds, buffer_seconds: 60)
      interval_seconds.to_i + max_skew_seconds.to_i + buffer_seconds.to_i
    end
  end
end
