# frozen_string_literal: true

module Schked
  class RedisLocker
    attr_reader :lock_manager,
      :lock_id,
      :lock_ttl

    LOCK_KEY = "schked:redis_locker"
    LOCK_TTL = 60_000 # ms

    def initialize(redis_servers, lock_ttl: LOCK_TTL)
      @lock_manager = Redlock::Client.new(redis_servers, retry_count: 0)
      @lock_ttl = lock_ttl
    end

    def lock
      valid_lock? || !!try_lock
    end

    def unlock
      lock_manager.unlock(lock_id) if valid_lock?
    end

    def extend_lock
      return false unless valid_lock?

      @lock_id = lock_manager.lock(LOCK_KEY, lock_ttl, extend: lock_id, extend_only_if_locked: true)

      !!@lock_id
    end

    def valid_lock?
      return false unless lock_id

      lock_manager.valid_lock?(lock_id)
    end

    private

    def try_lock
      @lock_id = lock_manager.lock(LOCK_KEY, lock_ttl)
    end
  end
end
