# AGENTS.md — Schked

Compact guide for working with this Ruby gem.

## What this repo is

A Ruby gem wrapping [`rufus-scheduler`](https://github.com/jmettraux/rufus-scheduler) for recurring jobs. It provides a DSL (`config/schedule.rb`), Redis-based distributed locking, Rails integration via a Railtie, and a Thor CLI.

## Setup

Local development is Docker-based via [`dip`](https://github.com/anycable/dip):

```sh
dip provision        # install bundles + appraisal gemfiles, copy lefthook-local.yml
dip standardrb       # lint
dip rspec agnostic   # core tests (spec/lib)
dip rspec rails      # Rails integration tests (spec/rails)
dip rspec redlock.1  # redlock 1.x compatibility tests
```

CI runs in this order: `standardrb` → `rspec agnostic` → `rspec rails` → `rspec redlock.1`. Rails 8 is tested only on Ruby 3.2+.

## Tooling

- **Ruby:** supports `>= 2.7`; CI tests `2.7`, `3.0`, `3.1`, `3.2`, `3.3`, `3.4`, `4.0`.
- **Linter:** [StandardRB](https://github.com/standardrb/standard) (configured in `.standard.yml`). Run with `dip standardrb` or `bundle exec standardrb`.
- **Pre-commit:** `lefthook.yml` runs `bundle exec standardrb --fix {staged_files}`.
- **Multi-version testing:** [Appraisal](https://github.com/thoughtbot/appraisal) generates gemfiles under `gemfiles/` from `Appraisals`. Regenerate with `dip appraisal install` after changing `Appraisals`.

## Architecture & entrypoints

- `lib/schked.rb` — main entrypoint; loads `Schked.config` and `Schked.worker` singletons.
- `lib/schked/cli.rb` — Thor CLI (`exe/schked`). Default command is `start`.
- `lib/schked/worker.rb` — wraps `Rufus::Scheduler`, loads schedule files, registers callbacks, and handles Redis locking.
- `lib/schked/config.rb` — configuration, callbacks, Redis settings.
- `lib/schked/railtie.rb` — auto-adds `config/schedule.rb` from Rails root and wires `Rails.logger`.
- `lib/schked/redis_locker.rb` — distributed lock using Redlock.

## Testing conventions

- Core specs use `spec_helper.rb`, which sets `ENV["RACK_ENV"] = "test"`.
- Rails specs use `rails_helper.rb`, which runs [`Combustion.initialize!`](https://github.com/pat/combustion) before loading `spec_helper`.
- Redis is required for tests. `spec_helper.rb` flushes the DB before each example using `ENV["REDIS_URL"]`.
- In test environments, `Config#standalone?` defaults to `true`, so Redis locking is disabled unless explicitly set to `false`.
- To run a single spec file locally without Docker: `bundle exec rspec spec/lib/schked/worker_spec.rb`.
- To run against a specific appraisal gemfile: `bundle exec appraisal rails.8 bundle exec rspec spec/rails`.

## Runtime behavior

- A `.schked` file in the working directory appends default CLI arguments (e.g. `--require config/environment.rb`).
- CLI commands: `bundle exec schked start` and `bundle exec schked show`.
- In Rails, the Railtie auto-discovers `config/schedule.rb`. Engines can append their own schedule via `Schked.config.paths << root.join("config", "schedule.rb")`.
- Callbacks: `:before_start`, `:after_finish`, `:on_error`, and `:around_job`. Note that `:before_start`/`:after_finish` run in the scheduler thread; `:around_job` runs in the job thread.
