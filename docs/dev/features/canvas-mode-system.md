---
type: feature
status: shipped
parent-goal: core-platform
tags:
  - feature
  - canvas
  - modes
  - graph
  - drawing
  - board
created: 2026-07-14
updated: 2026-07-14
---

# Canvas mode system

## Summary

Pluggable virtual surfaces that own their behavior per mode. Three modes exist: graph-surface (graph browsing), drawing (stylus/raster), and board (semantic connectors). Canvas modes are owned by the canvas widget and can be activated/deactivated, with panel transfer between them.

## Motivation

Different interaction surfaces (graph browsing, freehand drawing, structured boards) needed different input handling, rendering, and widget lifecycles. Rather than special-casing each inside the canvas widget, make them pluggable behaviors with a clean interface.

## Design

- **Mode interface**: each mode exposes `activate`, `deactivate`, and handles its own input routing, widget tree, and render state
- **Graph-surface mode**: graph nodes with force layout, selection, LOD, keyboard navigation
- **Drawing mode**: stylus input with pressure-sensitive strokes, vector + raster layers
- **Board mode**: semantic connectors, item selection, directed edges, resizable items
- **Panel transfer**: panels move between canvas modes and HUD via a receiver-registry protocol with rollback

## Tasks

- [x] Canvas mode shell with activate/deactivate lifecycle
- [x] Graph-surface mode → See [Graph Browsing](/dev/features/graph-browsing)
- [x] Drawing mode → See [Stylus Drawing Input](/dev/features/stylus-drawing-input)
- [x] Board mode → See [Board Canvas Mode](/dev/features/board-canvas-mode)
- [x] Panel transfer between modes → See [Panel Transfer System](/dev/features/panel-transfer-system)

## Related

- Goal: [Core Platform](/dev/features/core-platform)
- Depends on: [Layout Widget Engine](/dev/features/layout-widget-engine)
- ADR: [Composable States](/dev/adrs/adr-composable-states)
- See: [Lifecycle Invariants](/dev/lifecycle-invariants)
