---
type: subsystem
tags:
  - subsystem
  - process
created: 2026-07-14
---

# Process and system layer

Child process management, shell execution, system information queries, temporary files, main loop architecture, preload/bootstrap sequencing, and multithreading via the job system.

## Key files

- `src/lua_process.h`, `src/lua_shell.h`, `src/lua_sysinfo.h` — process/shell/sysinfo bindings
- `src/job_system.h` — thread pool for async work
- `src/lua_runtime.h` — Lua bootstrapping and main loop

## Dependencies

- Depends on: [Core Platform](/dev/features/core-platform)

## Dev notes

- [Process](/dev/notes/process) — child process management
- [Sysinfo](/dev/notes/sysinfo) — system information queries
- [Tempfile](/dev/notes/tempfile) — temporary file utilities
- [Loop](/dev/notes/loop) — main loop architecture
- [Preload](/dev/notes/preload) — module preload and bootstrap
- [Multithreading](/dev/notes/multithreading) — engine threading and job system

## See also

- [Core Platform](/dev/features/core-platform)
- [Subsystems](/dev/subsystems/)
