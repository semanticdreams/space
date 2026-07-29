# Sandbox Interaction Toolbar Design

## Context

The Sandbox activity needs richer direct manipulation controls. Today the global HUD has a top control panel, left and right rail/sidebar areas, scene/canvas middle content, and a bottom status panel. Camera movement is handled by the existing free first-person controls, while object movement is only available through `Alt` + left drag in the `movables` pointer pipeline. Physics bodies can be teleported or pushed through existing Bullet Lua bindings, but native Bullet constraints such as `btPoint2PointConstraint` are not currently bound.

## Goals

- Add a Sandbox-owned horizontal toolbar below the global control panel.
- Keep the toolbar visually separate from global HUD controls and scoped to Sandbox only.
- Let the Sandbox toolbar toggle:
  - camera mode between current free flight and a grounded terrain-following mode;
  - object move mode so scene objects can be dragged without holding `Alt`;
  - drag attachment behavior between current center/teleport-style dragging and clicked-anchor physics dragging.
- Make expanded sidebars accommodate the toolbar vertically instead of overlapping it.
- Introduce a small, clean camera animation foundation suitable for later camera features.
- Implement clicked-anchor physics dragging using currently available Bullet APIs first, and defer native constraint bindings unless force-based dragging proves insufficient.

## Non-Goals

- No toolbar for Graph, Drawing, Board, or other activities in this change.
- No global toolbar customization framework beyond the activity-owned HUD hook required for Sandbox.
- No full character controller, capsule collision, stair stepping, crouching, or slope-material behavior.
- No native Bullet constraint binding in the first implementation.
- No cinematic timeline/path editor, spline camera system, or user keybinding editor.

## Alternatives Considered

### A. Sandbox-specific toolbar hard-wired directly into HUD layout

This is the smallest surface area: `hud-layout` would directly know about Sandbox and insert a Sandbox toolbar band. It is fast but couples the generic HUD to one activity and makes later activity-specific toolbars harder.

### B. Generic activity-owned top-toolbar hook with Sandbox as the only provider

HUD layout gains a single optional top-toolbar band. Activities can contribute a builder, but Sandbox is the only built-in activity that does so now. This keeps Sandbox ownership intact, avoids global control-panel bloat, and leaves a reusable path for future activities without designing a large extension framework.

### C. Overlay toolbar floating above scene and sidebars

The toolbar could render in the HUD overlay layer and ignore layout. That maximizes screen space but creates ambiguous hit testing, can hide controls behind expanded sidebars, and makes toolbar width unpredictable.

**Decision:** Use approach B. It gives the right ownership boundary and predictable layout while staying small.

## Layout Design

The HUD keeps the global control panel as the full-width top band and keeps the left/right rails as general HUD affordances outside Sandbox ownership. Inside the middle HUD band, the layout becomes:

1. left rail/sidebar column;
2. center column containing the optional activity top toolbar above the scene/tile/float area;
3. right rail/sidebar column.

The Sandbox toolbar is measured only inside the center column between the left and right rails. It consumes vertical space from the center scene area before scene/tile/float layout occurs. Rails remain full-height general HUD anchors and must not be pushed down by Sandbox-owned controls.

Expanded sidebar panels are associated with their rail columns but should accommodate the Sandbox toolbar by starting below the toolbar or otherwise shrinking vertically to avoid covering it. This preserves rail access for global/app-level controls while keeping Sandbox toolbar controls visible and predictable.

The toolbar content itself is Sandbox-owned. It should be horizontally centered or start-aligned within the center column, use existing button primitives where possible, and remain compact enough for a 1280x720 viewport. Reusable button-group/view helpers are acceptable if they naturally fall out of the implementation, but the design should not introduce a broad toolbar framework.

## Sandbox Toolbar State

Sandbox runtime state owns three user-facing controls:

- `camera-mode`: `:flight` or `:grounded`; default `:flight`.
- `object-move-enabled?`: boolean; default `false`.
- `drag-attachment`: `:center` or `:anchor`; default `:center`.

The state exposes explicit setters/toggles and emits a `changed` signal after successful mutations so views and controls can update without polling. Invalid mode values fail loudly.

Toolbar state should be captured/restored with the Sandbox activity session so user preferences survive ordinary HomeWorld save/restore. Legacy aliases are not added.

## Input and Interaction Modes

Terminology:

- **Camera mode** controls how the camera moves (`:flight` vs `:grounded`).
- **Object move mode** controls whether left-drag can begin object movement without `Alt`.
- **Drag attachment** controls how movable physics bodies respond once dragging starts (`:center` vs `:anchor`).

Current `Alt` + left drag remains supported in all modes. When Sandbox object move mode is enabled, ordinary left drag can start a movable object drag without `Alt`. This behavior is supplied through an activity-level predicate so it is active only when Sandbox owns the active interaction context.

The pointer dispatch order should continue to protect existing click/resize/selection semantics. Object move mode should not force every click to become a drag immediately; the existing drag threshold should still distinguish click from drag.

## Drag Attachment Behavior

The existing drag flow ray-casts to the clicked object, stores the hit point, computes ray/plane intersections during pointer motion, and by default moves the target layout to the desired position.

For `:center` drag attachment, behavior remains equivalent to the current direct movement path.

For `:anchor` drag attachment on physics-backed movables:

- preserve the clicked world-space point as the drag anchor;
- compute the anchor relative to the rigid body at drag start;
- on drag update, compute a desired anchor position from the pointer ray/plane hit;
- apply a spring-like force at the relative anchor using existing Bullet binding `RigidBody:applyForceAtPosition` / `applyForce` semantics;
- activate the body while dragging;
- avoid teleporting the layout transform during anchor updates.

This should allow gravity and torque to rotate an object when lifted from one side. The first implementation may tune spring strength and damping conservatively for stability. If force-at-anchor proves too unstable or too weak for desired UX, the follow-up design should add native Bullet point-to-point constraint bindings instead of hiding the limitation.

## Grounded Camera Mode

Flight mode delegates to the existing first-person controls and preserves current behavior, including current movement mapping and `Space` as speed boost.

Grounded mode is a Sandbox camera controls wrapper with the same input interface expected by existing state handlers. In grounded mode:

- horizontal movement uses the existing movement action mapping where possible;
- yaw is unrestricted around world up;
- pitch is clamped to a comfortable range so the camera cannot flip or look far beyond vertical limits;
- roll is not applied;
- the camera has an eye height above terrain;
- terrain-follow samples the active Sandbox terrain below the camera's horizontal position;
- `Space` starts a jump by setting positive vertical velocity;
- gravity pulls the camera back down to terrain height plus eye height;
- when not airborne, camera height smoothly follows terrain height instead of snapping.

The first grounded implementation is terrain-following movement, not a physical character controller. It should fail loudly if required terrain sampling APIs are missing in contexts that claim grounded mode support, while tests can use a stub scene sampler.

## Camera Animation Foundation

Introduce a small camera animation module rather than embedding ad-hoc smoothing into grounded controls. The first primitive should be enough for terrain-follow and future expansion:

- scalar channel with current value, target value, smoothing rate, snap, and update;
- no overshoot for normal positive smoothing values;
- deterministic update from delta seconds.

Grounded controls use this for vertical terrain-follow smoothing. Future camera transitions can add vector/quaternion channels or timelines without changing the camera object itself.

## Architecture Components

- `hud-layout`: accepts an optional top-toolbar builder and lays it at the top of the center middle column, between the left and right rails.
- activity runtime/contribution layer: lets the active activity install or clear a top-toolbar builder and object-move predicate.
- `sandbox-toolbar-state`: owns toolbar mode state, signals, capture, and restore.
- `sandbox-toolbar-view`: builds the Sandbox toolbar buttons and mutates `sandbox-toolbar-state`.
- `movables`: supports an optional drag update callback that can override default position-setting behavior.
- physics-backed movable registration: implements anchor drag by applying force at the clicked local anchor when `drag-attachment` is `:anchor`.
- `camera-animation`: provides the initial scalar smoothing channel.
- `sandbox-camera-controls`: wraps existing flight controls and adds grounded controls behind the same handler interface.

## Data Flow

1. Sandbox activation ensures toolbar state and installs the toolbar builder plus object-move predicate.
2. HUD rebuild/layout calls the active toolbar builder and reserves toolbar height in the center column while preserving full-height rails.
3. Toolbar button clicks mutate Sandbox toolbar state and emit `changed`.
4. Pointer handlers allow movable drag when `Alt` is held or the active activity predicate returns true.
5. Movables compute hit/drag information and either use default target movement or delegate drag update to physics anchor behavior.
6. State handler update events call Sandbox camera controls; the controls delegate to flight controls or update grounded movement/jump/terrain-follow based on `camera-mode`.

## Error Handling

- Invalid toolbar state modes raise explicit errors.
- Missing required camera, state, or terrain sampler dependencies raise explicit errors at construction or grounded-mode use.
- Anchor dragging falls back to default movement only when the movable is not physics-backed or when `drag-attachment` is `:center`; physics-backed anchor mode should not silently no-op.
- Pointer predicates absent from non-Sandbox activities are treated as disabled, preserving existing behavior.

## Testing Strategy

- HUD layout tests verify the top toolbar consumes vertical space in the center column between rails, rails remain full-height, and expanded sidebars do not overlap the toolbar.
- Activity tests verify Sandbox installs and clears the toolbar and predicates on activation/deactivation.
- Toolbar state/view tests verify defaults, toggles, invalid values, capture/restore, button names, and button actions.
- Pointer/movables tests verify `Alt` drag still works and no-`Alt` drag only works when Sandbox object move mode is enabled.
- Physics movable tests verify anchor mode applies force at the clicked relative point and avoids teleport movement during anchor drag.
- Camera animation tests verify smoothing, snap, monotonic approach, and no overshoot.
- Grounded camera tests verify delegation in flight mode, pitch clamps, jump/gravity, terrain-follow sampling, and vertical smoothing.
- Final validation should run focused Fennel tests, the fast suite, and the repository's standard full test command.

## Acceptance Criteria

- Sandbox displays a horizontal toolbar below the global control panel.
- The toolbar is Sandbox-owned; other activities do not show it unless they explicitly contribute their own later.
- The toolbar reserves center-column layout space; left/right rails remain full-height and expanded sidebar panels do not overlap it.
- The camera button switches between free flight and grounded terrain-following controls.
- In grounded mode, `Space` jumps, gravity lands the camera back on terrain, and pitch is clamped.
- Object move mode allows dragging Sandbox objects without holding `Alt`; existing `Alt` drag remains available.
- Anchor drag mode applies force at the clicked point for physics-backed objects so off-center lifting can rotate under gravity.
- Direct center dragging remains available as the default.
- No native Bullet constraint binding is required for the first implementation.
