---
type: adr
status: accepted
decision-date: 2025-09-01
tags:
  - adr
  - language
  - fennel
  - python
  - migration
supersedes:
superseded-by:
---

# Fennel + C++ application model over Python

## Context

The project began with a Python scripting layer (`assets/python/`) driving the C++ engine. Python provided rapid prototyping but introduced performance issues, complex packaging, and a heavy runtime footprint for a 3D application that needed to be responsive and portable.

We needed a scripting language that:
- Embeds directly into the C++ process with minimal overhead
- Supports hot-reloading for live development
- Has good interop with our existing C++ engine
- Feels natural for a Lisp-heavy codebase (the team had Lisp experience)

## Decision

Adopt **Fennel** (a Lua Lisp) as the scripting language, running on LuaJIT via sol2 bindings.

- All new feature work, tests, and architecture decisions happen in `assets/lua/` using Fennel
- `assets/python/` is preserved as historical reference only
- C++ engine (`src/`) exposes bindings via `sol2` with factory functions instead of constructors
- Widget system, layout engine, and application model are built in pure Fennel

## Consequences

**Positive:**
- Single-process architecture — no Python subprocess, no IPC overhead
- Fast startup and hot-reload via LuaJIT
- Widget/layout system composes cleanly in a functional style
- Tests run in-process via the same `space` binary
- Smaller distribution footprint (no Python dependency)

**Negative:**
- Smaller ecosystem than Python — fewer libraries
- Fennel adds a compile step (though transparent at runtime)
- New contributors must learn Fennel/Lisp syntax
- sol2 binding code requires careful lifetime management

## Alternatives considered

**Stick with Python:** Rejected — performance and packaging were too painful for a 3D runtime.

**Lua without Fennel:** Rejected — the team valued Lisp's expressiveness and macros for DSLs (widget builders, layout constraints).

**Guile Scheme:** Rejected — weaker C++ interop story, larger runtime, less mature embedding.

**JavaScript (QuickJS/Duktape):** Rejected — didn't match the team's functional/Lisp affinity.

## Related

- Goal: [Core Platform](/dev/features/core-platform) — this decision enabled the entire Fennel application model
- See: [Project History](/dev/project/history) — Phase I
- See: [Lua Branch Development](/dev/adrs/adr-lua-branch-development) — the branch model used for the migration
