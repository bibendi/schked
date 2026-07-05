# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- Added optional Kubernetes liveness probe support. When enabled, Schked exposes a configurable HTTP `/healthz` endpoint that returns `200 OK` while healthy and `503 Service Unavailable` when the heartbeat is stale or during shutdown. Disabled by default; configurable via Ruby, CLI flags, or Rails application config.

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
