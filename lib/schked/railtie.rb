# frozen_string_literal: true

require "rails/railtie"

module Schked
  class Railtie < Rails::Railtie
    initializer "schked.paths" do |app|
      Schked.paths << app.root.join("config", "schedule.rb")
    end
  end
end
