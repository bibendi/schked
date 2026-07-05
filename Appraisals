# frozen_string_literal: true

# Test without any framework
appraise "agnostic" do
end

# Test with latest Ruby on Rails
appraise "rails.6" do
  gem "rails", "~> 6"
  gem "benchmark"
  gem "bigdecimal"
  gem "mutex_m"
  gem "tsort"
end

appraise "rails.7" do
  gem "rails", "~> 7"
  gem "bigdecimal"
  gem "mutex_m"
end

appraise "rails.8" do
  gem "rails", "~> 8"
  gem "bigdecimal"
end

appraise "redlock.1" do
  gem "redlock", "~> 1.3"
end
