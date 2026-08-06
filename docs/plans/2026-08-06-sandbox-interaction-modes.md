# Sandbox Interaction Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Sandbox's confusing independent interaction toggles with four mutually-exclusive modes: Fly, Walk, Move, and Grab.

**Architecture:** `SandboxToolbarState` becomes the single source of truth for a canonical `interaction-mode`. Activity/runtime input hooks derive object-drag behavior from that mode, camera controls derive navigation behavior from that mode, and Grab uses a narrow Bullet point-to-point constraint binding instead of a manual force spring.

**Tech Stack:** Space Fennel, existing HUD widgets, Space activity/runtime hooks, C++17, sol2 Lua bindings, Bullet Physics `btPoint2PointConstraint`, project-native Fennel validation.

## Global Constraints

- Use four user-facing modes only: **Fly**, **Walk**, **Move**, and **Grab**.
- `interaction-mode`: one of `:flight`, `:walk`, `:move`, `:grab`; default `:flight`.
- Remove `Alt` + drag object movement for now.
- Object dragging happens only when the selected mode is Move or Grab.
- Walk mode uses WASD movement, arrow-key yaw/pitch, Space jump, terrain grounding, and pitch limits.
- Grab uses Bullet point-to-point constraints, not the manual force approximation, as the primary implementation.
- The Bullet binding must be narrow and explicit; do not expose a broad constraint framework.
- Invalid modes, missing terrain sampler, missing Bullet constraint support, and missing physics bodies fail loudly.
- Existing persisted toolbar state must migrate to the new `interaction-mode` model without leaving old runtime aliases.
- Use `local` instead of `let` in new or touched Fennel code.
- Use factory functions instead of `.new` constructors.
- Do not add legacy aliases or compatibility shims beyond restore-time payload migration.
- Fennel validation order: compile check first, constraints second, focused Fennel tests third.
- `make build` timeout is `14400000`; run it before `./build/space` validation when the binary may be missing or stale or when C++ changed.

---

## File Structure

- `assets/lua/sandbox-toolbar-state.fnl` — canonical `interaction-mode` state, derived helpers, capture/restore, legacy payload migration.
- `assets/lua/sandbox-toolbar-view.fnl` — four explicit mode buttons and single-active highlighting.
- `assets/lua/activities.fnl` — activity lifecycle storage/clearing for one object-drag mode provider.
- `assets/lua/state-runtime.fnl` — validated runtime accessor for the active object-drag mode.
- `assets/lua/state-handlers/pointer.fnl` — movable drag gate with no `Alt` bypass.
- `assets/lua/sandbox-activity-unit.fnl` — Sandbox installs the toolbar, state, camera controls, and object-drag mode provider.
- `assets/lua/sandbox-camera-controls.fnl` — Fly delegation, Walk controls, and camera no-op behavior while object modes are selected.
- `src/physics.h`, `src/physics.cpp` — `Physics` add/remove/count constraint wrappers.
- `src/lua_physics.cpp` — narrow `btTypedConstraint` / `btPoint2PointConstraint` and `Physics` constraint Lua bindings.
- `assets/lua/physics-point-grab.fnl` — Fennel point-grab session factory that owns constraint lifetime for one drag.
- `assets/lua/layout-physics-bodies.fnl` — Move direct placement and Grab constraint session integration for physics-backed movables.
- `docs/dev/notes/sandbox-interaction-toolbar.md` — updated developer note for the new mode model.

## Validation Commands

Use these environment flags for direct Fennel test runs:

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
```

Focused Fennel gate after touched `.fnl` files is always:

```bash
make fennel-check
make constraints
```

Each task below lists the exact direct `./build/space -m tests...:main` modules
to run after those two gates.

Final local validation:

```bash
make build
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

---

### Task 1: Canonical Interaction Mode State

**Files:**
- Modify: `assets/lua/sandbox-toolbar-state.fnl`
- Test: `assets/lua/tests/test-sandbox-toolbar-state.fnl`

**Interfaces:**
- Produces: `SandboxToolbarState(opts: table|nil) -> state`
- Produces: `state.interaction-mode -> :flight|:walk|:move|:grab`
- Produces: `state:set-interaction-mode(mode: keyword|string) -> keyword`
- Produces: `state:navigation-mode() -> :flight|:walk|nil`
- Produces: `state:object-drag-mode() -> :move|:grab|nil`
- Produces: `state:capture-state() -> {:interaction-mode string}`
- Produces: `state:restore-state(payload: table|nil) -> true`

- [ ] **Step 1: Write failing state tests**

  In `test-sandbox-toolbar-state.fnl`, replace the camera/move/attachment assertions with tests for these exact behaviors:

  ```fennel
  (fn sandbox-toolbar-state-defaults-to-flight []
    (local state (SandboxToolbarState {}))
    (assert (= state.interaction-mode :flight) "default mode must be :flight")
    (assert (= (state:navigation-mode) :flight) "default navigation mode must be :flight")
    (assert (= (state:object-drag-mode) nil) "default object drag mode must be nil"))

  (fn sandbox-toolbar-state-sets-valid-modes []
    (local state (SandboxToolbarState {}))
    (each [_ mode (ipairs [:flight :walk :move :grab])]
      (state:set-interaction-mode mode)
      (assert (= state.interaction-mode mode) (.. "mode should be " (tostring mode)))))

  (fn sandbox-toolbar-state-rejects-invalid-mode []
    (local state (SandboxToolbarState {}))
    (local (ok err) (pcall state.set-interaction-mode state :grounded))
    (assert (not ok) "legacy :grounded must not be a valid runtime mode")
    (assert (string.find (tostring err) "Invalid interaction mode")
            (.. "error should mention invalid interaction mode, got " (tostring err))))

  (fn sandbox-toolbar-state-captures-canonical-payload []
    (local state (SandboxToolbarState {:interaction-mode :grab}))
    (local captured (state:capture-state))
    (assert (= captured.interaction-mode "grab") "capture must store interaction-mode")
    (assert (= captured.camera-mode nil) "capture must not store camera-mode")
    (assert (= captured.object-move-enabled? nil) "capture must not store object-move-enabled?")
    (assert (= captured.drag-attachment nil) "capture must not store drag-attachment"))

  (fn sandbox-toolbar-state-migrates-legacy-payloads []
    (local state (SandboxToolbarState {}))
    (state:restore-state {:object-move-enabled? true :drag-attachment "anchor" :camera-mode "flight"})
    (assert (= state.interaction-mode :grab) "legacy move+anchor must migrate to :grab")
    (state:restore-state {:object-move-enabled? true :drag-attachment "center" :camera-mode "flight"})
    (assert (= state.interaction-mode :move) "legacy move+center must migrate to :move")
    (state:restore-state {:object-move-enabled? false :camera-mode "grounded"})
    (assert (= state.interaction-mode :walk) "legacy grounded must migrate to :walk")
    (state:restore-state {:camera-mode "flight"})
    (assert (= state.interaction-mode :flight) "legacy flight must migrate to :flight"))

  (fn sandbox-toolbar-state-removes-legacy-runtime-aliases []
    (local state (SandboxToolbarState {}))
    (assert (= state.camera-mode nil) "camera-mode alias must be absent")
    (assert (= state.object-move-enabled? nil) "object-move-enabled? alias must be absent")
    (assert (= state.drag-attachment nil) "drag-attachment alias must be absent")
    (assert (= state.toggle-camera-mode nil) "toggle-camera-mode must be absent")
    (assert (= state.toggle-object-move-enabled! nil) "toggle-object-move-enabled! must be absent")
    (assert (= state.toggle-drag-attachment nil) "toggle-drag-attachment must be absent"))
  ```

- [ ] **Step 2: Run the focused test to verify RED**

  ```bash
  make build
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-toolbar-state:main
  ```

  Expected: FAIL because the state still exposes old fields.

- [ ] **Step 3: Implement the canonical state**

  Update `sandbox-toolbar-state.fnl` so it stores only `interaction-mode`. Use a `valid-interaction-modes` table for `:flight`, `:walk`, `:move`, and `:grab`. `restore-state` must accept the new `interaction-mode` string/keyword and perform only the legacy payload migration listed in Step 1. The final returned state literal must include only `changed`, `set-interaction-mode`, `navigation-mode`, `object-drag-mode`, `capture-state`, and `restore-state`; `__index` must return a value only for `:interaction-mode`.

- [ ] **Step 4: Run focused GREEN validation**

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-toolbar-state:main
  ```

  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add assets/lua/sandbox-toolbar-state.fnl assets/lua/tests/test-sandbox-toolbar-state.fnl
  git commit -m "feat(ui): add sandbox interaction mode state"
  ```

---

### Task 2: Four Explicit Toolbar Mode Buttons

**Files:**
- Modify: `assets/lua/sandbox-toolbar-view.fnl`
- Test: `assets/lua/tests/test-sandbox-toolbar-view.fnl`

**Interfaces:**
- Consumes: `state.interaction-mode`
- Consumes: `state:set-interaction-mode(mode)`
- Produces layout names: `sandbox-toolbar-mode-flight`, `sandbox-toolbar-mode-walk`, `sandbox-toolbar-mode-move`, `sandbox-toolbar-mode-grab`

- [ ] **Step 1: Verify icons exist**

  ```bash
  rg "^(flight|directions_walk|open_with|pan_tool) " assets/material-design-icons/icons.txt
  ```

  Expected: all four icon names are present. The repository icon list currently
  contains `flight`, `directions_walk`, `open_with`, and `pan_tool`; use
  `pan_tool` for Grab.

- [ ] **Step 2: Write failing toolbar tests**

  Update `test-sandbox-toolbar-view.fnl` so it asserts all four layout names exist, clicking each button selects that exact mode, clicking the active Fly button does not emit a change, and only the active mode button has `variant :primary`.

  Add this test body:

  ```fennel
  (fn sandbox-toolbar-view-clicking-each-mode-selects-mode []
    (local state (SandboxToolbarState {}))
    (local entity ((SandboxToolbarView state) (make-test-ctx)))
    (each [_ pair (ipairs [{:name "sandbox-toolbar-mode-flight" :mode :flight}
                           {:name "sandbox-toolbar-mode-walk" :mode :walk}
                           {:name "sandbox-toolbar-mode-move" :mode :move}
                           {:name "sandbox-toolbar-mode-grab" :mode :grab}])]
      (local btn (find-entity-by-layout-name entity pair.name))
      (assert btn (.. "missing button " pair.name))
      (btn:on-click {})
      (assert (= state.interaction-mode pair.mode)
              (.. pair.name " should select " (tostring pair.mode)))))
  ```

- [ ] **Step 3: Run focused test to verify RED**

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-toolbar-view:main
  ```

  Expected: FAIL because the view still renders old toggle buttons.

- [ ] **Step 4: Implement the toolbar view**

  Replace old camera/move/anchor button builders with a local table of four button specs. Each button uses `:primary` only when `(= state.interaction-mode spec.mode)`, and its click handler calls `(state:set-interaction-mode spec.mode)`. Remove camera label mutation logic; state changes only refresh variants.

- [ ] **Step 5: Run focused GREEN validation**

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-toolbar-view:main
  ```

  Expected: PASS.

- [ ] **Step 6: Commit**

  ```bash
  git add assets/lua/sandbox-toolbar-view.fnl assets/lua/tests/test-sandbox-toolbar-view.fnl
  git commit -m "feat(ui): render sandbox mode toolbar"
  ```

---

### Task 3: Object Drag Provider and Alt-Drag Removal

**Files:**
- Modify: `assets/lua/activities.fnl`
- Modify: `assets/lua/state-runtime.fnl`
- Modify: `assets/lua/state-handlers/pointer.fnl`
- Modify: `assets/lua/sandbox-activity-unit.fnl`
- Test: `assets/lua/tests/test-activity-retention.fnl`
- Test: `assets/lua/tests/test-sandbox-activity.fnl`
- Test: `assets/lua/tests/test-scene-drag.fnl`

**Interfaces:**
- Consumes: `toolbar-state:object-drag-mode() -> :move|:grab|nil`
- Produces: `ctx:set-object-drag-mode-provider!(provider: fn -> :move|:grab|nil)`
- Produces: `Runtime.activity-object-drag-mode() -> :move|:grab|nil`

- [ ] **Step 1: Write failing hook and pointer tests**

  Update activity tests so Sandbox installs `app.activity-object-drag-mode-provider` and clears it on deactivation. Update scene drag tests so `:mod 256` no longer starts object drag when the provider is nil, provider `:move` starts direct drag, and provider `:grab` reaches the physics drag path.

- [ ] **Step 2: Run focused tests to verify RED**

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-retention:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-activity:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-scene-drag:main
  ```

  Expected: FAIL because old providers and Alt gates are still active.

- [ ] **Step 3: Implement the single provider hook**

  In `activities.fnl`, replace `activity-object-move-predicate` and `activity-drag-attachment-provider` with `activity-object-drag-mode-provider`. In `state-runtime.fnl`, add `activity-object-drag-mode` that returns nil, `:move`, or `:grab`, and errors on any other provider result. In `pointer.fnl`, remove `Runtime.alt-held?` from the movable left-button gate. In `sandbox-activity-unit.fnl`, install `(fn [] (toolbar-state:object-drag-mode))`.

- [ ] **Step 4: Run focused GREEN validation**

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-retention:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-activity:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-scene-drag:main
  ```

  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add assets/lua/activities.fnl assets/lua/state-runtime.fnl assets/lua/state-handlers/pointer.fnl assets/lua/sandbox-activity-unit.fnl assets/lua/tests/test-activity-retention.fnl assets/lua/tests/test-sandbox-activity.fnl assets/lua/tests/test-scene-drag.fnl
  git commit -m "feat(input): gate sandbox dragging by mode"
  ```

---

### Task 4: Walk Mode Camera Controls

**Files:**
- Modify: `assets/lua/sandbox-camera-controls.fnl`
- Test: `assets/lua/tests/test-sandbox-camera-controls.fnl`

**Interfaces:**
- Consumes: `toolbar-state:navigation-mode() -> :flight|:walk|nil`
- Produces: Walk controls using W `119`, A `97`, S `115`, D `100`, Space `32`, left arrow `1073741904`, right arrow `1073741903`, up arrow `1073741906`, down arrow `1073741905`

- [ ] **Step 1: Write failing Walk tests**

  Update camera tests to use `SandboxToolbarState {:interaction-mode :walk}`. Add assertions that W moves forward, D moves right, Space jumps and lands, arrow keys yaw/pitch with clamp, and `:move` / `:grab` modes do not delegate to flight controls or mutate camera position.

- [ ] **Step 2: Run focused test to verify RED**

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-camera-controls:main
  ```

  Expected: FAIL because controls still inspect old camera mode and old movement mapping.

- [ ] **Step 3: Implement Walk semantics**

  In `sandbox-camera-controls.fnl`, dispatch on `(toolbar-state:navigation-mode)`. `:flight` delegates to existing flight controls. `:walk` uses terrain sampler, WASD horizontal movement relative to yaw, arrow yaw/pitch, pitch clamp, Space jump, gravity, landing, and eye height. `nil` returns without camera movement. Missing terrain sampler in Walk must error before mutating camera state.

- [ ] **Step 4: Run focused GREEN validation**

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-camera-controls:main
  ```

  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add assets/lua/sandbox-camera-controls.fnl assets/lua/tests/test-sandbox-camera-controls.fnl
  git commit -m "feat(input): add sandbox walk controls"
  ```

---

### Task 5: Bullet Point-to-Point Constraint Binding

**Files:**
- Modify: `src/physics.h`
- Modify: `src/physics.cpp`
- Modify: `src/lua_physics.cpp`
- Test: `assets/lua/tests/test-physics.fnl`

**Interfaces:**
- Produces: `Physics::addConstraint(btTypedConstraint* constraint, bool disableCollisionsBetweenLinkedBodies)`
- Produces: `Physics::removeConstraint(btTypedConstraint* constraint)`
- Produces: `Physics::getNumConstraints() const -> int`
- Produces Lua: `bt.Point2PointConstraint(body, pivotInA) -> constraint`
- Produces Lua methods: `constraint:setPivotB(bt.Vector3)`, `constraint:getPivotInA()`, `constraint:getPivotInB()`, `constraint:setTau(number)`, `constraint:setDamping(number)`, `constraint:setImpulseClamp(number)`
- Produces Lua: `Physics:addConstraint(constraint, disableCollisionsBetweenLinkedBodies)`
- Produces Lua: `Physics:removeConstraint(constraint)`
- Produces Lua: `Physics:getNumConstraints()`

- [ ] **Step 1: Write failing binding test**

  In `test-physics.fnl`, add a test that creates a rigid body, creates `bt.Point2PointConstraint body (bt.Vector3 0.25 0.5 0.75)`, adds it to `app.engine.physics`, asserts `getNumConstraints` increases by one, calls `constraint:setPivotB (bt.Vector3 3 4 5)`, asserts `getPivotInB` returns those coordinates, removes the constraint, removes the body, and asserts the constraint count returns to its starting value.

- [ ] **Step 2: Run binding test to verify RED**

  ```bash
  make build
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-physics:main
  ```

  Expected: FAIL because constraint binding is missing.

- [ ] **Step 3: Implement narrow C++ and Lua bindings**

  Add `Physics` wrapper methods in `physics.h/.cpp` and expose them in `lua_physics.cpp`. Bind `btTypedConstraint` only as the base type needed by `btPoint2PointConstraint`. Bind `btPoint2PointConstraint` methods listed above and a factory that errors when body is nil. Remove any constraints still present in `Physics::~Physics` before deleting the dynamics world.

- [ ] **Step 4: Run binding GREEN validation**

  ```bash
  make build
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-physics:main
  ```

  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add src/physics.h src/physics.cpp src/lua_physics.cpp assets/lua/tests/test-physics.fnl
  git commit -m "feat(engine): bind Bullet point constraints"
  ```

---

### Supervisor Gate Before Task 6: Confirm Grab Diagnosis and Lifetime

Before implementing Task 6, the supervisor must use systematic-debugging Phase 3.5 and dispatch `debug-advisor` with the evidence gathered from code inspection and Task 5. The advisor brief must ask whether replacing manual `applyForceAtPosition` anchor dragging with a Lua-owned `btPoint2PointConstraint` session removed on drag end is the correct root-cause fix and whether any lifetime cleanup paths are missing. Proceed only if the advisor verdict is `confirmed`; otherwise follow the systematic-debugging skill routing.

---

### Task 6: Physics Point Grab Session and Layout Integration

**Files:**
- Create: `assets/lua/physics-point-grab.fnl`
- Modify: `assets/lua/layout-physics-bodies.fnl`
- Test: `assets/lua/tests/test-layout-physics-bodies.fnl`

**Interfaces:**
- Consumes: `Runtime.activity-object-drag-mode() -> :move|:grab|nil`
- Consumes: `bt.Point2PointConstraint` and `Physics:addConstraint/removeConstraint`
- Produces: `PhysicsPointGrab.local-pivot-from-hit(body, hitPoint: glm.vec3) -> bt.Vector3`
- Produces: `PhysicsPointGrab.create(opts: {physics, body, hit-point, tau?, damping?, impulse-clamp?}) -> session`
- Produces: `session:update-target(worldPoint: glm.vec3) -> true`
- Produces: `session:destroy() -> true`
- Produces: `session:active?() -> boolean`

- [ ] **Step 1: Write failing Grab tests**

  Replace force/anchor expectations in `test-layout-physics-bodies.fnl` with tests that assert local pivot calculation uses the body transform inverse, Grab creates one point-to-point constraint on drag start, drag update calls `setPivotB` with `update.hit`, drag end removes the constraint, Move still allows default direct placement, and Grab errors when `entry.body` is missing.

- [ ] **Step 2: Run focused tests to verify RED**

  ```bash
  make build
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-layout-physics-bodies:main
  ```

  Expected: FAIL because point grab integration is absent.

- [ ] **Step 3: Implement `physics-point-grab.fnl`**

  Create a factory module with `local-pivot-from-hit` and `create`. `create` asserts `physics`, `body`, `hit-point`, `addConstraint`, and `removeConstraint`; computes the local pivot; creates `bt.Point2PointConstraint`; sets conservative defaults `tau 0.3`, `damping 1.0`, `impulse-clamp 30.0` unless opts override them; adds the constraint; activates the body; and returns an idempotent session literal with `update-target`, `destroy`, and `active?`.

- [ ] **Step 4: Integrate with layout physics movables**

  In `layout-physics-bodies.fnl`, replace `drag-attachment-mode`, `relative-anchor`, and `apply-anchor-force!` with object-drag mode handling. On drag start in `:grab`, create `drag.point-grab`. On drag update in `:grab`, call `drag.point-grab:update-target update.hit` and return true. On drag end, always destroy `drag.point-grab` before clearing the session, then sync layout position/rotation from the body transform. In `:move`, return false from `on-drag-update` so the existing default target position path remains active.

- [ ] **Step 5: Run focused GREEN validation**

  ```bash
  make build
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-layout-physics-bodies:main
  ```

  Expected: PASS.

- [ ] **Step 6: Search for removed force/anchor paths**

  ```bash
  rg "apply-anchor-force|relative-anchor|drag-attachment|applyForceAtPosition" assets/lua/layout-physics-bodies.fnl assets/lua/state-runtime.fnl assets/lua/sandbox-activity-unit.fnl
  ```

  Expected: no production matches for the removed force/anchor drag path.

- [ ] **Step 7: Commit**

  ```bash
  git add assets/lua/physics-point-grab.fnl assets/lua/layout-physics-bodies.fnl assets/lua/tests/test-layout-physics-bodies.fnl
  git commit -m "feat(physics): grab objects with point constraints"
  ```

---

### Task 7: Documentation and Final Validation

**Files:**
- Modify: `docs/dev/notes/sandbox-interaction-toolbar.md`

**Interfaces:**
- Consumes: final behavior from Tasks 1-6.
- Produces: updated developer note documenting Fly, Walk, Move, Grab, no Alt-drag, state migration, object-drag provider, Walk controls, and Grab constraint lifetime.

- [ ] **Step 1: Update the developer note**

  Rewrite the mode/state/input sections of `docs/dev/notes/sandbox-interaction-toolbar.md` so they document only the canonical four-mode model. The old field names may appear only in the legacy migration subsection.

- [ ] **Step 2: Run documentation consistency search**

  ```bash
  rg "object-move-enabled|drag-attachment|camera-mode|Alt \+ left drag|Alt\+drag" docs/dev/notes/sandbox-interaction-toolbar.md docs/specs/2026-08-06-sandbox-interaction-modes-design.md
  ```

  Expected: old state keys appear only in historical context or migration text; no text claims Alt-drag moves objects.

- [ ] **Step 3: Run focused validation suites**

  ```bash
  make build
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-toolbar-state:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-toolbar-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-retention:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-activity:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-scene-drag:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-camera-controls:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-physics:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-layout-physics-bodies:main
  ```

  Expected: PASS.

- [ ] **Step 4: Run final broad validation**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: PASS.

- [ ] **Step 5: Commit docs and validation evidence**

  ```bash
  git add docs/dev/notes/sandbox-interaction-toolbar.md
  git commit -m "docs(ui): document sandbox interaction modes"
  ```

## Acceptance Criteria

- Sandbox has exactly one active interaction mode at a time.
- Toolbar presents Fly, Walk, Move, and Grab as explicit mutually-exclusive buttons.
- Existing sessions restore into the new `interaction-mode` model through documented migration.
- `Alt` + drag does not move objects.
- Object movement starts only in Move or Grab mode.
- Walk supports WASD, arrow-key yaw/pitch, Space jump, terrain grounding, and pitch limits.
- Fly keeps existing free camera behavior.
- Move keeps direct object movement behavior.
- Grab controls the clicked surface point with a Bullet point-to-point constraint-style mechanism.
- Required failures are explicit, not silent no-ops.
