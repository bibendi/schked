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

  describe "#liveness_probe" do
    it "returns default config" do
      expect(config.liveness_probe).to be_a(Schked::LivenessProbeConfig)
      expect(config.liveness_probe.enabled).to be false
      expect(config.liveness_probe.bind).to eq "0.0.0.0"
      expect(config.liveness_probe.port).to eq 8080
      expect(config.liveness_probe.path).to eq "/healthz"
    end

    it "accepts a hash assignment" do
      config.liveness_probe = {enabled: true, bind: "127.0.0.1", port: 9090, path: "/ready"}

      expect(config.liveness_probe.enabled).to be true
      expect(config.liveness_probe.bind).to eq "127.0.0.1"
      expect(config.liveness_probe.port).to eq 9090
      expect(config.liveness_probe.path).to eq "/ready"
    end

    it "accepts a LivenessProbeConfig instance" do
      probe_config = Schked::LivenessProbeConfig.new(enabled: true, port: 9091)
      config.liveness_probe = probe_config

      expect(config.liveness_probe).to eq probe_config
    end

    it "raises for invalid values" do
      expect { config.liveness_probe = {port: 0} }
        .to raise_error(ArgumentError, /port/)
    end
  end
end
