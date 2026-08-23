# frozen_string_literal: true

require "spec_helper"

describe Schked::Callbacks do
  let(:config) { Schked::Config.new }
  let(:logger) { instance_double(Logger).as_null_object }

  before { config.logger = logger }

  describe "#install" do
    it "returns the scheduler after installing callbacks" do
      scheduler = Rufus::Scheduler.new
      result = described_class.new(config: config).install(scheduler)
      expect(result).to be scheduler
      scheduler.shutdown(wait: false)
    end

    it "is a no-op for store claims when no store is configured" do
      scheduler = Rufus::Scheduler.new
      described_class.new(config: config, job_run_store: nil).install(scheduler)
      expect(scheduler).to respond_to(:on_pre_trigger)
      expect(scheduler).to respond_to(:on_post_trigger)
      expect(scheduler).to respond_to(:on_error)
      expect(scheduler).to respond_to(:around_trigger)
      scheduler.shutdown(wait: false)
    end

    context "with a job_run_store" do
      let(:store) { instance_double(Schked::RedisJobRunStore, claim: true, cleanup: nil) }

      it "calls store.claim before on_pre_trigger fires the body" do
        scheduler = Rufus::Scheduler.new
        described_class.new(config: config, job_run_store: store).install(scheduler)

        body_called = false
        scheduler.in("0s", as: :claim_test) { body_called = true }
        sleep 0.3

        expect(body_called).to be true
        expect(store).to have_received(:claim).with("claim_test", anything)
        scheduler.shutdown(wait: false)
      end

      it "skips the job body when store.claim returns false" do
        allow(store).to receive(:claim).and_return(false)
        scheduler = Rufus::Scheduler.new
        described_class.new(config: config, job_run_store: store).install(scheduler)

        body_called = false
        scheduler.in("0s", as: :skip_test) { body_called = true }
        sleep 0.3

        expect(body_called).to be false
        expect(logger).to have_received(:info).with(/Skipped task: skip_test/)
        scheduler.shutdown(wait: false)
      end

      it "coerces symbol job names to strings" do
        scheduler = Rufus::Scheduler.new
        described_class.new(config: config, job_run_store: store).install(scheduler)

        scheduler.in("0s", as: :sym_job) {}
        sleep 0.3

        expect(store).to have_received(:claim).with("sym_job", anything)
        scheduler.shutdown(wait: false)
      end

      it "skips and logs an error when a job has no `as:` label" do
        scheduler = Rufus::Scheduler.new
        described_class.new(config: config, job_run_store: store).install(scheduler)

        body_called = false
        # Schedule WITHOUT `as:` — without that, job.job_id is per-process
        # and would silently duplicate the job across instances.
        scheduler.in("0s") { body_called = true }
        sleep 0.3

        expect(body_called).to be false
        expect(logger).to have_received(:error).with(/no `as:` label/)
        expect(store).not_to have_received(:claim)
        scheduler.shutdown(wait: false)
      end

      it "does not claim for internal Schked::Worker#* jobs" do
        scheduler = Rufus::Scheduler.new
        described_class.new(config: config, job_run_store: store).install(scheduler)

        body_called = false
        scheduler.in("0s", as: "Schked::Worker#cleanup_job_runs") { body_called = true }
        sleep 0.3

        expect(body_called).to be true
        expect(store).not_to have_received(:claim)
        scheduler.shutdown(wait: false)
      end
    end
  end
end
