---
type: subsystem
tags:
  - subsystem
  - build
created: 2026-07-14
---

# Build and compilation system

CMake-based C++ build with cross-platform packaging (DEB/RPM/AppImage/tarball), GCC JIT runtime compilation bindings, C intermediate representation for code generation, and native build integration.

## Key files

- `cmake/` — CMake build system with platform dispatchers
- `src/lua_gccjit.h` — libgccjit bindings for runtime C compilation
- `assets/lua/c-builder.fnl`, `assets/lua/c-ir.fnl` — Fennel C compilation layer
- `assets/lua/native-build.fnl` — native build integration

## Dependencies

- Depends on: [[core-platform]]

## Dev notes

- [[dev-notes/c-builder]] — C compilation via GCC JIT
- [[dev-notes/c-ir]] — C intermediate representation
- [[dev-notes/gccjit]] — libgccjit binding details
- [[dev-notes/native-build]] — native C build integration

## See also

- [[core-platform]]
- [[development-tooling]]
- [[subsystems]]
