# Activity Camera Boundary Design

## Context

Activity camera ownership has been patched more than once, but the user-visible
bug persists: changing the camera in one activity can still affect another
activity. The prior fixes moved many built-in activities to per-slot camera
objects, but they left retained-surface fallbacks and global control paths alive.
That makes the invariant fragile: activity slots may own cameras, while input,
screen-ray, or generated activity code can still accidentally route through a
surface-level camera/control object.

This must apply to built-in activities and dynamically added user activities such
as a generated `bubbles` activity. When ownership is ambiguous, the system must
fail loudly instead of guessing a fallback camera.

## Goal

Enforce a single presentation ownership boundary: an activity can render, receive
camera input, or convert screen coordinates only through state that it explicitly
owns or through a presentation target that the active activity exposes.

No activity may mutate another activity's camera by mistake through supported
Scene, Canvas, presentation, input, or screen-ray APIs.

## Non-Goals

- Protect against intentionally malicious code that directly walks runtime tables
  and mutates raw camera objects.
- Rewrite the C++ engine, `Camera`, `Scene`, or `Canvas` from scratch.
- Preserve compatibility for old bare camera/ray calls. Legacy direct calls should
  be migrated or should fail loudly.
- Add activity-id render toggles as a substitute for ownership.

## Current Failure Pattern

The current code has the right pieces but not a hard boundary:

- Canvas/Scene activity slots can own cameras and presentation targets.
- Built-in Graph, Drawing, Board, and Sandbox install activity cameras in their
  slots.
- A presentation provider can resolve active render targets and input controls.

However, accidental cross-activity mutation remains possible because retained
surface and app-level fallback paths still exist:

- `runtime.canvas-controls` is a default retained surface control object bound to
  a default retained canvas camera.
- `app.canvas-controls` / `app.active-pointer-controls` can bypass slot-owned
  controls.
- `CanvasControls` can fall back to `canvas.camera`.
- `Canvas:resolve-active-camera` and `Scene:resolve-active-camera` can fall back
  to retained `self.camera` when no visible active slot exists.
- Some activity code calls `canvas:screen-pos-ray` or `scene:screen-pos-ray`
  directly instead of using a slot/presentation target.
- Generated activity guidance currently encourages bare `app.canvas` screen-ray
  access, which teaches dynamic activities the unsafe pattern.

## Selected Approach

Use a strict **activity surface boundary** around Scene, Canvas, presentation
targets, input controls, and screen-ray helpers.

The boundary should centralize these decisions:

1. Which activity is currently allowed to mutate a slot.
2. Whether a slot belongs to the active or currently activating activity.
3. Whether a direct screen-ray request is authorized.
4. Whether a presentation target/control belongs to the active activity.
5. Which slots must be deactivated when activities switch.

This is preferred over call-site-only cleanup because dynamic activities can
continue to use old direct APIs unless the APIs themselves enforce ownership.
It is also preferred over wrapping raw camera mutators because the common bug is
wrong target/control selection, not just raw camera mutation.

## Core Invariants

1. **Activity-owned presentation only.** An activity must explicitly create or
   restore its camera/control state in its own slot/session before exposing a
   render target or receiving camera input.
2. **No retained-surface presentation fallback.** Retained `Scene` and `Canvas`
   surfaces may exist as containers, but their retained `camera` fields are not
   an active activity camera fallback.
3. **No global control fallback.** Runtime/app-level `canvas-controls` or
   `active-pointer-controls` must not be authoritative camera input for an active
   activity when a presentation provider exists.
4. **Foreign slot mutation fails.** During activity activation or active runtime
   execution, code may not create, activate, set a camera/control, or expose a
   render target for another activity id through public slot APIs.
5. **Ambiguous direct rays fail.** Bare `canvas:screen-pos-ray`,
   `app.canvas:screen-pos-ray`, `scene:screen-pos-ray`, and
   `app.scene:screen-pos-ray` fail in active activity contexts unless the caller
   supplies explicit view/projection matrices or an explicitly authorized
   activity-owned target.
6. **Presentation target rays stay supported.** The supported high-level path is
   `app.presentation-screen-pos-ray`, `provider:screen-pos-ray`, or a slot/
   presentation target carrying the activity-owned camera/projection/context.
7. **Dynamic activities use the same rules.** User/generated activities receive no
   special compatibility fallback. If a generated `bubbles` activity needs a
   canvas camera, it must create or obtain its own activity canvas slot, install
   its own camera/controls, expose its own render target, and use its own target
   for rays.

## Boundary API

Introduce a small Fennel module, conceptually `activity-surface-boundary`, to keep
the policy out of large Scene/Canvas files.

Expected responsibilities:

- Resolve the expected owner id from the active runtime and currently activating
  activity.
- Assert that a slot mutation is being performed for the owner activity.
- Assert that a direct screen-ray request is authorized by explicit matrices,
  explicit target ownership, or matching active slot ownership.
- Deactivate active Scene/Canvas slots that do not belong to the newly active
  activity after an activity switch commits.
- Produce clear errors that name the surface, requested activity id, active or
  activating activity id, and denied action.

The boundary should not silently create cameras, controls, slots, or sessions.

## Activity Switching Flow

When switching activities:

1. `Activities.activate-activity` records the id being activated while the
   activity's `activate` function runs.
2. Slot APIs allow the activating activity to create/activate/mutate only slots
   for that same id.
3. After activation succeeds and the new active id is committed, foreign active
   Scene/Canvas slots are deactivated so stale presentation targets cannot remain
   visible or interactive.
4. The presentation provider returns only targets/controls for slots owned by the
   active activity.

If activation fails, the activating id is cleared and no broad fallback is
installed.

## Screen-Ray and Input Flow

Screen-ray conversion should move through one of these paths:

- A presentation target returned for the active activity.
- A slot pointer target that carries the owning slot/context.
- Explicit low-level matrix input (`view` and `projection`) supplied by code that
  already owns the camera math.

Bare direct surface rays are intentionally unsafe because retained surfaces can
outlive activity switches. They must fail when the boundary cannot prove ownership.

Camera input should resolve through the active presentation provider. Default
surface controls may remain only for non-activity/bootstrap contexts if still
needed, but they must not be selected as a fallback for active activities.

## Dynamic Activity Contract

Dynamic activities register through `Activities.register-activity` and must follow
the same explicit ownership contract as built-ins:

1. Use the current runtime's Scene/Canvas slot API with the dynamic activity's own
   id.
2. Install a camera before exposing a camera-backed render target.
3. Bind controls to that exact camera if the activity supports camera input.
4. Use the slot context/pointer target or presentation helper for screen rays.
5. Avoid bare `app.canvas`, `app.scene`, `canvas.camera`, `scene.camera`, or
   retained surface controls as camera state.

Generated activity prompts and developer docs must state this directly. The
generated `bubbles` pattern must not recommend `app.canvas:screen-pos-ray`.

## Error Handling

- Missing required camera/control/target data errors at the call site that needs
  it.
- Foreign ownership errors name the active/activating activity id and the slot id.
- Ambiguous direct screen-ray calls explain the supported replacement: use a
  presentation target/helper, a slot pointer target, or explicit matrices.
- No fallback should convert an ownership error into nil, a no-op, or another
  activity's camera.

## Testing Strategy

Add tests that reproduce the real failure mode rather than only checking that two
camera objects are distinct:

- A dynamic activity that does not claim Graph/Board/Drawing/Sandbox slots cannot
  leave their slots presented or interactive after activation.
- A dynamic activity attempting to mutate Graph's slot camera/control/render target
  fails loudly.
- Bare direct `canvas:screen-pos-ray` / `scene:screen-pos-ray` fails in ambiguous
  active activity contexts.
- Presentation-provider and slot-target screen rays still work with the active
  slot's own camera.
- Camera input routing for Graph, Drawing, Board, Sandbox, and a dynamic canvas
  activity resolves to the active activity's controls, not retained surface
  controls.
- Existing built-in camera isolation tests remain green.

Validation must use Space-native Fennel checks, constraints, focused activity/
presentation/slot tests, and a broader suite because the change affects input,
runtime activity switching, generated activity guidance, and rendering.

## Acceptance Criteria

- A generated/dynamic activity cannot accidentally mutate Graph, Drawing, Board,
  or Sandbox cameras through public supported APIs.
- Switching activities deactivates foreign active Scene/Canvas slots and prevents
  stale presentation targets from being selected.
- No supported active-activity path falls back to `app.camera`, `app.canvas-controls`,
  `app.active-pointer-controls`, `runtime.canvas-controls`, `canvas.camera`, or
  `scene.camera` for camera ownership.
- Direct ambiguous surface screen-ray calls fail loudly with actionable messages.
- Supported presentation-target and explicit-matrix ray paths continue to work.
- Generated activity guidance documents the explicit slot/presentation pattern.
