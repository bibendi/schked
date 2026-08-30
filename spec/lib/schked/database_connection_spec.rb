# frozen_string_literal: true

require "spec_helper"

# A minimal duck-typed AR pool: responds to #with_connection for real.
class FakeARPool
  def initialize(connection)
    @connection = connection
  end

  def with_connection(&block)
    block.call(@connection)
  end
end

# A minimal duck-typed AR adapter connection: responds to #pool and
# #adapter_name for real, and not to #with_connection.
class FakeARConnection
  attr_reader :pool

  def initialize(pool)
    @pool = pool
  end

  def adapter_name
    "PostgreSQL"
  end
end

describe Schked::DatabaseConnection do
  let(:logger) { Logger.new(File::NULL) }

  describe ".detect" do
    it "returns a known adapter instance unchanged" do
      adapter = Schked::Adapters::Sequel.new(double("Sequel::Database", database_type: :postgres))
      expect(described_class.detect(connection: adapter, logger: logger)).to be adapter
    end

    it "raises a clear NotFoundError for an unsupported connection" do
      expect { described_class.detect(connection: Object.new, logger: logger) }
        .to raise_error(Schked::DatabaseConnection::NotFoundError, /could not detect/)
    end
  end

  describe ".wrap" do
    it "wraps a Sequel::Database into Schked::Adapters::Sequel" do
      stub_const("Sequel::Database", Class.new)
      database = double("Sequel::Database", database_type: :postgres)
      allow(database).to receive(:is_a?).with(Sequel::Database).and_return(true)

      expect(described_class.wrap(database, logger: logger)).to be_a(Schked::Adapters::Sequel)
    end

    it "wraps an ActiveRecord connection pool into Schked::Adapters::ActiveRecord" do
      connection = double("AR::Connection", adapter_name: "PostgreSQL")
      pool = FakeARPool.new(connection)

      expect(described_class.wrap(pool, logger: logger)).to be_a(Schked::Adapters::ActiveRecord)
    end

    it "normalizes a concrete AR connection to its pool" do
      connection = double("AR::Connection", adapter_name: "Mysql2")
      pool = FakeARPool.new(connection)
      concrete = FakeARConnection.new(pool)

      expect(described_class.wrap(concrete, logger: logger)).to be_a(Schked::Adapters::ActiveRecord)
    end

    it "raises NotFoundError for an unknown connection" do
      expect { described_class.wrap(Object.new, logger: logger) }
        .to raise_error(Schked::DatabaseConnection::NotFoundError, /could not detect/)
    end
  end
end
