# Handle Job Errors

Why: recurring jobs run in the background, and uncaught exceptions need to be reported to an external system such as Sentry, Bugsnag, or Rails logs.

When to use it: whenever you want centralized error tracking for scheduled jobs.

Steps:
1. Register an `:on_error` callback during initialization:
   ```ruby
   Schked.config.register_callback(:on_error) do |job, error|
     # job is the rufus-scheduler job object; error is the exception
     Raven.capture_exception(error) if defined?(Raven)
   end
   ```
2. The callback receives the job object and the raised error. Use `job.opts[:as]` to identify the job by name.
3. Schked already logs fatal/error messages with the backtrace before firing the callback, so the callback can focus on reporting rather than logging.

Common mistakes:
- Raising another exception inside the `:on_error` callback. This can destabilize the scheduler thread.
- Performing slow work in `:on_error`. The callback runs in the scheduler thread, so keep it short.

See also:
- Threading rules: `architecture.md#concurrency-model`
- Wrapping jobs with context: `recipes/wrap-job-execution.md`
