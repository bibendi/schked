# Configure Redis Locking

Why: production deployments usually start a new scheduler instance before stopping the old one, and Redis locking guarantees that only one instance fires jobs at a time.

When to use it: any production or multi-instance environment where duplicate job execution would cause problems.

Steps:
1. Ensure `Schked.config.standalone` is `false` (the default outside test environments).
2. Provide Redis configuration. Either set `REDIS_URL` in the environment or configure it explicitly:
   ```ruby
   Schked.config.redis = {url: ENV.fetch("REDIS_URL")}
   ```
3. For Redis Sentinel, pass the sentinel options through the same hash:
   ```ruby
   Schked.config.redis = {
     url: "redis://mymaster",
     sentinels: [{host: "sentinel-1", port: 26_379}, {host: "sentinel-2", port: 26_379}],
     sentinel_password: ENV.fetch("SENTINEL_PASSWORD", nil)
   }
   ```
4. Start the scheduler normally. It will acquire the lock, extend it every 10 seconds, and only run jobs while it owns the lock.

Common mistakes:
- Running with `standalone = true` in production. Both old and new deployment instances will then fire jobs.
- Pointing multiple unrelated applications at the same Redis database without changing the lock key. Schked uses a single lock key (`schked:redis_locker`), so separate apps need separate Redis databases or key prefixes.
- Letting the Redis connection become unreachable. The scheduler logs lock errors and skips job execution until the lock can be reacquired.

See also:
- Lock lifecycle: `architecture.md#lifecycle`
- Deprecated setter: `migration.md#deprecated-configuration`
