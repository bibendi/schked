# Changelog

All notable changes to this project will be documented in this file.

## 2.0.0 - 2026-07-05

### Added

- Ruby 3.3, 3.4, and 4.0 are now tested in CI.
- Rails 8 is now tested in CI.
- Local development Docker image defaults to Ruby 4.0.

### Removed

- **BREAKING**: Dropped support for Rails 5.

### Changed

- Updated `.standard.yml` to target Ruby 2.7, matching the gem's `required_ruby_version`.
- Updated GitHub Actions workflow to test Ruby 2.7–4.0 and to run Rails 8 tests only on Ruby 3.2+.
