[![Gem Version](https://badge.fury.io/rb/schked.svg)](https://badge.fury.io/rb/schked)
[![Build Status](https://travis-ci.org/bibendi/schked.svg?branch=master)](https://travis-ci.org/bibendi/schked)

# Schked

Framework agnostic [Rufus-scheduler](https://github.com/jmettraux/rufus-scheduler) wrapper to run recurring jobs.

<a href="https://evilmartians.com/?utm_source=schked">
<img src="https://evilmartians.com/badges/sponsored-by-evil-martians.svg" alt="Sponsored by Evil Martians" width="236" height="54"></a>

## Installation

Add this line to your application's Gemfile:

```ruby
gem "schked"
```

And then execute:

```sh
bundle
```

Or install it yourself as:

```sh
gem install schked
```

## Supported Ruby and Rails versions

Schked requires **Ruby 3.0+**.

The test matrix covers Ruby **3.0, 3.1, 3.2, 3.3, 3.4, and 4.0**. Rails integration tests run on every Ruby; Rails 8 is only included on Ruby **3.2+**.

## Usage

### Ruby on Rails

.schked

```
--require config/environment.rb
```

config/schedule.rb

```ruby
cron "*/30 * * * *", as: "CleanOrphanAttachmentsJob", timeout: "60s", overlap: false do
  CleanOrphanAttachmentsJob.perform_later
end
```

If you have a Rails engine with own schedule:

engine-path/lib/foo/engine.rb

```ruby
module Foo
  class Engine < ::Rails::Engine
    initializer "foo" do |app|
      Schked.config.paths << root.join("config", "schedule.rb")
    end
  end
end
```

And run Schked:

```sh
bundle exec schked start
```

To show schedule:

```sh
bundle exec schked show
```

### Duplicate scheduling

Schked ships two coordination strategies for multi-instance deployments. Choose one via `Schked.config.job_run_store`:

#### Single-active-instance (default)

When you deploy your schedule to production, you want to start new instance before you shut down the current. And you don't want simultaneous working of both. To achieve a seamless transition, Schked uses Redis for a global lock.

You can configure Redis client as the following:

```ruby
Schked.config.redis = {url: ENV.fetch("REDIS_URL") }
```

This is the default — one instance runs all jobs; standby instances hold the global Redis lock and stay idle. This strategy will continue to be supported because it is the simplest and most predictable for many setups.

#### Per-job deduplication

When you want every scheduler instance to do useful work (and not require a global leader), opt into the per-job deduplication mode. Each recurring job claims its schedule interval atomically; only one instance wins each interval, so each job still runs exactly once across the cluster.

Pick a coordination store:

```ruby
# Redis-backed (default Redis client from Schked.config.redis):
Schked.config.job_run_store = :redis

# Database-backed (no Redis required). The ActiveRecord or Sequel
# connection pool is auto-detected; override via:
Schked.config.job_run_store = :database
Schked.config.database_connection = conn   # optional: Sequel::Database, ActiveRecord pool, or AR connection (PostgreSQL, Mysql2, or Trilogy)

# Custom store responding to #claim(job_name, window_start) and #cleanup(older_than):
Schked.config.job_run_store = my_store
```

The database backend runs entirely through the ActiveRecord/Sequel connection pool: claims and the internal cleanup sweep check connections out per operation, so they are thread-safe and survive database restarts and failovers. MySQL 8.0+ is required for the MySQL DDL.

Additional tuning:

```ruby
Schked.config.max_skew = 60  # max expected clock skew between instances (seconds)
```

Schedule behavior in deduplication mode:

- `every` jobs are aligned to an absolute time grid so all instances share the same phase. The first firing is the next grid point relative to now — not relative to process start.
- `cron` jobs already align to absolute time natively and need no change.
- `at` / `in` (one-time) jobs are deduplicated too — the claim is kept for the store's retention period (the Redis TTL / the database sweep window).
- `interval` jobs **are not supported** and raise `Schked::ScheduleDSL::IntervalNotSupportedError` when scheduled in this mode. Their phase depends on job duration and cannot be grid-aligned. Use `every` or `cron` instead.

##### Durability of the coordination store

Choosing between `:redis` and `:database` is also choosing how strong the exactly-once guarantee is:

- **`:database`** — claims are durable rows guarded by a UNIQUE constraint. They survive database restarts and failovers, and nothing removes them before the internal cleanup sweep (which keeps rows for 24 hours). Prefer this backend when a duplicate run is unacceptable.
- **`:redis`** — claims are keys with a TTL of `max(10 × max_skew, 1 hour)`, so the guarantee is only as strong as the Redis instance's durability:
  - **Eviction policy** must be `noeviction` (or the instance must never reach `maxmemory`). Claim keys have a TTL, so both `allkeys-*` and `volatile-*` policies can evict them under memory pressure — the evicted window may then be claimed and executed by another instance.
  - **Persistence**: a Redis restart without AOF/RDB loses in-flight claims. If it happens inside the contention window (the `max_skew`-wide interval during which instances race to claim the same slot), the job may run twice. Enable AOF, or use `:database` if you cannot accept that risk.

Failure semantics (both backends):

- The claim is taken **before** the job runs, so the semantics are *at-most-once per window*: if the winning instance crashes mid-run, that window's execution is lost and Schked does not retry it.
- The coordination store is a hard dependency: when it is unreachable, the claim fails and the firing is skipped (fail-closed) rather than risking a duplicate.

##### Database store migration

Run the migration generator to print the `schked_job_runs` DDL:

```sh
bundle exec schked generate-migration               # Postgres
bundle exec schked generate-migration --flavor=mysql
```

Copy the SQL into your application's migration and run it. The gem does not write migration files or run DDL on its own — it stays framework-agnostic.

### Callbacks

Also, you can define callbacks for errors handling:

config/initializers/schked.rb

```ruby
Schked.config.register_callback(:on_error) do |job, error|
  Raven.capture_exception(error) if defined?(Raven)
end
```

There are `:before_start`, `:after_finish` and `:around_job` callbacks as well.

Warning: `:before_start` and `:after_finish` callbacks are executed in the scheduler thread, not in the work threads (the threads where the job execution really happens).

`:around_job` callback is executed in the job's thread.

```ruby
Schked.config.register_callback(:around_job) do |job, &block|
  ...
  block.call
  ...
end
```

### Logging

By default Schked writes logs into stdout. In Rails environment Schked is using application logger. You can change it like this:

config/initializers/schked.rb

```ruby
Schked.config.logger = Logger.new(Rails.root.join("log", "schked.log"))
```

### Liveness probe

Schked can expose a small HTTP endpoint for Kubernetes liveness probes. It is **disabled by default** to keep the existing behavior unchanged.

Configure it in Ruby:

```ruby
Schked.config.liveness_probe = {
  enabled: true,
  bind: "0.0.0.0",
  port: 8080,
  path: "/healthz",
  heartbeat_interval: 5,
  heartbeat_threshold: 15
}
```

Or via CLI flags:

```sh
bundle exec schked start --liveness-probe --liveness-bind 0.0.0.0 --liveness-port 8080 --liveness-path /healthz
```

In Rails, set it through the application config:

```ruby
# config/application.rb or config/environments/*.rb
config.schked.liveness_probe = {
  enabled: true,
  bind: "0.0.0.0",
  port: 8080,
  path: "/healthz",
  heartbeat_interval: 5,
  heartbeat_threshold: 15
}
```

The endpoint returns `200 OK` while the scheduler is responsive and `503 Service Unavailable` when the heartbeat is stale or during shutdown. The scheduler updates the heartbeat every `heartbeat_interval` seconds (default `5`); if it is not updated within `heartbeat_threshold` seconds (default `15`), the endpoint reports unhealthy. Use it in Kubernetes like this:

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10
```

### Monitoring

[Yabeda::Schked](https://github.com/yabeda-rb/yabeda-schked) - built-in metrics for monitoring Schked recurring jobs out of the box! Part of the [yabeda](https://github.com/yabeda-rb/yabeda) suite.

### Testing

```ruby
describe Schked do
  let(:worker) { described_class.worker.tap(&:pause) }

  around do |ex|
    Time.use_zone("UTC") { Timecop.travel(start_time, &ex) }
  end

  describe "CleanOrphanAttachmentsJob" do
    let(:start_time) { Time.zone.local(2008, 9, 1, 10, 42, 21) }
    let(:job) { worker.job("CleanOrphanAttachmentsJob") }

    specify do
      expect(job.next_time.to_local_time)
        .to eq Time.zone.local(2008, 9, 1, 11, 0, 0)
    end

    it "enqueues job" do
      expect { job.call(false) }
        .to have_enqueued_job(CleanOrphanAttachmentsJob)
    end
  end
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/bibendi/schked. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Schked project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/schked/blob/master/CODE_OF_CONDUCT.md).
