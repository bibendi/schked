# frozen_string_literal: true

require "thor"
require "shellwords"

module Schked
  class CLI < Thor
    def self.start(argv)
      if File.exist?(".schked")
        argv += File
          .read(".schked")
          .split("\n")
          .join(" ")
          .strip
          .shellsplit
      end

      super
    end

    def self.exit_on_failure?
      true
    end

    default_command :start

    desc "start", "Start scheduler"
    option :require, type: :array
    option :liveness_probe, type: :boolean, default: nil, desc: "Enable or disable the liveness probe"
    option :liveness_bind, type: :string, desc: "Address the liveness probe binds to"
    option :liveness_port, type: :numeric, desc: "Port the liveness probe listens on"
    option :liveness_path, type: :string, desc: "HTTP path for the liveness probe"
    def start
      load_requires
      apply_liveness_probe_options

      Schked.worker.wait
    end

    desc "show", "Output schedule to stdout"
    option :require, type: :array
    def show
      load_requires

      puts "====="
      puts Schked.worker.schedule
      puts "====="
    end

    private

    def load_requires
      options[:require].each { |file| load(File.join(Dir.pwd, file)) } if options[:require]&.any?

      # We have to load Schked at here, because of Rails and our railtie.
      require "schked"
    end

    def apply_liveness_probe_options
      overrides = {}
      overrides[:enabled] = options[:liveness_probe] unless options[:liveness_probe].nil?
      overrides[:bind] = options[:liveness_bind] if options[:liveness_bind]
      overrides[:port] = options[:liveness_port] if options[:liveness_port]
      overrides[:path] = options[:liveness_path] if options[:liveness_path]

      Schked.config.liveness_probe = Schked.config.liveness_probe.to_h.merge(overrides) if overrides.any?
    end
  end
end
