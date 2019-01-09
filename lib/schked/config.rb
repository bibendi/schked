# frozen_string_literal: true

require "logger"

module Schked
  class Config
    attr_writer :logger

    def paths
      @paths ||= []
    end
  end
end
