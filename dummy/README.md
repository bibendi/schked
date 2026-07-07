# Schked Dummy App

Minimal app for manually testing schked inside a container. Not part of the gem — a developer sandbox only.

## What's inside

- `config/environment.rb` — requires the local schked, configures it, sets `standalone = true` (no Redis needed).
- `config/schedule.rb` — sample recurring jobs. Edit this file freely.
- `docker-compose.yml` — runs `ruby:4.0-slim`, bind-mounts the schked repo as `/schked`, wires up a healthcheck.
- `entrypoint.sh` — runs `bundle check || bundle install`, then `exec`s `schked start`.
- `healthcheck.rb` — the Docker healthcheck script.

## Run

```sh
cd dummy
docker compose up scheduler
```

Tail scheduler logs:

```sh
docker compose logs -f scheduler
```

## Healthcheck

Defined in `docker-compose.yml`. Edit `healthcheck.rb` to match whatever you're currently testing.

Check status:

```sh
docker inspect --format '{{.State.Health.Status}}' $(docker compose ps -q scheduler)
```

## Ports and bind-mounts

- `8080:8080` — exposed to the host. Change in `docker-compose.yml` if a feature you're testing needs a different port.
- `../:/schked` — the schked repo; edits in `lib/` are picked up after restarting the container.
- `bundle_cache` — gems cache, so installs are skipped on subsequent runs.

## Configuration

All schked config goes in `config/environment.rb`: paths, logger, callbacks, liveness probe, etc. See the main schked README and `specs/` for what's available.

## Things to test by hand

- Start the scheduler, watch logs, confirm scheduled jobs fire.
- `docker compose stop scheduler` — verify graceful shutdown behavior.
- Change the port in compose/environment, restart, confirm the scheduler picks it up.
- Occupy a port the scheduler needs, then start it — confirm a clean failure.