# Architecture

## Lifecycle

1. **Initialization**
   - `Schked.worker` is built from the global `Schked.config`.
   - The worker reads every file listed in `config.paths`, concatenates their contents, and evaluates the result inside the rufus-scheduler instance. This is where recurring jobs are registered.
   - In non-standalone mode a `RedisLocker` is created and a background job is scheduled every 10 seconds to extend the distributed lock.
   - Signal traps for `TERM` and `INT` are installed; a watcher thread shuts the scheduler down gracefully when either signal is received.

2. **Steady state**
   - rufus-scheduler keeps its own thread pool and fires jobs according to their cron/every/in definitions.
   - The Redis lock is extended continuously so that, during a deployment, the old instance keeps ownership until it stops and the new instance can take over.
   - The scheduler blocks on `wait` (or `join`) until shutdown.

3. **Teardown**
   - A `TERM` or `INT` signal sets an internal shutdown flag.
   - The watcher thread calls `scheduler.shutdown(wait: 5)`, giving running jobs up to five seconds to finish.
   - The Redis lock is released automatically by Redlock when the client is shut down.

## Resource Management

- **Redis connections**: created once inside `RedisLocker`. In Redlock 2.x the connection is wrapped in a `ConnectionPool::Wrapper` backed by `redis-client`; in Redlock 1.x it is backed by the `redis` gem. The same connection is used for locking and for 10-second lock extensions.
- **Threads**: rufus-scheduler owns the worker threads that run jobs. Schked adds one watcher thread for signal-based shutdown and one internal scheduler job for lock extension. `before_start` and `after_finish` callbacks run in the scheduler thread; `around_job` callbacks run in the job's own thread.
- **Memory**: schedules are loaded as strings and evaluated once at boot. There is no hot-reload mechanism; to change a schedule you must restart the process.

## Concurrency Model

- Jobs can run concurrently unless explicitly prevented with rufus-scheduler options such as `overlap: false`.
- The distributed lock is **scheduler-wide**, not per-job. It guarantees that only one Schked process across the fleet is actively scheduling, but it does not serialize individual job execution.
- `before_start` and `after_finish` are scheduler-thread callbacks and must not block or perform long-running work.
- `around_job` wraps the actual job body and runs in the job thread, so it is safe to set request-local state there (for example, wrapping the job in a database transaction or a Sentry scope).

## Design Invariants

- Standalone mode defaults to `true` in test environments (`RAILS_ENV=test` or `RACK_ENV=test`) and `false` everywhere else. In standalone mode no Redis lock is used.
- The root schedule file (`config/schedule.rb`) is discovered automatically by the Rails railtie when it exists; other frameworks must add schedule paths manually.
- Schedule files are evaluated in the scheduler context, so they use rufus-scheduler DSL (`cron`, `every`, `in`) directly.
- The scheduler process is meant to run as a long-lived daemon. It is not designed for one-off script use.
