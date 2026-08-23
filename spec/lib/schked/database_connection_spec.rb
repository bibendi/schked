# frozen_string_literal: true

require "spec_helper"

describe Schked::DatabaseConnection do
  describe ".detect" do
    let(:mysql2_double) do
      Class.new do
        def self.adapter_name
          "Mysql2"
        end

        def self.execute(_sql, _params = [])
          1
        end
      end
    end

    let(:pg_double) do
      Class.new do
        def self.adapter_name
          "PostgreSQL"
        end

        def self.execute(_sql, _params = [])
          []
        end
      end
    end

    context "when an explicit connection is provided" do
      let(:adapter) { Schked::DatabaseAdapters::Passthrough.new(double(adapter_name: "PostgreSQL", execute: [])) }

      it "wraps the explicit connection and exposes the adapter" do
        result = described_class.detect(connection: adapter.connection)
        expect(result.adapter.connection).to be adapter.connection
      end

      it "respects an explicit flavor" do
        result = described_class.detect(connection: adapter.connection, flavor: :mysql)
        expect(result.flavor).to eq :mysql
      end
    end

    context "when no connection is available" do
      it "raises a clear NotFoundError" do
        expect(defined?(ActiveRecord)).to be_nil
        expect(defined?(Sequel)).to be_nil

        expect { described_class.detect }.to raise_error(Schked::DatabaseConnection::NotFoundError, /connection/)
      end
    end

    context "when adapter_name is unknown" do
      let(:adapter) { Schked::DatabaseAdapters::Passthrough.new(double(adapter_name: "MysteryDB", execute: [])) }

      it "defaults to :postgres flavor" do
        result = described_class.detect(connection: adapter.connection)
        expect(result.flavor).to eq :postgres
      end
    end

    context "when the underlying adapter is Mysql2" do
      it "auto-detects :mysql flavor via the wrapped adapter's adapter_name" do
        result = described_class.detect(connection: mysql2_double)
        expect(result.flavor).to eq :mysql
      end
    end

    context "when the underlying adapter is Postgres" do
      it "auto-detects :postgres flavor via the wrapped adapter's adapter_name" do
        result = described_class.detect(connection: pg_double)
        expect(result.flavor).to eq :postgres
      end
    end
  end
end
