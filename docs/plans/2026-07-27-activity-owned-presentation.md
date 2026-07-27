# Activity-Owned Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make activities the explicit owners of render targets, cameras, controls, scene services, and physics containment.

**Architecture:** Keep existing retained `Scene`, `Canvas`, and `Hud` surfaces, but introduce activity-owned presentation targets over their existing slots. Rendering, input, screen-ray helpers, audio listener updates, and containment management will query the active world runtime presentation provider instead of mutable app-level camera/control/containment globals.

**Tech Stack:** Fennel/Lua modules under `assets/lua`, existing Activities runtime, retained Scene/Canvas slots, BuildContext/LayoutRoot, Bullet physics bindings, renderer stack, Fennel test runner.

## Global Constraints

- Activities explicitly add/display what they own; no activity-id render toggles.
- Scene may stay in render path; if an activity hasn't added scene content, nothing should render.
- Camera is completely up to the activity: zero, one, or many cameras. No global active camera assumption.
- Eliminate global authoritative presentation state: `app.camera`, `app.first-person-controls`, `app.physics-containment-config`, `app.physics-containment-scene`, `app.__physics-global-containment`, shared `runtime.canvas-camera` as default canvas activity camera.
- Existing Scene/Canvas/HUD surfaces can remain retained surfaces/slots.
- The single global Bullet physics world may remain an engine service; containment bodies inside it must be activity/slot-owned.
- Missing camera/control data must fail loudly at the call site that requires it.
- Stale async/debounced containment callbacks must verify owner identity before mutating render or physics state.
- Out of scope: activity-id render toggles, removing the global engine physics world, building a generic compositor graph, and fixing bubbles-specific generated code bugs.

---

### Task 1: Scene Slot Presentation Targets

**Files:**
- Modify: `assets/lua/scene.fnl`
- Modify: `assets/lua/tests/test-scene-activity-slots.fnl`

**Interfaces:**
- Consumes: existing `Scene:ensure-activity-slot(activity-id) -> slot`, `Scene:activate-activity-slot(activity-id) -> slot`, `Camera`.
- Produces:
  - `(scene:ensure-activity-slot activity-id opts) -> slot`, where `opts` may include `:camera any` and `:controls any`.
  - `(slot:set-camera camera) -> slot`
  - `(slot:set-controls controls) -> slot`
  - `(slot:expose-render-target! opts) -> slot`, where `opts` may include `:layers table`.
  - `(slot:clear-render-target!) -> slot`
  - `(scene:presentation-target) -> target|nil`
  - Scene target shape: `{:kind :scene :surface scene :slot slot :camera camera :projection matrix :get-view-matrix fn :get-lighting-view-state fn :get-render-contexts fn :screen-pos-ray fn}`.

- [ ] **Step 1: Write failing Scene presentation tests**

Add these tests to `assets/lua/tests/test-scene-activity-slots.fnl`:

```fennel
(fn empty-scene-slot-exposes-no-presentation-target []
  (local fixture (make-scene))
  (local scene fixture.scene)
  (scene:ensure-activity-slot "drawing")
  (scene:activate-activity-slot "drawing")
  (assert (= (scene:presentation-target) nil)
          "An empty scene slot must not expose a render target")
  (drop-fixture fixture))

(fn scene-presentation-target-uses-slot-camera []
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local slot-camera-a (Camera {:position (glm.vec3 1 2 3)}))
  (local slot-camera-b (Camera {:position (glm.vec3 10 20 30)}))
  (local slot (scene:ensure-activity-slot "sandbox" {:camera slot-camera-a}))
  (scene:activate-activity-slot "sandbox")
  (slot:expose-render-target! {:layers [:geometry :text]})
  (local target-a (scene:presentation-target))
  (assert (= target-a.camera slot-camera-a)
          "Scene target must use the slot-owned camera")
  (slot:set-camera slot-camera-b)
  (local target-b (scene:presentation-target))
  (assert (= target-b.camera slot-camera-b)
          "Changing the slot camera must change the presentation target camera")
  (slot-camera-a:drop)
  (slot-camera-b:drop)
  (drop-fixture fixture))
```

Register both tests in the local `tests` table.

- [ ] **Step 2: Run the focused failing test**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-scene-activity-slots:main
```

Expected: FAIL because `Scene:presentation-target` and slot camera/render-target methods do not exist.

- [ ] **Step 3: Implement slot-owned Scene camera/control fields**

In `assets/lua/scene.fnl`, extend `make-activity-slot` / `ensure-activity-slot` so every slot owns `:camera`, `:controls`, and `:render-target-spec nil`. `ensure-activity-slot` must apply optional `opts.camera` and `opts.controls` only when supplied.

- [ ] **Step 4: Implement Scene slot render-target methods**

In `assets/lua/scene.fnl`, attach `set-camera`, `set-controls`, `expose-render-target!`, and `clear-render-target!` methods to Scene slots. `expose-render-target!` must assert that `slot.camera` is non-nil and must not create a camera implicitly.

- [ ] **Step 5: Implement `Scene:presentation-target`**

In `assets/lua/scene.fnl`, add `presentation-target` and export it on `self`. It must return nil unless the active slot is visible and has an explicit render-target spec. Returned target methods must use `slot.camera`, `slot.ctx`, and `scene.projection`.

- [ ] **Step 6: Keep empty Scene slots inert**

Update `Scene:get-view-matrix`, `Scene:get-lighting-view-state`, and `Scene:screen-pos-ray` so camera-dependent paths require an explicit target camera or active slot camera and fail loudly when absent. Do not fall back to `app.camera`.

- [ ] **Step 7: Run the focused Scene tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 8: Commit Task 1**

```bash
git add assets/lua/scene.fnl assets/lua/tests/test-scene-activity-slots.fnl
git commit -m "feat(lua): add scene slot presentation targets"
```

---

### Task 2: Canvas Slot-Owned Cameras and Canvas Presentation State

**Files:**
- Modify: `assets/lua/canvas.fnl`
- Modify: `assets/lua/tests/test-canvas-activity-slots.fnl`

**Interfaces:**
- Consumes: Scene target ownership pattern from Task 1.
- Produces:
  - `(canvas:ensure-activity-slot activity-id opts) -> slot`, where `opts` may include `:camera any`.
  - `(slot:set-camera camera) -> slot`
  - `(slot:expose-render-target! opts) -> slot`
  - `(slot:clear-render-target!) -> slot`
  - `(canvas:presentation-target) -> target|nil`
  - `(canvas:capture-activity-slot-state activity-id) -> {:camera table|nil :scale_factor number :panels table}`
  - `(canvas:restore-activity-slot-state activity-id state) -> true`.

- [ ] **Step 1: Write failing Canvas ownership tests**

Add these tests to `assets/lua/tests/test-canvas-activity-slots.fnl`:

```fennel
(fn empty-canvas-slot-exposes-no-presentation-target []
  (local fixture (make-canvas))
  (local canvas fixture.canvas)
  (canvas:ensure-activity-slot "graph")
  (canvas:activate-activity-slot "graph")
  (assert (= (canvas:presentation-target) nil)
          "An empty canvas slot must not expose a render target")
  (drop-fixture fixture))

(fn canvas-activity-slots-own-independent-cameras []
  (local fixture (make-canvas))
  (local canvas fixture.canvas)
  (local graph-camera (Camera {:position (glm.vec3 0 0 100)}))
  (local drawing-camera (Camera {:position (glm.vec3 25 0 100)}))
  (local graph-slot (canvas:ensure-activity-slot "graph" {:camera graph-camera}))
  (local drawing-slot (canvas:ensure-activity-slot "drawing" {:camera drawing-camera}))
  (canvas:activate-activity-slot "graph")
  (graph-slot:expose-render-target! {})
  (assert (= (canvas:presentation-target).camera graph-camera))
  (canvas:activate-activity-slot "drawing")
  (drawing-slot:expose-render-target! {})
  (assert (= (canvas:presentation-target).camera drawing-camera))
  (graph-camera:set-position (glm.vec3 77 0 100))
  (assert (= drawing-camera.position.x 25)
          "Updating graph camera must not move drawing camera")
  (graph-camera:drop)
  (drawing-camera:drop)
  (drop-fixture fixture))

(fn canvas-slot-state-captures-camera-per-activity []
  (local fixture (make-canvas))
  (local canvas fixture.canvas)
  (local graph-camera (Camera {:position (glm.vec3 11 22 33)}))
  (local slot (canvas:ensure-activity-slot "graph" {:camera graph-camera}))
  (canvas:activate-activity-slot "graph")
  (slot:expose-render-target! {})
  (local state (canvas:capture-activity-slot-state "graph"))
  (assert (= (. state.camera.position 1) 11))
  (assert (= (. state.camera.position 2) 22))
  (assert (= (. state.camera.position 3) 33))
  (graph-camera:drop)
  (drop-fixture fixture))
```

- [ ] **Step 2: Run the focused failing test**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-canvas-activity-slots:main
```

Expected: FAIL because Canvas slots still share `canvas.camera` and do not expose presentation targets.

- [ ] **Step 3: Implement slot-owned Canvas cameras**

In `assets/lua/canvas.fnl`, move render-time camera ownership to the active Canvas slot. Keep `Canvas` constructor compatibility for existing callers, but do not use the constructor camera as an implicit activity camera.

- [ ] **Step 4: Implement Canvas slot target methods**

Attach `set-camera`, `expose-render-target!`, and `clear-render-target!` to Canvas slots. `expose-render-target!` must assert that the slot owns a camera.

- [ ] **Step 5: Implement `Canvas:presentation-target`**

Return nil unless the active slot is visible and has an explicit render-target spec. The returned target must use `slot.camera`, `canvas.projection`, `slot.ctx`, and the Canvas screen-ray math.

- [ ] **Step 6: Implement Canvas slot state capture/restore**

Add `capture-activity-slot-state` and `restore-activity-slot-state` to capture/restore slot camera position/rotation, `scale_factor`, and slot panels. `Canvas:capture-state` may retain shell-level state but must no longer be the default activity camera state.

- [ ] **Step 7: Run the focused Canvas tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 8: Commit Task 2**

```bash
git add assets/lua/canvas.fnl assets/lua/tests/test-canvas-activity-slots.fnl
git commit -m "feat(lua): add canvas slot presentation targets"
```

---

### Task 3: Runtime Presentation Provider and Renderer Consumption

**Files:**
- Create: `assets/lua/activity-presentation.fnl`
- Create: `assets/lua/tests/test-activity-presentation.fnl`
- Modify: `assets/lua/renderers.fnl`
- Modify: `assets/lua/tests/test-renderers.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `(scene:presentation-target) -> target|nil`, `(canvas:presentation-target) -> target|nil`.
- Produces:
  - `(Presentation.for-runtime runtime) -> provider`
  - `(provider:render-targets) -> table`
  - `(provider:default-screen-ray-target opts) -> target|nil`
  - `(provider:screen-pos-ray pos opts) -> ray`
  - `(provider:input-controls) -> table|nil`
  - `(provider:audio-listener-camera) -> camera|nil`
  - `(provider:update delta) -> true`
  - Render target fields: `:kind`, `:surface`, `:slot`, `:camera`, `:projection`.

- [ ] **Step 1: Write failing provider tests**

Create `assets/lua/tests/test-activity-presentation.fnl`:

```fennel
(local tests [])
(local Presentation (require :activity-presentation))

(fn provider-returns-only-explicit-targets []
  (var scene-called? false)
  (var canvas-called? false)
  (local scene-target {:kind :scene})
  (local runtime
    {:scene {:presentation-target (fn [_self]
                                    (set scene-called? true)
                                    scene-target)}
     :canvas {:presentation-target (fn [_self]
                                     (set canvas-called? true)
                                     nil)}})
  (local provider (Presentation.for-runtime runtime))
  (local targets (provider:render-targets))
  (assert scene-called?)
  (assert canvas-called?)
  (assert (= (length targets) 1))
  (assert (= (. targets 1) scene-target)))

(fn provider-screen-ray-requires-target-camera []
  (local provider (Presentation.for-runtime {}))
  (local (ok err) (pcall (fn [] (provider:screen-pos-ray {:x 1 :y 2} {}))))
  (assert (not ok))
  (assert (string.find (tostring err) "screen ray target")
          "Missing screen-ray target must fail loudly"))

(table.insert tests {:name "Provider returns only explicit targets"
                     :fn provider-returns-only-explicit-targets})
(table.insert tests {:name "Provider screen ray requires target"
                     :fn provider-screen-ray-requires-target-camera})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "activity-presentation"
                       :tests tests})))

{:name "activity-presentation"
 :tests tests
 :main main}
```

- [ ] **Step 2: Write failing renderer test**

Add a renderer test in `assets/lua/tests/test-renderers.fnl` that installs `app.active-world-runtime.presentation` with one fake scene target and installs stale `app.scene` / `app.canvas` targets whose `get-view-matrix` methods error if used:

```fennel
(fn renderer-uses-presentation-targets-not-app-surfaces []
  (with-open-gl
    (fn [_mock]
      (with-renderers-constructor-deps
        (fn []
          (local Renderers (reload-renderers-module))
          (var presentation-target-drawn? false)
          (local target
            {:kind :scene
             :projection (glm.mat4 1)
             :get-view-matrix (fn [_self]
                                (set presentation-target-drawn? true)
                                (glm.mat4 1))
             :get-lighting-view-state (fn [_self]
                                         (LightingViewState.orthographic (glm.vec3 0 0 1)))
             :get-render-contexts (fn [_self] [])})
          (local saved-runtime app.active-world-runtime)
          (local saved-scene app.scene)
          (local saved-canvas app.canvas)
          (set app.scene {:projection (glm.mat4 1)
                          :get-view-matrix (fn [_self]
                                             (error "renderer read app.scene"))})
          (set app.canvas {:projection (glm.mat4 1)
                           :get-view-matrix (fn [_self]
                                              (error "renderer read app.canvas"))})
          (set app.active-world-runtime
               {:presentation {:render-targets (fn [_self] [target])}})
          ((Renderers):update)
          (assert presentation-target-drawn?
                  "Renderer must draw the runtime presentation target")
          (set app.active-world-runtime saved-runtime)
          (set app.scene saved-scene)
          (set app.canvas saved-canvas))))))
```

- [ ] **Step 3: Register the new test module**

Add `:tests.test-activity-presentation` to `assets/lua/tests/fast.fnl` near other activity/surface tests.

- [ ] **Step 4: Run focused failing tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-presentation:main
```

Then run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-renderers:main
```

Expected: FAIL because the provider module does not exist and renderers still draw `app.scene` / `app.canvas`.

- [ ] **Step 5: Implement `activity-presentation.fnl`**

Create `Presentation.for-runtime`. It must collect targets from runtime surfaces, preserve order `scene`, `canvas`, `hud`, and skip nil targets. It must choose default screen-ray targets from explicit `opts.target`, explicit `opts.surface`, then active interaction surface when available.

- [ ] **Step 6: Modify renderers to consume presentation targets**

In `assets/lua/renderers.fnl`, replace direct `app.scene` / `app.canvas` rendering with `app.active-world-runtime.presentation:render-targets()`. Render scene targets with skybox and two-pass geometry/text behavior; render canvas and HUD targets in returned order. Do not branch on activity id.

- [ ] **Step 7: Run focused provider and renderer tests**

Run both commands from Step 4.

Expected: PASS.

- [ ] **Step 8: Commit Task 3**

```bash
git add assets/lua/activity-presentation.fnl assets/lua/renderers.fnl assets/lua/tests/test-activity-presentation.fnl assets/lua/tests/test-renderers.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): render active presentation targets"
```

---

### Task 4: Presentation-Aware Input, Screen Rays, and Active Camera Helpers

**Files:**
- Modify: `assets/lua/main.fnl`
- Modify: `assets/lua/state-runtime.fnl`
- Modify: `assets/lua/fpc-state.fnl`
- Modify: `assets/lua/camera-state.fnl`
- Modify: `assets/lua/first-person-controls.fnl`
- Modify: `assets/lua/movables.fnl`
- Modify: `assets/lua/resizables.fnl`
- Modify: `assets/lua/object-selector.fnl`
- Modify: `assets/lua/heightfield-terrain-query.fnl`
- Modify: `assets/lua/graph-node-cube.fnl`
- Modify: `assets/lua/tests/test-activity-presentation.fnl`
- Modify: `assets/lua/tests/test-main-events.fnl`
- Modify: `assets/lua/tests/test-first-person-controls.fnl`
- Modify: `assets/lua/tests/test-screen-pos-ray.fnl`

**Interfaces:**
- Consumes: `provider:screen-pos-ray(pos, opts)`, `provider:input-controls()`, `provider:audio-listener-camera()`.
- Produces:
  - `(app.active-presentation) -> provider|nil`
  - `(app.presentation-screen-pos-ray pos opts) -> ray`
  - `(app.presentation-input-controls) -> controls|nil`
  - `(app.presentation-camera opts) -> camera|nil`.

- [ ] **Step 1: Write failing presentation input tests**

Extend `assets/lua/tests/test-activity-presentation.fnl` with:

```fennel
(fn app-screen-pos-ray-delegates-to-runtime-presentation []
  (local Main (require :main))
  (Main.install-app-shell!)
  (var called-pos nil)
  (local expected-ray {:origin :o :direction :d})
  (local saved-runtime app.active-world-runtime)
  (set app.active-world-runtime
       {:presentation {:screen-pos-ray (fn [_self pos _opts]
                                         (set called-pos pos)
                                         expected-ray)}})
  (local ray (app.screen-pos-ray {:x 4 :y 5} {}))
  (assert (= ray expected-ray))
  (assert (= called-pos.x 4))
  (set app.active-world-runtime saved-runtime))

(fn state-runtime-uses-presentation-controls []
  (local Runtime (require :state-runtime))
  (local controls {:on-mouse-wheel (fn [_self _payload] true)})
  (local saved-runtime app.active-world-runtime)
  (local saved-first-person app.first-person-controls)
  (local saved-active-pointer app.active-pointer-controls)
  (set app.first-person-controls nil)
  (set app.active-pointer-controls nil)
  (set app.active-world-runtime
       {:presentation {:input-controls (fn [_self] controls)}})
  (assert (= (Runtime.active-controls) controls))
  (set app.active-world-runtime saved-runtime)
  (set app.first-person-controls saved-first-person)
  (set app.active-pointer-controls saved-active-pointer))
```

- [ ] **Step 2: Run focused failing tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-presentation:main
```

Expected: FAIL because input and screen-ray helpers still use app-level camera/control globals.

- [ ] **Step 3: Add app presentation helper functions**

In `assets/lua/main.fnl`, add function helpers only; do not add app-level presentation state storage. `app.active-presentation` must read `app.active-world-runtime.presentation`.

- [ ] **Step 4: Replace `app.screen-pos-ray` fallback**

Update `app.screen-pos-ray` so it delegates to `app.active-presentation():screen-pos-ray(pos, opts)` and fails loudly if no provider/target exists. Remove fallback math that reads `app.camera`.

- [ ] **Step 5: Stop writing active camera/control globals during runtime binding**

In `bind-active-world-runtime`, remove assignments to `app.camera`, `app.first-person-controls`, and `app.active-pointer-controls` as presentation authority. Keep stable surface references `app.scene` and `app.canvas`.

- [ ] **Step 6: Move active controls lookup to presentation provider**

Update `assets/lua/state-runtime.fnl` and `assets/lua/fpc-state.fnl` so mouse wheel, hover eligibility, and FPC state dispatch use `(app.presentation-input-controls)`.

- [ ] **Step 7: Move camera-state reset and focus camera lookup to presentation provider**

Update `assets/lua/camera-state.fnl` and `assets/lua/state-runtime.fnl` to call `(app.presentation-camera {:required? true})` for camera reset and directional focus.

- [ ] **Step 8: Remove implicit camera fallbacks from interaction helpers**

Update `first-person-controls.fnl`, `movables.fnl`, `resizables.fnl`, `object-selector.fnl`, `heightfield-terrain-query.fnl`, and `graph-node-cube.fnl` to use explicit cameras from options, pointer targets, or presentation helper functions. `FirstPersonControls` must assert `options.camera`; it must not default to `app.camera`.

- [ ] **Step 9: Update focused tests for explicit cameras**

Update existing tests that construct `FirstPersonControls`, screen rays, movables, or selectors so they pass explicit cameras or install a fake presentation provider.

- [ ] **Step 10: Run focused input/screen-ray tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-presentation:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-first-person-controls:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-screen-pos-ray:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-main-events:main
```

Expected: PASS.

- [ ] **Step 11: Commit Task 4**

```bash
git add assets/lua/main.fnl assets/lua/state-runtime.fnl assets/lua/fpc-state.fnl assets/lua/camera-state.fnl assets/lua/first-person-controls.fnl assets/lua/movables.fnl assets/lua/resizables.fnl assets/lua/object-selector.fnl assets/lua/heightfield-terrain-query.fnl assets/lua/graph-node-cube.fnl assets/lua/tests/test-activity-presentation.fnl assets/lua/tests/test-main-events.fnl assets/lua/tests/test-first-person-controls.fnl assets/lua/tests/test-screen-pos-ray.fnl
git commit -m "feat(lua): route input through active presentation"
```

---

### Task 5: HomeWorld Activity-Owned Cameras and Built-In Activity Presentation

**Files:**
- Create: `assets/lua/activity-camera-state.fnl`
- Create: `assets/lua/tests/test-activity-camera-state.fnl`
- Modify: `assets/lua/home-world.fnl`
- Modify: `assets/lua/home-world-canvas-runtime.fnl`
- Modify: `assets/lua/sandbox-activity-unit.fnl`
- Modify: `assets/lua/graph-activity-unit.fnl`
- Modify: `assets/lua/drawing-activity-unit.fnl`
- Modify: `assets/lua/board-activity-unit.fnl`
- Modify: `assets/lua/drawing/render.fnl`
- Modify: `assets/lua/board/view.fnl`
- Modify: `assets/lua/tests/test-home-world-scene-activity-state.fnl`
- Modify: `assets/lua/tests/test-graph-activity-slots.fnl`
- Modify: `assets/lua/tests/test-drawing-activity-slots.fnl`
- Modify: `assets/lua/tests/test-board.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: Scene/Canvas slot target APIs, `Presentation.for-runtime`.
- Produces:
  - `(ActivityCameraState.camera-from-state state defaults) -> camera`
  - `(ActivityCameraState.capture-camera camera) -> table|nil`
  - `(ActivityCameraState.restore-camera! camera state) -> true`
  - `(HomeWorldCanvasRuntime.ensure-activity-canvas-camera! runtime activity-id defaults) -> camera`
  - Runtime field `runtime.presentation`, created with `Presentation.for-runtime(runtime)`.
  - Runtime tables `runtime.activity-cameras` and `runtime.activity-controls`, keyed by activity id and surface key.

- [ ] **Step 1: Write failing camera-state tests**

Create `assets/lua/tests/test-activity-camera-state.fnl`:

```fennel
(local tests [])
(local glm (require :glm))
(local ActivityCameraState (require :activity-camera-state))

(fn captures-and-restores-camera-state []
  (local camera (ActivityCameraState.camera-from-state
                  {:position [1 2 3]}
                  {:position (glm.vec3 0 0 100)}))
  (local captured (ActivityCameraState.capture-camera camera))
  (assert (= (. captured.position 1) 1))
  (assert (= (. captured.position 2) 2))
  (assert (= (. captured.position 3) 3))
  (ActivityCameraState.restore-camera! camera {:position [9 8 7]})
  (assert (= camera.position.x 9))
  (assert (= camera.position.y 8))
  (assert (= camera.position.z 7))
  (camera:drop))

(table.insert tests {:name "Activity camera state captures and restores"
                     :fn captures-and-restores-camera-state})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "activity-camera-state"
                       :tests tests})))

{:name "activity-camera-state"
 :tests tests
 :main main}
```

- [ ] **Step 2: Write failing built-in activity camera isolation tests**

Extend relevant activity tests with this intent:

```fennel
(fn graph-and-drawing-do-not-share-canvas-camera []
  (local runtime app.active-world-runtime)
  (app.set-active-activity "graph")
  (local graph-slot (runtime.canvas:activity-slot "graph"))
  (graph-slot.camera:set-position (glm.vec3 100 0 100))
  (app.set-active-activity "drawing")
  (local drawing-slot (runtime.canvas:activity-slot "drawing"))
  (assert (not (= drawing-slot.camera.position.x 100))
          "Drawing must not inherit Graph camera position"))

(fn sandbox-camera-does-not-populate-app-camera []
  (app.set-active-activity "sandbox")
  (assert (= app.camera nil)
          "Sandbox camera must be owned by the sandbox scene slot, not app.camera")
  (local runtime app.active-world-runtime)
  (local slot (runtime.scene:activity-slot "sandbox"))
  (assert slot.camera "Sandbox slot must own its camera"))
```

Place the first in `test-graph-activity-slots.fnl` or `test-drawing-activity-slots.fnl`; place the second in `test-home-world-scene-activity-state.fnl`.

- [ ] **Step 3: Register the new camera-state test module**

Add `:tests.test-activity-camera-state` to `assets/lua/tests/fast.fnl` near other activity tests.

- [ ] **Step 4: Run focused failing tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-camera-state:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-home-world-scene-activity-state:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

Expected: FAIL because HomeWorld still constructs `runtime.camera`, `runtime.first-person-controls`, and shared `runtime.canvas-camera`.

- [ ] **Step 5: Implement `activity-camera-state.fnl`**

Create a small helper around existing `Camera`, `MathUtils.vec3->array`, `MathUtils.quat->array`, `MathUtils.array->vec3`, and `MathUtils.array->quat`. It must sanitize invalid vectors using the supplied default position and never read app globals.

- [ ] **Step 6: Create runtime presentation provider in HomeWorld**

In `assets/lua/home-world.fnl`, require `activity-presentation` and set `runtime.presentation` with `Presentation.for-runtime(runtime)`. Remove `runtime.camera`, `runtime.first-person-controls`, `runtime.canvas-camera`, and `runtime.physics-containment-config` from runtime construction.

- [ ] **Step 7: Move Sandbox scene camera/control creation into Sandbox activation**

In `assets/lua/sandbox-activity-unit.fnl`, create or reuse the sandbox scene-slot camera and controls from sandbox session state. Call `slot:set-camera`, `slot:set-controls`, and `slot:expose-render-target!`. Persist camera state in `snapshot-sandbox-activity!` under `{:scene {:camera ...}}`.

- [ ] **Step 8: Move Canvas activity cameras into Canvas slots**

In `assets/lua/home-world-canvas-runtime.fnl`, implement `ensure-activity-canvas-camera!`. Graph, drawing, and board activation must call it, pass the resulting camera to `canvas:ensure-activity-slot`, and call `slot:expose-render-target!`.

- [ ] **Step 9: Pass slot cameras to activity views**

In `graph-activity-unit.fnl`, pass `:camera slot.camera` to `GraphView`. In `drawing-activity-unit.fnl` / `drawing/render.fnl`, use the drawing slot target or slot camera instead of `canvas.camera`. In `board-activity-unit.fnl` / `board/view.fnl`, use the board slot target or presentation screen rays instead of a shared canvas camera.

- [ ] **Step 10: Migrate persisted top-level camera state into activity sessions**

In `home-world.fnl`, migrate legacy `world.state.camera` into `activity.sessions.sandbox.scene.camera` and legacy `world.state.canvas.camera` into the active or default canvas activity session camera when no per-activity canvas camera exists. After normalization, runtime code must not read those top-level fields as active presentation fallback.

- [ ] **Step 11: Run focused activity tests**

Run commands from Step 4 plus:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-drawing-activity-slots:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-board:main
```

Expected: PASS.

- [ ] **Step 12: Commit Task 5**

```bash
git add assets/lua/activity-camera-state.fnl assets/lua/home-world.fnl assets/lua/home-world-canvas-runtime.fnl assets/lua/sandbox-activity-unit.fnl assets/lua/graph-activity-unit.fnl assets/lua/drawing-activity-unit.fnl assets/lua/board-activity-unit.fnl assets/lua/drawing/render.fnl assets/lua/board/view.fnl assets/lua/tests/test-activity-camera-state.fnl assets/lua/tests/test-home-world-scene-activity-state.fnl assets/lua/tests/test-graph-activity-slots.fnl assets/lua/tests/test-drawing-activity-slots.fnl assets/lua/tests/test-board.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): move activity cameras into presentation slots"
```

---

### Task 6: Activity-Owned Physics Containment Managers

**Files:**
- Modify: `assets/lua/physics-containment.fnl`
- Modify: `assets/lua/scene.fnl`
- Modify: `assets/lua/home-world.fnl`
- Modify: `assets/lua/theme-actions.fnl`
- Modify: `assets/lua/tests/test-physics-containment.fnl`
- Modify: `assets/lua/tests/test-scene-activity-slots.fnl`
- Modify: `assets/lua/tests/test-graph-activity-slots.fnl`

**Interfaces:**
- Consumes: Scene slot ownership from Task 1 and HomeWorld activity slot activation from Task 5.
- Produces:
  - `(PhysicsContainment.create-manager opts) -> manager`, where `opts` requires `:owner` and `:physics`.
  - `(manager:ensure-installed opts) -> boolean`
  - `(manager:refresh-visualization opts) -> boolean`
  - `(manager:schedule-refresh opts) -> true`
  - `(manager:clear) -> true`
  - `(manager:drop) -> true`
  - `(scene:active-containment-manager) -> manager|nil`
  - `(slot:ensure-containment-manager) -> manager`.

- [ ] **Step 1: Write failing manager ownership tests**

Extend `assets/lua/tests/test-physics-containment.fnl`:

```fennel
(fn containment-manager-requires-owner []
  (local (ok err)
    (pcall (fn []
             (PhysicsContainment.create-manager
               {:physics app.engine.physics}))))
  (assert (not ok))
  (assert (string.find (tostring err) "owner")
          "Containment manager must require an owner"))

(fn containment-managers-do-not-clear-each-other []
  (local owner-a {})
  (local owner-b {})
  (local manager-a (PhysicsContainment.create-manager
                     {:owner owner-a :physics app.engine.physics}))
  (local manager-b (PhysicsContainment.create-manager
                     {:owner owner-b :physics app.engine.physics}))
  (assert (manager-a:ensure-installed
            {:config {:mode "manual-bounds"
                      :bounds {:min [-10 -10 -10] :max [10 10 10]}}}))
  (assert (manager-b:ensure-installed
            {:config {:mode "manual-bounds"
                      :bounds {:min [-20 -20 -20] :max [20 20 20]}}}))
  (manager-a:clear)
  (assert manager-b.installation
          "Clearing manager A must not drop manager B installation")
  (manager-a:drop)
  (manager-b:drop))
```

Extend `assets/lua/tests/test-scene-activity-slots.fnl`:

```fennel
(fn stale-containment-refresh-does-not-install-into-new-active-slot []
  (local fixture (make-scene))
  (local scene fixture.scene)
  (local sandbox (scene:ensure-activity-slot "sandbox"))
  (local drawing (scene:ensure-activity-slot "drawing"))
  (scene:activate-activity-slot "sandbox")
  (local sandbox-manager (sandbox:ensure-containment-manager))
  (sandbox-manager:schedule-refresh {:scene scene
                                      :config {:debounce-ms 1000
                                               :mode "manual-bounds"
                                               :bounds {:min [-10 -10 -10]
                                                        :max [10 10 10]}}})
  (scene:activate-activity-slot "drawing")
  (app.engine.events.updated:emit 1000)
  (assert (= drawing.physics-containment-manager nil)
          "Sandbox refresh must not install containment into drawing slot")
  (drop-fixture fixture))
```

- [ ] **Step 2: Run focused failing tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-physics-containment:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-scene-activity-slots:main
```

Expected: FAIL because containment state is app-global.

- [ ] **Step 3: Implement containment manager instances**

Refactor `assets/lua/physics-containment.fnl` so installed planes, visualization, debouncer, scene, and config are fields on a manager object. Module-level normalization and bounds helpers stay pure module functions.

- [ ] **Step 4: Scope debounced refresh to owner identity**

`manager:schedule-refresh` must capture `manager.owner` in the debounced payload and must no-op if the manager was dropped or its owner no longer matches before installation.

- [ ] **Step 5: Attach containment managers to Scene slots**

In `assets/lua/scene.fnl`, add `slot:ensure-containment-manager`. Scene service application must install containment through the active slot manager. `drop-activity-slot` must call `manager:drop`.

- [ ] **Step 6: Update terrain-change scheduling**

In `home-world.fnl`, replace global `PhysicsContainment.schedule-refresh` calls with `scene:active-containment-manager():schedule-refresh(...)` when an active slot owns containment. If no manager exists, terrain changes must not install containment.

- [ ] **Step 7: Update theme-actions containment refresh**

In `theme-actions.fnl`, refresh visualization through the active Scene slot manager, not `app.physics-containment-scene`.

- [ ] **Step 8: Remove app-global containment fields from tests and code paths**

Update assertions in tests from `app.__physics-global-containment` to manager installation fields. Do not keep compatibility reads for `app.physics-containment-config` or `app.physics-containment-scene`.

- [ ] **Step 9: Run focused containment tests**

Run the commands from Step 2 plus:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

Expected: PASS.

- [ ] **Step 10: Commit Task 6**

```bash
git add assets/lua/physics-containment.fnl assets/lua/scene.fnl assets/lua/home-world.fnl assets/lua/theme-actions.fnl assets/lua/tests/test-physics-containment.fnl assets/lua/tests/test-scene-activity-slots.fnl assets/lua/tests/test-graph-activity-slots.fnl
git commit -m "feat(lua): scope physics containment to activity slots"
```

---

### Task 7: Scene Service State Ownership Cleanup

**Files:**
- Modify: `assets/lua/scene.fnl`
- Modify: `assets/lua/activity-scene-state.fnl`
- Modify: `assets/lua/sandbox-activity-unit.fnl`
- Modify: `assets/lua/drawing-activity-unit.fnl`
- Modify: `assets/lua/board-activity-unit.fnl`
- Modify: `assets/lua/graph-activity-unit.fnl`
- Modify: `assets/lua/tests/test-scene-activity-slots.fnl`
- Modify: `assets/lua/tests/test-home-world-scene-activity-state.fnl`

**Interfaces:**
- Consumes: slot containment manager API from Task 6.
- Produces:
  - `(scene:capture-active-service-state) -> state`
  - `(scene:apply-slot-service-state slot state) -> true`
  - `(scene:reset-services-to-empty) -> true`
  - Empty Scene slot service state: disabled lights, disabled skybox, neutral background, disabled containment.

- [ ] **Step 1: Write failing service leakage tests**

Add to `assets/lua/tests/test-scene-activity-slots.fnl`:

```fennel
(fn empty-scene-slot-applies-empty-services-without-render-target []
  (with-restored-app-fields
    [:lights :renderers]
    (fn []
      (local fixture (make-scene))
      (local scene fixture.scene)
      (var lights-state nil)
      (var background-state nil)
      (set app.lights {:set-state (fn [_self state] (set lights-state state))
                       :get-state (fn [_self] lights-state)})
      (set app.renderers {:set-background-state (fn [_self state]
                                                  (set background-state state))
                          :get-background-state (fn [_self] background-state)
                          :skybox {:set-state (fn [_self _state])
                                   :get-state (fn [_self] nil)}})
      (scene:ensure-activity-slot "sandbox")
      (scene:activate-activity-slot "sandbox")
      (local empty-slot (scene:ensure-activity-slot "drawing"))
      (scene:activate-activity-slot "drawing")
      (assert (= (scene:presentation-target) nil)
              "Empty drawing scene slot must not render")
      (assert empty-slot.scene-state
              "Empty slot must own explicit empty service state")
      (drop-fixture fixture))))
```

- [ ] **Step 2: Run focused failing tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-scene-activity-slots:main
```

Expected: FAIL where service state or containment still relies on app-global storage or manual activity cleanup.

- [ ] **Step 3: Normalize service state in `activity-scene-state.fnl`**

Ensure `empty-state` includes explicit disabled lights, disabled skybox, neutral background, and disabled containment. Include camera state only when supplied by an owning activity; empty state must not create a camera.

- [ ] **Step 4: Refactor Scene service capture/apply around slots**

Replace `apply-state-to-services` with `apply-slot-service-state`. It may write to engine service objects (`app.lights`, renderer skybox/background) as side effects, but the authoritative state must be `slot.scene-state`.

- [ ] **Step 5: Remove manual Sandbox global cleanup**

In `sandbox-activity-unit.fnl`, remove direct clearing of `app.lights`, renderer skybox/background, and global containment. Deactivation should only deactivate the sandbox Scene slot; Scene slot activation/reset owns service cleanup.

- [ ] **Step 6: Keep non-scene activities explicit but inert**

Graph, drawing, and board activation may continue to ensure/activate empty Scene slots, but must not expose Scene render targets or create Scene cameras unless they intentionally add scene content.

- [ ] **Step 7: Run focused service tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-scene-activity-slots:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-home-world-scene-activity-state:main
```

Expected: PASS.

- [ ] **Step 8: Commit Task 7**

```bash
git add assets/lua/scene.fnl assets/lua/activity-scene-state.fnl assets/lua/sandbox-activity-unit.fnl assets/lua/drawing-activity-unit.fnl assets/lua/board-activity-unit.fnl assets/lua/graph-activity-unit.fnl assets/lua/tests/test-scene-activity-slots.fnl assets/lua/tests/test-home-world-scene-activity-state.fnl
git commit -m "feat(lua): keep scene services activity owned"
```

---

### Task 8: Documentation, Acceptance Checks, and Final Validation

**Files:**
- Modify: `docs/dev/features/activities.md`

**Interfaces:**
- Consumes: all APIs introduced in Tasks 1-7.
- Produces: documented activity-owned presentation invariants and validation evidence.

- [ ] **Step 1: Update developer documentation**

In `docs/dev/features/activities.md`, add a section named `## Activity-Owned Presentation` after the Surface Host section. Include these exact points in prose:
- Activities expose render targets explicitly through Scene/Canvas/HUD slots.
- Scene and Canvas slots own cameras; no activity receives a default app camera.
- Renderers consume `runtime.presentation:render-targets()`.
- Input, screen rays, and audio listener camera lookup use the active presentation provider.
- Physics containment managers are owned by activity Scene slots.
- Empty Scene slots are inert and expose no render target.

- [ ] **Step 2: Run focused task-level tests**

Run all focused modules touched by this plan:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-presentation:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-camera-state:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-scene-activity-slots:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-canvas-activity-slots:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-physics-containment:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-renderers:main
```

Expected: PASS.

- [ ] **Step 3: Run complete relevant suite**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
```

Expected: PASS.

- [ ] **Step 4: Run broader final checks justified by render/input/physics risk**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: PASS.

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-integration
```

Expected: PASS.

- [ ] **Step 5: Run source-level invariant checks**

Run:

```bash
rg -n "app\.(camera|first-person-controls|physics-containment-config|physics-containment-scene)|__physics-global-containment|runtime\.canvas-camera" assets/lua --glob "*.fnl" --glob "!tests/**"
```

Expected: no matches.

Run:

```bash
rg -n "app\.scene|app\.canvas" assets/lua/renderers.fnl
```

Expected: no matches for implicit Scene/Canvas rendering.

Run:

```bash
rg -n "active-activity-id|activity-id" assets/lua/renderers.fnl
```

Expected: no matches.

- [ ] **Step 6: Verify observable acceptance criteria**

Confirm from tests and grep output:
- Switching activities does not carry camera transforms across activities.
- Canvas activities have independent camera state.
- Empty Scene slots expose no Scene render target/service state beyond explicit empty defaults.
- Containment installed by one activity is not visible or active in another.
- Debounced containment refresh after activity switch cannot install into the wrong owner.
- Renderers consume presentation targets rather than `app.scene` / `app.canvas`.
- User/external activity code can create an activity-owned Canvas camera/render target through the public slot APIs.

- [ ] **Step 7: Commit Task 8**

```bash
git add docs/dev/features/activities.md
git commit -m "docs: document activity-owned presentation"
```
