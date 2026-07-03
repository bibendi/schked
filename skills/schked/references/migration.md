# Migration

## Deprecated configuration

### `redis_servers=` is deprecated

The old `Schked.config.redis_servers = [...]` setter is deprecated. Replace it with the `redis=` hash:

```ruby
# Old
Schked.config.redis_servers = [ENV.fetch("REDIS_URL")]

# New
Schked.config.redis = {url: ENV.fetch("REDIS_URL")}
```

The new option accepts any hash that `redis-client` understands, including `url`, `username`, `password`, and sentinel configuration.

## Redlock version differences

Schked supports Redlock 1.x and 2.x. The behavior you see depends on the version resolved by Bundler:

- **Redlock 2.x**: uses `redis-client` via `ConnectionPool::Wrapper`.
- **Redlock 1.x**: uses the `redis` gem via `ConnectionPool::Wrapper`.

You do not need to change application code when moving between supported Redlock versions, but the Redis connection gem in your bundle will change, so verify monitoring and connection-pool tuning accordingly.

## Rollback options

- The scheduler itself is stateless except for the in-memory rufus-scheduler state and the Redis lock. Rolling back the gem version only requires stopping the process, changing the Gemfile, and starting a new process.
- If a bad schedule file is deployed, the scheduler process will fail to boot. Roll back the schedule file and restart; the scheduler does not hot-reload.
