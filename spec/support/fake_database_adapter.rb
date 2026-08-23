# frozen_string_literal: true

# Lightweight stand-in for a database-backed coordination store adapter used
# by the agnostic test suite (which does not depend on pg/mysql2). It
# satisfies the +DatabaseAdapters::Base+ contract:
# +execute(sql, params) -> 1+ (claim wins) / [] (claim conflicts).
#
# Tracks +INSERT INTO schked_job_runs+ by +(job_name, window_start)+ so a
# second claim for the same key loses — mirroring the UNIQUE constraint.
class FakeDatabaseAdapter < Schked::DatabaseAdapters::Base
  attr_reader :queries, :adapter_name

  def initialize(adapter_name: "PostgreSQL")
    super(nil)
    @adapter_name = adapter_name
    @queries = []
    @claims = {}
  end

  def execute(sql, params = [])
    @queries << {sql: sql, params: params}

    if sql.include?("INSERT INTO schked_job_runs")
      key = [params[0], params[1]]

      if @claims.key?(key)
        conflict_result(sql)
      else
        @claims[key] = true
        win_result(sql)
      end
    else
      []
    end
  end

  private

  def conflict_result(sql)
    if sql.include?("ON CONFLICT")
      []
    elsif sql.include?("ON DUPLICATE KEY")
      0
    else
      []
    end
  end

  def win_result(sql)
    if sql.include?("ON CONFLICT")
      [{id: @claims.size}]
    elsif sql.include?("ON DUPLICATE KEY")
      1
    else
      []
    end
  end
end
