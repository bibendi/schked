# frozen_string_literal: true

require "tempfile"

describe Schked do
  before { described_class.paths.clear }

  describe ".paths" do
    it "appends files" do
      described_class.paths << "foo"
      described_class.paths << "bar"

      expect(described_class.paths).to eq %w[foo bar]
    end
  end

  describe ".schedule" do
    it "loads schedules" do
      Tempfile.open("foo") do |foo|
        foo.write "Foo"
        foo.flush

        described_class.paths << foo.path

        Tempfile.open("bar") do |bar|
          bar.write "Bar"
          bar.flush

          described_class.paths << bar.path

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
