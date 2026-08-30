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

  describe "#dedup_enabled?" do
    it "is false by default" do
      expect(config.dedup_enabled?).to be false
    end

    it "is true when job_run_store is set to :redis" do
      config.job_run_store = :redis
      expect(config.dedup_enabled?).to be true
    end

    it "is true when job_run_store is set to :database" do
      config.job_run_store = :database
      expect(config.dedup_enabled?).to be true
    end

    it "is true when job_run_store is a custom object" do
      custom = Object.new
      config.job_run_store = custom
      expect(config.dedup_enabled?).to be true
    end
  end

  describe "#max_skew" do
    it "defaults to 60" do
      expect(config.max_skew).to eq 60
    end

    it "can be overridden" do
      config.max_skew = 120
      expect(config.max_skew).to eq 120
    end
  end

  describe "#database_connection" do
    it "is nil by default" do
      expect(config.database_connection).to be_nil
    end

    it "can be set to an object" do
      conn = Object.new
      config.database_connection = conn
      expect(config.database_connection).to be conn
    end
  end

  describe "#validate!" do
    it "passes for default configuration" do
      expect { config.validate! }.not_to raise_error
    end

    it "passes for :redis job_run_store" do
      config.job_run_store = :redis
      expect { config.validate! }.not_to raise_error
    end

    it "passes for :database job_run_store" do
      config.job_run_store = :database
      expect { config.validate! }.not_to raise_error
    end

    it "passes for a custom object responding to claim/cleanup" do
      custom = double(claim: true, cleanup: nil)
      config.job_run_store = custom
      expect { config.validate! }.not_to raise_error
    end

    it "raises for an invalid symbol job_run_store" do
      config.job_run_store = :something_invalid
      expect { config.validate! }.to raise_error(ArgumentError, /job_run_store/)
    end

    it "raises for an object that doesn't respond to claim" do
      config.job_run_store = Object.new
      expect { config.validate! }.to raise_error(ArgumentError, /job_run_store/)
    end
  end
end
