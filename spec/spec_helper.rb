# frozen_string_literal: true

ENV["RACK_ENV"] = "test"

require "bundler/setup"
require "schked"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.filter_run_when_matching :focus

  redis = RedisClient.new(url: ENV["REDIS_URL"])
  config.before(:each) do
    redis.call("FLUSHDB")
  end
end
