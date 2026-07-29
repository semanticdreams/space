---
type: dev-note
tags:
  - note
---

# Sandbox Interaction Toolbar

This note describes the Sandbox-owned center-column activity toolbar added in `docs/dev/notes/sandbox-interaction-toolbar.md`. It covers the layout, activity hooks, Sandbox toolbar state, object move mode, anchor drag, and grounded camera controls.

## Layout

The Sandbox toolbar is contributed by the active activity and laid out in the HUD center column between full-height left and right rails.

- **`hud-layout.fnl`** reserves a top-toolbar slot in the center column only, placed above the scene stack. It does not appear in the left or right rails.
- **`activity-top-toolbar-view.fnl`** is a Layout wrapper that tracks `app.activity-top-toolbar-builder`. When the builder changes (e.g., activation or deactivation), it drops the previous toolbar and builds the new one. Its measured height is stored in `app.activity-top-toolbar-height`.
- **Expanded sidebar panels** query `app.activity-top-toolbar-height` so their content area reserves that height. The rails retain full height.
- **Left and right rails** remain full-height general HUD controls outside Sandbox ownership. Non-Sandbox activities have no toolbar by default; the toolbar slot is empty until an activity contributes a builder.

## Activity Hooks

The activity activation context (`ctx`) in `activities.fnl` exposes three new hooks:

### `ctx:set-top-toolbar-builder!(builder)`
Sets the current activity's top-toolbar builder. The builder must be a function `(fn [ctx] -> widget)` that produces a Layout-compatible widget tree. Sandbox sets this to `(SandboxToolbarView toolbar-state)`. The toolbar is rebuilt when the builder reference changes or on each frame.

### `ctx:set-object-move-predicate!(predicate)`
Sets a zero-argument function that returns `true` when no-`Alt` object dragging is enabled for this activity. `state-runtime.fnl` calls `app.activity-object-move-predicate` to gate `MovableMouseButtonDown`. Sandbox sets this to `(fn [] (= toolbar-state.object-move-enabled? true))`. When no activity sets a predicate (or it returns `false`/`nil`), only `Alt`+drag works — this is the safe default for all other activities.

### `ctx:set-drag-attachment-provider!(provider)`
Sets a zero-argument function that returns either `:center` (default) or `:anchor`. This controls the drag attachment mode for physics-backed movables. Sandbox sets this to `(fn [] toolbar-state.drag-attachment)`. When no provider is set, drag uses center attachment.

All three hooks are cleared by `clear-activity-runtime-hooks!` during activity deactivation (`app.activity-top-toolbar-builder`, `app.activity-object-move-predicate`, `app.activity-drag-attachment-provider` all set to `nil`).

## Sandbox Toolbar State

**File:** `assets/lua/sandbox-toolbar-state.fnl`

`(SandboxToolbarState opts)` creates a toolbar state table with three properties and a `Signal` for change notifications.

### Properties
| Property | Type | Default | Valid Values |
|---|---|---|---|
| `camera-mode` | keyword | `:flight` | `:flight`, `:grounded` |
| `object-move-enabled?` | boolean | `false` | `true`, `false` |
| `drag-attachment` | keyword | `:center` | `:center`, `:anchor` |

State fields are accessed via metatable `__index` (e.g., `state.camera-mode`) though the tests primarily use the accessor and setter methods.

### Key Methods

- **`state:set-camera-mode(mode)`** / **`state:toggle-camera-mode()`** — set or toggle between `:flight` and `:grounded`. Emits `changed` signal.
- **`state:set-object-move-enabled!(enabled?)`** / **`state:toggle-object-move-enabled!()`** — set or toggle object move mode. Emits `changed` signal. Validates that `enabled?` is boolean; errors on non-boolean input.
- **`state:set-drag-attachment(mode)`** / **`state:toggle-drag-attachment()`** — set or toggle between `:center` and `:anchor`. Emits `changed` signal.
- **`state:capture-state()`** — returns a serializable table `{:camera-mode "flight"/"grounded" :object-move-enabled? bool :drag-attachment "center"/"anchor"}`.
- **`state:restore-state(payload)`** — restores from a capture-state payload. Validates all fields. Accepts `nil` (no-op).
- **`state.changed`** — a `Signal` emitted whenever any state field changes. Connected by `SandboxToolbarView` to trigger toolbar button updates.

### Errors
- Invalid `camera-mode` or `drag-attachment` keyword raises a descriptive error.
- Non-boolean `object-move-enabled?` raises a descriptive error.
- Invalid values in `restore-state` payload raise descriptive errors.

## Sandbox Toolbar View

**File:** `assets/lua/sandbox-toolbar-view.fnl`

`(SandboxToolbarView state)` returns a builder function `(fn [ctx] -> root-widget)`. The builder creates a horizontal `Flex` (axis=1, yalign=:center) containing three `Button` widgets:

| Button | Icon | Default Text | Mode Toggle |
|---|---|---|---|
| Camera mode | `flight` | "Flight" / "Grounded" | `:primary` when grounded, `:secondary` when flight |
| Object move | `open_with` | "Move" | `:primary` when enabled, `:secondary` when disabled |
| Drag attachment | `anchor` | "Anchor" | `:primary` when anchor, `:secondary` when center |

### Update Cycle

The view connects to `state.changed`. On any state change, it:
1. Updates the camera button label between "Flight" and "Grounded"
2. Re-resolves theme colors for each button based on the new variant
3. Marks layout dirty for the affected button background color change

### Layout Names
Each button's `layout.name` is set for testing and debugging: `sandbox-toolbar-camera-mode`, `sandbox-toolbar-object-move`, `sandbox-toolbar-drag-attachment`.

### Cleanup
`root.drop` disconnects from `state.changed` before delegating to the Flex's original `drop`, preventing stale callbacks on rebuilt toolbars.

## Dragging

### Alt-Drag
`Alt` + left drag always works, regardless of activity. This is the unconditional drag path in `MovableMouseButtonDown` (`pointer.fnl`).

### Object Move Mode
When Sandbox is active and `object-move-enabled?` is `true`, `state-runtime.fnl`'s `activity-object-move-enabled?` returns `true`. This allows `MovableMouseButtonDown` to initiate a drag without `Alt` being held. The drag threshold is preserved — the pointer must move at least the configured distance before a drag session begins. This prevents accidental drags on click.

When `object-move-enabled?` is `false` (default) or no activity sets a predicate, only `Alt`+drag works.

### Anchor Drag
When `drag-attachment` is `:anchor`, physics-backed movable entries receive an `on-drag-update` callback that applies force at the clicked anchor point rather than teleporting the entity via layout.

**File:** `assets/lua/layout-physics-bodies.fnl`

**Mechanism:**
1. On drag start: `relative-anchor` is computed as `(drag.hit-point - body-center)` and stored on the drag table.
2. On drag update: `apply-anchor-force!` computes a spring force from the displacement between the current anchor world position and the desired position, applies velocity damping via `getVelocityInLocalPoint` when available, and calls `body:applyForceAtPosition(damped-force, relative-anchor)`.
3. Spring strength: 35.0, damping multiplier: 4.0 (conservative values for stability).
4. `resolve-entry-world-state` reads the actual body transform during anchor drag (skipping `apply-layout-to-body`) so the body moves via forces without being reset every frame.
5. On drag end: the layout position and rotation are synced **from** the body's final transform (position + rotation from `getCenterOfMassTransform`). `apply-layout-to-body` is NOT called for anchor mode.

**Limitations:**
- No native Bullet constraint bindings (point-to-point or 6DOF) are added. Force-at-anchor uses `applyForceAtPosition` and `getVelocityInLocalPoint` only — these are existing Bullet Lua bindings.
- If `getVelocityInLocalPoint` is unavailable, damping is skipped (spring force only, may oscillate).
- Assertions fail loudly when `entry.body`, `body.applyForceAtPosition`, or related bindings are missing.

## Grounded Camera

**File:** `assets/lua/sandbox-camera-controls.fnl`

`SandboxCameraControls` is a wrapper around `FirstPersonControls` that delegates all handlers in `:flight` mode and provides terrain-following grounded movement in `:grounded` mode.

### Dependencies
- `camera` — the scene camera (required)
- `toolbar-state` — `SandboxToolbarState` instance (required)
- `flight-controls` — a `FirstPersonControls` instance (required)
- `terrain-sampler` — an object with `:height-at-world-point(world-point)` method (required for grounded mode)

### Terrain Sampler
The Scene (`scene.fnl`) implements `:height-at-world-point` by querying `TerrainQuery.surface-info-at-world-point` and returning the world-space Y of the surface point, or 0.0 when no surface is found.

### Failure Behavior
- **Missing terrain sampler at construction with grounded mode**: immediate error.
- **Missing terrain sampler after construction**: every handler that touches grounded state (`update`, `on-key-down`, `on-key-up`, `on-mouse-button-down`, `on-mouse-button-up`, `on-mouse-motion`) calls `ensure-grounded-deps!` before any camera or state mutation.
- Invalid `delta-unit` raises an error with the expected values.

### Movement
- **Horizontal**: Keyboard keys (`move-left`/`move-right`/`move-forward`/`move-backward`) move the camera along the horizontal projection of the camera's forward and right vectors. Speed is multiplied by 1.5 while the jump key is held (sprint).
- **Look**: Keyboard `look-up`/`look-down` adjust pitch. `look-left`/`look-right` adjust yaw. Mouse left-drag also adjusts yaw and pitch.
- **Pitch clamp**: Accumulated pitch is clamped to `[pitch-min, pitch-max]` (default `[-1.2, 1.2]` radians). The pitch accumulator is tracked internally and reset on `drop`.

### Jump and Gravity
- **Jump**: Pressing `Space` sets `vertical-velocity` to `jump-speed` (default 8.0) and sets `airborne?` to `true`. Jumps are only possible from the grounded state.
- **Gravity**: While airborne, `vertical-velocity` decreases by `gravity * delta-seconds` (default gravity: 18.0). Position is integrated directly.
- **Landing**: When `vertical-velocity <= 0` and the camera Y position reaches or passes the terrain + eye-height threshold, the camera snaps to the terrain and `airborne?` is cleared.
- **Terrain following**: While grounded, a `CameraAnimation.scalar-channel` with smoothing rate 8.0 smoothly adjusts the camera Y to follow terrain height changes. The channel uses exponential easing (`alpha = 1 - exp(-rate * delta-seconds)`).

### What It's Not
- Grounded camera is terrain-following movement, **not a full character controller**. There is no collision detection, no step-up, no crouch, and no slope handling beyond the terrain height query.
- `on-mouse-wheel` is a no-op in grounded mode.
- Gamepad controls delegate to flight controls; grounded mode has no native gamepad support.

### Additional Options
| Option | Default | Description |
|---|---|---|
| `eye-height` | 2.0 | Height above terrain for camera |
| `gravity` | 18.0 | Downward acceleration |
| `jump-speed` | 8.0 | Initial vertical speed on jump |
| `pitch-min` | -1.2 | Minimum pitch angle (radians) |
| `pitch-max` | 1.2 | Maximum pitch angle (radians) |
| `movement-speed` | 10.0 | Horizontal movement speed |
| `mouse-look-speed` | 0.001 | Mouse-look sensitivity |
| `delta-unit` | `:milliseconds` | Unit for delta (`:milliseconds` or `:seconds`) |

## Camera Animation

**File:** `assets/lua/camera-animation.fnl`

`CameraAnimation.scalar-channel(opts)` is a lightweight easing helper used by grounded camera for smooth terrain following.

- `channel:value` — returns the current scalar value
- `channel:set-target(n)` — sets the target value; returns `true`
- `channel:snap(n)` — sets both current and target to `n`; returns `true`
- `channel:update(delta-seconds)` — approaches target exponentially via `alpha = 1 - exp(-rate * delta)`; snaps when distance < 1e-5
- All inputs validated; non-numeric values raise errors

## See Also

- [Layout](./sandbox-interaction-toolbar) — this document
- [Activity Retention Tests](../assets/lua/tests/test-activity-retention.fnl) — tests for hook lifecycle
- [Scene Drag Tests](../assets/lua/tests/test-scene-drag.fnl) — tests for predicate-gated dragging
- [Layout Physics Bodies Tests](../assets/lua/tests/test-layout-physics-bodies.fnl) — tests for anchor drag
- [Sandbox Camera Controls Tests](../assets/lua/tests/test-sandbox-camera-controls.fnl) — tests for grounded camera
- [Camera Animation Tests](../assets/lua/tests/test-camera-animation.fnl) — tests for scalar channel
