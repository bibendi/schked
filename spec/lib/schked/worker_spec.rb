# frozen_string_literal: true

require "spec_helper"
require "tempfile"

describe Schked::Worker do
  subject(:worker) { described_class.new(config: config) }

  let(:config) { Schked::Config.new }
  let(:logger) { instance_double(Logger).as_null_object }

  before do
    @taoe = Thread.abort_on_exception
    Thread.abort_on_exception = false

    config.logger = logger
  end

  after do
    Thread.abort_on_exception = @taoe
    worker.stop
  end

  describe "schedule" do
    it "loads schedules" do
      Tempfile.open("foo") do |foo|
        foo.write "every('100d') { puts 'foo' }"
        foo.flush

        config.paths << foo.path

        Tempfile.open("bar") do |bar|
          bar.write "every('200d') { puts 'bar' }"
          bar.flush

          config.paths << bar.path
          config.paths << bar.path # add duplicate path to ensure it will be ignored"

          expect(worker.schedule).to eq "every('100d') { puts 'foo' }\nevery('200d') { puts 'bar' }"
        end
      end
    end
  end

  describe "start" do
    it "starts rufus scheduler" do
      expect_any_instance_of(Rufus::Scheduler).to receive(:join)
      expect(Schked::RedisLocker).not_to receive(:new)
      expect_any_instance_of(described_class).not_to receive(:define_extend_lock)

      worker.wait
    end
  end

  describe "callbacks" do
    specify do
      counter = 0
      config.register_callback(:on_error) { counter += 1 }

      expect_any_instance_of(Schked::Worker)
        .to receive(:schedule)
        .and_return("self.in('0s', as: :test_task) { raise 'Boom' }")

      worker

      sleep 0.5

      expect(counter).to eq 1
      expect(logger).to have_received(:info).with(/Started task: test_task/)
      expect(logger).to have_received(:fatal).with(/Task test_task failed with error: Boom/)
      expect(logger).to have_received(:error)
      expect(logger).to have_received(:info).with(/Finished task: test_task/)
    end

    context "when there are no registered callbacks" do
      specify do
        allow_any_instance_of(Rufus::Scheduler).to receive(:logger).and_return(logger)
        expect_any_instance_of(Schked::Worker)
          .to receive(:schedule)
          .and_return("self.in('0s', as: :test_task) { logger.info('inside job') }")

        expect(logger).to receive(:info).with(/Started task: test_task/).ordered
        expect(logger).to receive(:info).with(/inside job/).ordered
        expect(logger).to receive(:info).with(/Finished task: test_task/).ordered

        worker

        sleep 0.5
      end
    end

    context "when there are registered around_job callbacks" do
      specify "single callback" do
        counter = 0
        config.register_callback(:around_job) do |_job, &block|
          logger.info("callback before")
          counter += 1
          block.call
          counter += 1
          logger.info("callback after")
        end

        allow_any_instance_of(Rufus::Scheduler).to receive(:logger).and_return(logger)
        expect_any_instance_of(Schked::Worker)
          .to receive(:schedule)
          .and_return("self.in('0s', as: :test_task) { logger.info('inside job') }")

        expect(logger).to receive(:info).with(/Started task: test_task/).ordered
        expect(logger).to receive(:info).with(/callback before/).ordered
        expect(logger).to receive(:info).with(/inside job/).ordered
        expect(logger).to receive(:info).with(/callback after/).ordered
        expect(logger).to receive(:info).with(/Finished task: test_task/).ordered

        worker

        sleep 0.5

        expect(counter).to eq 2
      end

      specify "multiple callbacks" do
        counter = 0

        config.register_callback(:around_job) do |_job, &block|
          logger.info("callback 1 before")
          counter += 1
          block.call
          counter += 1
          logger.info("callback 1 after")
        end

        config.register_callback(:around_job) do |_job, &block|
          logger.info("callback 2 before")
          counter += 1
          block.call
          counter += 1
          logger.info("callback 2 after")
        end

        allow_any_instance_of(Rufus::Scheduler).to receive(:logger).and_return(logger)
        expect_any_instance_of(Schked::Worker)
          .to receive(:schedule)
          .and_return("self.in('0s', as: :test_task) { logger.info('inside job') }")

        expect(logger).to receive(:info).with(/Started task: test_task/).ordered
        expect(logger).to receive(:info).with(/callback 1 before/).ordered
        expect(logger).to receive(:info).with(/callback 2 before/).ordered
        expect(logger).to receive(:info).with(/inside job/).ordered
        expect(logger).to receive(:info).with(/callback 2 after/).ordered
        expect(logger).to receive(:info).with(/callback 1 after/).ordered
        expect(logger).to receive(:info).with(/Finished task: test_task/).ordered

        worker

        sleep 0.5

        expect(counter).to eq 4
      end
    end

    context "when there are multiple around_job callbacks" do
      it "persists callbacks between jobs" do
        counter = 0
        config.register_callback(:around_job) do |job, &block|
          logger.info("callback before - #{job.opts[:as]}")
          counter += 1
          block.call
          counter += 1
          logger.info("callback after - #{job.opts[:as]}")
        end

        allow_any_instance_of(Rufus::Scheduler).to receive(:logger).and_return(logger)
        expect_any_instance_of(Schked::Worker)
          .to receive(:schedule)
          .and_return(
            "self.in('0s', as: :test_task_1) { logger.info('inside job 1') };" \
            "self.in('0.1s', as: :test_task_2) { logger.info('inside job 2') }"
          )

        expect(logger).to receive(:info).with(/Started task: test_task_1/).ordered
        expect(logger).to receive(:info).with(/callback before - test_task_1/).ordered
        expect(logger).to receive(:info).with(/inside job 1/).ordered
        expect(logger).to receive(:info).with(/callback after - test_task_1/).ordered
        expect(logger).to receive(:info).with(/Finished task: test_task_1/).ordered
        expect(logger).to receive(:info).with(/Started task: test_task_2/).ordered
        expect(logger).to receive(:info).with(/callback before - test_task_2/).ordered
        expect(logger).to receive(:info).with(/inside job 2/).ordered
        expect(logger).to receive(:info).with(/callback after - test_task_2/).ordered
        expect(logger).to receive(:info).with(/Finished task: test_task_2/).ordered

        worker

        sleep 0.5

        expect(counter).to eq 4
      end
    end
  end

  describe "when is not standalone" do
    let(:config) { Schked::Config.new.tap { |x| x.standalone = false } }

    it "starts rufus scheduler" do
      expect_any_instance_of(Rufus::Scheduler).to receive(:join)
      expect(Schked::RedisLocker).to receive(:new).and_call_original
      expect_any_instance_of(described_class).to receive(:define_extend_lock).and_call_original

      worker.wait
    end
  end
end
