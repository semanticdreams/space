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

The underlying runtime platform that all other features are built on: the C++ engine with its rendering/physics/audio pipeline, the Fennel widget and layout engine, in-world surfaces (browser, video), developer tooling (hot-reload, panel transfer), and interaction surfaces (canvas modes, drawing, board). These are the foundational capabilities that shipped during the early phases and Milestone 0.

## Why

Before higher-level features like graph browsing, world building, or agent tools can be useful, the platform itself must be solid. The core platform provides the runtime, the UI primitives, the spatial interaction model, and the developer workflow that everything else depends on.

## Success criteria

- C++ engine: OpenGL rendering, Bullet physics, OpenAL audio, SDL3 input — stable and performant
- Widget system: layout primitives (flex, stack, grid), leaf widgets (rectangle, text, image, button, input, list), composition — declarative and composable
- In-world surfaces: CEF browser, FFmpeg video playback renderable on arbitrary 3D geometry
- Developer tooling: hot-reload with snapshot/restore, panel transfer between surfaces, file watching
- Interaction surfaces: canvas modes (graph-surface, drawing, board), stylus input, touch routing

## Features implementing this goal

- [[layout-widget-engine]] — constraint-based layout and widget system
- [[canvas-mode-system]] — pluggable virtual surfaces (graph, drawing, board)
- [[board-canvas-mode]] — semantic board with connectors, selection, resizable items
- [[stylus-drawing-input]] — pressure-sensitive stylus with vector and raster layers
- [[cef-in-world-browser]] — CEF browser surfaces on 3D geometry
- [[ffmpeg-video-playback]] — in-world video with positional audio
- [[hot-reload-units]] — live code reload with snapshot/restore and file watching
- [[panel-transfer-system]] — transactional panel movement between surfaces
- [[wallet-system]] — crypto wallet with mnemonic generation and signing
- [[kernel-system]] — interactive computational kernel manager

- [[development-tooling]] — profiling, testing, render capture, remote control, CLI tools

- [[opencode-agent-workflow]] — Python-based multi-role OpenCode agent orchestrator

## Bugs

- [[bugs/windows-cef-support]] — no Windows CEF handler
- [[bugs/mystery-layout-errors]] — intermittent layout computation errors
- [[bugs/stale-async-callbacks]] — stale callbacks after widget teardown

## ADRs underlying this goal

- [[adr-fennel-over-python]] — language choice for the application model
- [[adr-sdl3-migration]] — input and windowing migration
- [[adr-ssbo-quad-pipeline]] — unified UI rendering pipeline
- [[adr-composable-states]] — input handling architecture
- [[adr-lua-branch-development]] — how the platform was built

## Related

- [[subsystems]] — full architecture map
- [[milestones]] (Milestone 0)
- [[history]] — Phases I‑V built this foundation
- Subsystems: [[subsystems/rendering]], [[subsystems/input]], [[subsystems/audio]], [[subsystems/networking]], [[subsystems/build]], [[subsystems/process]], [[subsystems/cross-platform]]
- Direct dev notes: [[dev-notes/cef-in-world-browsing]], [[dev-notes/hackernews]], [[dev-notes/morphs]], [[dev-notes/ripgrep]], [[dev-notes/sub_world]], [[dev-notes/terminal]], [[dev-notes/xapian]], [[dev-notes/wallet]], [[dev-notes/wallet-core]], [[dev-notes/kernels]], [[dev-notes/entity-store]], [[dev-notes/force-layout-barnes-hut]]
