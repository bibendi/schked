# frozen_string_literal: true

require "spec_helper"

describe Schked::ScheduleDSL do
  let(:scheduler) { Rufus::Scheduler.new }
  let(:logger) { Logger.new(File::NULL) }

  after { scheduler.shutdown(wait: false) }

  describe "dedup disabled (default)" do
    subject(:dsl) { described_class.new(scheduler: scheduler, dedup_enabled: false) }

    it "forwards `every` calls without modification" do
      dsl.instance_eval { every("100d", as: "noop") {} }

      job = scheduler.jobs.find { |j| j.opts[:as] == "noop" }
      expect(job).not_to be_nil
      expect(job.first_at).to be_nil
    end

    it "allows `interval` calls" do
      dsl.instance_eval { interval("100s", as: "interval_job") {} }

      job = scheduler.jobs.find { |j| j.opts[:as] == "interval_job" }
      expect(job).not_to be_nil
    end
  end

  describe "dedup enabled" do
    subject(:dsl) { described_class.new(scheduler: scheduler, dedup_enabled: true, max_skew_seconds: 60) }

    it "injects aligned first_at into `every` jobs" do
      dsl.instance_eval { every("6m", as: "grid_aligned") {} }

      job = scheduler.jobs.find { |j| j.opts[:as] == "grid_aligned" }
      expect(job).not_to be_nil
      expect(job.first_at).not_to be_nil

      now = Time.now.to_f
      first_at = job.first_at.to_f
      # rufus-scheduler rejects a past +first_at+, so the slot must be
      # strictly in the future...
      expect(first_at).to be > now
      # ...and land on the absolute grid (multiples of the interval),
      # which is what keeps instances phase-aligned despite clock skew.
      expect(first_at % (6 * 60)).to be_within(0.001).of(0)
    end

    it "keeps sub-skew intervals strictly in the future" do
      # Regression: intervals comparable to or smaller than +max_skew+ used to
      # resolve to a slot in the past, making rufus raise
      # `ArgumentError: cannot set first[_at|_in] in the past` during boot.
      25.times do |i|
        expect {
          dsl.instance_eval { every("30s", as: "sub_skew_#{i}") {} }
        }.not_to raise_error

        job = scheduler.jobs.find { |j| j.opts[:as] == "sub_skew_#{i}" }
        expect(job.first_at.to_f).to be > Time.now.to_f - 1
        expect(job.first_at.to_i % 30).to be_within(0.001).of(0)
      end
    end

    it "overrides a user-supplied first_at: in dedup mode, with a warning" do
      dsl_logger = instance_double(Logger).as_null_object
      warned_dsl = described_class.new(scheduler: scheduler, dedup_enabled: true, max_skew_seconds: 60, logger: dsl_logger)

      expect(dsl_logger).to receive(:warn).with(/ignoring `first_at:/)

      warned_dsl.instance_eval do
        every("6m", first_at: Time.now + 3600, as: "user_first_at") {}
      end

      job = scheduler.jobs.find { |j| j.opts[:as] == "user_first_at" }
      # The user-supplied first_at is intentionally overwritten with the
      # grid-aligned value — documented in ScheduleDSL.
      expect(job.first_at.to_i % 360).to be_within(1.0).of(0)
    end

    it "rejects `interval` jobs with a clear error" do
      expect {
        dsl.instance_eval { interval("5s", as: "interval_job") {} }
      }.to raise_error(Schked::ScheduleDSL::IntervalNotSupportedError, /interval/)
    end

    it "forwards `cron` calls without modification" do
      dsl.instance_eval { cron("0 * * * *", as: "cron_job") {} }

      job = scheduler.jobs.find { |j| j.opts[:as] == "cron_job" }
      expect(job).not_to be_nil
      expect(job).to be_a(Rufus::Scheduler::CronJob)
    end

    it "forwards `at` calls for one-time jobs" do
      dsl.instance_eval { at(Time.now + 60, as: "onetime") {} }

      job = scheduler.jobs.find { |j| j.opts[:as] == "onetime" }
      expect(job).not_to be_nil
    end
  end
end
