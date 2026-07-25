---
type: feature
status: shipped
parent-goal: core-platform
tags:
  - feature
  - stylus
  - drawing
  - input
created: 2026-07-14
updated: 2026-07-14
---

# Stylus drawing input

## Summary

Pressure-sensitive stylus input routed through explicit pen routing to the Drawing activity. Supports vector strokes and raster layer painting with pressure-based width/opacity.

## Motivation

Drawing on a canvas surface needed stylus-aware input handling distinct from mouse/keyboard. Pressure sensitivity, tilt, and explicit pen routing (avoiding accidental touch input during drawing) were required.

## Design

- **Explicit pen routing**: Stylus events are routed to the drawing surface only; touch events are suppressed in drawing mode
- **Pressure-sensitive strokes**: Vector strokes vary width/opacity with pen pressure
- **Raster layer**: Separate raster backend for brush-based painting (documented in [Drawing Raster Implementation](/dev/notes/drawing-raster-implementation))
- **Layer model**: Vector and raster layers coexist in the same drawing document

## Tasks

- [x] Stylus input routing with pressure/tilt
- [x] Vector stroke rendering
- [x] Raster layer brush painting
- [x] Explicit pen routing (touch suppression)

## Related

- Goal: [Core Platform](/dev/features/core-platform)
- Depends on: [Activities Architecture](/dev/features/activities)
- See: [Drawing Architecture](/dev/notes/drawing-architecture), [Drawing Raster Implementation](/dev/notes/drawing-raster-implementation)
