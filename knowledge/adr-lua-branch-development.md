---
type: adr
status: accepted
decision-date: 2025-10-01
tags:
  - adr
  - workflow
  - git
  - development
supersedes:
superseded-by:
---

# Long-lived branch development model

## Context

From October 2025 through January 2026, development happened on a long-lived Lua branch off main. During this period, the Python prototype was replaced with a Fennel/C++ implementation across nearly every subsystem: rendering, layout, entities, physics, search, torrent, wallet, video, browser. Only 1 commit landed on main during these 4 months. On `2026-02-04`, the branch was squash-merged as a single "Merge lua" commit with 128 commits worth of changes.

## Decision

Use long-lived feature branches for major architectural changes (like the Python-to-Fennel migration), merging via squash to keep main's history linear and clean.

## Consequences

**Positive:**
- Main branch stays stable; large refactors don't destabilize the default build
- Squash-merged history is clean and readable
- Freedom to restructure aggressively on the branch without main's constraints

**Negative:**
- 4 months of invisible work on main — external contributors can't track progress
- Squash merge loses per-commit history (128 commits collapsed to one)
- Integration pain on merge day (conflicts with any concurrent main changes)
- Minimal opportunity for incremental code review

## Status

Currently (2026-07), the project has shifted to smaller, more frequent commits directly on main (10-52 commits/month, many with conventional commit prefixes). The branch model was used for the one major migration but is not the ongoing pattern.

## Related

- Goal: [[core-platform]] — this development model built the core platform
- [[history]] — project timeline
- [[adr-fennel-over-python]] — the migration that used this model
