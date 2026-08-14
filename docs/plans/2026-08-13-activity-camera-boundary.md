# Activity Camera Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce an activity-owned camera and presentation boundary so built-in and dynamically generated activities cannot accidentally mutate or raycast through another activity's camera.

**Architecture:** Add a focused Fennel boundary module that centralizes activity ownership checks for Scene/Canvas slots, direct surface rays, presentation targets, and foreign-slot deactivation after activity switches. Then route Scene, Canvas, Activities, presentation, input-control selection, CanvasControls, and generated activity guidance through that boundary instead of retained-surface or app-global fallbacks.

**Tech Stack:** Space Fennel modules under `assets/lua`, existing Scene/Canvas activity slots, `Activities.register-activity`, runtime presentation provider, Space-native `tools.fennel-check`, constraints, focused Fennel tests, and the repo's full test suite.

## Global Constraints

- Activity-owned presentation only: an activity must explicitly create or restore camera/control state in its own slot/session before exposing a render target or receiving camera input.
- No retained-surface presentation fallback: retained `Scene` and `Canvas` surfaces may exist as containers, but `scene.camera` and `canvas.camera` are not active activity camera fallbacks.
- No global control fallback: `app.canvas-controls`, `app.active-pointer-controls`, and `runtime.canvas-controls` must not be authoritative camera input for an active activity when a presentation provider exists.
- Foreign slot mutation fails: public slot APIs must reject create/activate/camera/control/render-target mutation for an activity id other than the active or currently activating activity.
- Ambiguous direct rays fail: bare `canvas:screen-pos-ray`, `app.canvas:screen-pos-ray`, `scene:screen-pos-ray`, and `app.scene:screen-pos-ray` fail in active activity contexts unless explicit matrices or an explicitly authorized activity-owned target are supplied.
- Presentation target rays stay supported: `app.presentation-screen-pos-ray`, provider rays, slot pointer-target rays, and explicit-matrix rays continue to work.
- Dynamic activities use the same rules as built-ins; generated `bubbles` must own its activity slot/camera/controls and must not use bare `app.canvas:screen-pos-ray`.
- Do not add legacy aliases, compatibility shims, or silent fallbacks.
- Fennel validation must use Space-native `tools.fennel-check`, `make constraints`, and focused Fennel tests. Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- Run validation in order: compile check first, constraints second, focused tests third, broader suite when required.
- Run `make build` with timeout `14400000` before direct `./build/space` validation if `build/space` is missing or stale.
- Use `local` instead of `let`; use multi-branch `if` forms rather than nested `if` when practical; use factory functions rather than `.new` constructors.
- On Fennel delimiter/parse errors, inspect the nearest enclosing form and simplify into helper functions rather than guessing delimiters.

---

## File Structure

- Create `assets/lua/activity-surface-boundary.fnl` as the single policy module for activity owner resolution, slot mutation assertions, direct ray authorization, target ownership checks, and foreign-slot deactivation.
- Create `assets/lua/tests/test-activity-surface-boundary.fnl` for focused boundary tests, dynamic activity regressions, and generated guidance text checks.
- Modify `assets/lua/tests/fast.fnl` to register the new focused test module.
- Modify `assets/lua/canvas.fnl` and `assets/lua/scene.fnl` so slot APIs and direct ray APIs enforce the boundary while presentation target ray closures pass explicit authorized context.
- Modify `assets/lua/activities.fnl` so activation records the currently activating activity id and deactivates foreign slots after a successful switch.
- Modify `assets/lua/activity-presentation.fnl` so render target, default ray target, camera, and input-control resolution reject foreign/stale targets and never return retained surface controls in active activity contexts.
- Modify `assets/lua/main.fnl` so `sync-interaction-surface-state` stops selecting `app.canvas-controls` as active pointer controls when presentation input controls are available.
- Modify `assets/lua/canvas-controls.fnl` so controls require an explicit camera and pass explicit camera matrices into screen-ray math.
- Modify `assets/lua/home-world-canvas-runtime.fnl` to keep existing explicit camera call sites valid after `CanvasControls` requires explicit cameras, and to document that default bootstrap controls are not an active-activity fallback.
- Modify `assets/lua/tests/test-canvas-controls.fnl` and `assets/lua/tests/test-activity-presentation.fnl` for focused regressions around explicit cameras and presentation filtering.
- Modify `assets/lua/llm/presets/builtins/units.fnl` and `docs/dev/features/activities.md` to document the dynamic activity camera contract and remove generated-activity guidance that recommends bare surface rays.

---

### Task 1: Boundary Policy Module and Unit Tests

**Files:**
- Create: `assets/lua/activity-surface-boundary.fnl`
- Create: `assets/lua/tests/test-activity-surface-boundary.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: global `app`, `app.active-activity-id`, `app.activity-registry.active-activity-id`, `app.activity-registry.activating-activity-id`, `app.active-world-runtime.active-activity-id`, and `app.active-world-runtime.activating-activity-id`.
- Produces:
  - `(Boundary.active-owner-id) -> string|nil`
  - `(Boundary.activating-owner-id) -> string|nil`
  - `(Boundary.expected-owner-id) -> string|nil`
  - `(Boundary.assert-slot-owner! surface action requested-activity-id opts) -> true|error`
  - `(Boundary.authorized-ray-opts opts slot) -> table`
  - `(Boundary.assert-screen-ray-authorized! surface action opts active-slot) -> true|error`
  - `(Boundary.target-owned-by-active? target) -> boolean`
  - `(Boundary.deactivate-foreign-slots! surface active-activity-id) -> integer`

- [ ] **Step 1: Write failing boundary tests**

  In `assets/lua/tests/test-activity-surface-boundary.fnl`, create helper functions that snapshot and restore only `app.active-activity-id`, `app.activity-registry`, and `app.active-world-runtime`. Add tests that:

  - assert a matching owner can mutate a slot:
    ```fennel
    (Boundary.assert-slot-owner! :canvas "set-camera" "bubbles" {})
    ```
    with active owner `"bubbles"`.
  - assert a foreign mutation fails:
    ```fennel
    (Boundary.assert-slot-owner! :canvas "set-camera" "graph" {})
    ```
    with active owner `"bubbles"`; the error must contain `activity surface boundary denied`, `canvas`, `set-camera`, `graph`, and `bubbles`.
  - assert direct ray options with both `:view` and `:projection` are authorized.
  - assert empty direct ray options fail in an active context with an error containing `ambiguous direct screen ray` and `presentation target/helper`.
  - assert `{:activity-slot {:activity-id "bubbles"}}` authorizes a ray for active owner `"bubbles"`.
  - assert `deactivate-foreign-slots!` marks visible/interactable `"graph"` slot inactive while preserving active `"bubbles"` slot.

- [ ] **Step 2: Register the test module**

  Add `:tests.test-activity-surface-boundary` to `assets/lua/tests/fast.fnl` near other activity/presentation tests.

- [ ] **Step 3: Run the focused test and verify it fails before implementation**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-activity-surface-boundary.fnl --file assets/lua/tests/fast.fnl
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-surface-boundary:main
  ```

  Expected: FAIL because `activity-surface-boundary` does not exist or exported functions are missing.

- [ ] **Step 4: Implement `activity-surface-boundary.fnl`**

  Implement these exact exports:

  ```fennel
  {:active-owner-id active-owner-id
   :activating-owner-id activating-owner-id
   :expected-owner-id expected-owner-id
   :assert-slot-owner! assert-slot-owner!
   :authorized-ray-opts authorized-ray-opts
   :assert-screen-ray-authorized! assert-screen-ray-authorized!
   :target-owned-by-active? target-owned-by-active?
   :deactivate-foreign-slots! deactivate-foreign-slots!}
  ```

  Required behavior:

  - `activating-owner-id` returns the first non-empty string from `app.activity-registry.activating-activity-id`, then `app.active-world-runtime.activating-activity-id`.
  - `active-owner-id` returns the first non-empty string from `app.activity-registry.active-activity-id`, `app.active-world-runtime.active-activity-id`, then `app.active-activity-id`.
  - `expected-owner-id` returns activating owner first, otherwise active owner.
  - `assert-slot-owner!` allows when no expected owner exists, when `opts.boundary-internal?` is true, or when `requested-activity-id` equals expected owner. Otherwise it errors with a message containing `activity surface boundary denied`, `surface=...`, `action=...`, `requested=...`, `active=...`, and `activating=...`.
  - `authorized-ray-opts` returns a shallow copy of `opts` with `:activity-slot slot` filled in when `slot` is provided and `opts.activity-slot` is absent.
  - `assert-screen-ray-authorized!` allows when `opts.view` and `opts.projection` are both present. It also allows `opts.activity-slot.activity-id` or `opts.pointer-target.activity-slot.activity-id` when it matches `expected-owner-id`. It allows bootstrap context when no expected owner exists. Otherwise it errors with a message containing `ambiguous direct screen ray`, the surface/action, and `use a presentation target/helper, a slot pointer target, or explicit matrices`.
  - `target-owned-by-active?` returns true for non-scene/canvas targets with no slot, true for scene/canvas targets whose `target.slot.activity-id` matches `expected-owner-id`, true in bootstrap context, and false otherwise.
  - `deactivate-foreign-slots!` iterates `surface.activity-slots`, calls `surface:deactivate-activity-slot(activity-id, {:boundary-internal? true})` for visible or interactive slots whose activity id is not the active id, clears `surface.active-activity-slot` and `surface.active-activity-slot-id` if they point to a foreign slot, and returns the number of deactivated slots.

- [ ] **Step 5: Re-run Task 1 validation**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/activity-surface-boundary.fnl --file assets/lua/tests/test-activity-surface-boundary.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-surface-boundary:main
  ```

  Expected: PASS.

- [ ] **Step 6: Commit Task 1**

  ```bash
  git add assets/lua/activity-surface-boundary.fnl assets/lua/tests/test-activity-surface-boundary.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(lua): add activity surface boundary policy"
  ```

---

### Task 2: Scene and Canvas Slot/Ray Enforcement

**Files:**
- Modify: `assets/lua/canvas.fnl`
- Modify: `assets/lua/scene.fnl`
- Modify: `assets/lua/tests/test-activity-surface-boundary.fnl`

**Interfaces:**
- Consumes: `Boundary.assert-slot-owner!`, `Boundary.assert-screen-ray-authorized!`, `Boundary.authorized-ray-opts`, and `Boundary.target-owned-by-active?` from Task 1.
- Produces: Scene/Canvas public slot APIs enforce owner activity ids, and direct surface ray APIs fail loudly when ownership is ambiguous.

- [ ] **Step 1: Add failing Canvas and Scene integration tests**

  Extend `test-activity-surface-boundary.fnl` with helpers that create a `Camera`, `FocusManager`, `Canvas`, `Scene`, set positive `app.viewport`, call `:on-viewport-changed` on both surfaces, and drop created objects after the callback. Add tests that:

  - With active owner `"bubbles"`, `(canvas:ensure-activity-slot "graph" {:camera camera})` fails with boundary text.
  - With active owner `"bubbles"`, `(canvas:ensure-activity-slot "bubbles" {:camera camera})` succeeds.
  - With active owner `"bubbles"`, `(scene:ensure-activity-slot "sandbox" {:camera camera})` fails with boundary text.
  - With active owner `"bubbles"` and an exposed `"bubbles"` canvas slot, bare `(canvas:screen-pos-ray {:x 1 :y 1})` and `(scene:screen-pos-ray {:x 1 :y 1})` fail with `ambiguous direct screen ray`.
  - The canvas presentation target returned for the active `"bubbles"` slot still returns a ray from `(target:screen-pos-ray {:x 1 :y 1} {})`.

- [ ] **Step 2: Run focused tests and verify they fail before enforcement**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-activity-surface-boundary.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-surface-boundary:main
  ```

  Expected: FAIL because Scene/Canvas do not yet call the boundary.

- [ ] **Step 3: Wire Canvas through the boundary**

  In `assets/lua/canvas.fnl`:

  - Require `:activity-surface-boundary` as `Boundary`.
  - Add optional `opts` parameters to `activate-activity-slot`, `deactivate-activity-slot`, and `drop-activity-slot`.
  - Call `Boundary.assert-slot-owner!` in `ensure-activity-slot`, `activate-activity-slot`, `deactivate-activity-slot`, `drop-activity-slot`, and slot methods `set-camera`, `expose-render-target!`, and `clear-render-target!`.
  - In slot `screen-pos-ray`, pass `(Boundary.authorized-ray-opts opts slot)` to `self:screen-pos-ray`.
  - In `Canvas:screen-pos-ray`, call `Boundary.assert-screen-ray-authorized!` before resolving the view matrix.
  - In `presentation-target`, build the target and return it only if `Boundary.target-owned-by-active?` is true. The target's `screen-pos-ray` closure must include `:activity-slot slot`, `:view (slot.camera:get-view-matrix)`, and `:projection self.projection` before delegating.

- [ ] **Step 4: Wire Scene through the boundary**

  In `assets/lua/scene.fnl`, apply the same pattern as Canvas to public slot functions, slot mutator methods, pointer target ray helpers, `Scene:screen-pos-ray`, and `presentation-target`. Preserve existing Scene activation rollback behavior; add boundary checks at public entry points and direct slot mutators.

- [ ] **Step 5: Re-run Task 2 validation**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/canvas.fnl --file assets/lua/scene.fnl --file assets/lua/tests/test-activity-surface-boundary.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-surface-boundary:main
  ```

  Expected: PASS.

- [ ] **Step 6: Commit Task 2**

  ```bash
  git add assets/lua/canvas.fnl assets/lua/scene.fnl assets/lua/tests/test-activity-surface-boundary.fnl
  git commit -m "feat(lua): enforce activity-owned scene and canvas surfaces"
  ```

---

### Task 3: Activity Switch Cleanup and Presentation Filtering

**Files:**
- Modify: `assets/lua/activities.fnl`
- Modify: `assets/lua/activity-presentation.fnl`
- Modify: `assets/lua/main.fnl`
- Modify: `assets/lua/tests/test-activity-surface-boundary.fnl`
- Modify: `assets/lua/tests/test-activity-presentation.fnl`

**Interfaces:**
- Consumes: `Boundary.deactivate-foreign-slots!` and `Boundary.target-owned-by-active?` from Task 1.
- Produces: activity activation tracks the activating id, successful switches deactivate foreign slots, presentation provider filters foreign targets/controls, and main input state stops choosing retained canvas controls.

- [ ] **Step 1: Add failing activity switch cleanup tests**

  In `test-activity-surface-boundary.fnl`, add helpers for a minimal runtime with `canvas`, `scene`, `camera`, `activity-cameras`, `activity-controls`, and `presentation`. Add tests that:

  - Pre-activate `"graph"` canvas slot and `"sandbox"` scene slot using `{:boundary-internal? true}` setup.
  - Register dynamic `"bubbles"` with `Activities.register-activity`; its activation creates and activates a matching `"bubbles"` canvas slot with a camera and render target.
  - After `Activities.activate-activity "bubbles"`, assert graph/sandbox slots are not visible or interactive and bubbles slot remains visible/interactable.
  - Register another dynamic `"bubbles"` variant that attempts `(app.active-world-runtime.canvas:ensure-activity-slot "graph")` during activation; assert activation fails loudly with the boundary error.

- [ ] **Step 2: Add failing presentation/input tests**

  In `test-activity-presentation.fnl`, add coverage that:

  - provider `render-targets` excludes a target whose `slot.activity-id` does not match active activity;
  - provider `input-controls` returns active slot controls and never returns `runtime.canvas-controls` when an active canvas slot exists;
  - `app.sync-interaction-surface-state` does not assign `app.active-pointer-controls` from `app.canvas-controls` in an active activity context.

- [ ] **Step 3: Run focused tests and verify failure**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-activity-surface-boundary.fnl --file assets/lua/tests/test-activity-presentation.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-surface-boundary:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-presentation:main
  ```

  Expected: FAIL because activation lifecycle and presentation filtering do not yet enforce the boundary.

- [ ] **Step 4: Update `activities.fnl` activation lifecycle**

  - Add `activating-activity-id` to registry initialization.
  - Add local helpers `set-activating-activity!`, `clear-activating-activity!`, and `deactivate-foreign-surface-slots!`.
  - Set activating id immediately before calling the next activity's `activate` function.
  - Clear activating id on both success and failure.
  - After successful commit and `sync-app-active-activity! resolved-id`, call `deactivate-foreign-surface-slots! app.active-world-runtime resolved-id`.
  - Do not install any fallback when activation fails.

- [ ] **Step 5: Update `activity-presentation.fnl`**

  - Require `:activity-surface-boundary` as `Boundary`.
  - Filter `render-targets` through `Boundary.target-owned-by-active?` for scene/canvas targets.
  - `default-screen-ray-target` must return only active-owned scene/canvas presentation targets.
  - `input-controls` must return controls for active slot id only; when a slot is active and no matching controls exist, return nil instead of `runtime.canvas-controls`.

- [ ] **Step 6: Update `main.fnl` interaction controls**

  Update `sync-interaction-surface-state` so `app.active-pointer-controls` is assigned from `app.presentation-input-controls` only. Do not assign `app.canvas-controls` as active pointer controls in active presentation paths.

- [ ] **Step 7: Re-run Task 3 validation**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/activities.fnl --file assets/lua/activity-presentation.fnl --file assets/lua/main.fnl --file assets/lua/tests/test-activity-surface-boundary.fnl --file assets/lua/tests/test-activity-presentation.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-surface-boundary:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-presentation:main
  ```

  Expected: PASS.

- [ ] **Step 8: Commit Task 3**

  ```bash
  git add assets/lua/activities.fnl assets/lua/activity-presentation.fnl assets/lua/main.fnl assets/lua/tests/test-activity-surface-boundary.fnl assets/lua/tests/test-activity-presentation.fnl
  git commit -m "feat(lua): bind activity switches to owned presentation targets"
  ```

---

### Task 4: Remove Canvas Control Camera Fallbacks

**Files:**
- Modify: `assets/lua/canvas-controls.fnl`
- Modify: `assets/lua/home-world-canvas-runtime.fnl`
- Modify: `assets/lua/tests/test-canvas-controls.fnl`
- Modify: `assets/lua/tests/test-activity-surface-boundary.fnl`

**Interfaces:**
- Consumes: CanvasControls call sites provide explicit `:camera`; `Canvas:screen-pos-ray` allows explicit matrices.
- Produces: `CanvasControls(opts)` requires explicit `opts.camera` and passes explicit camera matrices into Canvas ray math.

- [ ] **Step 1: Add failing CanvasControls fallback tests**

  In `test-canvas-controls.fnl`, add a test that creates a canvas table with `camera`, calls `(CanvasControls {:canvas canvas})` without `:camera`, and asserts the constructor fails with `CanvasControls requires camera`.

  In `test-activity-surface-boundary.fnl`, add a regression where canvas controls for a dynamic `"bubbles"` slot pan or wheel-zoom the slot camera while a different retained `canvas.camera` remains unchanged.

- [ ] **Step 2: Run focused tests and verify failure**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-canvas-controls.fnl --file assets/lua/tests/test-activity-surface-boundary.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-canvas-controls:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-surface-boundary:main
  ```

  Expected: FAIL because CanvasControls still falls back to `canvas.camera`.

- [ ] **Step 3: Update `canvas-controls.fnl`**

  - Change constructor camera binding to require only `options.camera`; do not fall back to `canvas.camera`.
  - In `plane-hit-at`, pass explicit `:view (camera:get-view-matrix)` and `:projection projection` into `canvas:screen-pos-ray`.
  - Keep existing pointer-directed zoom and pan behavior unchanged.

- [ ] **Step 4: Verify constructor call sites**

  Confirm `home-world-canvas-runtime.fnl` still passes explicit cameras in both default bootstrap controls and `ensure-activity-canvas-controls!`. If needed, adjust comments to clarify the default controls are not an active-activity fallback.

- [ ] **Step 5: Re-run Task 4 validation**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/canvas-controls.fnl --file assets/lua/home-world-canvas-runtime.fnl --file assets/lua/tests/test-canvas-controls.fnl --file assets/lua/tests/test-activity-surface-boundary.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-canvas-controls:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-surface-boundary:main
  ```

  Expected: PASS.

- [ ] **Step 6: Commit Task 4**

  ```bash
  git add assets/lua/canvas-controls.fnl assets/lua/home-world-canvas-runtime.fnl assets/lua/tests/test-canvas-controls.fnl assets/lua/tests/test-activity-surface-boundary.fnl
  git commit -m "fix(lua): require explicit cameras for canvas controls"
  ```

---

### Task 5: Generated Activity Guidance and Developer Documentation

**Files:**
- Modify: `assets/lua/llm/presets/builtins/units.fnl`
- Modify: `docs/dev/features/activities.md`
- Modify: `assets/lua/tests/test-activity-surface-boundary.fnl`

**Interfaces:**
- Consumes: activity boundary behavior from Tasks 1-4.
- Produces: generated/user activity guidance forbids unsafe retained-surface camera/ray patterns and documents the explicit slot/presentation contract.

- [ ] **Step 1: Add failing guidance regression checks**

  In `test-activity-surface-boundary.fnl`, add a text regression that reads `assets/lua/llm/presets/builtins/units.fnl` and asserts:

  - it contains `bubbles`;
  - it contains `app.presentation-screen-pos-ray`;
  - it contains `own activity canvas slot` or `own canvas activity slot`;
  - it does not recommend `app.canvas:screen-pos-ray` except in text explicitly labeled unsafe or failing.

- [ ] **Step 2: Run focused test and verify failure**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-activity-surface-boundary.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-surface-boundary:main
  ```

  Expected: FAIL because generated unit guidance still recommends unsafe surface access or lacks explicit dynamic activity ownership instructions.

- [ ] **Step 3: Update generated unit guidance**

  In `assets/lua/llm/presets/builtins/units.fnl`, update the global app/activity guidance so it states:

  - dynamic activities must register through `Activities.register-activity`;
  - generated `bubbles` must create or obtain its own activity canvas slot using its own activity id;
  - generated activities must install their own camera/controls, expose their own render target, and use `app.presentation-screen-pos-ray`, provider rays, slot pointer targets, or explicit matrices;
  - bare `app.canvas:screen-pos-ray`, `app.scene:screen-pos-ray`, `canvas.camera`, `scene.camera`, and retained surface controls are unsafe and fail in active activity contexts.

- [ ] **Step 4: Update developer docs**

  In `docs/dev/features/activities.md`, add a section titled `Activity Camera Boundary` that documents:

  - no retained-surface camera fallback;
  - no global control fallback;
  - direct surface screen rays require explicit matrices or authorized slot/target context;
  - dynamic/generated activities, including `bubbles`, follow the same explicit slot/presentation pattern as built-ins.

- [ ] **Step 5: Re-run Task 5 validation**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/presets/builtins/units.fnl --file assets/lua/tests/test-activity-surface-boundary.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-surface-boundary:main
  rg "app\\.canvas:screen-pos-ray|app\\.scene:screen-pos-ray|canvas\\.camera|scene\\.camera" assets/lua/llm/presets/builtins/units.fnl docs/dev/features/activities.md
  ```

  Expected for `rg`: no unsafe recommendation text; historical mentions are allowed only when explicitly labeled unsafe/failing.

- [ ] **Step 6: Commit Task 5**

  ```bash
  git add assets/lua/llm/presets/builtins/units.fnl docs/dev/features/activities.md assets/lua/tests/test-activity-surface-boundary.fnl
  git commit -m "docs(lua): document dynamic activity camera ownership"
  ```

---

### Task 6: Final Integration Validation

**Files:**
- Validate all files changed in Tasks 1-5.

**Interfaces:**
- Consumes: all previous task outputs.
- Produces: final evidence that activity camera boundary behavior is integrated across compile, constraints, focused tests, fast suite, full local suite, and PR CI.

- [ ] **Step 1: Run runtime freshness and compile check**

  ```bash
  make build
  make fennel-check
  ```

- [ ] **Step 2: Run constraints**

  ```bash
  make constraints
  ```

- [ ] **Step 3: Run focused tests**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-surface-boundary:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-presentation:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-canvas-controls:main
  ```

- [ ] **Step 4: Run broader Fennel fast suite**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  ```

- [ ] **Step 5: Run final local suite**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 6: Route validation fixes through the review loop**

  If validation fails, capture the failing command, failing tests, relevant output,
  current branch state, and `git status --porcelain`. Invoke systematic debugging,
  route the repository fix through implementer and reviewer, commit the reviewed
  fix with a focused `fix(lua): ...` message, and restart Task 6 from Step 1.

- [ ] **Step 7: Final integration gate**

  Open the PR after local validation is green. Treat PR CI as the full integration gate before claiming ready-to-merge.
