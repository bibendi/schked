# frozen_string_literal: true

require "thor"
require "shellwords"

module Schked
  class CLI < Thor
    def self.start(argv)
      if File.exist?(".schked")
        argv += File.
          read(".schked").
          split("\n").
          join(" ").
          strip.
          shellsplit
      end

      super(argv)
    end

    def self.exit_on_failure?
      true
    end

    default_command :start

    desc "start", "Start scheduler"
    option :require, type: :array
    def start
      load_requires

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
      if options[:require]&.any?
        options[:require].each { |file| require(File.join(Dir.pwd, file)) }
      end

      # We have to load Schked at here, because of Rails and our railtie.
      require "schked"
    end
  end
end
