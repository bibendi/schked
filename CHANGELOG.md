# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2026-08-23

- Added an opt-in per-job deduplication mode for multi-instance deployments. The single-active-instance Redis lock remains one of the supported strategies. Set `job_run_store = :redis`, `:database`, or a custom object to enable dedup. [#43]
  - Each recurring job claims its schedule interval atomically, so different jobs run on different instances concurrently while every job still runs exactly once per interval across the whole cluster.
  - The new database backend lets you deduplicate without Redis. `database_connection` can be a `PG::Connection`, `Mysql2::Client`, `Sequel::Database`, or an ActiveRecord adapter; the connection is also auto-detected when ActiveRecord or Sequel is loaded. `schked generate-migration [--flavor=mysql]` prints the required table DDL.
  - **BREAKING** in dedup mode: `every` jobs are aligned to an absolute time grid so all instances share the same phase — the first firing is no longer relative to process start. `cron`, `at`, and `in` jobs are unaffected. `interval` jobs are no longer supported and raise a clear error, since their phase drifts with job duration and cannot be deduplicated.
- **BREAKING**: Dropped support for Ruby 2.7. The minimum supported Ruby is now 3.0. CI no longer runs on 2.7, `required_ruby_version` is `>= 3.0`, and `.standard.yml` targets Ruby 3.0.

## [1.5.0] - 2026-07-08

- Added optional Kubernetes liveness probe support. When enabled, Schked exposes a configurable HTTP `/healthz` endpoint that returns `200 OK` while healthy and `503 Service Unavailable` when the heartbeat is stale or during shutdown. Disabled by default; configurable via Ruby, CLI flags, or Rails application config. [#42]

## [1.4.0] - 2026-07-05

- Ruby 3.3, 3.4, and 4.0 are now tested in CI.
- Rails 8 is now tested in CI.
- Local development Docker image defaults to Ruby 4.0.
- **BREAKING**: Dropped support for Rails 5.
- Updated `.standard.yml` to target Ruby 2.7, matching the gem's `required_ruby_version`.
- Updated GitHub Actions workflow to test Ruby 2.7–4.0 and to run Rails 8 tests only on Ruby 3.2+.

## [1.3.1] - 2025-04-21

- Prevent double schedule loading and task duplication [#39]

## [1.3.0] - 2023-09-06

- Added support for Redlock 2.0 gem
- Renamed the `redis_servers=` config option to `redis=`
- Added support for Redis Sentinels (requires Redlock >= 2)
- Added Connection Pool for a performance reason

## [1.2.0] - 2023-06-09

- Added around_job callback [#37]

## [1.1.2] - 2022-12-16

- Don't fail when Redis is down [#35]

## [1.1.1] - 2022-11-15

- Fix Schked hanging when Redis fails [#34]

## [1.1.0] - 2022-10-19

- Added a standalone mode [#32]

## [1.0.0] - 2022-10-10

- Added locks to support seamless deployments [#31]
- **BREAKING**: Schked requires Redis now.

## [0.4.0] - 2022-08-12

- Added a config option `do_not_load_root_schedule` [#30]
