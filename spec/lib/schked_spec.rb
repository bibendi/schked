# frozen_string_literal: true

describe Schked do
  it { expect(described_class.config).to be_a(Schked::Config) }

  it { expect(described_class.worker).to be_a(Schked::Worker) }
end
