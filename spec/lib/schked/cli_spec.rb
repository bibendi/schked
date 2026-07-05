# frozen_string_literal: true

require "spec_helper"
require "schked/cli"

describe Schked::CLI do
  before do
    Schked.instance_variable_set(:@config, nil)
    Schked.instance_variable_set(:@worker, nil)
    allow(Schked).to receive(:worker).and_return(instance_double(Schked::Worker).as_null_object)
  end

  after do
    Schked.instance_variable_set(:@config, nil)
    Schked.instance_variable_set(:@worker, nil)
  end

  describe "start" do
    it "keeps the liveness probe disabled by default" do
      described_class.start(["start"])

      expect(Schked.config.liveness_probe.enabled).to be false
    end

    it "enables the liveness probe via --liveness-probe" do
      expect {
        described_class.start(["start", "--liveness-probe"])
      }.to change { Schked.config.liveness_probe.enabled }.from(false).to(true)
    end

    it "explicitly disables the liveness probe via --no-liveness-probe" do
      Schked.config.liveness_probe = {enabled: true}

      expect {
        described_class.start(["start", "--no-liveness-probe"])
      }.to change { Schked.config.liveness_probe.enabled }.from(true).to(false)
    end

    it "sets custom bind, port, and path" do
      described_class.start(["start", "--liveness-probe", "--liveness-bind", "127.0.0.1", "--liveness-port", "9090", "--liveness-path", "/ready"])

      expect(Schked.config.liveness_probe.enabled).to be true
      expect(Schked.config.liveness_probe.bind).to eq "127.0.0.1"
      expect(Schked.config.liveness_probe.port).to eq 9090
      expect(Schked.config.liveness_probe.path).to eq "/ready"
    end

    it "raises a clear error for an invalid port" do
      expect {
        described_class.start(["start", "--liveness-probe", "--liveness-port", "0"])
      }.to raise_error(ArgumentError, /port/)
    end
  end
end
