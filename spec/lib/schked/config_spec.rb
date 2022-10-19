# frozen_string_literal: true

require "spec_helper"

describe Schked::Config do
  subject(:config) { described_class.new }

  describe "#paths" do
    it "appends files" do
      config.paths << "foo"
      config.paths << "bar"

      expect(config.paths).to eq %w[foo bar]
    end
  end

  it { expect(config.logger).to be_a(Logger) }

  it { expect(config).to be_standalone }

  context "when RACK_ENV=production" do
    it "is not standalone" do
      old_val = ENV["RACK_ENV"]
      ENV["RACK_ENV"] = "production"
      expect(config).not_to be_standalone
      ENV["RACK_ENV"] = old_val
    end
  end
end
