# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require "bundler/setup"
require "pry-byebug"
require "combustion"

Combustion.initialize!

require "spec_helper"
