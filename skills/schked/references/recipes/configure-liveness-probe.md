# Recipe: Configure the Kubernetes Liveness Probe

Schked can expose a minimal HTTP endpoint for Kubernetes liveness probes. The endpoint is disabled by default and does not add any gem dependencies.

## Goal

Enable an HTTP endpoint that returns `200 OK` while the scheduler process is healthy and `503 Service Unavailable` when it is not.

## Steps

1. Enable the probe in configuration.
2. Optionally customize the bind address, port, and path.
3. Reference the endpoint in your Kubernetes manifest.

## Ruby configuration

```ruby
Schked.config.liveness_probe = {
  enabled: true,
  bind: "0.0.0.0",
  port: 8080,
  path: "/healthz",
  heartbeat_interval: 5,
  heartbeat_threshold: 15
}
```

## CLI configuration

```sh
bundle exec schked start \
  --liveness-probe \
  --liveness-bind 0.0.0.0 \
  --liveness-port 8080 \
  --liveness-path /healthz
```

## Rails configuration

```ruby
# config/application.rb or config/environments/production.rb
config.schked.liveness_probe = {
  enabled: true,
  bind: "0.0.0.0",
  port: 8080,
  path: "/healthz",
  heartbeat_interval: 5,
  heartbeat_threshold: 15
}
```

## Kubernetes manifest

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10
```

## Validation

Check the endpoint manually:

```sh
curl -i http://localhost:8080/healthz
```

You should see:

```http
HTTP/1.1 200 OK
Content-Type: text/plain

OK
```

## Notes

- The probe is disabled by default; omit `enabled: true` or pass `--no-liveness-probe` to keep it off.
- `heartbeat_interval` controls how often the scheduler updates the heartbeat (default `5` seconds).
- `heartbeat_threshold` is the maximum age of the heartbeat before the endpoint returns `503` (default `15` seconds; must be >= `heartbeat_interval`).
- The endpoint returns `503` while the scheduler is shutting down.
- If the configured port is already in use, the scheduler exits immediately with a clear error.
