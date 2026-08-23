# AGENTS.md — Schked

Compact guide for working with this Ruby gem.

## What this repo is

A Ruby gem wrapping [`rufus-scheduler`](https://github.com/jmettraux/rufus-scheduler) for recurring jobs. It provides a DSL (`config/schedule.rb`), a pluggable coordination store (Redis or database) for multi-instance deduplication, Rails integration via a Railtie, and a Thor CLI.

## Setup

Local development is Docker-based via [`dip`](https://github.com/anycable/dip):

```sh
dip provision        # install bundles + appraisal gemfiles, copy lefthook-local.yml
dip standardrb       # lint
dip rspec agnostic   # core tests (spec/lib)
dip rspec rails      # Rails integration tests (spec/rails) + ActiveRecord adapter integration
dip rspec redlock.1  # redlock 1.x compatibility tests
dip rspec postgres   # real Postgres integration (spec/integration)
dip rspec mysql      # real MySQL integration (spec/integration)
dip rspec sequel     # real Sequel adapter integration (spec/integration)
```

CI runs in this order: `standardrb` → `rspec agnostic` → `rspec rails` → `rspec redlock.1` → `rspec postgres` → `rspec mysql` → `rspec sequel`. Rails 8 is tested only on Ruby 3.2+; database integration suites are gated on Ruby ≥ 3.0.

## Tooling

- **Ruby:** supports `>= 2.7`; CI tests `2.7`, `3.0`, `3.1`, `3.2`, `3.3`, `3.4`, `4.0`.
- **Linter:** [StandardRB](https://github.com/standardrb/standard) (configured in `.standard.yml`). Run with `dip standardrb` or `bundle exec standardrb`.
- **Pre-commit:** `lefthook.yml` runs `bundle exec standardrb --fix {staged_files}`.
- **Multi-version testing:** [Appraisal](https://github.com/thoughtbot/appraisal) generates gemfiles under `gemfiles/` from `Appraisals`. Regenerate with `dip appraisal install` after changing `Appraisals`.

## Architecture & entrypoints

- `lib/schked.rb` — main entrypoint; loads `Schked.config` and `Schked.worker` singletons.
- `lib/schked/cli.rb` — Thor CLI (`exe/schked`). Default command is `start`. Commands: `start`, `show`, `generate-migration [--flavor=mysql]`.
- `lib/schked/worker.rb` — wraps `Rufus::Scheduler`, loads schedule files, registers callbacks, and wires the coordination store.
- `lib/schked/callbacks.rb` — installs rufus callbacks (extracted from Worker): per-job dedup claim, `:as:` enforcement, internal-job exemption.
- `lib/schked/config.rb` — configuration. New dedup-related options: `job_run_store` (`:redis`/`:database`/custom), `max_skew` (default 60), `database_connection`, `database_flavor`.
- `lib/schked/job_run_store.rb` — store interface contract (`claim`, `cleanup`).
- `lib/schked/redis_job_run_store.rb` — Redis-backed store (`SET NX EX` with TTL).
- `lib/schked/database_job_run_store.rb` — pure-SQL store (Postgres `ON CONFLICT`, MySQL `ON DUPLICATE KEY`).
- `lib/schked/database_adapters.rb` — wraps `PG::Connection`, `Mysql2::Client`, `Sequel::Database`, ActiveRecord adapter into a uniform `execute(sql, params)` contract.
- `lib/schked/database_connection.rb` — auto-detects a connection (AR → Sequel) and infers flavor.
- `lib/schked/schedule_dsl.rb` — wraps the rufus DSL to grid-align `every` and reject `interval` in dedup mode.
- `lib/schked/migration_generator.rb` — DDL constants for `schked generate-migration`.
- `lib/schked/railtie.rb` — auto-adds `config/schedule.rb` from Rails root and wires `Rails.logger`.
- `lib/schked/redis_locker.rb` — legacy global Redis lock (default behavior).

## Testing conventions

- Core specs use `spec_helper.rb`, which sets `ENV["RACK_ENV"] = "test"`.
- Rails specs use `rails_helper.rb`, which runs [`Combustion.initialize!`](https://github.com/pat/combustion) before loading `spec_helper`.
- Database integration specs live in `spec/integration/` and run only under the `postgres`, `mysql`, or `sequel` Appraisal gemfiles (against live services in `docker-compose.yml`).
- Redis is required for tests. `spec_helper.rb` flushes the DB before each example using `ENV["REDIS_URL"]`.
- In test environments, `Config#standalone?` defaults to `true`, so Redis locking is disabled unless explicitly set to `false`.
- To run a single spec file locally without Docker: `bundle exec rspec spec/lib/schked/worker_spec.rb`.
- To run against a specific appraisal gemfile: `bundle exec appraisal rails.8 bundle exec rspec spec/rails`.

## Runtime behavior

- A `.schked` file in the working directory appends default CLI arguments (e.g. `--require config/environment.rb`).
- CLI commands: `bundle exec schked start`, `bundle exec schked show`, `bundle exec schked generate-migration [--flavor=mysql]`.
- In Rails, the Railtie auto-discovers `config/schedule.rb`. Engines can append their own schedule via `Schked.config.paths << root.join("config", "schedule.rb")`.
- Callbacks: `:before_start`, `:after_finish`, `:on_error`, and `:around_job`. Note that `:before_start`/`:after_finish` run in the scheduler thread; `:around_job` runs in the job thread.

## Deduplication mode

Set `Schked.config.job_run_store = :redis`, `:database`, or a custom object to opt into per-job deduplication across instances.

- Each `every` / `cron` / `at` / `in` job must declare an `as:` label. Schedules without `as:` are skipped with an error log — without one, the dedup key falls back to `job.job_id` which is per-process and silently duplicates every run across the cluster.
- `every` jobs are aligned to an absolute time grid via `first_at`; the grid is shifted by `max_skew` so two instances whose clocks differ by up to `max_skew` land on the same slot.
- `interval` jobs are rejected with `Schked::ScheduleDSL::IntervalNotSupportedError` (their phase drifts with job duration and cannot be deduplicated).
- Internal Schked jobs ("Schked::Worker#…") skip dedup claims and run on every instance (cleanup sweep, liveness heartbeat).
- For database-backed dedup, apply the `schked_job_runs` DDL (printed by `schked generate-migration`) to your database; the table requires a UNIQUE index on `(job_name, window_start)`.
