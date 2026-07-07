require "schked"

Schked.config.paths << File.expand_path("schedule.rb", __dir__)
Schked.config.standalone = true

Schked.config.liveness_probe = {
  enabled: true,
  bind: "0.0.0.0",
  port: 8080,
  path: "/healthz",
  heartbeat_interval: 5,
  heartbeat_threshold: 15
}
