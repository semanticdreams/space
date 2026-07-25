---
type: goal
status: done
tags:
  - goal
  - platform
  - foundation
  - engine
created: 2026-07-14
updated: 2026-07-14
---

# Core platform foundation

## Summary

The underlying runtime platform that all other features are built on: the C++ engine with its rendering/physics/audio pipeline, the Fennel widget and layout engine, in-world surfaces (browser, video), developer tooling (hot-reload, panel transfer), and HomeWorld activities (graph, drawing, board). These are the foundational capabilities that shipped during the early phases and Milestone 0.

## Why

Before higher-level features like graph browsing, world building, or agent tools can be useful, the platform itself must be solid. The core platform provides the runtime, the UI primitives, the spatial interaction model, and the developer workflow that everything else depends on.

## Success criteria

- C++ engine: OpenGL rendering, Bullet physics, OpenAL audio, SDL3 input — stable and performant
- Widget system: layout primitives (flex, stack, grid), leaf widgets (rectangle, text, image, button, input, list), composition — declarative and composable
- In-world surfaces: CEF browser, FFmpeg video playback renderable on arbitrary 3D geometry
- Developer tooling: hot-reload with snapshot/restore, panel transfer between surfaces, file watching
- Interaction surfaces: HomeWorld activities (graph, drawing, board), stylus input, touch routing

## Features implementing this goal

- [Layout Widget Engine](/dev/features/layout-widget-engine) — constraint-based layout and widget system
- [Activities Architecture](/dev/features/activities) — retained HomeWorld workflows for graph, drawing, and board
- [Board Canvas Mode](/dev/features/board-canvas-mode) — legacy implementation notes for the board activity
- [Stylus Drawing Input](/dev/features/stylus-drawing-input) — pressure-sensitive stylus with vector and raster layers
- [CEF In-World Browser](/dev/features/cef-in-world-browser) — CEF browser surfaces on 3D geometry
- [FFmpeg Video Playback](/dev/features/ffmpeg-video-playback) — in-world video with positional audio
- [Hot Reload Units](/dev/features/hot-reload-units) — live code reload with snapshot/restore and file watching
- [Panel Transfer System](/dev/features/panel-transfer-system) — transactional panel movement between surfaces
- [Wallet System](/dev/features/wallet-system) — crypto wallet with mnemonic generation and signing
- [Kernel System](/dev/features/kernel-system) — interactive computational kernel manager

- [Development Tooling](/dev/features/development-tooling) — profiling, testing, render capture, remote control, CLI tools

## Bugs

- [Windows Cef Support](/dev/project/bugs/windows-cef-support) — no Windows CEF handler
- [Mystery Layout Errors](/dev/project/bugs/mystery-layout-errors) — intermittent layout computation errors
- [Stale Async Callbacks](/dev/project/bugs/stale-async-callbacks) — stale callbacks after widget teardown

## ADRs underlying this goal

- [Fennel Over Python](/dev/adrs/adr-fennel-over-python) — language choice for the application model
- [SDL3 Migration](/dev/adrs/adr-sdl3-migration) — input and windowing migration
- [SSBO Quad Pipeline](/dev/adrs/adr-ssbo-quad-pipeline) — unified UI rendering pipeline
- [Composable States](/dev/adrs/adr-composable-states) — input handling architecture
- [Lua Branch Development](/dev/adrs/adr-lua-branch-development) — how the platform was built

## Related

- [Subsystems](/dev/subsystems/) — full architecture map
- [Milestones](/dev/project/milestones/) (Milestone 0)
- [Project History](/dev/project/history) — Phases I‑V built this foundation
- Subsystems: [Rendering](/dev/subsystems/rendering), [Input](/dev/subsystems/input), [Audio](/dev/subsystems/audio), [Networking](/dev/subsystems/networking), [Build](/dev/subsystems/build), [Process](/dev/subsystems/process), [Cross Platform](/dev/subsystems/cross-platform)
- Direct dev notes: [Cef In World Browsing](/dev/notes/cef-in-world-browsing), [Hackernews](/dev/notes/hackernews), [Morphs](/dev/notes/morphs), [Ripgrep](/dev/notes/ripgrep), [Sub_world](/dev/notes/sub_world), [Terminal](/dev/notes/terminal), [Xapian](/dev/notes/xapian), [Wallet](/dev/notes/wallet), [Wallet Core](/dev/notes/wallet-core), [Kernels](/dev/notes/kernels), [Entity Store](/dev/notes/entity-store), [Force Layout Barnes Hut](/dev/notes/force-layout-barnes-hut)
