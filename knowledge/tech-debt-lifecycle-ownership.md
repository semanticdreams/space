---
type: tech-debt
impact: high
effort: large
status: resolved
tags:
  - tech-debt
  - lifecycle
  - ownership
  - drop
created: 2026-07-14
updated: 2026-07-14
---

# Lifecycle ownership bugs

## Where

Widget tree, graph views, signal callbacks throughout `assets/lua/`

## Problem

Before the April 2026 lifecycle hardening, the runtime had no clear ownership model:
- Frame update was split across multiple disconnected callers, each updating partially overlapping subsets
- Layout and widget teardown were confused — dropping layout didn't drop widgets, leaving orphaned objects
- Async completions could fire after the owning object was dropped (use-after-drop)
- Post-drop state was undefined — no explicit contract for what remains valid after teardown
- Stale rebuild contexts: when a widget was rebuilt, the rebuild function captured stale references to the old state

## Why it matters

These bugs were the single largest source of runtime crashes during development. Without clear ownership, every async callback, every signal handler, and every rebuild was a potential crash site.

## Plan

Resolved in April 2026 through a series of hardening commits:
1. `fix(ui): centralize frame update ownership` — single update entry point owns the full update pass
2. `fix(ui): harden signal and graph view lifecycle` — signals disconnect when owners drop
3. `fix(ui): stop double-dropping composite view children` — teardown ownership clarified
4. See [[docs/dev/lifecycle-invariants]] for the finalized rules
5. See [[lifecycle-hardening-plan]] for the full strategy

## Related

- [[lifecycle-hardening-plan]]
- [[docs/dev/lifecycle-invariants]]
- [[docs/dev/widget-ownership-and-teardown]]
- Goal: [[core-platform]]
- See: commits from 2026-04-15 to 2026-04-22
