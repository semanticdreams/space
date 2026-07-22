---
type: feature
status: shipped
parent-goal: core-platform
tags:
  - feature
  - layout
  - widget
  - ui
created: 2026-07-14
updated: 2026-07-14
---

# Layout widget engine

## Summary

Custom 2D/3D layout engine for Fennel widgets, built from scratch in Fennel starting `2025-09-01`. The engine uses explicit `Layout` objects with `measurer` and `layouter` closures, dirty propagation, and depth offsets. It underpins everything visual in Space — HUD, dialogs, canvas panels, graph views, agent transcripts, and board items.

## Motivation

The Python prototype had a manual layout system where nodes were assembled by hand without a uniform widget hierarchy. Each object tracked its own children for teardown. The Fennel layout system provides:
- Declarative widget composition (Flex, Stack, Grid, Padding, Sized)
- Automatic measure/layout passes with dirty tracking
- Proper ownership: composite widgets own their children; teardown cascades through the widget tree
- Depth offsets for z-ordering without z-fighting

## Design

- **Layout objects**: `Layout` instances with `measurer` (compute desired size) and `layouter` (assign child positions)
- **Dirty rules**: `mark-measure-dirty` propagates to descendants; `mark-layout-dirty` is subtree-local
- **Depth offsets**: `layout.depth-offset-index` for ordering; backgrounds at parent, content at parent+1
- **Widget composition**: `Flex`, `Stack`, `Grid`, `Padding`, `Sized` as layout primitives; `Rectangle`, `TextSpan`, `Button` as leaf widgets
- **Build pattern**: Each widget exports a constructor returning a `build` closure; `build` receives renderer context, instantiates children, returns entity with `layout` and `drop`

## Tasks

- [x] Measure/layout pass with dirty propagation
- [x] Flex, Stack, Grid, Padding, Sized layout primitives
- [x] Rectangle, TextSpan, Image, Button, Input leaf widgets
- [x] Depth offsets and z-ordering
- [x] Widget ownership and recursive teardown
- [x] Layout contract tests

## Related

- Goal: [Core Platform](/dev/features/core-platform)
- Used by: [Canvas Mode System](/dev/features/canvas-mode-system), [CEF In-World Browser](/dev/features/cef-in-world-browser), [Board Canvas Mode](/dev/features/board-canvas-mode)
- ADR: [SSBO Quad Pipeline](/dev/adrs/adr-ssbo-quad-pipeline)
- See: [Widget Ownership](/dev/widget-ownership-and-teardown)
- See: [Mystery Layout Error](/dev/notes/mystery-layout-error), [Resize Bugs](/dev/notes/resize-bugs)
