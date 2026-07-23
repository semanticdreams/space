---
type: goal
status: active
tags:
  - goal
  - world
  - terrain
  - building
created: 2026-07-14
updated: 2026-07-14
---

# Interactive world building

## Summary

Make the 3D world editable, usable, and playable. Users should be able to add and manipulate terrain interactively, place arbitrary widgets into the world, create new geometry live in context, and control physics and lighting. This is what distinguishes Space from a flat desktop UI.

## Why

Space is a 3D spatial computing platform, not a 2D window manager. Without interactive world building, the spatial dimension is just decoration. Terrain, physics, lighting, and in-world widgets make the 3D environment a first-class creative surface.

## Success criteria

- Terrain is created, edited, and persisted as a world-state-backed object exposed through the graph
- Physics collision works on editable terrain, not just an infinite floor plane
- Lighting controls are interactive and spatial (not buried in config dialogs)
- Widgets can be placed into the 3D world, not just on the HUD or canvas
- A small set of terrain, geometry, widget, physics, and lighting workflows feel natural

## Features implementing this goal

- [Terrain Heightfield System](/dev/features/terrain-heightfield-system) — Perlin-noise heightfield with runtime editing and physics

## Bugs

*(none yet)*

## Related

- [Subsystems](/dev/subsystems/) — Engine (Physics, Rendering), Widget System (Terrain)
- [Milestones](/dev/project/milestones/) (Milestone 3)
- [Project History](/dev/project/history) — Phase IV was the "world building" month (March 2026)
- Dev notes: [Terrain Architecture](/dev/notes/terrain-architecture), [Heightfield Terrain Implementation](/dev/notes/heightfield-terrain-implementation), [Terrain Selection](/dev/notes/terrain-selection), [Terrain Physics Debugging](/dev/notes/terrain-physics-debugging), [Lighting](/dev/notes/lighting)
