---
type: planning
tags:
  - plan
  - history
  - timeline
created: 2026-07-14
---

# Project History

Chronological evolution of Space, extracted from 440 commits (2025-07 to 2026-07).

## Phase I: Inception (2025-07 to 2025-09) — ~31 commits

Project bootstrap. Initial commit contained the C++ engine and a Python prototype under `assets/python/` with entity system, skybox, mesh/text renderers, dynamic graph, and force layout. By September, Fennel rendering began with triangle output and the first layout system in Fennel (`2025-09-01`).

Key events:
- Entity system in Python (sqlite-backed, class entities with 2-way filesystem sync)
- Dynamic graph with force layout
- Python-to-Fennel rendering bridge (FBO displayed on Python scene texture)
- [Fennel Over Python](/dev/adrs/adr-fennel-over-python)

## Phase II: Quiet development (2025-10 to 2026-01) — ~1 commit on main

Work happened on a long-lived Lua branch. [Lua Branch Development](/dev/adrs/adr-lua-branch-development)

## Phase III: Lua migration (2026-02-04 to 2026-02-28) — ~128 commits

Massive merge from the Lua branch. Nearly every subsystem appeared:
- [SDL3 Migration](/dev/adrs/adr-sdl3-migration)
- [Graph as Universal Model](/dev/adrs/adr-graph-as-universal-model) — Notebooks, code directories, entities all unified under graph nodes
- [CEF In-World Browser](/dev/features/cef-in-world-browser)
- [FFmpeg Video Playback](/dev/features/ffmpeg-video-playback)
- [Libtorrent](/dev/notes/libtorrent)
- [Xapian](/dev/notes/xapian)
- [Wallet](/dev/notes/wallet)
- Multi-light rendering, world tabs, per-world persistence

## Phase IV: Peak velocity (2026-03) — ~130 commits

The "world building" month. Terrain, graph editing, world entities, and lighting matured into a cohesive graph-backed system.

Key events:
- [Terrain Heightfield System](/dev/features/terrain-heightfield-system)
- Graph editing (selection, keyboard focus, inline property editing)
- World entity architecture (skybox, background, terrain as graph nodes)
- Physics containment over infinite floor plane
- [SSBO Quad Pipeline](/dev/adrs/adr-ssbo-quad-pipeline)
- Controller/dial input, QR encoding, Codex SDK

## Phase V: Stabilization (2026-04) — ~68 commits

Heavy refactoring month. Centralized lifecycle ownership, signal cleanup, and [canvas modes](/dev/features/canvas-mode-system) as pluggable behaviors.

Key events:
- [Composable States](/dev/adrs/adr-composable-states)
- [Lifecycle Centralization](/dev/lifecycle-centralization) — ownership over silent signal-driven code
- [Stylus Drawing Input](/dev/features/stylus-drawing-input) — raster layer, pressure-sensitive strokes
- [Yojimbo](/dev/notes/yojimbo)
- Canvas mode system (graph-surface, drawing, board)

## Phase VI: Agent layer (2026-05) — ~29 commits

Agent infrastructure: runner, presets, MCP transport, OpenCode streaming, reloadable units.

Key events:
- [Agent Runner System](/dev/features/agent-runner-system)
- Agent presets with risk model and MCP tool exposure
- [Hot Reload Units](/dev/features/hot-reload-units)
- User code directory scanner, HTTP ownership moved to Lua

## Phase VII: Cross-platform (2026-06) — ~52 commits

Windows cross-compile sprint. Board canvas mode.

Key events:
- [Board Canvas Mode](/dev/features/board-canvas-mode) — semantic connectors, item selection
- Windows cross-compilation (MinGW headers, path separators, clipboard CRLF)
- DEB/RPM packaging maturation, distro smoke tests
- Fennel cache clearing during hot-reload

## Phase VIII: Current (2026-07) — ~10 commits

Panel transfer system, repository workbench, conversation-first supervisor.

Key events:
- [Panel Transfer System](/dev/features/panel-transfer-system)
- [Repository Workbench](/dev/repository-workbench)
- Conversation-first supervisor with tee streaming

## Related

- [Milestones](/dev/project/milestones/) — current and future milestones
- [Subsystems](/dev/subsystems/) — architecture map
