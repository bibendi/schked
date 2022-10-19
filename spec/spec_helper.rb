# frozen_string_literal: true

ENV["RACK_ENV"] = "test"

require "bundler/setup"
require "pry-byebug"
require "schked"
require "redis"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.filter_run_when_matching :focus

  config.before(:each) do
    Redis.new(url: ENV["REDIS_URL"]).flushdb
  end
end
