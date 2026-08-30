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
  gem "pg", "~> 1.5"
end

appraise "rails.7" do
  gem "rails", "~> 7"
  gem "bigdecimal"
  gem "mutex_m"
  gem "pg", "~> 1.5"
end

if RUBY_VERSION >= "3.2"
  appraise "rails.8" do
    gem "rails", "~> 8"
    gem "bigdecimal"
    gem "pg", "~> 1.5"
  end
end

appraise "redlock.1" do
  gem "redlock", "~> 1.3"
end

appraise "postgres" do
  gem "activerecord"
  gem "pg", "~> 1.5"
end

appraise "mysql" do
  gem "activerecord"
  gem "mysql2", "~> 0.5"
  gem "trilogy"
end

appraise "sequel" do
  gem "sequel", "~> 5.0"
  gem "pg", "~> 1.5"
  gem "mysql2", "~> 0.5"
end
