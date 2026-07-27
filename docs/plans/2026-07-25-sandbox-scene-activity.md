# Sandbox Scene Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add retained per-activity Scene slots and make the new Sandbox activity the sole owner of the former default 3D workspace.

**Architecture:** Keep `Scene` as the retained 3D capability surface, but give each activity an isolated retained Scene slot. The active slot alone supplies render data, pointer targets, physics participation, lights, skybox, and background. Canonical scene state moves into activity sessions; load-time normalization migrates legacy state into Sandbox without runtime compatibility reads.

**Tech Stack:** Fennel/Lua modules under `assets/lua`, existing Activities and Canvas activity-slot patterns, BuildContext/LayoutRoot, Bullet bindings, renderer skybox/background services, Fennel test runner.

## Global Constraints

- `Scene` remains the retained 3D capability provider for the active HomeWorld.
- `Scene` must not own universal terrain, panels, lights, physics objects, environment settings, or scene actions.
- Each activity has at most one retained Scene slot, following the Canvas activity-slot pattern.
- Only the active slot contributes render data, picking targets, scene interaction, physics simulation, lights, skybox, or background.
- Inactive slots remain retained; ordinary activity switching must not drop/recreate them.
- Add activity id `sandbox`, label `Sandbox`, icon `toys`, and a Scene preferred interaction surface.
- Sandbox is the default activity for a new HomeWorld.
- Graph, Drawing, and Board activate empty Scene slots and must not inherit Sandbox state.
- The single Bullet world, `app.lights`, renderer skybox, and renderer background are engine services whose effective state is reset then supplied by the active slot only.
- Canonical activity-owned scene state is under `activity.sessions.<activity-id>.scene`.
- Legacy top-level `scene.*` and `physics.containment` are migrated once at load, removed from the canonical state, and never read as runtime fallback.
- Missing required slot/session bindings and duplicate/unknown slot activation fail loudly.
- Do not add a generic multi-slot compositor, multiple simultaneous active slots, Sandbox-content sharing, or compatibility aliases.

---

## File Structure Map

- Create `assets/lua/activity-scene-state.fnl`: canonical Scene-session shape, default/empty state factories, validation, and legacy migration.
- Create `assets/lua/sandbox-activity-unit.fnl`: registration and retained lifecycle for the Sandbox activity.
- Create `assets/lua/sandbox-activity-actions.fnl`: Sandbox-only scene root actions.
- Create `assets/lua/tests/test-scene-activity-slots.fnl`: isolated render/input/retention/environment tests.
- Create `assets/lua/tests/test-sandbox-activity.fnl`: Sandbox registration, default activity, and action/hydration tests.
- Create `assets/lua/tests/test-home-world-scene-activity-state.fnl`: canonical-state migration and persistence tests.
- Modify `assets/lua/scene.fnl`: Scene slot registry, active-slot rendering/input bridge, activity-scoped content operations, and state capture/restore.
- Modify `assets/lua/layout-physics-bodies.fnl` and `assets/lua/physics-containment.fnl`: activate/deactivate retained bodies and clear/apply active containment.
- Modify `assets/lua/home-world.fnl`: state normalization, runtime construction, capture, and removal of global default-scene hydration.
- Modify `assets/lua/main.fnl`: built-in activity-unit registration and active-scene-slot pointer routing.
- Modify `assets/lua/root-context-menu-actions.fnl`: delegate former default scene actions to the active Sandbox contribution.
- Modify `assets/lua/graph-activity-unit.fnl`, `assets/lua/drawing-activity-unit.fnl`, and `assets/lua/board-activity-unit.fnl`: ensure/activate empty Scene slots.
- Modify `assets/lua/graph/world-data.fnl` and relevant `assets/lua/graph/nodes/scene-*.fnl`: read canonical Sandbox session state rather than legacy top-level scene state.
- Modify focused existing tests and `assets/lua/tests/fast.fnl`; update `docs/dev/features/activities.md` after implementation.

Use this test environment for focused Fennel tests throughout:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m
```

### Task 1: Add isolated retained Scene slots

**Files:**
- Create: `assets/lua/tests/test-scene-activity-slots.fnl`
- Modify: `assets/lua/scene.fnl` (`Scene` constructor; render-accessor methods; exports)
- Modify: `assets/lua/main.fnl` (`app.pointer-target-enabled?`)
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: existing Canvas `ensure-activity-slot` / `activate-activity-slot` pattern and `BuildContext`.
- Produces:
  ```fennel
  (scene:ensure-activity-slot activity-id) ; -> slot
  (scene:activity-slot activity-id)        ; -> slot|nil
  (scene:activate-activity-slot activity-id) ; -> slot
  (scene:deactivate-activity-slot activity-id) ; -> slot|nil
  (scene:drop-activity-slot activity-id)   ; -> true
  ```
  Each slot has `:activity-id`, `:ctx`, `:layout-root`, `:pointer-target`, `:root`, `:entity`, `:visible?`, `:interactive?`, `:activate`, `:deactivate`, and `:drop`.

- [ ] **Step 1: Write failing Scene-slot tests**

  Create `test-scene-activity-slots.fnl` using the existing Scene test fixture conventions. Add tests that:
  - `ensure-activity-slot "sandbox"` returns the same slot on repeat calls, while `"graph"` returns a different slot;
  - each slot has a build context and layout root distinct from the Scene surface's empty context/root;
  - activating Sandbox makes only its context visible through all Scene draw-source accessors; activating Graph hides Sandbox without dropping its root;
  - a slot pointer target is accepted by `app.pointer-target-enabled?` only while that exact slot is active and interactive;
  - `drop-activity-slot` drops the slot root and removes it from the registry.

  Use an explicit retained-root assertion:
  ```fennel
  (set sandbox-slot.root {:drop (fn [_] (set dropped? true))})
  (scene:activate-activity-slot "graph")
  (assert (not dropped?))
  ```

- [ ] **Step 2: Run the new test to confirm it fails**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-scene-activity-slots:main
  ```
  Expected: FAIL because `Scene` has no `ensure-activity-slot` method.

- [ ] **Step 3: Implement the Scene slot registry**

  In `scene.fnl`, add surface fields `:activity-slots {}`, `:active-activity-slot-id nil`, and `:active-activity-slot nil`. Keep the existing Scene build context as an empty fallback source, not an activity-content owner.

  Implement a slot factory that constructs a slot-local `LayoutRoot`, focus scope, and `BuildContext`. Its pointer target must include:
  ```fennel
  {:interaction-surface :scene
   :activity-slot slot
   :screen-pos-ray (fn [pos opts] (scene:screen-pos-ray pos opts))}
  ```
  `activate-activity-slot` deactivates the old slot without dropping it, activates the target, and updates both active-slot fields. `deactivate-activity-slot` clears active fields only when deactivating the active slot. Unknown ids are created only by `ensure-activity-slot`; `activity-slot` does not create one.

- [ ] **Step 4: Bind render sources and pointer routing to the active slot**

  Add a private active-render-context helper. Every `Scene` draw-source method used by `renderers.fnl` (`get-triangle-vector`, triangle batches, lines, points, images, quads, text, meshes, and instanced meshes) must read the active visible slot context. With no active slot, it returns the empty surface context so stale activity vectors cannot render.

  In `main.fnl`, extend `app.pointer-target-enabled?` with:
  ```fennel
  (local slot (and target target.activity-slot))
  (local scene-slot-enabled?
    (or (not slot)
        (and (= target.interaction-surface :scene)
             app.scene
             (= app.scene.active-activity-slot slot)
             (= slot.interactive? true))))
  ```
  Require `scene-slot-enabled?` for scene pointer targets while retaining existing Canvas routing behavior.

- [ ] **Step 5: Export methods, register the module, and verify pass**

  Export the five slot methods from `Scene`; add `tests.test-scene-activity-slots` to `tests/fast.fnl`; then rerun the command from Step 2.

  Expected: PASS; inactive slot draw vectors and pointer targets are unavailable.

- [ ] **Step 6: Commit the isolated slot foundation**

  ```bash
  git add assets/lua/scene.fnl assets/lua/main.fnl assets/lua/tests/test-scene-activity-slots.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(lua): add retained scene activity slots"
  ```

### Task 2: Make scene content, environment, and physics slot-owned

**Files:**
- Create: `assets/lua/activity-scene-state.fnl`
- Modify: `assets/lua/scene.fnl` (content mutators; capture/restore; lights/skybox/background)
- Modify: `assets/lua/layout-physics-bodies.fnl`
- Modify: `assets/lua/physics-containment.fnl`
- Modify: `assets/lua/tests/test-scene-activity-slots.fnl`

**Interfaces:**
- Consumes: Task 1 Scene slot API; existing light, terrain, skybox, background, and containment normalizers.
- Produces:
  ```fennel
  (ActivitySceneState.empty-state)            ; -> complete empty scene state
  (ActivitySceneState.default-sandbox-state)  ; -> current first-run scene state
  (ActivitySceneState.normalize-state state path) ; -> canonical state
  (scene:capture-activity-slot-state id)      ; -> state
  (scene:restore-activity-slot-state id state) ; -> true
  (LayoutPhysicsBodies.activate entity)
  (LayoutPhysicsBodies.deactivate entity)
  ```
  Canonical state has `:panels`, `:terrains`, `:lights`, `:skybox`, `:background`, and `:containment`.

- [ ] **Step 1: Write failing environment and physics-isolation tests**

  Extend `test-scene-activity-slots.fnl`. Restore a Sandbox slot with a non-default background, enabled skybox, enabled ambient light, a terrain record, and enabled containment; restore Graph with `(ActivitySceneState.empty-state)`.

  Assert that Sandbox activation applies its values to `app.lights`, renderer skybox/background, and containment; then Graph activation leaves an empty terrain/panel capture, disabled ambient light, disabled skybox, neutral background, and no active containment. Also assert switching back to Sandbox preserves its stored values.

- [ ] **Step 2: Run the focused test to confirm failure**

  Run the Task 1 test command. Expected: FAIL because activity scene state and slot state restore APIs do not exist.

- [ ] **Step 3: Define canonical scene-state factories and validation**

  Create `activity-scene-state.fnl`. `empty-state` returns no panels/terrains, a disabled normalized light state, disabled skybox, neutral normalized background, and disabled containment. `default-sandbox-state` uses the existing default terrain records, light state, skybox, background, and containment defaults.

  `normalize-state` must assert each required key exists and delegate to existing subsystem normalizers. It must return a cloned canonical table so slots never share mutable persisted state. Do not read HomeWorld state or legacy keys in this module.

- [ ] **Step 4: Add suspend/resume primitives for physics and containment**

  Export `LayoutPhysicsBodies.deactivate` to remove every registered Bullet body for a retained entity without dropping the entity; export `activate` to add those same stored bodies once. Preserve existing normal drop behavior.

  Extend containment normalization/serialization with `:enabled?`. When false, `ensure-installed` must clear containment and install nothing. Ensure `clear` removes the current containment bodies and clears the app-level installed-scene reference.

- [ ] **Step 5: Bind content operations to the active slot**

  Move Scene-owned mutable fields such as entity/root, children, terrain records, queued panels, and object registrations into the slot. Make existing content operations (`build-default`, terrain mutation, `add-panel-child`, `add-object`, light ball/cuboid/demo-browser creation, and panel restore) assert an active slot with this message:
  ```text
  Scene content mutation requires an active activity scene slot
  ```
  Existing external callers retain the same Scene method names; the methods route to the active slot.

  Slot activation sequence is: capture old active service state; deactivate old physics; reset lights/skybox/background/containment to empty state; bind target slot content; apply target state; activate target physics. A failed application must restore the empty service state before rethrowing.

- [ ] **Step 6: Add activity-scoped capture/restore and verify pass**

  Implement capture/restore methods using the established Scene persistence format for panels and terrain records, but store every result on the requested slot. Restoring records builds only terrain/environment data; panel hydration remains deferred to Task 5.

  Rerun the Task 1 command. Expected: PASS with no Sandbox environment or physics leaking into Graph.

- [ ] **Step 7: Commit slot-owned services**

  ```bash
  git add assets/lua/activity-scene-state.fnl assets/lua/scene.fnl assets/lua/layout-physics-bodies.fnl assets/lua/physics-containment.fnl assets/lua/tests/test-scene-activity-slots.fnl
  git commit -m "feat(lua): isolate scene slot environment and physics"
  ```

### Task 3: Migrate HomeWorld scene state into activity sessions

**Files:**
- Create: `assets/lua/tests/test-home-world-scene-activity-state.fnl`
- Modify: `assets/lua/activity-scene-state.fnl`
- Modify: `assets/lua/home-world.fnl` (default state, load normalization, runtime creation, capture)
- Modify: `assets/lua/tests/test-world-manager.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: Task 2 state factories and Scene slot capture/restore.
- Produces:
  ```fennel
  (ActivitySceneState.ensure-session-scene! activity-state id state) ; -> scene state
  (ActivitySceneState.scene-state activity-state id)                 ; -> scene state
  (ActivitySceneState.migrate-legacy-world-state! world-state)       ; -> changed?
  ```
  Canonical persistence: `activity.sessions.sandbox.scene`; Graph/Drawing/Board have empty `:scene` entries.

- [ ] **Step 1: Write failing HomeWorld migration tests**

  Create `test-home-world-scene-activity-state.fnl` using a temporary `world.json`. Test:
  - a fresh HomeWorld has `activity.active_id == "sandbox"`, a default Sandbox scene session, and no canonical top-level scene content/containment;
  - a legacy file containing `scene.panels`, `scene.terrains`, `scene.lights`, `scene.skybox`, `scene.background`, and `physics.containment` loads those exact values into `activity.sessions.sandbox.scene`;
  - after save/reload, the canonical JSON is unchanged and contains no legacy content fields;
  - existing canonical Sandbox state wins if legacy keys coexist, while legacy keys are removed.

- [ ] **Step 2: Confirm the tests fail**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-home-world-scene-activity-state:main
  ```
  Expected: FAIL because HomeWorld still seeds and captures top-level scene state.

- [ ] **Step 3: Implement idempotent state normalization**

  Add `ensure-session-scene!`, `scene-state`, and `migrate-legacy-world-state!` to `activity-scene-state.fnl`. Migration must:
  1. ensure `activity`, `activity.sessions`, and `activity.active_id` (defaulting only nil to `"sandbox"`);
  2. create Sandbox state from legacy values only when `sessions.sandbox.scene` is absent;
  3. create empty scene states for Graph, Drawing, and Board without overwriting an existing session;
  4. remove migrated fields from top-level `scene` and `physics`; and
  5. return whether serialization must be rewritten.

- [ ] **Step 4: Change HomeWorld loading, defaults, and capture**

  In `home-world.fnl`, seed the new canonical activity sessions in default state. Remove top-level default terrain/lights/skybox/background/containment seeding. Run migration immediately after legacy activity-field normalization, then persist the normalized state if it changed.

  Runtime construction must create an empty Scene surface and pass canonical activity session state to the activity runtime; it must not call `scene:build-default` or apply global scene environment/containment. Runtime capture must collect slot state through activity snapshots and write it only under `activity.sessions`.

- [ ] **Step 5: Update existing state tests and verify pass**

  Change assertions in `test-world-manager.fnl` from `world.state.scene.*` and `world.state.physics.containment` to `world.state.activity.sessions.sandbox.scene.*`. Register the new test in `tests/fast.fnl`.

  Run the command from Step 2 and:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-world-manager:main
  ```
  Expected: PASS.

- [ ] **Step 6: Commit canonical persistence**

  ```bash
  git add assets/lua/activity-scene-state.fnl assets/lua/home-world.fnl assets/lua/tests/test-home-world-scene-activity-state.fnl assets/lua/tests/test-world-manager.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(lua): migrate scene state into activity sessions"
  ```

### Task 4: Add the retained Sandbox activity and move hydration/actions

**Files:**
- Create: `assets/lua/sandbox-activity-unit.fnl`
- Create: `assets/lua/sandbox-activity-actions.fnl`
- Create: `assets/lua/tests/test-sandbox-activity.fnl`
- Modify: `assets/lua/main.fnl` (built-in activity-unit specs)
- Modify: `assets/lua/home-world.fnl` (remove global hydration/update path)
- Modify: `assets/lua/root-context-menu-actions.fnl`
- Modify: `assets/lua/tests/test-menu.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: Tasks 1–3 and existing `Activities.register-activity`/session snapshot hooks.
- Produces Sandbox spec:
  ```fennel
  {:id "sandbox" :label "Sandbox" :icon "toys"
   :button-name "sandbox-activity" :show-in-switcher? true
   :activate activate! :deactivate deactivate!
   :snapshot snapshot! :restore restore!}
  ```

- [ ] **Step 1: Write failing Sandbox lifecycle tests**

  Create `test-sandbox-activity.fnl`. Test that loading the unit registers exactly the spec above; activating it ensures and activates the Sandbox Scene slot, restores the canonical Sandbox state, exposes Scene interaction/root actions, and hydrates persisted panels incrementally through its update hook.

  Add a switch test: activate Sandbox, retain a scene panel/object identity, switch to Graph, then reactivate Sandbox and assert the same retained object is present and no second default terrain was created.

- [ ] **Step 2: Confirm failure**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-activity:main
  ```
  Expected: FAIL because the Sandbox module is absent.

- [ ] **Step 3: Implement Sandbox session lifecycle**

  `sandbox-activity-unit.fnl` must follow the Graph/Drawing/Board unit export pattern. On first activation, obtain the persisted state from `runtime.activity-session-state.sandbox.scene`, ensure/activate the Sandbox slot, restore its environment and terrains, then queue persisted panels for incremental hydration. On subsequent activation, only reactivate the retained slot.

  The activation context must set preferred interaction surface `:scene`, set a Scene-target predicate, install Sandbox root actions, and install an update hook that restores at most one queued panel per frame. Deactivation hides/disables the slot without dropping it. `snapshot!` captures the Sandbox slot state; `restore!` stages canonical state for first activation.

- [ ] **Step 4: Move former global actions and hydration ownership**

  Extract the existing scene root actions (add physics body/light ball/demo browser and terrain recovery) into `sandbox-activity-actions.fnl`. The root context menu must request active activity actions; it must no longer attach those actions merely because `app.scene` exists.

  Remove HomeWorld's global scene panel hydration/update helpers and its global default-scene restoration calls. Retain existing panel-restorer behavior, but require it to operate through the active Sandbox slot.

- [ ] **Step 5: Register the unit and verify pass**

  Add Sandbox to `built-in-activity-unit-specs` before Graph so fresh-world default activation can resolve it. Register the test in `tests/fast.fnl`; update `test-menu.fnl` to activate Sandbox before asserting former scene actions.

  Rerun the Step 2 command and:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-menu:main
  ```
  Expected: PASS.

- [ ] **Step 6: Commit Sandbox ownership**

  ```bash
  git add assets/lua/sandbox-activity-unit.fnl assets/lua/sandbox-activity-actions.fnl assets/lua/main.fnl assets/lua/home-world.fnl assets/lua/root-context-menu-actions.fnl assets/lua/tests/test-sandbox-activity.fnl assets/lua/tests/test-menu.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(lua): add sandbox scene activity"
  ```

### Task 5: Give existing activities empty retained Scene slots

**Files:**
- Modify: `assets/lua/graph-activity-unit.fnl`
- Modify: `assets/lua/drawing-activity-unit.fnl`
- Modify: `assets/lua/board-activity-unit.fnl`
- Modify: `assets/lua/tests/test-graph-activity-slots.fnl`
- Modify: `assets/lua/tests/test-drawing-activity-slots.fnl`
- Modify: `assets/lua/tests/test-activity-retention.fnl`

**Interfaces:**
- Consumes: Task 1 `scene:ensure-activity-slot` and `scene:activate/deactivate-activity-slot`.
- Produces: Every built-in activity owns a Scene slot; non-Sandbox slots begin with `(ActivitySceneState.empty-state)`.

- [ ] **Step 1: Write failing non-Sandbox isolation tests**

  In the Graph, Drawing, and retention tests, activate Sandbox and create one visible terrain/object; switch each activity in turn. Assert its Scene active slot is not Sandbox's slot, its captured terrain/panel lists are empty, its slot has no enabled lights/skybox/background/containment, and Sandbox's pointer target is rejected. Switch back and assert Sandbox content identity remains unchanged.

- [ ] **Step 2: Confirm failure**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-retention:main
  ```
  Expected: FAIL because these activities do not activate their own Scene slots.

- [ ] **Step 3: Activate each activity's empty Scene slot**

  In each existing activity's activation path, ensure and activate the slot matching its id before configuring Canvas hooks. Initialize/restore the activity session's `:scene` state with `ActivitySceneState.empty-state` only when absent. In each deactivation path, deactivate that same Scene slot without dropping it.

  Keep Graph/Drawing/Board preferred interaction surfaces and Canvas policies unchanged. An empty Scene slot is still the active Scene render/input source, which is how it prevents inherited Sandbox data rather than hiding the Scene surface.

- [ ] **Step 4: Verify focused activity tests pass**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-drawing-activity-slots:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-retention:main
  ```
  Expected: PASS.

- [ ] **Step 5: Commit activity isolation**

  ```bash
  git add assets/lua/graph-activity-unit.fnl assets/lua/drawing-activity-unit.fnl assets/lua/board-activity-unit.fnl assets/lua/tests/test-graph-activity-slots.fnl assets/lua/tests/test-drawing-activity-slots.fnl assets/lua/tests/test-activity-retention.fnl
  git commit -m "feat(lua): isolate built-in activity scene slots"
  ```

### Task 6: Move scene-data consumers to canonical Sandbox state

**Files:**
- Modify: `assets/lua/graph/world-data.fnl`
- Modify: `assets/lua/graph/nodes/scene-panels.fnl`
- Modify: `assets/lua/graph/nodes/scene-panel.fnl`
- Modify: `assets/lua/graph/nodes/terrain.fnl`
- Modify: `assets/lua/graph/nodes/light.fnl`
- Modify: `assets/lua/tests/test-world-nodes.fnl`
- Modify: `assets/lua/tests/test-world-background-node.fnl`
- Modify: `assets/lua/tests/test-world-skybox-node.fnl`

**Interfaces:**
- Consumes: `ActivitySceneState.scene-state activity-state "sandbox"` from Task 3.
- Produces: World graph/node APIs resolve the Sandbox scene session explicitly; they never access legacy `world.state.scene.*` or `world.state.physics.containment`.

- [ ] **Step 1: Write failing canonical-owner tests**

  Add tests where `world.state.scene` is empty but `activity.sessions.sandbox.scene` has terrain, panel, light, skybox, and background data. Assert scene panel/terrain/light/background/skybox nodes enumerate and edit the Sandbox data. Add a negative assertion that a Graph slot's independently populated future-style state is not treated as Sandbox world content.

- [ ] **Step 2: Confirm failure**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-world-nodes:main
  ```
  Expected: FAIL because node code still reads legacy top-level state.

- [ ] **Step 3: Replace legacy state access at the graph boundary**

  Add one explicit `WorldData.resolve-sandbox-scene-state(world)` helper that asserts a HomeWorld activity/session binding and returns `ActivitySceneState.scene-state world.state.activity "sandbox"`. Route all listed graph node modules through that helper. When Sandbox is active, mutations must update its retained slot and canonical session state; when inactive, mutate canonical Sandbox state and let next activation apply it. Do not route these nodes through the currently active non-Sandbox slot.

- [ ] **Step 4: Verify canonical world-node behavior**

  Run the Step 2 command plus:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-world-background-node:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-world-skybox-node:main
  ```
  Expected: PASS.

- [ ] **Step 5: Commit canonical scene consumers**

  ```bash
  git add assets/lua/graph/world-data.fnl assets/lua/graph/nodes/scene-panels.fnl assets/lua/graph/nodes/scene-panel.fnl assets/lua/graph/nodes/terrain.fnl assets/lua/graph/nodes/light.fnl assets/lua/tests/test-world-nodes.fnl assets/lua/tests/test-world-background-node.fnl assets/lua/tests/test-world-skybox-node.fnl
  git commit -m "refactor(lua): resolve world scene data from sandbox"
  ```

### Task 7: Complete regression migration and document the finished architecture

**Files:**
- Modify: `assets/lua/tests/test-demo-browser.fnl`
- Modify: `assets/lua/tests/test-scene-drag.fnl`
- Modify: `assets/lua/tests/test-panel-transfer.fnl`
- Modify: `assets/lua/tests/test-physics-containment.fnl`
- Modify: `assets/lua/tests/test-renderers.fnl`
- Modify: `assets/lua/tests/test-main-events.fnl`
- Modify: `assets/lua/tests/fast.fnl`
- Modify: `docs/dev/features/activities.md`

**Interfaces:**
- Consumes: completed slot/session APIs from Tasks 1–6.
- Produces: all focused scene tests construct/activate an explicit Scene slot before mutating scene content; architecture documentation marks Scene slots/Sandbox ownership implemented.

- [ ] **Step 1: Add regression assertions before updating fixtures**

  For each affected test family, first add an assertion that content construction occurs only after explicit Sandbox activation (or an explicitly created test activity slot). Add a renderer test proving only the active slot's draw source reaches `draw-target`; add a panel-transfer test proving transferred content goes to the active slot, not a global Scene root; add a physics test proving deactivation removes active bodies while retaining slot state.

- [ ] **Step 2: Run the focused regression group to confirm failures**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-demo-browser:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-scene-drag:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-panel-transfer:main
  ```
  Expected: FAIL until fixtures explicitly activate their target scene slot.

- [ ] **Step 3: Update fixtures and remove legacy assumptions**

  Update test setup to call `scene:activate-activity-slot "sandbox"` before current Sandbox-content operations, or a named test slot for generic surface tests. Replace all assertions of top-level persisted scene/containment state with canonical activity-session paths. Ensure no live production or test code retains a read of `world.state.scene.panels`, `world.state.scene.terrains`, `world.state.scene.lights`, `world.state.scene.skybox`, `world.state.scene.background`, or `world.state.physics.containment`.

- [ ] **Step 4: Update activity architecture documentation**

  In `docs/dev/features/activities.md`, mark Phase 4 complete. State that Sandbox owns the former default 3D workspace, scene slots are retained and active-slot isolated, and canonical persisted state is activity-session scene state. Retain historical descriptions only where explicitly labeled as prior architecture.

- [ ] **Step 5: Run focused and fast suites**

  Run the Step 2 commands plus:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-physics-containment:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  ```
  Expected: PASS.

- [ ] **Step 6: Commit regression completion**

  ```bash
  git add assets/lua/tests/test-demo-browser.fnl assets/lua/tests/test-scene-drag.fnl assets/lua/tests/test-panel-transfer.fnl assets/lua/tests/test-physics-containment.fnl assets/lua/tests/test-renderers.fnl assets/lua/tests/test-main-events.fnl assets/lua/tests/fast.fnl docs/dev/features/activities.md
  git commit -m "test(lua): cover sandbox scene activity isolation"
  ```

## Final validation

- [ ] Run `git diff --check` and confirm no staged or unstaged unintended files.
- [ ] Run `./build/space -m tests.fast:main` with the documented Fennel environment and confirm PASS.
- [ ] Exercise a persisted legacy HomeWorld manually: it opens in Sandbox with the former terrain/panels/lights; switch Graph, Draw, and Board and confirm no Sandbox content or interaction remains; switch back to Sandbox and confirm retained state returns.
- [ ] Verify every new task commit has passed implementer review before integration.
