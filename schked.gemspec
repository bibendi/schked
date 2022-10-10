# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "schked/version"

Gem::Specification.new do |s|
  s.name = "schked"
  s.version = Schked::VERSION
  s.authors = ["Misha Merkushin"]
  s.email = ["merkushin.m.s@gmail.com"]
  s.summary = "Ruby Scheduler"
  s.description = "Rufus-scheduler wrapper to run recurring jobs"
  s.homepage = "https://github.com/bibendi/schked"
  s.license = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if s.respond_to?(:metadata)
    s.metadata["allowed_push_host"] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  s.files = Dir.glob("{exe,lib}/**/*") + %w[LICENSE.txt README.md]
  s.bindir = "exe"
  s.executables = s.files.grep(%r{^exe/}) { |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.required_ruby_version = "> 2.5"

  s.add_dependency "redlock"
  s.add_dependency "rufus-scheduler", "~> 3.0"
  s.add_dependency "thor"

  s.add_development_dependency "appraisal", "~> 2.2"
  s.add_development_dependency "bundler", ">= 1.16"
  s.add_development_dependency "combustion", "~> 1.3"
  s.add_development_dependency "pry-byebug", "~> 3.9"
  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "rspec", "~> 3.9"
  s.add_development_dependency "standard", "~> 0.4"
end
