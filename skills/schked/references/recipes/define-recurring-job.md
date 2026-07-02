# Define a Recurring Job

Why: schedule files are the only place where recurring jobs are declared, and they are evaluated once when the scheduler boots.

When to use it: any time you need a job to run repeatedly based on cron syntax, an interval, or a one-off delay.

Steps:
1. Create or open the schedule file (commonly `config/schedule.rb`).
2. Declare a job using rufus-scheduler syntax and give it a stable name with `as:`:
   ```ruby
   cron "*/30 * * * *", as: "CleanOrphanAttachmentsJob", timeout: "60s", overlap: false do
     CleanOrphanAttachmentsJob.perform_later
   end
   ```
3. Make sure the schedule file is in `Schked.config.paths`. In Rails this happens automatically; otherwise add it manually before the worker starts.
4. Restart the scheduler. Schked does not hot-reload schedule files.

Common mistakes:
- Omitting `as:` makes the job harder to identify in logs and tests.
- Forgetting `overlap: false` when the job must not run concurrently with itself.
- Referencing application constants that are not loaded yet. In Rails, use Active Job or lazily resolve constants inside the block.

See also:
- Runtime constraints: `architecture.md#lifecycle`
- Threading rules for callbacks: `architecture.md#concurrency-model`
- Testing the job definition: `recipes/test-scheduled-jobs.md`
