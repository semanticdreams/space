---
type: tech-debt
impact: high
effort: medium
status: resolved
tags:
  - tech-debt
  - fennel
  - cache
  - hot-reload
created: 2026-07-14
updated: 2026-07-14
---

# Fennel cache poisoning during hot-reload

## Where

`assets/lua/` — Fennel compiler cache

## Problem

When modules were hot-reloaded, the compiled Fennel bytecode cache held stale versions. Code changes on disk were invisible at runtime because the cache returned the old compiled form. This meant hot-reload appeared to succeed (no errors) but actually ran the old code.

## Why it matters

Hot-reload is useless if the old code keeps running. During the June 2026 Windows cross-compile sprint, this was compounded by path separator issues (cached paths used `/` but Windows paths used `\`, causing cache misses that silently loaded old code).

## Plan

Fixed in June 2026: `fix(fennel-cache): clear compiled Fennel caches during hot-reload and module unload`. The hot-reload sequence now explicitly clears the Fennel compiler cache before loading new code. Per-module cache keys were also hardened to handle both path separators.

## Related

- [Hot Reload Units](/dev/features/hot-reload-units)
- Goal: [Core Platform](/dev/features/core-platform)
- See: commit `432eb41d` (2026-06-17)
