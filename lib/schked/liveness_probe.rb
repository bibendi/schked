# frozen_string_literal: true

require "socket"
require "ipaddr"

module Schked
  class LivenessProbeConfig
    attr_reader :enabled, :bind, :port, :path, :heartbeat_interval, :heartbeat_threshold

    DEFAULTS = {
      enabled: false,
      bind: "0.0.0.0",
      port: 8080,
      path: "/healthz",
      heartbeat_interval: 5,
      heartbeat_threshold: 15
    }.freeze

    def initialize(attrs = {})
      attrs = DEFAULTS.merge(attrs)

      @enabled = !!attrs[:enabled]
      @bind = validate_bind(attrs[:bind])
      @port = validate_port(attrs[:port])
      @path = validate_path(attrs[:path])
      @heartbeat_interval = validate_positive_integer(attrs[:heartbeat_interval], :heartbeat_interval)
      @heartbeat_threshold = validate_threshold(attrs[:heartbeat_threshold], attrs[:heartbeat_interval])
    end

    def to_h
      {
        enabled: enabled,
        bind: bind,
        port: port,
        path: path,
        heartbeat_interval: heartbeat_interval,
        heartbeat_threshold: heartbeat_threshold
      }
    end

    private

    def validate_bind(value)
      value = value.to_s
      raise ArgumentError, "Schked liveness_probe `bind` must be non-empty" if value.empty?

      IPAddr.new(value)
      value
    rescue IPAddr::InvalidAddressError
      raise ArgumentError, "Schked liveness_probe `bind` is invalid: #{value}"
    end

    def validate_port(value)
      port = Integer(value)
      raise ArgumentError, "Schked liveness_probe `port` must be between 1 and 65535, got: #{port}" unless port.between?(1, 65_535)

      port
    rescue ArgumentError, TypeError
      raise ArgumentError, "Schked liveness_probe `port` must be an integer between 1 and 65535, got: #{value.inspect}"
    end

    def validate_path(value)
      value = value.to_s
      raise ArgumentError, "Schked liveness_probe `path` must start with /, got: #{value}" unless value.start_with?("/")

      value
    end

    def validate_positive_integer(value, name)
      int = Integer(value)
      raise ArgumentError, "Schked liveness_probe `#{name}` must be a positive integer, got: #{int}" unless int.positive?

      int
    rescue ArgumentError, TypeError
      raise ArgumentError, "Schked liveness_probe `#{name}` must be a positive integer, got: #{value.inspect}"
    end

    def validate_threshold(value, interval)
      int = validate_positive_integer(value, :heartbeat_threshold)
      interval = validate_positive_integer(interval, :heartbeat_interval)
      raise ArgumentError, "Schked liveness_probe `heartbeat_threshold` must be >= heartbeat_interval" if int < interval

      int
    end
  end

  class LivenessProbe
    attr_reader :config, :logger

    def initialize(config:, logger:)
      @config = config
      @logger = logger
      @last_heartbeat_at = nil
      @shutting_down = false
      @server = nil
      @thread = nil
      @mutex = Mutex.new
    end

    def start
      return unless config.enabled

      @server = create_server
      logger.info("Schked liveness probe listening on #{config.bind}:#{config.port}#{config.path}")

      @thread = Thread.new {
        Thread.current.name = "schked-liveness-probe" if Thread.current.respond_to?(:name=)
        accept_loop
      }
    end

    def heartbeat
      @last_heartbeat_at = Time.now
    end

    def stop
      @mutex.synchronize do
        return if @shutting_down

        @shutting_down = true
      end

      sleep 0.1
      @server&.close
      @thread&.join(5)
      logger.info("Schked liveness probe stopped")
    end

    def healthy?
      return false if @shutting_down
      return false if @last_heartbeat_at.nil?

      Time.now - @last_heartbeat_at <= config.heartbeat_threshold
    end

    private

    def create_server
      TCPServer.new(config.bind, config.port)
    rescue Errno::EADDRINUSE => e
      raise ArgumentError, "Schked liveness probe port #{config.port} is already in use on #{config.bind}: #{e.message}"
    end

    def accept_loop
      loop do
        client = @server.accept

        Thread.new(client) do |conn|
          handle_client(conn)
        end
      rescue IOError, Errno::EBADF
        break
      end
    end

    def handle_client(client)
      request_line = read_request_line(client)
      return if request_line.nil?

      _method, path, _protocol = request_line.split(" ", 3)

      response = response_for(path)
      client.print(response)
    ensure
      begin
        client.close
      rescue IOError
        # already closed
      end
    end

    def read_request_line(client)
      return nil unless IO.select([client], nil, nil, 5)

      client.gets
    end

    def response_for(path)
      if path == config.path
        if healthy?
          "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
        else
          "HTTP/1.1 503 Service Unavailable\r\nContent-Type: text/plain\r\nContent-Length: 11\r\nConnection: close\r\n\r\nUnavailable"
        end
      else
        "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n"
      end
    end
  end
end
