# frozen_string_literal: true

require "rails/railtie"

module Schked
  class Railtie < Rails::Railtie
    config.schked = ActiveSupport::OrderedOptions.new

    class PathsConfig
      def self.call(app)
        return if Schked.config.do_not_load_root_schedule?

        root_schedule = app.root.join("config", "schedule.rb")
        if root_schedule.exist?
          path = root_schedule.to_s
          Schked.config.paths << path unless Schked.config.paths.include?(path)
        end
      end
    end

    class LivenessConfig
      def self.call(app)
        liveness_probe = app.config.schked.liveness_probe
        Schked.config.liveness_probe = liveness_probe if liveness_probe
      end
    end

    initializer("schked.paths", &PathsConfig.method(:call))
    initializer("schked.liveness", after: :load_config_initializers) { |app| LivenessConfig.call(app) }

    config.to_prepare do
      Schked.config.logger = ::Rails.logger unless Schked.config.logger?
    end
  end
end
