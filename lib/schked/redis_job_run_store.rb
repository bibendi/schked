# frozen_string_literal: true

module Schked
  # Redis-backed implementation of the per-job coordination store.
  # Uses +SET key 1 NX EX <ttl>+ so the first caller wins and TTL handles
  # expiration; #cleanup is a no-op because native TTL covers retention.
  class RedisJobRunStore
    include JobRunStore

    KEY_PREFIX = "schked:job_run"

    attr_reader :redis_client, :logger, :max_skew_seconds

    def initialize(redis_client:, logger: Logger.new($stdout), max_skew_seconds: 60)
      @redis_client = redis_client
      @logger = logger
      @max_skew_seconds = Integer(max_skew_seconds)
    end

    def claim(job_name, window_start)
      validate!(job_name, window_start)

      key = build_key(job_name, window_start)
      ttl = @ttl || default_ttl

      # +SET ... NX EX+ returns "OK" if the key was created, +nil+ if it
      # already existed. Transport errors (connection refused, timeout, ...)
      # raise out of this method so the caller knows the store is unavailable
      # — silently returning +false+ would skip every job while Redis is down.
      redis_client.call("SET", key, "1", "NX", "EX", ttl) == "OK"
    end

    def cleanup(_older_than)
      # Native Redis TTL handles expiration; nothing to do here.
      nil
    end

    # Sets the TTL (seconds) used for subsequent claims. Intended for tests
    # that need to assert TTL behavior without waiting for the natural default.
    def ttl=(seconds)
      @ttl = Integer(seconds)
    end

    private

    def default_ttl
      # TTL must cover the longest possible interval between two firings
      # plus the maximum clock skew between instances, plus a safety buffer
      # so the claim key still exists when a slow instance polls it. The
      # store does not know the per-job interval, so we fall back to 1 day
      # as a safe default; callers running very long intervals should rely
      # on the database backend's explicit cleanup job.
      [2 * @max_skew_seconds + 3600, 86_400].max
    end

    def build_key(job_name, window_start)
      ts = window_start.is_a?(Time) ? window_start.to_i : Integer(window_start)
      "#{KEY_PREFIX}:#{job_name}:#{ts}"
    end

    def validate!(job_name, window_start)
      raise ArgumentError, "job_name must be a non-empty String" if job_name.to_s.empty?
      raise ArgumentError, "window_start must not be nil" if window_start.nil?
    end
  end
end
