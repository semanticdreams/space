# Sandbox Interaction Modes Cleanup Design

## Context

The Sandbox toolbar currently exposes three independent controls: a camera button
that toggles flight/grounded behavior, a move toggle that enables ordinary
left-drag object movement, and an anchor toggle that changes how physics-backed
objects respond once a drag has already started. These independent toggles allow
confusing combinations such as flight + move + anchor, while anchor mode does not
itself make objects draggable. The result is hard to explain and easy to use
incorrectly.

The anchor implementation is also not matching the desired behavior. The user
intent is a surface-point grab: click a point on an object, drag the cursor, and
have that clicked point remain under the pointer while the object can rotate
naturally around it. The current implementation approximates this with a manual
spring force using `RigidBody:applyForceAtPosition`. Code inspection found that
the force target is likely using the desired layout origin rather than the
pointer hit point, and the stored anchor offset is not robust once the body
rotates. Public Bullet examples use `btPoint2PointConstraint` for mouse picking:
convert the hit point to the body's local pivot, add a point-to-point constraint,
update the constraint target as the cursor moves, and remove it on release.

## Goals

- Replace the independent Sandbox toolbar toggles with one mutually-exclusive
  `interaction-mode` state.
- Make user-facing modes simple enough to explain in one sentence each.
- Remove `Alt` + drag object movement for now. Object dragging should happen
  only when the selected mode is an object manipulation mode.
- Add a natural navigation mode that behaves like a grounded character: WASD
  movement, arrow-key rotation, Space jump, terrain/ground following, limited
  pitch, and no accidental object dragging.
- Replace the unstable force-based anchor behavior with a Bullet
  point-to-point-style grab mechanism so the clicked surface point is the point
  being controlled.
- Preserve the existing activity-owned toolbar boundary and Sandbox-only input
  hooks.
- Keep persisted state migratable from existing sessions without exposing old
  runtime aliases.

## Non-Goals

- No reintroduction of `Alt` + drag in this cleanup.
- No user keybinding editor or broader input-remapping system.
- No full game character controller feature set: no crouch, sprint stamina,
  stair stepping, slope materials, capsule/ghost controller binding, or gamepad
  support in this pass.
- No global HUD toolbar redesign outside the Sandbox toolbar row.
- No object drag enablement for non-Sandbox activities by default.

## Alternatives Considered

### A. Keep the three existing fields and add guard logic

The current `camera-mode`, `object-move-enabled?`, and `drag-attachment` fields
could be kept, with setter rules that turn other fields off when one is enabled.
This minimizes file churn but preserves the leaky mental model. Code would still
need to ask multiple questions to know what the user intended, and persisted
state would continue to encode invalid-looking combinations.

### B. Use separate navigation mode and tool mode fields

Another option is a navigation mode (`:flight`, `:walk`) plus a nullable tool
mode (`nil`, `:move`, `:grab`). This is more structured than today but still
creates two-mode combinations. It also leaves open questions such as whether
keyboard navigation remains active while Move is selected.

### C. Use a single interaction-mode enum

Sandbox exposes exactly one selected interaction mode. The toolbar shows one
primary button at a time, input dispatch derives behavior from that one value,
and impossible combinations cannot exist.

**Decision:** Use approach C with four user-facing modes: **Fly**, **Walk**,
**Move**, and **Grab**.

## User-Facing Modes

### Fly

Fly preserves the current free first-person camera/navigation behavior. It is
for inspecting the Sandbox scene quickly without being constrained by terrain or
physical movement. Object left-drag is disabled in this mode.

### Walk

Walk is the new natural navigation mode. It behaves like a simple grounded
avatar/camera:

- `W`, `A`, `S`, and `D` move horizontally relative to the current yaw.
- Left/right arrow keys rotate yaw.
- Up/down arrow keys adjust pitch within a clamp.
- `Space` jumps only when grounded.
- Gravity returns the avatar to the terrain height after a jump.
- The camera follows the avatar at an eye height above terrain.
- Object left-drag is disabled in this mode.

Walk should be deterministic and testable. The first implementation may use the
existing terrain sampler and a lightweight avatar state rather than binding a
full Bullet character controller, but it must behave as a physical/grounded
navigation mode from the user's perspective and fail loudly if required terrain
sampling is unavailable.

### Move

Move is direct object manipulation. Ordinary left-drag can begin a movable object
drag after the existing drag threshold. The object follows direct/center movement
using the existing movable target-position path. Camera movement is not active
while Move is selected.

### Grab

Grab replaces the anchor toggle. Ordinary left-drag grabs the clicked surface
point on a physics-backed movable object. The clicked point, not the object's
center or layout origin, is the controlled point. The object may rotate naturally
around that point under gravity and contacts.

Grab should use Bullet constraints, not the current manual force approximation:

1. raycast/select the movable and hit point;
2. compute the local pivot from the body's center-of-mass transform inverse and
   the world hit point;
3. create a `btPoint2PointConstraint` for the selected body and local pivot;
4. add the constraint to the physics world;
5. update the constraint's world target as the cursor ray/drag plane hit moves;
6. remove and destroy the constraint on drag end;
7. sync layout position and rotation from the final body transform.

If Bullet point-to-point constraints prove insufficient for the desired feel,
the next design should evaluate a richer 6DoF/spring constraint. The cleanup
should not hide constraint failures behind silent fallback to center movement.

## State Model

`SandboxToolbarState` should own one canonical field:

- `interaction-mode`: one of `:flight`, `:walk`, `:move`, `:grab`; default
  `:flight`.

The state exposes:

- `state.interaction-mode`
- `state:set-interaction-mode(mode)`
- `state:navigation-mode()` returning `:flight`, `:walk`, or `nil`
- `state:object-drag-mode()` returning `:move`, `:grab`, or `nil`
- `state:capture-state()` returning a serializable table with only
  `interaction-mode`
- `state:restore-state(payload)` accepting the new payload and migrating old
  persisted toolbar payloads

Existing persisted state should migrate as follows:

- `object-move-enabled? == true` and `drag-attachment == "anchor"` -> `:grab`
- `object-move-enabled? == true` otherwise -> `:move`
- otherwise `camera-mode == "grounded"` -> `:walk`
- otherwise -> `:flight`

The old fields should not remain runtime aliases after migration. Invalid modes
or malformed payloads should raise explicit errors.

## Toolbar Design

The Sandbox toolbar remains activity-owned and appears in the existing center
column top-toolbar slot. It renders four explicit mode buttons:

| Label | Icon | Mode |
|---|---|---|
| Fly | `flight` | `:flight` |
| Walk | `directions_walk` | `:walk` |
| Move | `open_with` | `:move` |
| Grab | `pan_tool` | `:grab` |

Only the active mode button uses the primary variant. Clicking a button selects
that mode; clicking the already-active mode is a no-op rather than toggling back
to another mode.

Stable layout names should be mode-based:

- `sandbox-toolbar-mode-flight`
- `sandbox-toolbar-mode-walk`
- `sandbox-toolbar-mode-move`
- `sandbox-toolbar-mode-grab`

## Input and Activity Hook Design

The activity runtime should expose one object-drag mode provider instead of the
current separate move predicate and drag attachment provider. Sandbox installs a
provider derived from `toolbar-state:object-drag-mode()`.

Pointer dispatch starts movable drag only when the provider returns `:move` or
`:grab`. `Alt` should not bypass this gate. Non-Sandbox activities, absent a
provider, retain no ordinary object-drag behavior.

Camera controls derive behavior from `toolbar-state:navigation-mode()`:

- `:flight` delegates to existing flight controls;
- `:walk` delegates to the new Walk controls;
- `nil` means object manipulation is active, so camera movement handlers should
  not move the camera.

The existing terrain-following grounded implementation can be reused internally
if it serves Walk, but Walk is the user-facing mode and must have the specified
WASD/arrow/Space semantics.

## Bullet Constraint Binding Design

The C++/Lua physics binding needs the minimal constraint surface required for
Grab:

- construct a point-to-point constraint for a rigid body and local pivot;
- set/update the second/world pivot target during drag;
- add/remove constraints on the dynamics world or physics wrapper;
- configure conservative impulse/tau/damping parameters if Bullet exposes them
  through the chosen API;
- ensure constraint lifetime is owned safely by the drag/session object and is
  removed on normal drag end, pointer-target loss, or cleanup.

The binding should be narrow and explicit. It should not expose a broad,
unreviewed constraint framework in this cleanup.

## Error Handling

- Invalid interaction modes fail loudly.
- Missing terrain sampler in Walk mode fails loudly before mutating camera state.
- Missing Bullet constraint bindings or missing physics world support in Grab
  mode fails loudly.
- Grab should not silently fall back to Move if the selected object lacks a
  physics body; it should either refuse the drag with an explicit diagnostic or
  surface a clear error in tests/development.
- Drag sessions must remove constraints on end/drop to avoid stale physics-world
  state.

## Testing Strategy

- Toolbar state tests cover defaults, valid/invalid mode setting, change signal
  behavior, capture/restore, and legacy payload migration.
- Toolbar view tests cover the four buttons, layout names, click behavior, and
  single-primary highlighting.
- Activity tests cover installation/clearing of the single object-drag provider
  and Sandbox provider values for all modes.
- Pointer/scene drag tests prove `Alt` + left-drag no longer starts object drag,
  Move starts center/direct movement, and Grab starts the physics grab path.
- Walk controls tests cover WASD movement, arrow-key yaw/pitch, pitch clamp,
  Space jump, gravity/landing, and no camera movement while object modes are
  selected.
- Physics/Grab tests cover local pivot calculation from the clicked hit point,
  constraint creation/addition, target update from pointer hit, constraint
  removal on drag end, and layout sync from the body transform.
- Fennel validation should run compile checks first, then constraints, then
  focused tests. Because this touches input, activity hooks, C++ physics
  bindings, and runtime behavior, final validation should include the repository
  standard full test command.

## Acceptance Criteria

- Sandbox has exactly one active interaction mode at a time.
- The toolbar presents Fly, Walk, Move, and Grab as explicit mutually-exclusive
  buttons.
- Existing sessions restore into the new `interaction-mode` model through the
  documented migration.
- `Alt` + drag does not move objects.
- Object movement starts only in Move or Grab mode.
- Walk mode supports WASD movement, arrow-key yaw/pitch, Space jump, terrain
  grounding, and pitch limits.
- Fly mode keeps existing free camera behavior.
- Move mode keeps direct object movement behavior.
- Grab mode controls the clicked surface point using a Bullet point-to-point
  constraint-style mechanism and no longer uses the manual force spring as the
  primary implementation.
- Required failures are explicit, not silent no-ops.
