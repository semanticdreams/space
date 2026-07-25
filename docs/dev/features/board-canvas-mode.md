---
type: feature
status: legacy
parent-goal: core-platform
tags:
  - feature
  - board
  - canvas
  - connectors
created: 2026-07-14
updated: 2026-07-14
---

# Board activity

This page documents the original board canvas-mode implementation. The current runtime exposes board through the HomeWorld [Activities Architecture](/dev/features/activities).

## Summary

Semantic board surface for structured visual thinking. Items can be placed, resized, connected with directed edges, and selected. Built as a retained HomeWorld activity.

## Motivation

Unlike freeform drawing, a board needs structured items with typed relationships — think mind maps, flowcharts, dependency diagrams. The board activity provides this with item types, connector edges, selection, and resize handles.

## Design

- **Board items**: Typed visual nodes (text blocks, shapes, images) with resize handles
- **Connectors**: Directed edges between items with start/end anchor points
- **Selection**: Multi-select with rubber-band or click
- **Connect Items action**: Quick connector creation between selected items
- **Resizables**: Board items use the resizables system for consistent resize interaction

## Tasks

- [x] Board item creation and placement
- [x] Item selection and multi-select
- [x] Directed connector edges
- [x] Connect Items action
- [x] Item resizing via resizables system

## Related

- Goal: [Core Platform](/dev/features/core-platform)
- Depends on: [Activities Architecture](/dev/features/activities)
- See: commits `f554cadf`, `108311a1` (2026-06/07)
