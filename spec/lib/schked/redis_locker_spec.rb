# frozen_string_literal: true

require "spec_helper"

describe Schked::RedisLocker do
  let(:redis_servers) { [ENV["REDIS_URL"]] }
  subject { described_class.new(redis_servers) }

  describe "#lock" do
    it "locks" do
      expect(subject.lock).to be true
    end

    context "when is locked by someone else" do
      before do
        described_class.new(redis_servers).lock
      end

      it "fails to lock" do
        expect(subject.lock).to be false
      end
    end

    context "when is locked by us" do
      before do
        subject.lock
      end

      it "keeps locking" do
        expect(subject.lock).to be true
      end
    end
  end

  describe "#unlock" do
    context "when is locked by us" do
      before do
        subject.lock
      end

      it "unlocks" do
        expect { subject.unlock }.to change { subject.valid_lock? }.from(true).to(false)
      end
    end

    context "when is locked by someone else" do
      before do
        described_class.new(redis_servers).lock
      end

      it "fails to unlock" do
        expect { subject.unlock }.not_to change { subject.valid_lock? }.from(false)
      end
    end
  end

  describe "#extend_lock" do
    subject { described_class.new(redis_servers, lock_ttl: 1000) }

    context "when is locked by us" do
      it "extends lock" do
        subject.lock
        sleep 0.5
        expect(subject.extend_lock).to be true
        sleep 0.7
        expect(subject.valid_lock?).to be true
        sleep 0.5
        expect(subject.valid_lock?).to be false
      end
    end

    context "when is locked by someone else" do
      before do
        described_class.new(redis_servers, lock_ttl: 1000).lock
      end

      it "fails to extend" do
        expect(subject.extend_lock).to be false
      end
    end
  end
end
