# Schked Dummy App

Minimal app for manually testing schked inside a container. Not part of the gem — a developer sandbox only.

## What's inside

- `config/environment.rb` — requires the local schked, configures it, sets `standalone = true` (no Redis needed).
- `config/schedule.rb` — sample recurring jobs. Edit this file freely.
- `docker-compose.yml` — runs `ruby:4.0-slim`, bind-mounts the schked repo as `/schked`, wires up a healthcheck.
- `entrypoint.sh` — runs `bundle check || bundle install`, then `exec`s `schked start`.
- `healthcheck.rb` — the Docker healthcheck script.

## Run

The dummy app ships [dip](https://github.com/anycable/dip) combos for every
coordination backend combination. Run from this directory:

```sh
dip scheduler                # AR + Postgres (default)
dip scheduler-mysql          # AR + MySQL
dip scheduler-sequel         # Sequel + Postgres
dip scheduler-sequel-mysql   # Sequel + MySQL
dip scheduler-redis          # Redis-backed job run store
dip scheduler-legacy         # no dedup — plain single-instance scheduler
```

First run compiles native gems (pg, mysql2, trilogy) and installs the bundle;
subsequent runs are fast thanks to the `bundle_cache` volume.

### Dedup cluster

The whole point of the dedup mode is running several scheduler instances.
Each `cluster*` dip command boots **2 replicas** of its combo:

```sh
dip cluster                  # 2 x (AR + Postgres)
dip cluster-mysql            # 2 x (AR + MySQL)
dip cluster-sequel           # 2 x (Sequel + Postgres)
dip cluster-sequel-mysql     # 2 x (Sequel + MySQL)
dip cluster-redis            # 2 x (Redis-backed job run store)
```

Exactly one instance executes each job; the others log
`Skipped task: ... (already claimed)`. Job log lines are prefixed with the
container hostname so you can tell the instances apart. The
`schked_job_runs.claimer` column tells you which instance won each window
(`dip postgres-console` / `dip mysql-console`).

### Without dip

With plain `docker compose`, host env vars work directly:

```sh
docker compose up scheduler                                     # single instance, defaults
SCHEDULERS=3 SCHEDULER_PORT= docker compose up -d scheduler                        # 3-instance cluster
SCHEDULERS=2 SCHEDULER_PORT= SCHKED_DB_DRIVER=sequel docker compose up -d scheduler
```

Combo flags: `SCHKED_JOB_RUN_STORE`, `SCHKED_DB_DRIVER`,
`SCHKED_DB_ENGINE`, `SCHKED_MAX_SKEW`. `SCHEDULER_PORT=` (empty) publishes ephemeral host ports, which replicas need; pin a fixed port for a single instance with `SCHEDULER_PORT=8080`.

DB consoles: `dip postgres-console`, `dip mysql-console` (no passwords
needed — the service env carries them).

> Tip: if you kill dip/compose with `timeout` or a hard Ctrl-C, `run`
> containers may keep living and still claim jobs (you will see
> "already claimed" skips from nowhere). Clean them up with:
>
> ```sh
> docker compose rm -sf scheduler
> ```

## Healthcheck

Defined in `docker-compose.yml`. Edit `healthcheck.rb` to match whatever you're currently testing.

Check status:

```sh
docker inspect --format '{{.State.Health.Status}}' $(docker compose ps -q scheduler | head -1)
```

The host port defaults to 8080, but a cluster publishes ephemeral ports —
use `docker compose port scheduler 8080` (per container) to resolve them,
or pin one with `SCHEDULER_PORT=9090`.

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
