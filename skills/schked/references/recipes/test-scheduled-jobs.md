# Test Scheduled Jobs

Why: tests should verify job scheduling and behavior without waiting for real time or running the scheduler continuously.

When to use it: in RSpec (or another test framework) when you need to assert that a job is scheduled correctly and enqueues the expected work.

Steps:
1. Pause the worker so background firing does not interfere:
   ```ruby
   let(:worker) { described_class.worker.tap(&:pause) }
   ```
2. Find the job by the name given in `as:`:
   ```ruby
   let(:job) { worker.job("CleanOrphanAttachmentsJob") }
   ```
3. Assert the next scheduled time:
   ```ruby
   specify do
     expect(job.next_time.to_local_time)
       .to eq Time.zone.local(2008, 9, 1, 11, 0, 0)
   end
   ```
4. Trigger the job body synchronously with `call(false)` and assert side effects:
   ```ruby
   it "enqueues job" do
     expect { job.call(false) }
       .to have_enqueued_job(CleanOrphanAttachmentsJob)
   end
   ```

Common mistakes:
- Calling `job.call` without pausing the worker. Background jobs can fire unexpectedly during assertions.
- Forgetting that the test environment defaults to `standalone = true`, so Redis locking is bypassed. This is usually desirable for tests.
- Hard-coding times without controlling `Time.zone` or Timecop.

See also:
- Standalone mode default: `architecture.md#design-invariants`
- Lifecycle: `architecture.md#lifecycle`
