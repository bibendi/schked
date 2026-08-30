# frozen_string_literal: true

# Shared contract examples for any coordination store. Both built-in backends
# (Redis and database) must satisfy this contract.
#
# The including context is expected to define `subject(:store)` (or expose a
# +store+ helper) so the examples can call +store.claim(...)+.
RSpec.shared_examples "a job run store" do
  describe "#claim" do
    it "returns true the first time an interval is claimed" do
      expect(store.claim("job_a", Time.now.to_i)).to be true
    end

    it "returns false when the same interval is already claimed" do
      window = Time.now.to_i
      expect(store.claim("job_a", window)).to be true
      expect(store.claim("job_a", window)).to be false
    end

    it "allows a different job in the same interval" do
      window = Time.now.to_i
      expect(store.claim("job_a", window)).to be true
      expect(store.claim("job_b", window)).to be true
    end

    it "allows the same job in a different interval" do
      expect(store.claim("job_a", Time.now.to_i)).to be true
      expect(store.claim("job_a", Time.now.to_i + 10)).to be true
    end

    it "requires a non-empty job name" do
      expect { store.claim("", Time.now.to_i) }.to raise_error(ArgumentError)
    end

    it "requires a non-nil window_start" do
      expect { store.claim("job_a", nil) }.to raise_error(ArgumentError)
    end
  end
end
