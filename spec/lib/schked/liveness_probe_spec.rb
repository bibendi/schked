# frozen_string_literal: true

require "spec_helper"
require "socket"

describe Schked::LivenessProbe do
  let(:logger) { instance_double(Logger).as_null_object }

  def probe_config(overrides = {})
    Schked::LivenessProbeConfig.new({
      enabled: true,
      bind: "127.0.0.1",
      port: 0,
      path: "/healthz"
    }.merge(overrides))
  end

  def fetch(port, path)
    socket = TCPSocket.new("127.0.0.1", port)
    socket.print("GET #{path} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    response = socket.read
    socket.close
    response
  end

  def available_port
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    port
  end

  describe "#start" do
    it "binds to the configured address and port" do
      config = probe_config(port: available_port)
      probe = described_class.new(config: config, logger: logger)

      probe.start

      expect(probe.send(:instance_variable_get, :@server)).to be_a(TCPServer)

      probe.stop
    end

    it "does not bind when disabled" do
      config = probe_config(enabled: false, port: available_port)
      probe = described_class.new(config: config, logger: logger)

      probe.start

      expect(probe.send(:instance_variable_get, :@server)).to be_nil
    end
  end

  describe "HTTP responses" do
    it "returns 200 OK when healthy" do
      config = probe_config(port: available_port)
      probe = described_class.new(config: config, logger: logger)
      probe.start
      port = probe.send(:instance_variable_get, :@server).addr[1]

      probe.heartbeat
      response = fetch(port, "/healthz")

      expect(response).to include("HTTP/1.1 200 OK")
      expect(response).to include("OK")

      probe.stop
    end

    it "returns 503 Service Unavailable when heartbeat is stale" do
      config = probe_config(port: available_port, heartbeat_threshold: 1, heartbeat_interval: 1)
      probe = described_class.new(config: config, logger: logger)
      probe.start
      port = probe.send(:instance_variable_get, :@server).addr[1]

      probe.heartbeat
      sleep 1.1
      response = fetch(port, "/healthz")

      expect(response).to include("HTTP/1.1 503 Service Unavailable")
      expect(response).to include("Unavailable")

      probe.stop
    end

    it "returns 503 Service Unavailable during shutdown" do
      config = probe_config(port: available_port)
      probe = described_class.new(config: config, logger: logger)
      probe.start
      port = probe.send(:instance_variable_get, :@server).addr[1]

      probe.heartbeat
      stop_thread = Thread.new { probe.stop }
      response = fetch(port, "/healthz")
      stop_thread.join

      expect(response).to include("HTTP/1.1 503 Service Unavailable")
      expect(response).to include("Unavailable")
    end

    it "returns 404 Not Found for unknown paths" do
      config = probe_config(port: available_port)
      probe = described_class.new(config: config, logger: logger)
      probe.start
      port = probe.send(:instance_variable_get, :@server).addr[1]

      response = fetch(port, "/unknown")

      expect(response).to include("HTTP/1.1 404 Not Found")

      probe.stop
    end

    it "does not block the accept thread on a slow client" do
      config = probe_config(port: available_port)
      probe = described_class.new(config: config, logger: logger)
      probe.start
      port = probe.send(:instance_variable_get, :@server).addr[1]
      probe.heartbeat

      slow_socket = TCPSocket.new("127.0.0.1", port)
      # Do not send anything; the server should time out the read after 5 seconds.

      start_time = Time.now
      response = fetch(port, "/healthz")
      elapsed = Time.now - start_time

      expect(response).to include("HTTP/1.1 200 OK")
      expect(elapsed).to be < 5.0

      slow_socket.close
      probe.stop
    end
  end

  describe "port conflict" do
    it "raises a clear error when the port is already in use" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]

      config = probe_config(port: port)
      probe = described_class.new(config: config, logger: logger)

      expect { probe.start }
        .to raise_error(ArgumentError, /port #{port} is already in use/)
    ensure
      server&.close
    end
  end

  describe "#stop" do
    it "stops the server and joins the thread" do
      config = probe_config(port: available_port)
      probe = described_class.new(config: config, logger: logger)
      probe.start

      probe.stop

      expect(probe.send(:instance_variable_get, :@thread)).not_to be_alive
    end
  end
end

describe Schked::LivenessProbeConfig do
  describe "defaults" do
    subject(:config) { described_class.new }

    it { expect(config.enabled).to be false }
    it { expect(config.bind).to eq "0.0.0.0" }
    it { expect(config.port).to eq 8080 }
    it { expect(config.path).to eq "/healthz" }
    it { expect(config.heartbeat_interval).to eq 5 }
    it { expect(config.heartbeat_threshold).to eq 15 }
  end

  describe "custom values" do
    subject(:config) do
      described_class.new(
        enabled: true,
        bind: "127.0.0.1",
        port: 9090,
        path: "/ready",
        heartbeat_interval: 2,
        heartbeat_threshold: 10
      )
    end

    it { expect(config.enabled).to be true }
    it { expect(config.bind).to eq "127.0.0.1" }
    it { expect(config.port).to eq 9090 }
    it { expect(config.path).to eq "/ready" }
    it { expect(config.heartbeat_interval).to eq 2 }
    it { expect(config.heartbeat_threshold).to eq 10 }
  end

  describe "validation" do
    it "raises for an empty bind address" do
      expect { described_class.new(bind: "") }
        .to raise_error(ArgumentError, /bind.*must be non-empty/)
    end

    it "raises for an invalid bind address" do
      expect { described_class.new(bind: "not-an-address") }
        .to raise_error(ArgumentError, /bind.*is invalid/)
    end

    it "raises for a port out of range" do
      expect { described_class.new(port: -1) }
        .to raise_error(ArgumentError, /port.*1 and 65535/)
    end

    it "raises for a non-integer port" do
      expect { described_class.new(port: "abc") }
        .to raise_error(ArgumentError, /port.*must be an integer/)
    end

    it "raises for a path not starting with /" do
      expect { described_class.new(path: "healthz") }
        .to raise_error(ArgumentError, /path.*must start with \//)
    end

    it "raises for a non-positive heartbeat interval" do
      expect { described_class.new(heartbeat_interval: 0) }
        .to raise_error(ArgumentError, /heartbeat_interval.*must be a positive integer/)
    end

    it "raises when threshold is less than interval" do
      expect { described_class.new(heartbeat_interval: 10, heartbeat_threshold: 5) }
        .to raise_error(ArgumentError, /heartbeat_threshold.*must be >= heartbeat_interval/)
    end
  end
end
