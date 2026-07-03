# Run the Scheduler

Why: Schked is a long-lived process; it must be started, monitored, and stopped correctly.

When to use it: when starting the scheduler manually, writing a service definition, or deploying to production.

Steps:
1. Make sure schedule paths and Redis are configured before the worker starts (see `initialization.md`).
2. Start the scheduler from the project root:
   ```sh
   bundle exec schked start
   ```
3. The CLI reads `.schked` in the current directory for default flags. For Rails, that file should contain `--require config/environment.rb`.
4. Stop the process with `TERM` or `INT`. The scheduler waits up to 5 seconds for running jobs before exiting.
5. To preview the concatenated schedule without running it:
   ```sh
   bundle exec schked show
   ```

Common mistakes:
- Starting the scheduler without configuring Redis in production. It will run in standalone mode and may duplicate work across instances.
- Sending `KILL` before `TERM`. Running jobs are aborted immediately and the Redis lock may not be released cleanly.
- Running multiple scheduler processes on the same machine in development without understanding that the Redis lock (or its absence) controls which instance fires.

See also:
- Lifecycle and shutdown: `architecture.md#lifecycle`
- Rails integration: `recipes/integrate-with-rails.md`
- Redis locking: `recipes/configure-redis-locking.md`
