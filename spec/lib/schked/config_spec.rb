# frozen_string_literal: true

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
end
