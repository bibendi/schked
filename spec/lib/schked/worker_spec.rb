# frozen_string_literal: true

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

          expect(worker.schedule).to eq "every('100d') { puts 'foo' }\nevery('200d') { puts 'bar' }"
        end
      end
    end
  end

  describe "start" do
    it "starts rufus scheduler" do
      expect_any_instance_of(Rufus::Scheduler).to receive(:join)

      worker.wait
    end
  end

  describe "callbacks" do
    specify do
      counter = 0
      config.register_callback(:on_error) { counter += 1 }

      expect_any_instance_of(Schked::Worker).
        to receive(:schedule).
        and_return("self.in('0s', as: :test_task) { raise 'Boom' }")

      worker

      sleep 0.5

      expect(counter).to eq 1
      expect(logger).to have_received(:info).with(/Started task: test_task/)
      expect(logger).to have_received(:fatal).with(/Task test_task failed with error: Boom/)
      expect(logger).to have_received(:error)
      expect(logger).to have_received(:info).with(/Finished task: test_task/)
    end
  end
end
