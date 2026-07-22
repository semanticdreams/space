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

- Depends on: [[core-platform]]

## Dev notes

- [[dev-notes/process]] — child process management
- [[dev-notes/sysinfo]] — system information queries
- [[dev-notes/tempfile]] — temporary file utilities
- [[dev-notes/loop]] — main loop architecture
- [[dev-notes/preload]] — module preload and bootstrap
- [[dev-notes/multithreading]] — engine threading and job system

## See also

- [[core-platform]]
- [[subsystems]]
