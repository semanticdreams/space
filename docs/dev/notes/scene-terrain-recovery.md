---
type: dev-note
tags:
  - note
---

# Scene Terrain Recovery

This note documents the repair action that recovers scene objects which have fallen below terrain.

The feature is intentionally designed as a rare maintenance tool, not as a general runtime placement system. The long-term plan is to prevent objects from getting into these bad states in the first place. Because of that, the implementation favors containment and reliability over broad abstraction.

## Goal

The recovery action should:

- find terrain-bound scene objects that are below terrain
- raise them onto the terrain surface while preserving their current horizontal location when possible
- if no terrain covers the current `xz`, move them to the nearest terrain domain in horizontal distance and place them on that surface

## Where It Lives

The main implementation lives in:

- `assets/lua/scene-terrain-recovery.fnl`

It is exposed from the root context menu through:

- `assets/lua/menu-manager.fnl`

Shared modules only provide the minimum support needed:

- `assets/lua/scene.fnl`
  stores per-child `:terrain-binding` metadata
- `assets/lua/layout-physics-bodies.fnl`
  exposes a reposition helper for layout-backed physics bodies
- `assets/lua/ball.fnl`
  provides a ball-specific teleport path so recovery does not reuse drag side effects

The recovery feature should stay mostly inside `scene-terrain-recovery.fnl`. Avoid growing `scene` into a recovery-specific orchestration layer unless there is a strong reason.

## Candidate Selection

Recovery does not operate on all scene content blindly.

It builds candidates from two sources:

1. scene panel children
2. registered scene objects

Scene panel children are considered terrain-bound by default unless their `:terrain-binding` metadata explicitly disables them.

Registered scene objects are not terrain-bound by default. They must opt in by supplying `:terrain-binding {:enabled? true ...}` when they need recovery. This keeps generic object additions from being silently swept into terrain repair.

## Terrain Binding Contract

Recovery works with a small adapter contract:

- `get-origin-position`
- `get-support-bounds`
- `move-origin-position!`

### `get-origin-position`

Returns the object origin used for preserving horizontal location and for applying the final recovered transform.

### `get-support-bounds`

Returns the world-space support bounds for placement.

This is the key design choice. Recovery does not use a scalar vertical offset anymore. Instead it computes the object’s world AABB from the returned bounds and uses the minimum `y` of that AABB as the bottom contact point.

This handles:

- bottom-left-origin widgets naturally
- non-bottom origins
- rotated support shapes, as long as the bounds returned are correct

### `move-origin-position!`

Moves the object to a new origin position.

This must also keep any runtime physics representation in sync. For layout-backed rigid bodies this is done through `layout-physics-bodies`. For balls this is a dedicated teleport path in `ball.fnl`.

Do not implement this by simulating a drag interaction unless you truly want drag semantics. Recovery should be a deterministic reposition operation.

## Terrain Query Rules

Recovery uses runtime terrain transforms, not just persisted terrain records.

This is important because terrain may be affected by:

- scene root transforms
- runtime layout transforms
- future terrain replacement or other runtime changes

When checking support under the current horizontal location, recovery uses the same runtime terrain-query-record path as scene terrain queries.

When no terrain covers the current `xz`, recovery finds the nearest terrain domain in horizontal distance and snaps to the nearest surface point on that terrain.

## Why “Lowest Covering Terrain”

If multiple terrains overlap at the object’s current `xz`, recovery chooses the lowest covering surface.

That rule is conservative:

- it avoids pushing an object upward through an upper terrain layer when it may actually belong on a lower one
- it is stable and easy to reason about

If future gameplay semantics require a different rule, that should be an explicit change with tests. Do not silently reinterpret this behavior.

## Trade-Offs

### What we optimize for

- reliable one-shot repair
- minimal coupling to core scene architecture
- explicit hooks only where needed

### What we intentionally do not optimize for

- high-frequency runtime use
- rich placement semantics for every object type
- a universal object capability system
- perfect inference of “which terrain this object really belongs to”

This is not a general terrain attachment system. It is a repair tool.

## Current Limitations

- Terrain-bound scene panel children default to enabled. That matches current scene semantics, but it means callers must explicitly disable recovery for scene panels that should be free-floating.
- Recovery uses world AABB bottom placement. That is robust, but it is still an approximation for irregular objects whose real support footprint is not well represented by their bounds.
- Nearest-terrain selection is based on horizontal domain distance, not semantic ownership.
- Objects with custom movement/physics behavior must supply a correct `move-origin-position!` hook or they may visually move while physics state lags behind.
- Recovery reposition for physics-backed layouts is a teleport/sync path, not a drag-release path. Do not reintroduce impulses there unless tests prove they are necessary.

## What To Watch Out For

### 1. Do not spread recovery logic into `scene`

If a future change requires more special cases, prefer extending `scene-terrain-recovery.fnl` first.

Bad direction:

- new recovery-specific methods on `scene`
- more recovery branching in generic scene add/remove/update flows

Good direction:

- keep `scene` as a source of runtime state
- keep recovery logic in the recovery module

### 2. Be careful with new object types

If a new object can be recovered, ask:

- should it be terrain-bound at all?
- is its default layout AABB good enough for support placement?
- does moving it require synchronizing physics or other runtime state?

If the default panel adapter is not enough, add a small custom terrain-binding override near that object’s implementation. Do not broaden the shared contract casually.

### 3. Preserve runtime transform correctness

Nearest-terrain and surface-under-point logic must always use runtime terrain transforms. If someone “simplifies” recovery by querying raw terrain records directly, transformed-terrain recovery will regress.

### 4. Avoid hidden impulses or side effects

Recovery should not:

- apply drag-only behavior
- inject motion unless necessary to synchronize physics state
- trigger unrelated UI actions

The action should be idempotent enough that running it twice does not create new drift.

### 5. Test transformed cases

Whenever recovery logic changes, keep at least these cases covered:

- lowest overlapping terrain wins
- nearest terrain recovery
- physics-backed object reposition
- transformed terrain or transformed scene root

## Recommended Future Direction

As preventive measures are added and objects stop falling below terrain in the first place:

- keep this feature available as a manual repair tool
- resist turning it into a bigger subsystem
- only revisit its architecture if real object types prove the current adapter model insufficient

If the feature ever becomes common enough to matter in normal workflows, that is a signal to fix the underlying placement/physics pipeline, not to make recovery more elaborate.


## See also

- [World Building](/dev/features/world-building), [Terrain Heightfield System](/dev/features/terrain-heightfield-system)
