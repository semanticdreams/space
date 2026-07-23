---
type: feature
status: shipped
parent-goal: world-building
tags:
  - feature
  - terrain
  - heightfield
  - world
created: 2026-07-14
updated: 2026-07-14
---

# Terrain heightfield system

## Summary

Perlin-noise-based heightfield terrain with runtime editing, graph integration, and physics interaction. 51 commits from 2026-02 to 2026-04 formed this subsystem.

## Motivation

Interactive world building requires editable terrain as a first-class object. Terrain should be exposed through the graph like everything else, with live editing, physics collision, and persistence.

## Design

- **Heightfield mesh**: Perlin noise generation with runtime vertex manipulation
- **Graph integration**: Each terrain is exposed through the graph with typed properties (size, resolution, heightmap). Terrain data lives in world scene state; the graph node is a projection.
- **Physics**: Terrain mesh generates Bullet collision shapes; physics containment replaced the infinite floor plane
- **Editing**: Raise/lower/smooth/flatten brushes with visual feedback and undo
- **Persistence**: Heightmap stored in world state, persisted alongside world serialization. The graph exposes the terrain for navigation/linking/editing.

## Tasks

- [x] Heightfield mesh generation (Perlin noise)
- [x] Runtime terrain editing (brush tools)
- [x] Physics collision from heightfield
- [x] Graph node integration (terrain exposed as graph node)
- [x] Persistence and serialization
- [x] Selection model for terrain editing

## Related

- Goal: [World Building](/dev/features/world-building)
- See: [Terrain Architecture](/dev/notes/terrain-architecture), [Heightfield Terrain Implementation](/dev/notes/heightfield-terrain-implementation), [Terrain Selection](/dev/notes/terrain-selection), [Terrain Physics Debugging](/dev/notes/terrain-physics-debugging)
