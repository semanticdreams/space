# Activity-Aware World Graph Exposure Design

## Context

Space previously exposed HomeWorld scene data through world-level graph keys such as `background:<world-id>`, `skybox:<world-id>`, `terrains:<world-id>`, `lights:<world-id>`, and `scene-panels:<world-id>`. That matched an older model where much of this state appeared to belong directly to the world.

Activities changed that ownership boundary. Scene state now lives under activity sessions, with canonical keys like `:panels`, `:terrains`, `:lights`, `:skybox`, `:background`, and `:containment` in `world.state.activity.sessions.<activity-id>.scene`. The sandbox activity owns the durable editable scene; the graph activity has its own scene slot and background; drawing and board also have activity session state. The same principle applies beyond scene: HUD, canvas, and any future surface-specific state should be exposed through the activity that owns it, not flattened onto the world root.

The graph doctrine remains: graph core persists topology only; graph nodes are adapters over owning systems; `GraphMap` owns interaction context, map-local membership, layout, and selection.

## Problem

The current graph exposure is semantically stale:

- World-level scene keys actually read and write the sandbox activity session.
- `WorldNode` presents scene panels, terrains, skybox, background, and lights as if they are direct world categories.
- Other activity-owned surfaces, especially graph canvas state and activity HUD/canvas contributions, do not have a clear graph exposure model.
- Persisted graph topology may contain old keys that no longer describe the owning state.
- Documentation still mixes possible world-shared scene state with the implemented activity-session model.

This makes graph navigation less useful and risks future bugs where graph nodes mutate the wrong activity surface.

## Goals

- Make world graph exposure activity-aware across surfaces, not only scene.
- Preserve graph doctrine: domain state remains in activity/world owning systems, and graph nodes adapt it.
- Keep world root nodes useful for world identity, activation, close actions, and world-level metadata.
- Expose activity-owned scene, HUD, canvas, and future surfaces through keys that identify both world and activity.
- Provide deterministic handling for old persisted graph topology keys.
- Avoid long-term legacy aliases that hide ownership.

## Non-Goals

- Do not move activity state into graph persistence.
- Do not reintroduce a broad world-shared scene state unless a later product decision explicitly requires it.
- Do not redesign activity runtime lifecycle or scene slot activation beyond what is needed for correct graph adapters.
- Do not expose every possible runtime-only UI implementation detail; expose durable or inspectable activity-owned surface state that is useful in graph navigation.

## Design Direction

Use activity-aware graph keys for world-owned activities and their surfaces.

Recommended key hierarchy:

```text
worlds
world:<world-id>
world-activities:<world-id>
world-activity:<world-id>:<activity-id>
activity-surfaces:<world-id>:<activity-id>
activity-scene:<world-id>:<activity-id>
activity-background:<world-id>:<activity-id>
activity-skybox:<world-id>:<activity-id>
activity-lights:<world-id>:<activity-id>
activity-terrains:<world-id>:<activity-id>
activity-scene-panels:<world-id>:<activity-id>
activity-hud:<world-id>:<activity-id>
activity-canvas:<world-id>:<activity-id>
```

The hierarchy is conceptual; implementation can introduce nodes incrementally. The important invariant is that keys for activity-owned data include both `world-id` and `activity-id`.

`WorldNode` should expose:

- world metadata and world actions;
- an activities category;
- activity nodes beneath that category.

`WorldNode` should not directly expose background, skybox, lights, terrain, scene panels, HUD, or canvas nodes unless those records are truly world-owned. For current code, sandbox scene state should be visible as activity-owned state under `world-activity:<world-id>:sandbox`.

## Surface Model

Activity-owned surfaces are graph-exposed through surface adapters:

- **Scene surface:** scene panels, terrain, skybox, background, lights, containment, and scene cameras when durable/inspectable.
- **HUD surface:** durable or declarative activity HUD contributions, panel state, dock contribution state, or activity-specific HUD controls where useful.
- **Canvas surface:** graph map/canvas presentation state, drawing canvas state, board canvas state, and activity-specific canvas cameras/layouts where durable/inspectable.

Surface nodes should be omitted when an activity does not own meaningful state for that surface. Empty placeholder nodes should be used only when they improve discoverability and have clear actions.

## Data Flow

1. A graph map loads a key through `graph/key-loaders.fnl`.
2. The key loader parses `world-id`, `activity-id`, and optional surface/object identifiers.
3. The loader resolves the world through `world-manager`.
4. The loader resolves the owning activity session and surface state.
5. The loader constructs a graph node adapter with identifiers and accessors.
6. Node actions mutate the owning activity/session state, not graph core.
7. If the mutated activity surface is active, runtime services are synchronized for that same activity slot/surface only.
8. The owning world is persisted and `world-manager.changed` is emitted.

## Legacy Topology Handling

Old persisted keys should be migrated or pruned at graph-map hydration time:

- `background:<world-id>` → `activity-background:<world-id>:sandbox`
- `skybox:<world-id>` → `activity-skybox:<world-id>:sandbox`
- `lights:<world-id>` → `activity-lights:<world-id>:sandbox`
- `terrains:<world-id>` → `activity-terrains:<world-id>:sandbox`
- `scene-panels:<world-id>` → `activity-scene-panels:<world-id>:sandbox`

The migration should be deterministic and one-time. Invalid old keys should not create duplicate canonical nodes. Long-term compatibility aliases should not remain in key loaders unless a specific migration window is documented.

## Error Handling

- Missing world entries should cause graph adapters to remove themselves from the current graph/map where existing patterns support that.
- Corrupt activity state should fail loudly with context identifying the world, activity, and surface.
- Missing optional surfaces should be represented as absent nodes rather than silently fabricating data, unless the owning activity explicitly defines an empty canonical state.
- Updates must not silently fall back from the requested activity to sandbox.

## Testing and Validation

Focused coverage should include:

- world node category expansion now exposes activities/surfaces instead of direct world scene categories;
- sandbox scene state remains reachable through activity-aware keys;
- non-sandbox activity state can be exposed without mutating sandbox state;
- legacy graph topology keys migrate to sandbox activity-aware keys;
- graph map-local adapter semantics remain unchanged;
- active runtime sync updates only the matching active activity surface.

Validation should follow the Space Fennel ladder: `make fennel-check`, then `make constraints`, then focused Fennel tests for graph/world/activity exposure, with broader tests when persisted graph map hydration or shared runtime behavior changes.

## Recommended Approach

Implement activity-aware exposure incrementally:

1. Update docs and graph terminology.
2. Introduce generic activity/surface accessors in `graph/world-data.fnl`.
3. Register activity-aware key loaders.
4. Update world/activity/surface nodes.
5. Migrate old topology keys.
6. Update tests and remove sandbox-as-world assumptions.

This approach keeps the graph useful as a navigable interface while making ownership explicit and future-proof for scene, HUD, canvas, and additional activity surfaces.
