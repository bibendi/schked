# Wrap Job Execution

Why: `around_job` callbacks let you set up and tear down context around every job body, such as request stores, database transactions, or tracing spans.

When to use it: when jobs need shared setup/teardown that must run in the same thread as the job itself.

Steps:
1. Register one or more `:around_job` callbacks:
   ```ruby
   Schked.config.register_callback(:around_job) do |job, &block|
     Rails.logger.tagged(job.opts[:as]) do
       block.call
     end
   end
   ```
2. Always call `block.call` to execute the job. Multiple callbacks are nested in registration order.
3. Keep the setup/teardown lightweight so job scheduling is not delayed.

Common mistakes:
- Forgetting to call `block.call`. The job will not run.
- Assuming `around_job` runs in the scheduler thread. It runs in the job thread, which is correct for request-local state but means you cannot rely on scheduler-thread state.
- Adding long-running cleanup that exceeds the shutdown grace period.

See also:
- Threading rules: `architecture.md#concurrency-model`
- Error handling: `recipes/handle-job-errors.md`
