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

- Depends on: [Core Platform](/dev/features/core-platform)

## Dev notes

- [C Builder](/dev/notes/c-builder) — C compilation via GCC JIT
- [C Ir](/dev/notes/c-ir) — C intermediate representation
- [Gccjit](/dev/notes/gccjit) — libgccjit binding details
- [Native Build](/dev/notes/native-build) — native C build integration

## See also

- [Core Platform](/dev/features/core-platform)
- [Development Tooling](/dev/features/development-tooling)
- [Subsystems](/dev/subsystems/)
