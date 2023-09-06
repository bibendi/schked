# frozen_string_literal: true

module Schked
  class RedisLocker
    attr_reader :lock_manager,
      :lock_id,
      :lock_ttl,
      :logger

    LOCK_KEY = "schked:redis_locker"
    LOCK_TTL = 60_000 # ms

    def initialize(redis_conf, lock_ttl: LOCK_TTL, logger: Logger.new($stdout))
      @lock_manager = Redlock::Client.new([redis_client(redis_conf)], retry_count: 0)
      @lock_ttl = lock_ttl
      @logger = logger
    end

    def lock
      valid_lock? || !!try_lock
    rescue => e
      logger.error("Failed to acquire a lock with error: #{e.message}")
      false
    end

    def unlock
      lock_manager.unlock(lock_id) if valid_lock?
    rescue => e
      logger.error("Failed to release the lock with error: #{e.message}")
      false
    end

    def extend_lock
      return false unless valid_lock?

      @lock_id = lock_manager.lock(LOCK_KEY, lock_ttl, extend: lock_id, extend_only_if_locked: true)

      !!@lock_id
    rescue => e
      logger.error("Failed to extend the lock with error: #{e.message}")
      false
    end

    def valid_lock?
      return false unless lock_id

      lock_manager.valid_lock?(lock_id)
    end

    private

    def redis_client(redis_conf)
      if Gem::Version.new(Redlock::VERSION) >= Gem::Version.new("2.0.0")
        ConnectionPool::Wrapper.new { RedisClientFactory.build(redis_conf) }
      else
        ConnectionPool::Wrapper.new { Redis.new(**redis_conf) }
      end
    end

    def try_lock
      @lock_id = lock_manager.lock(LOCK_KEY, lock_ttl)
    end
  end
end
