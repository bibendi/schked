# frozen_string_literal: true

require "redis-client"

module Schked
  module RedisClientFactory
    def self.build(options)
      unless options.key?(:reconnect_attempts)
        options[:reconnect_attempts] = 3
      end

      if options.key?(:sentinels)
        if (url = options.delete(:url))
          uri = URI.parse(url)
          if !options.key?(:name) && uri.host
            options[:name] = uri.host
          end

          if !options.key?(:password) && uri.password && !uri.password.empty?
            options[:password] = uri.password
          end

          if !options.key?(:username) && uri.user && !uri.user.empty?
            options[:username] = uri.user
          end
        end

        RedisClient.sentinel(**options).new_client
      else
        RedisClient.config(**options).new_client
      end
    end
  end
end
