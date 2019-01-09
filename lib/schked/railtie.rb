# frozen_string_literal: true

require "rails/railtie"

module Schked
  class Railtie < Rails::Railtie
    initializer "schked.paths" do |app|
      Schked.config.paths << app.root.join("config", "schedule.rb")
      Schked.config.logger = ::Rails.logger
    end
  end
end
