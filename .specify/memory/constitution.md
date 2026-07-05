<!--
Sync Impact Report
Version change: template placeholders → 1.0.0
Modified principles: none (all principles are newly defined)
Added sections:
  - Core Principles
  - Technology & Standards
  - Development Workflow
  - Governance
Removed sections: none
Templates requiring updates:
  - .specify/templates/plan-template.md: ✅ no update required (Constitution Check gate remains generic)
  - .specify/templates/spec-template.md: ✅ no update required
  - .specify/templates/tasks-template.md: ✅ no update required
  - .specify/templates/commands/*.md: ✅ directory does not exist
Runtime guidance requiring updates:
  - README.md: ✅ no constitution references to update
  - AGENTS.md: ✅ no constitution references to update
Follow-up TODOs:
  - RATIFICATION_DATE: original adoption date unknown; replace TODO with actual ISO date when known
-->

# Schked Constitution

## Core Principles

### I. Gem-First, Framework-Agnostic Core

Schked is a Ruby gem first. The core library MUST be usable without Rails or any
web framework. Framework integrations (e.g., Rails Railtie, engine schedule
paths) MUST be optional adapters that load only when the host framework is
present. The public Ruby API and the Thor CLI MUST provide equivalent runtime
capabilities.

**Rationale**: Keeps the gem lightweight, reusable, and avoids forcing framework
dependencies on non-Rails consumers.

### II. First-Class CLI

The Thor CLI (`exe/schked`) MUST remain the primary production entrypoint. All
commands MUST produce human-readable output on stdout and errors on stderr with
a non-zero exit code. The CLI MUST support a `.schked` file in the working
directory to append default arguments.

**Rationale**: Operators schedule and inspect jobs via the CLI; predictable I/O
simplifies automation and debugging.

### III. Test Discipline (NON-NEGOTIABLE)

Every code change MUST include RSpec coverage for the affected behavior. The full
CI matrix MUST pass before merging: `standardrb`, `rspec agnostic`, `rspec rails`,
`rspec redlock.1`. Tests MUST exercise supported Ruby versions (2.7, 3.0, 3.1,
3.2) and Appraisal gemfiles. Redis MUST be available for test execution.

**Rationale**: Schked coordinates production jobs; regressions in scheduling,
locking, or Rails integration are costly.

### IV. Production Reliability

Distributed Redis locking MUST prevent duplicate job execution when multiple
scheduler instances overlap. Callback hooks (`:before_start`, `:after_finish`,
`:on_error`, `:around_job`) MUST be preserved, documented, and execute in their
specified threads. Logging MUST default to stdout and be configurable to any
`Logger`-compatible target.

**Rationale**: Recurring job infrastructure must be observable, debuggable, and
safe to deploy with zero downtime.

### V. Minimal, Backward-Compatible Evolution

Public API changes MUST follow Semantic Versioning. New features MUST justify
their added surface area against the core recurring-job scheduling mission.
Multi-version compatibility (Ruby >= 2.7, multiple Rails and Redlock versions)
MUST be maintained via Appraisal.

**Rationale**: A small, stable API reduces maintenance burden and protects
downstream consumers.

## Technology & Standards

- Ruby >= 2.7 is the minimum supported runtime.
- StandardRB is the mandatory linter; all code MUST pass `bundle exec standardrb`.
- RSpec is the mandatory test framework.
- Docker/`dip` provides the canonical local development environment.
- Redis is required for production distributed locking and for test execution.
- Appraisal gemfiles under `gemfiles/` define the supported dependency matrix.

## Governance

- This constitution supersedes all other project practices where conflicts arise.
- Amendments require a version bump following Semantic Versioning rules:
  - **MAJOR**: backward-incompatible principle removals or redefinitions;
  - **MINOR**: new principles/sections or materially expanded guidance;
  - **PATCH**: clarifications, wording fixes, or non-semantic refinements.
- All pull requests and reviews MUST verify compliance with these principles.
- Runtime development guidance is maintained in `AGENTS.md`.

**Version**: 1.0.0 | **Ratified**: TODO(RATIFICATION_DATE): original adoption date unknown | **Last Amended**: 2026-07-05
