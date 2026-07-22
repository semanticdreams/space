---
type: adr
status: accepted
decision-date: 2026-02-25
tags:
  - adr
  - sdl
  - input
  - windowing
supersedes:
superseded-by:
---

# SDL3 migration

## Context

The project initially used SDL2 for windowing and input. SDL3 brought a redesigned API with:
- More explicit event handling
- Modernized GPU API (removing legacy fixed-function paths)
- Better Wayland and cross-platform support
- Different coordinate and touch semantics

The migration happened as part of the large Lua branch merge (`2026-02-04 to 2026-02-25`), touching both the C++ engine and the Lua/Fennel input layer.

## Decision

Migrate the entire runtime from SDL2 to SDL3, vendoring SDL3 in `external/`. All input handling, window creation, and event loops use the new SDL3 API.

## Consequences

**Positive:**
- Cleaner input abstraction with explicit state tracking
- Better Wayland/multi-monitor handling
- Foundation for cross-platform work (Windows support followed in June 2026)

**Negative:**
- Touch and pointer coordinates diverged, requiring follow-up hardening (`fix(input): restore consistent touch and pointer coordinates`, 2026-04-22)
- Required extensive engine-side changes to input semantics and event flow
- CEF integration needed SDL3-specific window parent/embed logic

## Related

- Goal: [Core Platform](/dev/features/core-platform) — SDL3 underpins windowing and input for the platform
- [Subsystems](/dev/subsystems/) — Engine section
- See `src/` for SDL3 initialization and event loop
