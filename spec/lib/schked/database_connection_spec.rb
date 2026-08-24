# frozen_string_literal: true

require "spec_helper"

describe Schked::DatabaseConnection do
  describe ".detect" do
    it "returns a known adapter instance unchanged" do
      adapter = Schked::Adapters::Pg.new(double("PG::Connection"))
      expect(described_class.detect(connection: adapter)).to be adapter
    end

    it "raises a clear NotFoundError for an unsupported connection" do
      expect { described_class.detect(connection: Object.new) }
        .to raise_error(Schked::DatabaseConnection::NotFoundError, /could not detect/)
    end
  end

  describe ".wrap" do
    it "wraps a PG::Connection into Schked::Adapters::Pg" do
      conn = double("PG::Connection")
      stub_const("PG::Connection", Class.new)
      allow(conn).to receive(:is_a?).with(PG::Connection).and_return(true)

      expect(described_class.wrap(conn)).to be_a(Schked::Adapters::Pg)
    end

    it "wraps a Mysql2::Client into Schked::Adapters::Mysql2" do
      client = double("Mysql2::Client")
      stub_const("Mysql2::Client", Class.new)
      allow(client).to receive(:is_a?).with(Mysql2::Client).and_return(true)

      expect(described_class.wrap(client)).to be_a(Schked::Adapters::Mysql2)
    end

    it "raises NotFoundError for an unknown connection" do
      expect { described_class.wrap(Object.new) }
        .to raise_error(Schked::DatabaseConnection::NotFoundError, /could not detect/)
    end
  end
end
