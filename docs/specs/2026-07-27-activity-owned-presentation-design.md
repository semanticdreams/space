# Activity-Owned Presentation Design

## Context

Recent activity/sandbox work exposed a mismatch in Space's runtime model. Activities
are intended to explicitly add the content they want displayed, but several display
and control systems still use mutable `app` globals as if there were one active
world camera, one active control stack, and one global physics containment state.

The problematic global assumptions include:

- `app.camera` and `app.first-person-controls` as active scene camera/control state.
- A single runtime canvas camera shared by canvas-oriented activities.
- `app.physics-containment-config`, `app.physics-containment-scene`, and
  `app.__physics-global-containment` as global containment state.
- Scene service state, such as lights, skybox, and background, captured/applied
  through app-level services rather than activity-owned presentation state.

Keeping `Scene` in the render path is not itself the problem. If an activity does
not add scene content, nothing scene-specific should render. The anti-pattern is
activity-based render toggling or global state cleanup that compensates for leaked
ownership.

## Design Goal

Activities own their presentation state completely. An activity may have zero, one,
or many cameras; zero, one, or many control objects; and any combination of scene,
canvas, HUD, or other renderable targets. Nothing is inherited from another
activity unless the activity explicitly references shared domain data.

Shared world/domain data remains shared when modeled as domain data. Presentation
state is not shared implicitly.

## Selected Approach

Use an activity-owned presentation API over the existing retained `Scene`, `Canvas`,
and `Hud` surfaces.

This keeps the current surface and slot architecture, but changes ownership and
discovery:

- Activities declare the render targets they contribute.
- Activities own cameras and controls used by those targets.
- Activities own service state required by those targets: lights, skybox,
  background, and physics containment.
- App-level render/input helpers query the active world runtime presentation rather
  than reading mutable global camera/control/containment state.

This is intentionally smaller than introducing a fully generic compositor graph,
but it establishes the same ownership invariant.

## Core Invariants

1. No activity receives scene/canvas content, cameras, controls, lighting, skybox,
   background, or containment unless it creates/restores that state in its own
   activity-owned session or slot.
2. App globals may hold stable references to systems, such as the active world
   runtime or renderer manager, but they must not be authoritative storage for
   activity presentation state.
3. Renderers do not toggle surfaces based on activity ids. They draw the render
   targets exposed by the active presentation model.
4. Empty scene slots are naturally inert: no content, no camera, no containment,
   no lights/skybox/background contribution beyond explicit defaults owned by the
   active presentation.
5. Physics containment installation is owned by an activity presentation/slot, not
   by `app` globals.

## Presentation Model

The active world runtime exposes a presentation provider. Conceptually, it supports:

- `render-targets`: ordered render views contributed by the active activity.
- `input-targets`: the controls and pointer targets contributed by the active
  activity.
- `service-state`: lights, skybox, background, and containment contributed by the
  active activity.
- `screen-ray-targets`: target-aware ray conversion for interactions that need it.

A render target is not just a surface. It is a view over a surface, with the camera
or projection data required to render it. This allows an activity to expose no
camera, one camera, or multiple cameras without a global `app.camera` assumption.

Example conceptual render target shape:

```fennel
{:surface app.scene
 :slot scene-slot
 :camera sandbox-camera
 :projection projection
 :layers [:geometry :text :sub-apps]
 :service-state sandbox-scene-services}
```

The exact field names can follow existing Fennel style during implementation, but
the ownership boundary is required: the activity/session/slot owns the target and
its camera.

## Scene and Canvas Slots

Existing Scene and Canvas activity slots remain useful retention boundaries.

- Sandbox owns a scene slot with scene content, scene camera(s), controls, and
  containment when it wants containment.
- Graph, drawing, board, and user activities own canvas slots and may also own
  scene slots if they intentionally add scene content.
- Creating an empty scene slot is acceptable, but it must not automatically imply
  a camera, controls, lights, skybox, background, or containment.
- Canvas-oriented activities must not share a single runtime canvas camera by
  default. Each canvas slot/activity should own its camera state if it needs one.

## Rendering Flow

The renderer asks the active runtime presentation for render targets and draws
those targets in order. It no longer treats `app.scene`, `app.canvas`, or
`app.camera` as the active presentation truth.

Scene may still be rendered every frame if the presentation provider returns a
scene target. If the active activity did not add scene content or expose a scene
target, no scene content is rendered. This avoids activity-id conditionals while
preserving the principle that activities display what they add.

## Input and Camera Flow

Input routing uses active presentation controls instead of `app.first-person-controls`
or `app.active-pointer-controls` as authoritative state.

Screen-to-world helpers become target-aware. Code that needs a ray asks for a ray
from a specific activity-owned render target or uses the active presentation's
declared default ray target. Calls that depend on a camera fail loudly if the
activity has not supplied one.

## Physics Containment

`physics-containment` becomes an owned manager/instance API rather than an app-global
singleton.

Required behavior:

- Installed containment planes are associated with the owning activity presentation
  or scene slot.
- Visualization batches are created in the owner slot's build context.
- Deactivating or dropping the owner drops its containment installation.
- Debounced refresh cannot install containment into a different active activity's
  slot. Pending refreshes are scoped to the owner and are cancelled when the owner
  deactivates/drops.
- The global physics world may remain an engine service, but containment bodies in
  that physics world are owned and tracked by their activity slot/manager.

## Persistence

Presentation state is persisted inside the activity session that owns it.

- Sandbox scene camera state belongs to the sandbox session.
- Graph canvas camera state belongs to the graph session.
- Drawing canvas camera state belongs to the drawing session.
- User activity cameras belong to the user activity session.
- Containment config belongs to the activity/slot that installed it.

World-level state may include shared domain records, but it must not be used as an
implicit active presentation cache.

## Error Handling

- Missing required camera/control data fails loudly at the call site that requires
  it.
- Presentation providers validate that exposed render targets have the required
  fields for their surface type.
- Ownership violations, such as attempting to install containment without an owner,
  fail loudly.
- Stale async/debounced callbacks verify owner identity before mutating render or
  physics state.

## Testing Strategy

Add focused tests for ownership and absence of leakage:

- Switching activities does not carry camera transforms across activities.
- Canvas activities have independent camera state.
- Empty scene slots expose no scene render target/service state by default.
- Containment installed by one activity is not visible or active in another.
- Debounced containment refresh after an activity switch cannot install into the
  wrong owner.
- Renderers consume presentation targets rather than `app.scene`/`app.canvas` as
  implicit active state.
- User/external activity harness can create an activity-owned canvas camera/render
  target without relying on global camera state.

## Non-Goals

- Do not introduce activity-id render toggles.
- Do not remove the global engine physics world in this phase.
- Do not build a full generic compositor graph in this phase.
- Do not solve bubbles-specific generated code bugs before establishing the
  presentation ownership boundary.

## Success Criteria

- `app.camera`, `app.first-person-controls`, and app-global physics containment are
  no longer authoritative active presentation state.
- Activities explicitly expose the targets, cameras, controls, and services they
  want displayed/used.
- Switching activities cannot leak cameras, controls, containment, lights, skybox,
  or background through global presentation state.
- Scene remaining in the render path is harmless because empty/unowned scene slots
  contribute no renderable presentation.
