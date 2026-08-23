# frozen_string_literal: true

require "spec_helper"

describe Schked::MigrationGenerator do
  describe ".sql" do
    it "returns Postgres DDL by default" do
      sql = described_class.sql
      expect(sql).to include("CREATE TABLE schked_job_runs")
      expect(sql).to include("BIGSERIAL")
      expect(sql).to include("UNIQUE")
    end

    it "returns Postgres DDL when flavor is 'postgres'" do
      sql = described_class.sql("postgres")
      expect(sql).to include("BIGSERIAL")
    end

    it "returns MySQL DDL when flavor is 'mysql'" do
      sql = described_class.sql("mysql")
      expect(sql).to include("AUTO_INCREMENT")
      expect(sql).to include("UNIQUE KEY")
    end

    it "is case-insensitive for the flavor" do
      expect(described_class.sql("MYSQL")).to include("UNIQUE KEY")
      expect(described_class.sql("Postgres")).to include("BIGSERIAL")
    end

    it "always includes a unique index on (job_name, window_start)" do
      expect(described_class.sql("postgres")).to include("UNIQUE (job_name, window_start)")
      expect(described_class.sql("mysql")).to include("UNIQUE KEY schked_job_runs_unique (job_name, window_start)")
    end
  end
end
