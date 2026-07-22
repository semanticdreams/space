---
type: feature
status: shipped
parent-goal: core-platform
tags:
  - feature
  - hot-reload
  - live-development
created: 2026-07-14
updated: 2026-07-14
---

# Hot reload and reloadable units

## Summary

Live code update system with Fennel cache clearing, file watching (efsw), and user-extensible reloadable units. Units define load/unload/snapshot/restore lifecycles, enabling safe runtime code changes without restart.

## Motivation

Live development requires changing code and seeing effects immediately. The reload system must:
- Watch filesystem for changes and route them to the correct unit
- Clear stale compiled Fennel caches so code updates are actually picked up
- Support user-authored code in arbitrary directories, not just the built-in asset tree
- Handle reload failure with rollback to the last known-good state

## Design

- **Unit API** (`assets/lua/units.fnl`): Each unit defines `load`, `unload`, `snapshot`, `restore` closures
- **HotReloadController** (`assets/lua/hot-reload.fnl`): efsw-based file watcher, routes changes to units
- **Reload algorithm**: snapshot → unload → load → restore; rollback on failure
- **Unit boundaries**: Root, HUD, Canvas are independent reloadable units
- **User code scanner**: Scans user-specified directories for `init.fnl` and registers as units

## Tasks

- [x] Unit API with load/unload/snapshot/restore
- [x] efsw-based file watcher with change routing
- [x] Reload algorithm with rollback
- [x] Fennel cache clearing on reload
- [x] User code directory scanner
- [x] Subdirectory init.fnl support

## Related

- Goal: [Core Platform](/dev/features/core-platform)
- See: [Reloadable Units](/dev/reloadable-units)
- See: [Lifecycle Centralization](/dev/lifecycle-centralization) — prerequisite for safe reload
