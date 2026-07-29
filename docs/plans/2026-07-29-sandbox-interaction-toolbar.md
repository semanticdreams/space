# Sandbox Interaction Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Sandbox-owned center-column toolbar for camera mode, object move mode, and drag attachment, plus grounded camera movement and force-at-anchor physics dragging.

**Architecture:** HUD layout provides a small activity toolbar slot in the middle center column only; left/right rails remain full-height general HUD controls. Sandbox owns toolbar state, toolbar view, activity predicates, camera controls, and session persistence. Movable dragging gains a single override callback so physics-backed Sandbox bodies can apply force at the clicked anchor using existing Bullet Lua bindings instead of teleporting.

**Tech Stack:** Fennel modules in `assets/lua`, existing HUD `Layout`/`Flex`/`Stack`/`Button` widgets, existing activity hooks in `assets/lua/activities.fnl`, existing Bullet Lua `RigidBody` force bindings, and Fennel tests under `assets/lua/tests`.

## Global Constraints

- The toolbar is Sandbox-owned and does not appear for Graph, Drawing, Board, or other activities unless those activities contribute their own toolbar in a future change.
- The toolbar is below the global control panel but only inside the center column between left and right rails.
- Left and right rails remain full-height because they are general controls outside Sandbox ownership.
- Expanded sidebar panels must not overlap the Sandbox toolbar; their panel content reserves the toolbar height while their rails remain full-height.
- Current `Alt` + left drag remains supported.
- Object move mode allows no-`Alt` object dragging only while Sandbox enables it.
- Default drag attachment remains `:center`; anchor dragging is explicitly opt-in.
- Anchor dragging uses existing Bullet force APIs first; do not add native Bullet constraint bindings in this implementation.
- Grounded camera is terrain-following movement, not a full character controller.
- Invalid state values and missing required grounded-camera dependencies fail loudly.
- Use canonical option keys only; do not add compatibility aliases.
- For icon names used by new buttons, validate exact names against `assets/material-design-icons/icons.txt` before committing implementation tasks.

---

## File Structure

- Create `assets/lua/activity-top-toolbar-view.fnl`: dynamic HUD wrapper that builds the active activity toolbar and publishes its measured height to `app.activity-top-toolbar-height`.
- Create `assets/lua/sandbox-toolbar-state.fnl`: Sandbox toolbar mode state, mutation API, changed signal, capture, and restore.
- Create `assets/lua/sandbox-toolbar-view.fnl`: compact horizontal Sandbox toolbar with camera, object move, and drag attachment buttons.
- Create `assets/lua/camera-animation.fnl`: scalar smoothing channel used by grounded camera vertical follow.
- Create `assets/lua/sandbox-camera-controls.fnl`: mode-switching controls wrapper; delegates to existing flight controls or runs grounded movement.
- Modify `assets/lua/activities.fnl`: add toolbar, object-move predicate, and drag-attachment provider hooks.
- Modify `assets/lua/hud-layout.fnl`: lay out center toolbar above the center scene stack while rails remain full-height.
- Modify `assets/lua/hud-extended-sidebar-view.fnl`: reserve top toolbar height for expanded right sidebar panel only.
- Modify `assets/lua/activity-dock-view.fnl`: reserve top toolbar height for expanded left activity panel only.
- Modify `assets/lua/main.fnl`: wire `ActivityTopToolbarView` and sidebar reserve providers into HUD construction.
- Modify `assets/lua/sandbox-activity-unit.fnl`: create Sandbox toolbar state, install hooks, persist toolbar state, and install Sandbox camera controls.
- Modify `assets/lua/state-runtime.fnl` and `assets/lua/state-handlers/pointer.fnl`: route object move predicate into the movable mouse-down condition.
- Modify `assets/lua/movables.fnl`: pass drag lifecycle state to callbacks and add `:on-drag-update` override.
- Modify `assets/lua/layout-physics-bodies.fnl`: implement force-at-anchor drag for physics-backed bodies.
- Modify `assets/lua/scene.fnl`: preserve `:on-drag-update` when scene movable entries are normalized/registered.
- Create or modify focused tests under `assets/lua/tests` listed in each task.
- Create `docs/dev/notes/sandbox-interaction-toolbar.md` and link it from `docs/dev/notes/index.md`.

Use this focused test environment for Fennel module commands throughout:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m <module>:main
```

---

### Task 1: Activity Toolbar Hook and Center-Column HUD Layout

**Files:**
- Create: `assets/lua/activity-top-toolbar-view.fnl`
- Modify: `assets/lua/activities.fnl`
- Modify: `assets/lua/hud-layout.fnl`
- Modify: `assets/lua/hud-extended-sidebar-view.fnl`
- Modify: `assets/lua/activity-dock-view.fnl`
- Modify: `assets/lua/main.fnl`
- Modify: `assets/lua/tests/test-activity-retention.fnl`
- Modify: `assets/lua/tests/test-hud-layout.fnl`
- Modify: `assets/lua/tests/test-hud-extended-sidebar.fnl`

**Interfaces:**
- Consumes: existing `Activities.activity-context`, `HudLayout.make-hud-builder(opts)`, `HudExtendedSidebarView(sidebar)`, and `ActivityDockView(opts)`.
- Produces:
  ```fennel
  (ctx:set-top-toolbar-builder! builder-or-nil) ; -> builder-or-nil
  (ctx:set-object-move-predicate! predicate-or-nil) ; -> predicate-or-nil
  (ctx:set-drag-attachment-provider! provider-or-nil) ; -> provider-or-nil
  app.activity-top-toolbar-builder
  app.activity-object-move-predicate
  app.activity-drag-attachment-provider
  app.activity-top-toolbar-height ; number, defaults to 0 when absent
  (ActivityTopToolbarView {}) ; -> builder
  (HudExtendedSidebarView sidebar {:top-reserve-height-provider provider})
  (ActivityDockView {:top-reserve-height-provider provider})
  ```

- [ ] **Step 1: Add failing activity hook tests**

  In `assets/lua/tests/test-activity-retention.fnl`, add a test named `activity-hooks-include-toolbar-and-sandbox-interaction-providers` that registers a temporary activity whose `activate` callback calls:

  ```fennel
  (ctx:set-top-toolbar-builder! toolbar-builder)
  (ctx:set-object-move-predicate! move-predicate)
  (ctx:set-drag-attachment-provider! drag-provider)
  ```

  Assert after activation that `app.activity-top-toolbar-builder`, `app.activity-object-move-predicate`, and `app.activity-drag-attachment-provider` are exactly those functions. Then deactivate and assert all three app fields are nil.

- [ ] **Step 2: Run the activity hook test and verify it fails**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-activity-retention:main
  ```

  Expected: FAIL because the three `ctx:set-*` methods do not exist.

- [ ] **Step 3: Implement activity hook plumbing**

  In `activities.fnl`:

  - add `app.activity-top-toolbar-builder`, `app.activity-object-move-predicate`, and `app.activity-drag-attachment-provider` resets to `clear-activity-runtime-hooks!`;
  - add `:top-toolbar-builder`, `:object-move-predicate`, and `:drag-attachment-provider` keys to `empty-activity-hooks`;
  - copy those keys into app fields in `apply-activity-hooks!`;
  - add context methods with these exact names:

  ```fennel
  :set-top-toolbar-builder! (fn [_self value] (set-staged-hook! :top-toolbar-builder value))
  :set-object-move-predicate! (fn [_self value] (set-staged-hook! :object-move-predicate value))
  :set-drag-attachment-provider! (fn [_self value] (set-staged-hook! :drag-attachment-provider value))
  ```

- [ ] **Step 4: Add failing center-column HUD layout tests**

  In `test-hud-layout.fnl`, add a test named `top-toolbar-reserves-center-column-between-full-height-rails`. Build a HUD with:

  ```fennel
  {:control-builder (fixed-widget "control" (glm.vec3 100 3 0))
   :status-builder (fixed-widget "status" (glm.vec3 100 2 0))
   :left-dock-builder (fixed-widget "left" (glm.vec3 5 7 0))
   :right-dock-builder (fixed-widget "right" (glm.vec3 6 7 0))
   :top-toolbar-builder (fixed-widget "toolbar" (glm.vec3 20 4 0))}
  ```

  With HUD content `100 x 40`, assert after layout:

  ```fennel
  (assert (= entity.top-toolbar-root.layout.size.x 89)) ; 100 - 5 - 6
  (assert (= entity.top-toolbar-root.layout.size.y 4))
  (assert (= entity.left-dock-root.layout.size.y 35)) ; 40 - control 3 - status 2
  (assert (= entity.right-dock-root.layout.size.y 35))
  (assert (= entity.tiles-root.layout.size.y 31)) ; middle 35 - toolbar 4
  ```

- [ ] **Step 5: Run the HUD layout test and verify it fails**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hud-layout:main
  ```

  Expected: FAIL because `top-toolbar-root` is not produced and the middle layout has no center-column toolbar.

- [ ] **Step 6: Implement `activity-top-toolbar-view.fnl`**

  Create a builder that reads `app.activity-top-toolbar-builder`. It returns an entity with a `Layout` named `activity-top-toolbar-view`. Its measurer:

  - builds a child when the app builder identity changes;
  - measures the child when present;
  - sets measure to `glm.vec3 0 0 0` when absent;
  - sets `app.activity-top-toolbar-height` to the measured height.

  Its layouter assigns child `position`, `size`, `rotation`, `clip-region`, and `depth-offset-index` directly. Its `drop` drops the child and sets `app.activity-top-toolbar-height` to `0`.

- [ ] **Step 7: Modify `hud-layout.fnl` for center-column toolbar**

  Add `local top-toolbar-builder options.top-toolbar-builder`. In `build`, create `top-toolbar` when the builder exists. Replace the single center `tiles` child in the middle row with a center stack made from vertical `Flex`:

  ```fennel
  (local scene-stack ((Stack {:depth-offset-step panel-depth-layer-step
                             :children [(fn [_ctx] tiles)
                                        (fn [_ctx] float)
                                        (fn [_ctx] middle-overlay)]}) ctx))
  (local center-children [])
  (when top-toolbar
    (table.insert center-children (FlexChild (fn [_ctx] top-toolbar))))
  (table.insert center-children (FlexChild (fn [_ctx] scene-stack) 1))
  (local center-column ((Flex {:axis 2 :xalign :stretch :yspacing 0 :children center-children}) ctx))
  ```

  Insert `center-column` as the flexing middle child between left and right docks. Expose `:top-toolbar-root top-toolbar` and keep `:middle-root` pointing to the scene stack or a clearly named center entity used by tests. Update `update` and `drop` to include `top-toolbar`.

- [ ] **Step 8: Add failing sidebar reserve tests**

  In `test-hud-extended-sidebar.fnl`, add a test named `expanded-panel-reserves-toolbar-height-while-rail-remains-full-height`. Build `HudExtendedSidebarView` with `{:top-reserve-height-provider (fn [] 4)}`. Allocate height `30`. Assert:

  ```fennel
  (assert (= entity.rail-entity.layout.size.y 30))
  (assert (= entity.active-panel-entity.layout.position.y 4))
  (assert (= entity.active-panel-entity.layout.size.y 26))
  ```

  In the existing activity dock tests or `test-hud-layout.fnl`, add equivalent coverage for the left activity dock expanded content while the feature rail remains full-height.

- [ ] **Step 9: Implement sidebar reserve support**

  In `hud-extended-sidebar-view.fnl`, accept an optional `opts` table. Add local:

  ```fennel
  (fn top-reserve-height []
    (math.max 0 (or (and options.top-reserve-height-provider
                         (options.top-reserve-height-provider)) 0)))
  ```

  During layout, keep rail size `(glm.vec3 rail-w height 0)`. For `active-panel-entity`, set y offset to reserve height and size.y to `(math.max 0 (- height reserve))`.

  In `activity-dock-view.fnl`, accept the same option and apply the reserve only to activity-provided content, not to the feature rail.

- [ ] **Step 10: Wire the toolbar view in `main.fnl`**

  Require `activity-top-toolbar-view`. When building HUD options, pass `:top-toolbar-builder (ActivityTopToolbarView {})`. When building right sidebar and left activity dock, pass `{:top-reserve-height-provider (fn [] (or app.activity-top-toolbar-height 0))}`.

- [ ] **Step 11: Run focused validation and commit Task 1**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-activity-retention:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hud-layout:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hud-extended-sidebar:main
  ```

  Commit:

  ```bash
  git add assets/lua/activity-top-toolbar-view.fnl assets/lua/activities.fnl assets/lua/hud-layout.fnl assets/lua/hud-extended-sidebar-view.fnl assets/lua/activity-dock-view.fnl assets/lua/main.fnl assets/lua/tests/test-activity-retention.fnl assets/lua/tests/test-hud-layout.fnl assets/lua/tests/test-hud-extended-sidebar.fnl
  git commit -m "feat(ui): add activity center toolbar slot"
  ```

---

### Task 2: Sandbox Toolbar State, View, and Persistence

**Files:**
- Create: `assets/lua/sandbox-toolbar-state.fnl`
- Create: `assets/lua/sandbox-toolbar-view.fnl`
- Create: `assets/lua/tests/test-sandbox-toolbar-state.fnl`
- Create: `assets/lua/tests/test-sandbox-toolbar-view.fnl`
- Modify: `assets/lua/sandbox-activity-unit.fnl`
- Modify: `assets/lua/tests/test-sandbox-activity.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: Task 1 activity hooks.
- Produces:
  ```fennel
  (SandboxToolbarState opts) ; -> state
  state.camera-mode ; :flight or :grounded
  state.object-move-enabled? ; boolean
  state.drag-attachment ; :center or :anchor
  state.changed ; Signal
  (state:set-camera-mode mode) ; -> mode
  (state:toggle-camera-mode) ; -> mode
  (state:set-object-move-enabled! enabled?) ; -> boolean
  (state:toggle-object-move-enabled!) ; -> boolean
  (state:set-drag-attachment mode) ; -> mode
  (state:toggle-drag-attachment) ; -> mode
  (state:capture-state) ; -> table with string values
  (state:restore-state payload) ; -> true
  (SandboxToolbarView state) ; -> builder
  ```

- [ ] **Step 1: Add failing toolbar state tests**

  Create `test-sandbox-toolbar-state.fnl` with tests for defaults, changed signal count, invalid value errors, capture, and restore. Canonical capture output is:

  ```fennel
  {:camera-mode "flight"
   :object-move-enabled? false
   :drag-attachment "center"}
  ```

- [ ] **Step 2: Run state tests and verify failure**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-sandbox-toolbar-state:main
  ```

  Expected: FAIL because `sandbox-toolbar-state` does not exist.

- [ ] **Step 3: Implement `sandbox-toolbar-state.fnl`**

  Implement validation sets:

  ```fennel
  (local valid-camera-modes {:flight true :grounded true})
  (local valid-drag-attachments {:center true :anchor true})
  ```

  Emit `changed` only after successful mutation. Restore accepts nil by leaving defaults unchanged; non-nil restore must use canonical strings `"flight"`, `"grounded"`, `"center"`, and `"anchor"`.

- [ ] **Step 4: Add failing toolbar view tests**

  Create `test-sandbox-toolbar-view.fnl`. Build the view with a fresh state and assert it creates buttons named:

  ```text
  sandbox-toolbar-camera-mode
  sandbox-toolbar-object-move
  sandbox-toolbar-drag-attachment
  ```

  Invoke each button's `on-click` and assert the corresponding state field changes. Assert `entity:update()` after a state change updates button text or variant so active modes are visible.

- [ ] **Step 5: Implement `sandbox-toolbar-view.fnl`**

  Use existing `Button`, `Flex`, `FlexChild`, `Padding`, and `Rectangle`/`Stack`. Validate icon names with:

  ```bash
  rg -n "^(flight|directions_walk|open_with|anchor)" assets/material-design-icons/icons.txt
  ```

  If `anchor` is unavailable, use the exact closest available Material icon from the search result and record it in the implementation commit message. Use compact labels: `Flight`/`Grounded`, `Move`, and `Anchor`.

- [ ] **Step 6: Add failing Sandbox integration tests**

  In `test-sandbox-activity.fnl`, add coverage that Sandbox activation:

  - creates or reuses `runtime.sandbox-toolbar-state`;
  - installs `app.activity-top-toolbar-builder`;
  - installs object move predicate returning state value;
  - installs drag attachment provider returning state value;
  - snapshots toolbar state under `scene.toolbar`;
  - restores `scene.toolbar` into the state.

- [ ] **Step 7: Integrate Sandbox toolbar**

  In `sandbox-activity-unit.fnl`:

  - require `sandbox-toolbar-state` and `sandbox-toolbar-view`;
  - ensure `world-runtime.sandbox-toolbar-state` before controls are created;
  - set `app.sandbox-toolbar-state` while Sandbox is active;
  - install hooks:

  ```fennel
  (ctx:set-top-toolbar-builder! (SandboxToolbarView toolbar-state))
  (ctx:set-object-move-predicate! (fn [] (= toolbar-state.object-move-enabled? true)))
  (ctx:set-drag-attachment-provider! (fn [] toolbar-state.drag-attachment))
  ```

  Add `(set app.sandbox-toolbar-state nil)` in Sandbox deactivation. Snapshot with `(set captured.toolbar (toolbar-state:capture-state))`. Restore with `(toolbar-state:restore-state scene-state.toolbar)`.

- [ ] **Step 8: Register tests and validate**

  Add new modules to `tests/fast.fnl`. Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-sandbox-toolbar-state:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-sandbox-toolbar-view:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-sandbox-activity:main
  ```

  Commit:

  ```bash
  git add assets/lua/sandbox-toolbar-state.fnl assets/lua/sandbox-toolbar-view.fnl assets/lua/sandbox-activity-unit.fnl assets/lua/tests/test-sandbox-toolbar-state.fnl assets/lua/tests/test-sandbox-toolbar-view.fnl assets/lua/tests/test-sandbox-activity.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(lua): add sandbox toolbar state and view"
  ```

---

### Task 3: Object Move Predicate and Physics Anchor Drag

**Files:**
- Modify: `assets/lua/state-runtime.fnl`
- Modify: `assets/lua/state-handlers/pointer.fnl`
- Modify: `assets/lua/movables.fnl`
- Modify: `assets/lua/layout-physics-bodies.fnl`
- Modify: `assets/lua/scene.fnl`
- Modify: `assets/lua/tests/test-movables.fnl`
- Modify: `assets/lua/tests/test-scene-drag.fnl`
- Modify: `assets/lua/tests/test-layout-physics-bodies.fnl`

**Interfaces:**
- Consumes:
  ```fennel
  app.activity-object-move-predicate ; function or nil
  app.activity-drag-attachment-provider ; function or nil
  ```
- Produces:
  ```fennel
  (Runtime.activity-object-move-enabled? payload) ; -> boolean
  (Runtime.drag-attachment-mode) ; -> :center or :anchor
  (Movables.register widget {:on-drag-update callback})
  ;; callback signature:
  (fn [entry drag update] handled?)
  ;; update fields: :payload :pointer :ray :hit :new-position :plane
  ```

- [ ] **Step 1: Add failing pointer predicate tests**

  In `test-scene-drag.fnl`, add tests proving:

  - `Alt` + left drag still starts movement;
  - no-`Alt` left drag does not start movement when predicate is nil or false;
  - no-`Alt` left drag starts movement when `app.activity-object-move-predicate` returns true;
  - click without crossing the existing drag threshold remains a click.

- [ ] **Step 2: Implement predicate routing**

  In `state-runtime.fnl`, add:

  ```fennel
  (fn activity-object-move-enabled? [_payload]
    (and app.activity-object-move-predicate
         (= (app.activity-object-move-predicate) true)))
  ```

  In `pointer.fnl`, change `MovableMouseButtonDown` to allow drag when either `(Runtime.alt-held? payload)` or `(Runtime.activity-object-move-enabled? payload)` is true.

- [ ] **Step 3: Add failing Movables override tests**

  In `test-movables.fnl`, add tests proving:

  - `on-drag-start` receives `(entry drag payload)` and `drag.hit-point`;
  - `on-drag-update` receives `update.new-position`;
  - when `on-drag-update` returns true, default `target:set-position` is not called;
  - when `on-drag-update` returns false, default `target:set-position` still runs;
  - `on-drag-end` receives `(entry drag)` before drag state is cleared.

- [ ] **Step 4: Implement Movables drag callbacks**

  In `movables.fnl`:

  - store `options.on-drag-update` on each entry;
  - call `entry.on-drag-start entry drag payload`;
  - in `update-drag`, build:

  ```fennel
  {:payload payload :pointer pointer :ray ray :hit hit :new-position new-position :plane drag.plane}
  ```

  - call `entry.on-drag-update entry drag update`; skip default `target:set-position` only when it returns true;
  - call `entry.on-drag-end entry drag` before clearing `self.drag`.

- [ ] **Step 5: Add failing physics anchor tests**

  In `test-layout-physics-bodies.fnl`, add a fake body that records `applyForceAtPosition`, `activate`, and `forceActivationState`. Assert in anchor mode:

  - clicked relative anchor is recorded on drag start;
  - `applyForceAtPosition` is called during drag update;
  - default layout teleport is suppressed;
  - body activation is requested;
  - physics-backed anchor mode raises an explicit error if `applyForceAtPosition` is absent.

- [ ] **Step 6: Implement anchor force drag**

  In `layout-physics-bodies.fnl`, add `drag-attachment-mode`, `body-center`, and `apply-anchor-force!` helpers. `drag-attachment-mode` returns `:center` when no provider is installed. `body-center` reads `entry.body:getCenterOfMassTransform():getOrigin()` when a body is active and falls back to the entry layout center. `apply-anchor-force!` computes current anchor world position, spring displacement, optional velocity damping, and calls `entry.body:applyForceAtPosition`.

  In `create-movable-entry`, add `:on-drag-update`. For `:center`, return false so current direct movement runs. For `:anchor`, require `entry.body` and `entry.body.applyForceAtPosition`; compute `relative-anchor` from `drag.hit-point - body-center`; compute `force = (desired-anchor-world - current-anchor-world) * spring-strength`; call `body:applyForceAtPosition (bt-glm-vec3 force) (bt-glm-vec3 relative-anchor)`; activate the body; return true.

  Use `spring-strength` default `35.0`. If `body:getVelocityInLocalPoint` is available, subtract `velocity * 4.0` from force for damping.

- [ ] **Step 7: Preserve new movable option through scene registration**

  In `scene.fnl`, update movable entry normalization/registration to preserve `:on-drag-update` exactly as a function value. Do not rename existing option keys.

- [ ] **Step 8: Validate and commit Task 3**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-movables:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-scene-drag:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-layout-physics-bodies:main
  ```

  Commit:

  ```bash
  git add assets/lua/state-runtime.fnl assets/lua/state-handlers/pointer.fnl assets/lua/movables.fnl assets/lua/layout-physics-bodies.fnl assets/lua/scene.fnl assets/lua/tests/test-movables.fnl assets/lua/tests/test-scene-drag.fnl assets/lua/tests/test-layout-physics-bodies.fnl
  git commit -m "feat(lua): add sandbox object move and anchor drag"
  ```

---

### Task 4: Camera Animation Foundation and Grounded Sandbox Controls

**Files:**
- Create: `assets/lua/camera-animation.fnl`
- Create: `assets/lua/sandbox-camera-controls.fnl`
- Create: `assets/lua/tests/test-camera-animation.fnl`
- Create: `assets/lua/tests/test-sandbox-camera-controls.fnl`
- Modify: `assets/lua/sandbox-activity-unit.fnl`
- Modify: `assets/lua/tests/test-sandbox-activity.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `SandboxToolbarState` from Task 2 and existing `FirstPersonControls`.
- Produces:
  ```fennel
  (CameraAnimation.scalar-channel {:value n :target n :smoothing-rate n}) ; -> channel
  (channel:value) ; -> number
  (channel:set-target n) ; -> true
  (channel:snap n) ; -> true
  (channel:update delta-seconds) ; -> number
  (SandboxCameraControls opts) ; -> controls with existing control handler interface
  ```

  Required `SandboxCameraControls` opts: `:camera`, `:toolbar-state`, and `:flight-controls`. Optional opts: `:terrain-sampler`, `:delta-unit`, `:eye-height`, `:gravity`, `:jump-speed`, `:pitch-min`, and `:pitch-max`.

- [ ] **Step 1: Add failing camera animation tests**

  Create `test-camera-animation.fnl` with tests for snap, target update, monotonic approach, no overshoot for positive smoothing, deterministic fixed-delta output, and explicit errors for non-number value/target/delta.

- [ ] **Step 2: Implement `camera-animation.fnl`**

  Implement scalar smoothing only. Use exponential approach:

  ```fennel
  (local alpha (- 1 (math.exp (* -1 smoothing-rate delta-seconds))))
  (set current (+ current (* (- target current) alpha)))
  ```

  Clamp `alpha` to `[0, 1]` and snap to target when distance is below `1e-5`.

- [ ] **Step 3: Add failing Sandbox camera controls tests**

  Create `test-sandbox-camera-controls.fnl`. Use fake camera and fake flight controls. Verify:

  - flight mode delegates `update`, mouse, wheel, gamepad, and key handlers to flight controls;
  - grounded mode does not call flight `update`;
  - grounded mouse look clamps pitch between configured min/max;
  - grounded `Space` sets positive vertical velocity;
  - gravity lands camera at sampled terrain height plus eye height;
  - terrain follow uses the scalar channel rather than snapping immediately;
  - missing terrain sampler in grounded mode raises `SandboxCameraControls grounded mode requires terrain sampler`.

- [ ] **Step 4: Implement `sandbox-camera-controls.fnl`**

  Mirror `FirstPersonControls` handler names: `update`, `drop`, `drag-active?`, `should-suppress-click?`, `on-key-down`, `on-key-up`, `on-mouse-wheel`, `on-mouse-button-down`, `on-mouse-button-up`, `on-mouse-motion`, `on-gamepad-button-down`, `on-gamepad-axis-motion`, and `on-gamepad-removed`.

  In `:flight`, delegate to `flight-controls`. In `:grounded`, track key state, yaw, pitch, vertical velocity, airborne flag, mouse drag state, and a y scalar channel. Use defaults: `eye-height 2.0`, `gravity 18.0`, `jump-speed 8.0`, `pitch-min -1.2`, `pitch-max 1.2`, `movement-speed 10.0`.

- [ ] **Step 5: Integrate controls into Sandbox activation**

  In `sandbox-activity-unit.fnl`, create the inner `FirstPersonControls` as before, then wrap it:

  ```fennel
  (SandboxCameraControls {:camera sandbox-camera
                          :toolbar-state toolbar-state
                          :flight-controls flight-controls
                          :terrain-sampler scene})
  ```

  Store the wrapper in `world-runtime.activity-controls.scene.sandbox`. If a previous raw `FirstPersonControls` is present, replace it with the wrapper and keep the raw controls as the wrapper's `flight-controls`.

- [ ] **Step 6: Add terrain sampler method if missing**

  If `scene` has no height query matching the controls tests, add `scene:height-at-world-point(world-point)` that queries the active Sandbox terrain and returns a number. If no terrain is under the point, return `0` for the default ground plane.

- [ ] **Step 7: Register tests, validate, and commit Task 4**

  Add new tests to `fast.fnl`. Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-camera-animation:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-sandbox-camera-controls:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-first-person-controls:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-sandbox-activity:main
  ```

  Commit:

  ```bash
  git add assets/lua/camera-animation.fnl assets/lua/sandbox-camera-controls.fnl assets/lua/sandbox-activity-unit.fnl assets/lua/scene.fnl assets/lua/tests/test-camera-animation.fnl assets/lua/tests/test-sandbox-camera-controls.fnl assets/lua/tests/test-sandbox-activity.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(lua): add grounded sandbox camera controls"
  ```

---

### Task 5: Developer Documentation and Final Validation

**Files:**
- Create: `docs/dev/notes/sandbox-interaction-toolbar.md`
- Modify: `docs/dev/notes/index.md`
- Modify: `assets/lua/tests/fast.fnl` only if a new test module from earlier tasks was not registered in its task.

**Interfaces:**
- Consumes: all interfaces produced by Tasks 1 through 4.
- Produces: developer documentation for the activity toolbar hook, Sandbox toolbar state, object move mode, anchor drag limitations, and grounded camera controls.

- [ ] **Step 1: Write the developer note**

  Create `docs/dev/notes/sandbox-interaction-toolbar.md` with sections:

  ```markdown
  # Sandbox Interaction Toolbar

  ## Layout
  The Sandbox toolbar is contributed by the active activity and laid out in the HUD center column between full-height left and right rails.

  ## Activity Hooks
  Document set-top-toolbar-builder!, set-object-move-predicate!, and set-drag-attachment-provider!.

  ## Sandbox State
  Document camera-mode, object-move-enabled?, and drag-attachment.

  ## Dragging
  Alt-drag always works. Object move mode permits no-Alt drag. Anchor drag applies force at the clicked point and does not add Bullet constraints.

  ## Grounded Camera
  Grounded camera follows terrain, jumps with Space, clamps pitch, and is not a character controller.
  ```

- [ ] **Step 2: Link the developer note**

  Add a bullet for `sandbox-interaction-toolbar.md` in `docs/dev/notes/index.md` using the file's existing link style.

- [ ] **Step 3: Verify all focused tests are registered**

  Confirm `assets/lua/tests/fast.fnl` includes:

  ```fennel
  :tests.test-sandbox-toolbar-state
  :tests.test-sandbox-toolbar-view
  :tests.test-camera-animation
  :tests.test-sandbox-camera-controls
  ```

- [ ] **Step 4: Run focused validation**

  Run all focused modules touched by this plan:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-activity-retention:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hud-layout:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hud-extended-sidebar:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-sandbox-toolbar-state:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-sandbox-toolbar-view:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-sandbox-activity:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-movables:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-scene-drag:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-layout-physics-bodies:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-camera-animation:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-sandbox-camera-controls:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-first-person-controls:main
  ```

- [ ] **Step 5: Run broad validation**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.fast:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 6: Commit documentation**

  Commit:

  ```bash
  git add docs/dev/notes/sandbox-interaction-toolbar.md docs/dev/notes/index.md assets/lua/tests/fast.fnl
  git commit -m "docs: document sandbox interaction toolbar"
  ```

---

## Validation Ladder

1. Each task runs its focused tests before commit.
2. Task 5 reruns all focused modules in one pass.
3. Task 5 runs `tests.fast:main`.
4. Task 5 runs the repository standard full test command from `AGENTS.md`:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

## Acceptance Criteria

- Sandbox displays a horizontal toolbar below the global control panel.
- Toolbar is laid out only in the center column between rails.
- Left and right rails remain full-height.
- Expanded sidebar panels do not overlap the toolbar.
- Toolbar exists only when Sandbox contributes it.
- Camera mode toggles between flight and grounded.
- Grounded camera supports jump, gravity landing, pitch clamp, and terrain-follow smoothing.
- Object move mode allows no-`Alt` dragging only when Sandbox enables it.
- Existing `Alt` drag remains supported.
- Anchor drag applies force at the clicked point for physics-backed movables.
- Center drag remains the default.
- No native Bullet constraint binding is added.

## Risks and Mitigations

- HUD layout changes can regress rail and center sizing. Mitigation: Task 1 asserts exact rail, toolbar, and scene sizes.
- Pointer dispatch changes can steal clicks. Mitigation: Task 3 preserves the drag threshold and reruns scene drag tests.
- Force-at-anchor tuning may feel weak or unstable. Mitigation: first implementation uses conservative spring and damping constants and fails loudly for missing physics methods.
- Grounded camera terrain sampling may be absent in test or non-Sandbox contexts. Mitigation: grounded mode requires an explicit sampler and errors clearly when it is missing.

## Out of Scope

- Toolbars for non-Sandbox activities.
- A broad toolbar customization framework.
- Native Bullet point-to-point or 6DOF constraint bindings.
- Full character controller behavior.
- Cinematic camera timelines, spline paths, or keybinding UI.
