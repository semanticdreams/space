# Remaining Presentation Test Failures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the 15 remaining Lua test failures without reintroducing app-global camera/control fallbacks.

**Architecture:** Terrain screen-rect picking will construct rays from explicit `view`/`projection`/`viewport` matrix options, and scene terrain callers will provide an explicit scene target when matrix options are absent. Stale tests will install presentation provider/control/camera stubs through `app.active-world-runtime.presentation`, with cleanup that restores globals even after assertions fail.

**Tech Stack:** Fennel/Lua, `glm`, existing `./build/space` Lua test runner, `make test`.

## Global Constraints

- Existing broader plan: `docs/plans/2026-07-27-activity-owned-presentation.md`.
- Core invariant: no production authoritative `app.camera`, `app.first-person-controls`, app-global containment, or shared `runtime.canvas-camera`.
- Missing camera/control data must fail loudly at call sites requiring it.
- Do not restore app-global fallbacks.
- Production changes are limited to terrain ray construction and explicit terrain ray targets.
- Stale tests must be migrated to presentation provider/control/camera stubs instead of `app.first-person-controls` / `app.camera` for the failing paths.
- All changed tests that mutate globals must restore them with pcall/finally-style cleanup.
- Out of scope: redesigning presentation ownership, adding compatibility fallbacks, changing non-failing legacy tests outside the named fixtures.

**Acceptance Criteria:**

- `tests.test-terrain-query` screen-rect target tests pass, including rebased runtime origin.
- `tests.test-demo-browser` scene screen-rect terrain target and heightfield target capture tests pass.
- `tests.test-selection` presentation-control/default-camera failures pass.
- `tests.test-scene-drag` hidden-canvas active pointer controls assertion passes.
- Targeted four-module validation passes, then full `make test` passes.

---

### Task 1: Terrain Screen-Rect Ray Construction

**Files:**
- Modify: `assets/lua/heightfield-terrain-query.fnl`
- Modify: `assets/lua/scene.fnl`
- Test: `assets/lua/tests/test-terrain-query.fnl`
- Test: `assets/lua/tests/test-demo-browser.fnl`

**Interfaces:**
- Consumes: `(app.screen-pos-ray pos opts) -> {:origin vec3 :direction vec3}`, requiring active provider or explicit target.
- Produces: `(HeightfieldTerrainQuery.screen-rect-target record start-pos end-pos opts) -> target|nil`, where `opts` may contain complete `:view`, `:projection`, `:viewport` matrix data, or explicit `:target` / `:pointer-target`.

- [ ] **Step 1: Confirm baseline terrain failure**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl ./build/space -m tests.test-terrain-query:main
  ```
  Expected before fix: failure through `heightfield-terrain-query.fnl:173` to `main.fnl:747`.

- [ ] **Step 2: Add private matrix ray helper in `heightfield-terrain-query.fnl`**

  Add a local helper equivalent to existing scene/canvas ray math:
  ```fennel
  (fn screen-pos-ray-from-matrices [pos view projection viewport]
    (local vp (viewport-utils.to-table viewport))
    (assert vp "screen-rect-target requires a viewport")
    (assert view "screen-rect-target requires a view matrix")
    (assert projection "screen-rect-target requires a projection matrix")
    (local sample-pos
      (or (viewport-utils.input-pos->viewport-pos pos vp app.engine)
          {:x (+ vp.x (/ vp.width 2))
           :y (+ vp.y (/ vp.height 2))}))
    (local px (or sample-pos.x vp.x))
    (local py (or sample-pos.y vp.y))
    (local inverted-y (- (+ vp.height vp.y) py))
    (local viewport-vec (viewport-utils.to-glm-vec4 vp))
    (local near (glm.unproject (glm.vec3 px inverted-y 0.0) view projection viewport-vec))
    (local far (glm.unproject (glm.vec3 px inverted-y 1.0) view projection viewport-vec))
    (local direction (glm.normalize (- far near)))
    (assert-finite-vec3 near "near")
    (assert-finite-vec3 far "far")
    (assert-finite-vec3 direction "direction")
    {:origin near :direction direction})
  ```
  If `assert-finite-vec3` is currently scoped inside another function, hoist a private finite-vector assertion helper so both code paths can use it.

- [ ] **Step 3: Update `screen-rect-target` branching**

  In `screen-rect-target`:
  - read only `options.view`, `options.projection`, and `options.viewport` for matrix-local ray construction;
  - if all three matrix options are present, call `screen-pos-ray-from-matrices` for both endpoints;
  - otherwise call `app.screen-pos-ray` with the provided `options` unchanged, relying on its provider/explicit-target assertion;
  - remove internal fallback reads from `app.scene`, `app.presentation-camera`, and `app.projection`.

- [ ] **Step 4: Pass explicit Scene target from `Scene:screen-rect-terrain-target`**

  In `scene.fnl`, copy `opts` before delegation:
  ```fennel
  (local ray-opts {})
  (each [k v (pairs (or opts {}))]
    (set (. ray-opts k) v))
  (when (and (not ray-opts.target)
             (not ray-opts.pointer-target)
             (or (not ray-opts.view)
                 (not ray-opts.projection)
                 (not ray-opts.viewport)))
    (set ray-opts.target self))
  ```
  Pass `ray-opts` to `TerrainQuery.screen-rect-target`. Do not mutate the caller's opts table.

- [ ] **Step 5: Validate terrain-focused fixes**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl ./build/space -m tests.test-terrain-query:main
  ```
  Expected: PASS.

---

### Task 2: Presentation Fixture Migration

**Files:**
- Modify: `assets/lua/tests/test-selection.fnl`
- Modify: `assets/lua/tests/test-scene-drag.fnl`
- Modify: `assets/lua/tests/test-demo-browser.fnl`

**Interfaces:**
- Consumes: `app.active-world-runtime.presentation:input-controls() -> controls|nil`.
- Consumes: `app.active-world-runtime.presentation:camera(opts) -> camera|nil`.
- Produces: migrated test fixtures that no longer rely on `app.first-person-controls` or `app.camera` for the failing paths.

- [ ] **Step 1: Add or inline presentation-provider fixture helpers**

  In each touched test file, add or inline a helper with this behavior:
  ```fennel
  (fn install-presentation-fixture [controls camera]
    (local original-runtime app.active-world-runtime)
    (set app.active-world-runtime
         {:presentation {:input-controls (fn [_self] controls)
                         :camera (fn [_self _opts] camera)}})
    (fn []
      (set app.active-world-runtime original-runtime)))
  ```
  If a test does not need a camera, pass `nil`; if it does not need controls, pass `nil`. Always call the restore function during cleanup after `pcall`.

- [ ] **Step 2: Migrate `test-selection` input-control fixtures**

  In `selection-input-prefers-selection-only-for-primary-button` and `selection-input-ignores-disabled-pointer-target`:
  - keep the existing `fp` spy objects;
  - expose `fp` through the presentation fixture's `input-controls`;
  - stop depending on `app.first-person-controls` for these assertions;
  - restore runtime, selector, clickables, movables, resizables, and pointer-target hooks in cleanup before assertions report success/failure.

- [ ] **Step 3: Migrate `test-selection` default projection fixture**

  In `graph-selects-with-default-projection`:
  - create the `Camera` as before;
  - expose it through presentation `camera`;
  - keep `app.projection` explicit;
  - restore runtime/projection/viewport and drop the camera in pcall cleanup.

- [ ] **Step 4: Migrate `test-scene-drag` hidden-canvas fixture**

  In `drag-through-normal-state-moves-scene-entity-when-canvas-hidden`:
  - expose `controls` through presentation `input-controls`;
  - expose `camera` through presentation `camera`;
  - update the assertion to compare `app.active-pointer-controls` directly with `controls`, not `app.first-person-controls`.

- [ ] **Step 5: Migrate `test-demo-browser` terrain state fixtures**

  In terrain paint/rect-pick state tests around the existing `app.first-person-controls` spies:
  - replace `app.first-person-controls` mutation with provider-returned control stubs;
  - preserve wheel spy behavior by setting `forwarded-wheel` inside the provider control's `on-mouse-wheel`;
  - restore `app.active-world-runtime` in cleanup alongside existing app globals.

- [ ] **Step 6: Validate targeted fixture modules**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl ./build/space -m tests.test-selection:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl ./build/space -m tests.test-scene-drag:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl ./build/space -m tests.test-demo-browser:main
  ```
  Expected: all PASS.

---

### Task 3: Final Validation

**Files:**
- Test: `assets/lua/tests/test-terrain-query.fnl`
- Test: `assets/lua/tests/test-selection.fnl`
- Test: `assets/lua/tests/test-scene-drag.fnl`
- Test: `assets/lua/tests/test-demo-browser.fnl`

**Interfaces:**
- Consumes: Task 1 terrain ray behavior.
- Consumes: Task 2 presentation fixture stubs.
- Produces: evidence that the 15 remaining failures are resolved without fallback regressions.

- [ ] **Step 1: Run complete targeted module set**

  Run all four module commands:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl ./build/space -m tests.test-terrain-query:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl ./build/space -m tests.test-selection:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl ./build/space -m tests.test-scene-drag:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl ./build/space -m tests.test-demo-browser:main
  ```

- [ ] **Step 2: Run final full suite**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 3: Inspect for accidental fallback restoration**

  Confirm changed production code did not reintroduce `app.camera`, `app.first-person-controls`, implicit `app.scene` ray fallback, or shared `runtime.canvas-camera`.
