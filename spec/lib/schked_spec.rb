# frozen_string_literal: true

require "tempfile"

describe Schked do
  describe ".schedule" do
    it "loads schedules" do
      Tempfile.open("foo") do |foo|
        foo.write "Foo"
        foo.flush

        described_class.config.paths << foo.path

        Tempfile.open("bar") do |bar|
          bar.write "Bar"
          bar.flush

          described_class.config.paths << bar.path

          expect(described_class.schedule).to eq "Foo\nBar"
        end
      end
    end
  end

  describe ".start" do
    it "starts rufus scheduler" do
      expect_any_instance_of(Rufus::Scheduler).to receive(:join)

      described_class.start
    end
  end
end
