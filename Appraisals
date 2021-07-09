# frozen_string_literal: true

# Test without any framework
appraise "agnostic" do
end

# Test with latest Ruby on Rails
if RUBY_VERSION < "3"
  appraise "rails.5" do
    gem "rails", "~> 5"
  end
end

appraise "rails.6" do
  gem "rails", "~> 6"
end
