# frozen_string_literal: true

require "spec_helper"

describe Schked::RedisJobRunStore do
  let(:redis_client) { RedisClient.new(url: ENV["REDIS_URL"]) }
  let(:logger) { Logger.new(File::NULL) }

  subject(:store) { described_class.new(redis_client: redis_client, logger: logger) }

  it_behaves_like "a job run store"

  describe "#claim" do
    it "stores the claim under schked:job_run:<job_name>:<window_start>" do
      window = Time.now.to_i
      store.claim("job_a", window)

      key = "schked:job_run:job_a:#{window}"
      expect(redis_client.call("EXISTS", key)).to eq 1
    end

    it "sets a TTL on the claim key sized for the contention window" do
      store.claim("job_a", Time.now.to_i)

      keys = redis_client.call("KEYS", "schked:job_run:*")
      expect(keys).not_to be_empty
      # max(10 * max_skew, 1h): covers contention across skewed instances
      # with a floor for one-shot at/in claims, without hoarding a day of
      # keys for high-frequency jobs.
      expect(redis_client.call("TTL", keys.first)).to eq 3600
    end

    it "scales the TTL with max_skew" do
      skewed = described_class.new(redis_client: redis_client, logger: logger, max_skew_seconds: 700)
      skewed.claim("job_a", Time.now.to_i)

      key = redis_client.call("KEYS", "schked:job_run:job_a:*").first
      expect(redis_client.call("TTL", key)).to eq 7000
    end

    it "raises when Redis is unreachable (so the worker can fail loudly instead of silently skipping every job)" do
      bad = RedisClient.new(url: "redis://127.0.0.1:1") # unreachable port
      bad_store = described_class.new(redis_client: bad, logger: logger)

      expect { bad_store.claim("job_a", Time.now.to_i) }.to raise_error(RedisClient::ConnectionError)
    end
  end

  describe "#cleanup" do
    it "is a no-op (relies on native TTL)" do
      store.claim("job_a", Time.now.to_i)
      expect { store.cleanup(Time.now.to_i) }.not_to raise_error
    end
  end
end
