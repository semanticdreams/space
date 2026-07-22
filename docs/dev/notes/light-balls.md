---
type: dev-note
tags:
  - note
---

# Light Balls

This note documents the first `light-ball` design and implementation.

## Summary

`light-ball` is a new scene object kind.

- It owns its own physics body.
- It owns its own editable light-ball config.
- It attempts to create one runtime point light when present in a live scene.
- The runtime point light is transient and is not persisted into `scene.lights`.
- Persistence works like `physics-ball`: the scene panel record is the source of truth.

This keeps the feature local to the scene-object system and avoids entangling graph/world light persistence with physics-owned light behavior.

## Why Not Persist The Point Light?

We explored two models:

1. Persist the linked point light in `scene.lights.point`.
2. Persist the light settings inside the light ball itself and recreate the runtime point light on load.

The second model was chosen.

Reasons:

- It avoids feature-disable/re-enable overwrite problems. If light balls are disabled for a while and the user edits normal point lights directly, re-enabling light balls should not silently overwrite those point lights from stale state.
- It keeps ownership clear: normal point lights are persisted by the world lighting state, while light-ball point lights are derived runtime state.
- It matches the existing scene-object persistence model better. `physics-ball` persists as a scene panel; `light-ball` now does the same.

Trade-off:

- Runtime point lights created by light balls are not visible through persisted world light state alone.
- The first version accepts that trade-off because light balls are not exposed through graph yet.

## Source Of Truth

There are two separate sources of truth:

- `scene.lights`
  - persisted lighting state for normal world lights
- `scene.panels[kind=light-ball]`
  - persisted state for light-ball-owned light config and physics config

At runtime, a light ball materializes a point light into `app.lights`.

The runtime point light is derived state:

- created when the light ball is added/restored
- may remain absent when all runtime point-light slots are already in use
- removed when the light ball is removed/dropped
- retried automatically during sync when capacity later becomes available
- recreated automatically if the live light system is replaced

## Runtime Lifecycle

### Creation

Creation is routed through `Scene.add-light-ball`.

Creation no longer preflights point-light capacity.

The light ball scene object is always created.

If runtime point-light capacity is already exhausted:

- the light ball still exists
- it simply starts in an unlit state
- it keeps retrying runtime light allocation during sync

This keeps persistence simple and makes it possible to support future runtime light-selection strategies, such as activating only the nearest light balls to the camera.

### Live Scene Registration

When the element is added to the scene:

- it attempts to allocate one transient runtime point light in `app.lights`
- it registers itself as a scene object for per-frame sync and physics lifecycle
- it registers a right-click context menu with `Edit` and `Remove`

### Sync

The light ball sync path does two things:

1. sync physics body -> scene layout
2. sync scene layout center -> runtime point light position

Runtime light allocation is also retried during sync when the ball is currently unlit.

Only transform is synchronized every frame once a runtime light exists.

Light parameters are not rewritten every frame.

Why:

- per-frame transform sync is required because physics is the source of truth for spatial state
- per-frame full light-field stomping would add unnecessary work
- if a user edits the runtime point light elsewhere, those non-transform edits are allowed to survive in this simplified version

### Removal

Manual removal through the context menu is ordered strictly:

1. remove runtime point light
2. remove scene object

If no runtime point light is currently assigned, removal just removes the scene object.

Scene unload/drop also removes the runtime point light in the element drop path.

## Persistence

`light-ball` persistence includes:

- transform captured by the scene panel record
- point-light parameters
- physics tuning parameters
- render color
- radius and size

It restores through `light-ball.restore`.

The restore path delegates to `Scene.add-light-ball`.

Restore does not fail when the world contains more light balls than available runtime point-light slots. Extra light balls restore normally and remain unlit until a slot becomes available.

## Why Runtime Lights Must Be Transient

`Scene.capture-state` persists `app.lights:get-state()`.

If light-ball-created runtime point lights were serialized like normal lights:

- they would be saved into `scene.lights`
- restore would reapply them as normal persisted point lights
- restoring the panels would then create a second copy through `light-ball`

That would duplicate lights on restore.

To avoid that, the runtime point light created by `light-ball` is marked transient inside `LightSystem`.

Transient lights:

- participate in the live renderer path
- count against runtime capacity
- are excluded from serialized light state

This keeps world save output clean without teaching the graph or persisted light state about light-ball ownership.

## Why Graph Is Not Involved

The current feature deliberately does not introduce graph coupling.

- `light-ball` is not a graph node type
- normal point-light graph views stay unchanged
- no “controlled by …” logic is added to graph light editing

This means:

- graph continues to expose persisted world lights
- light-ball runtime lights remain a scene-object concern

That is intentional simplification for the first version.

## Visual Path

The original `raw-sphere.fnl` path was not used directly for the final runtime visual because it allocates and rewrites triangle data per instance.

`light-ball` instead uses a shared instanced sphere visual built from the same sphere algorithm:

- sphere geometry is generated once per style/resolution
- instances use `InstancedColorMeshBatch`
- shared mesh lifetime is handled through `SharedInstancedMeshCache`

This matches the performance model already used by `soccer-ball-visual.fnl` while keeping the light-ball mesh visually simple.

## Editor

Editing is done through a HUD float dialog opened from the light-ball context menu.

The dialog contains two tabs:

- `Light`
  - point-light parameters
- `Physics`
  - the same tuning surface as the soccer ball path

Edits apply only when the user presses `Apply`.

### Light Tab

Applying light changes:

- updates the persisted light-ball config
- updates the live runtime point light immediately

### Physics Tab

Applying physics changes:

- updates the persisted light-ball config
- rebuilds the live rigid body immediately
- keeps the object centered at the same physics/layout position

Radius changes are live and rebuild both physics assumptions and rendered size.

## Defaults

Light-ball defaults intentionally do not use the canonical point-light defaults.

The initial runtime light parameters are copied from the customized point light in the first home world:

- ambient `[5, 5, 4]`
- diffuse `[100, 70, 0]`
- specular `[50, 50, 0]`
- specular power `5`
- constant `3`
- linear `0.001`
- quadratic `0.00132`

Physics defaults match the soccer ball path except:

- radius is half-sized
- mass is lower

## Known Trade-Offs

- Because graph is intentionally uninvolved, light-ball-owned runtime point lights are not represented as persisted world point lights.
- Because only transform is synchronized every frame, edits to runtime light parameters from elsewhere are not blocked and may persist until the light ball is reconfigured or recreated.
- Because runtime lighting is now best-effort, some light balls may currently be unlit when the scene contains more candidate emitters than the live point-light budget allows.
- The first version chooses simpler ownership and persistence boundaries over unified light editing semantics.

## Future Directions

Potential later improvements:

- expose light balls through graph as first-class scene objects
- surface read-only runtime light inspection in graph
- add generic runtime light-controller concepts if more systems begin to own live lights
- separate reusable physics-sphere object logic from both `ball` and `light-ball` if more sphere-like scene objects appear


## See also

- [World Building](/dev/features/world-building)
