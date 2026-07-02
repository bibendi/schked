---
name: schked
description: Guide for working with Schked, a Ruby recurring-job scheduler built on top of rufus-scheduler.
---

# Schked

Schked is a framework-agnostic Ruby wrapper around [rufus-scheduler](https://github.com/jmettraux/rufus-scheduler) for running recurring jobs. It adds Redis-based distributed locking (so only one scheduler instance is active at a time), Rails integration, callbacks, and a small CLI.

## Routing Map

| Question | Go to |
|---|---|
| How does the scheduler start, run, and shut down? | `references/architecture.md` |
| How do I install and configure it? | `references/initialization.md` |
| What changed between versions or what is deprecated? | `references/migration.md` |
| How do I perform a concrete task? | `references/recipes/{use-case}.md` |
| What is broken and how do I fix it? | `references/troubleshooting.md` |

## Reading Order

1. Read `references/architecture.md` first to understand the runtime model, especially the threading rules and the Redis lock.
2. Read `references/initialization.md` when the task involves setup or configuration.
3. Read the specific `references/recipes/{use-case}.md` for the task at hand.
4. Read `references/migration.md` only when upgrading or handling deprecations.
5. Read `references/troubleshooting.md` only when diagnosing failures.

## Critical Constraints

- Do not rely on class or method signatures from this skill. Open the gem source or the rufus-scheduler documentation when you need exact API details.
- Verify whether the current environment is `standalone` or Redis-locked before changing scheduling behavior.
- Prefer linking to rufus-scheduler cron/every/in documentation over duplicating scheduling syntax.
