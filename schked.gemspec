# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "schked/version"

Gem::Specification.new do |s|
  s.name = "schked"
  s.version = Schked::VERSION
  s.authors = ["bibendi@evilmartians.com"]
  s.summary = "Ruby Scheduler"
  s.description = "Rufus-scheduler wrapper to run recurring jobs"

  s.files = Dir["{exe,lib}/**/*", "Rakefile"]
  s.bindir = "exe"
  s.executables = s.files.grep(%r{^exe/}) { |f| File.basename(f) }

  s.add_dependency "rufus-scheduler", "~> 3.0"
  s.add_dependency "thor"

  s.add_development_dependency "appraisal", "~> 2.2"
  s.add_development_dependency "bundler", ">= 1.16"
  s.add_development_dependency "combustion", "~> 1.1"
  s.add_development_dependency "pry-byebug", "~> 3.4"
  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "rspec", "~> 3.0"
  s.add_development_dependency "rubocop", "~> 0.60"
  s.add_development_dependency "rubocop-rspec"
  s.add_development_dependency "standard", "~> 0.4.2"
end
