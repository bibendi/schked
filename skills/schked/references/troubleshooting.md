# Troubleshooting

| Error / Symptom | Root Cause | Fix |
|---|---|---|
| Two scheduler instances fire the same job at the same time | Redis locking is disabled or misconfigured; or `standalone` is `true` in production. | Set `Schked.config.standalone = false` and configure `Schked.config.redis` with a shared Redis URL. |
| `bundle exec schked start` exits immediately | The schedule file could not be loaded, or `Schked.worker` raised during initialization. | Check the backtrace, verify every path in `Schked.config.paths` exists, and ensure referenced constants are loadable. |
| `bundle exec schked show` prints an empty schedule | No schedule paths are registered, or `config/schedule.rb` is missing. | In Rails, confirm the railtie loaded; otherwise add the path manually before starting the worker. |
| Jobs stop firing after a Redis failover | The scheduler lost the distributed lock and cannot reacquire it. | Verify Redis is reachable and that the lock key is not being held stale by a zombie process. |
| `:on_error` callback is never called | The job did not actually raise; or the callback itself raises and aborts the scheduler thread. | Add a deliberate `raise` in a test job, and keep the callback short and exception-free. |
| `:around_job` callback runs but the job body does not | `block.call` was omitted. | Always call `block.call` inside an `:around_job` callback. |
| `before_start` callback blocks subsequent jobs | Long-running code was placed in the scheduler thread. | Move heavy setup into `:around_job` or directly into the job body. |
| Cannot acquire Redis lock warnings in logs | Redis is unreachable, the lock is held by another instance, or Redlock cannot talk to the configured server. | Check `REDIS_URL`, network connectivity, and that all instances use the same Redis database. |
| Changes to `config/schedule.rb` have no effect | Schked evaluates schedule files only at boot. | Restart the scheduler process after editing the schedule. |
