# Graph Map Camera Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate Board and Graph cameras, persist independent camera transforms per graph map, restore them on switches/reloads, and center new graph maps once on their first/start node.

**Architecture:** Keep graph core topology untouched. Store camera state in existing per-graph-map view metadata, and restore transforms into the stable live Graph canvas slot camera so `CanvasControls` bindings remain valid. `GraphViewPersistence` owns metadata read/write, `GraphView` captures camera state and applies one-shot initial centering, and `graph-activity-unit` coordinates map/activity switching.

**Tech Stack:** Space Fennel modules under `assets/lua`, `ActivityCameraState`, `GraphViewPersistence`, activity canvas slots, project-native `tools.fennel-check`, `make constraints`, and focused Fennel tests through `./build/space`.

## Global Constraints

- Preserve strict Board-vs-Graph camera isolation: moving Board must not move Graph, and moving Graph must not move Board.
- Give each graph map its own camera transform.
- Persist per-graph-map camera state across world/app reload.
- Save the active graph map camera before graph map switches, graph activity deactivation, world save/session snapshot, and graph view teardown paths that can otherwise lose the latest camera transform.
- Restore the target graph map camera when switching to or reloading that map.
- If a first/start node point is already present for a map with no persisted camera state, center it as if the user selected/clicked it from the node list.
- If the camera exists before the first node point is added, start from the identity/default camera and center the first added node point once.
- Do not auto-center successive nodes after the first automatic centering.
- No camera state in graph core topology. `Graph` persists topology only.
- No camera state on individual graph nodes or backing domain stores.
- No Board-specific redesign beyond adding regression coverage that Board and Graph do not share cameras.
- No simultaneous multi-map rendering or multiple visible Graph maps.
- No graph map duplication camera semantics beyond the new-map default policy.
- No broad `CanvasControls` rewrite unless evidence shows stable camera transform restoration cannot preserve control correctness.
- Fennel validation must use Space-native `tools.fennel-check`, `make constraints`, and focused Fennel tests. Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- Use `local` instead of `let`; use multi-branch `if` forms rather than nested `if` when practical; use factory functions rather than `.new` constructors.
- Missing required graph activity runtime, graph map manager, graph map, graph view persistence, or graph slot camera should fail loudly.
- Malformed persisted camera state should fail with an explicit message naming the map/camera field.

---

## File Structure

- Modify `assets/lua/tests/test-graph-activity-slots.fnl` for Board/Graph camera isolation, graph map camera switching, and new-map first-node centering integration tests.
- Modify `assets/lua/graph/view/persistence.fnl` to add validated optional `camera` metadata accessors while preserving existing metadata keys.
- Create `assets/lua/tests/test-graph-view-camera-persistence.fnl` for graph-map camera metadata and GraphView initial-centering unit tests.
- Modify `assets/lua/tests/fast.fnl` to include the new camera persistence test module.
- Modify `assets/lua/graph/view/init.fnl` so GraphView captures camera state and owns one-shot initial centering for maps with no saved camera.
- Modify `assets/lua/graph-activity-unit.fnl` so Graph activity restores per-map camera state and resets unsaved maps to the default camera before initial centering.
- Modify `docs/dev/graph-maps.md` to document graph map camera metadata and switching semantics.

---

### Task 1: Board/Graph Camera Isolation Regression

**Files:**
- Modify: `assets/lua/tests/test-graph-activity-slots.fnl`
- Modify only when the new regression fails: `assets/lua/graph-activity-unit.fnl`, `assets/lua/board-activity-unit.fnl`, `assets/lua/home-world-canvas-runtime.fnl`

**Interfaces:**
- Consumes: `Activities.activate-activity(activity-id:string) -> any`.
- Consumes: `runtime.activity-cameras.canvas.graph` and `runtime.activity-cameras.canvas.board` camera objects.
- Produces: test function `board-and-graph-activity-cameras-stay-isolated`.

- [ ] **Step 1: Add the regression test**

In `assets/lua/tests/test-graph-activity-slots.fnl`, add a test using the same fixture style as `graph-and-drawing-do-not-share-canvas-camera`. The core assertions must be:

```fennel
(fn board-and-graph-activity-cameras-stay-isolated []
  ;; Use a fresh runtime with Canvas, Scene, GraphMapManager, ObjectSelector,
  ;; and board-state. Load GraphActivityUnit and BoardActivityUnit.
  (Activities.activate-activity "graph")
  (local graph-slot (canvas:activity-slot "graph"))
  (local graph-camera (. runtime.activity-cameras.canvas "graph"))
  (assert graph-camera "Graph activity should create a graph camera")
  (assert (= graph-slot.camera graph-camera)
          "Graph slot must use the graph activity camera")
  (graph-camera:set-position (glm.vec3 10 20 100))

  (Activities.activate-activity "board")
  (local board-slot (canvas:activity-slot "board"))
  (local board-camera (. runtime.activity-cameras.canvas "board"))
  (assert board-camera "Board activity should create a board camera")
  (assert (= board-slot.camera board-camera)
          "Board slot must use the board activity camera")
  (assert (not (= graph-camera board-camera))
          "Graph and Board must not share the same activity camera object")
  (board-camera:set-position (glm.vec3 -30 -40 100))
  (assert (= graph-camera.position.x 10)
          "Moving Board must not change Graph camera x")
  (assert (= graph-camera.position.y 20)
          "Moving Board must not change Graph camera y")

  (Activities.activate-activity "graph")
  (assert (= graph-camera.position.x 10)
          "Graph camera x should restore after Board activity movement")
  (assert (= graph-camera.position.y 20)
          "Graph camera y should restore after Board activity movement")
  (assert (= board-camera.position.x -30)
          "Graph reactivation must not change Board camera x")
  (assert (= board-camera.position.y -40)
          "Graph reactivation must not change Board camera y"))
```

Use the real fixture setup/cleanup patterns already present in the file rather than leaving the comment block in the final test.

- [ ] **Step 2: Register the test**

Append near the existing graph activity slot test registrations:

```fennel
(table.insert tests {:name "Board and Graph activity cameras stay isolated"
                     :fn board-and-graph-activity-cameras-stay-isolated})
```

- [ ] **Step 3: Run Task 1 validation**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-graph-activity-slots.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

Expected before a production fix: the test may pass if the intended Board/Graph path already isolates cameras. Keep the regression either way.

- [ ] **Step 4: Fix only when the regression fails**

When the regression fails because camera objects or slot cameras are shared, restrict the fix to the broken activity camera path:

```fennel
;; Required invariant for Graph activation
(HomeWorldCanvasRuntime.ensure-activity-canvas-camera! world-runtime "graph" {:position (glm.vec3 0 0 100)})

;; Required invariant for Board activation
(HomeWorldCanvasRuntime.ensure-activity-canvas-camera! world-runtime "board" {:position (glm.vec3 0 0 100)})
```

Also ensure controls are keyed with the same activity id as their camera:

```fennel
(HomeWorldCanvasRuntime.ensure-activity-canvas-controls! world-runtime "graph" graph-camera)
(HomeWorldCanvasRuntime.ensure-activity-canvas-controls! world-runtime "board" board-camera)
```

- [ ] **Step 5: Re-run Task 1 validation**

Run the three commands from Step 3 again. Expected: all pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add assets/lua/tests/test-graph-activity-slots.fnl assets/lua/graph-activity-unit.fnl assets/lua/board-activity-unit.fnl assets/lua/home-world-canvas-runtime.fnl
git commit -m "test(graph): cover board and graph camera isolation"
```

Commit body must include:

```text
Constraint impact: not applicable
Testing: tools.fennel-check graph activity slot test files; make constraints; tests.test-graph-activity-slots passed.
```

---

### Task 2: Graph Map Camera Metadata Accessors

**Files:**
- Modify: `assets/lua/graph/view/persistence.fnl`
- Create: `assets/lua/tests/test-graph-view-camera-persistence.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Produces: `GraphViewPersistence:saved-camera-state() -> table|nil`.
- Produces: `GraphViewPersistence:set-camera-state(camera-state:table|nil) -> true`.
- Produces: optional top-level `camera` metadata in `graph/maps/<map-id>/metadata.json`.
- Camera metadata shape: `{:position [x y z] :rotation [w x y z]}`; `rotation` is optional.

- [ ] **Step 1: Create failing metadata tests**

Create `assets/lua/tests/test-graph-view-camera-persistence.fnl` with this module structure:

```fennel
(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local GraphViewPersistence (require :graph/view/persistence))
(local tests [])

(local temp-root "/tmp/space/tests/graph-view-camera-persistence")

(fn reset-dir []
  (when (fs.exists temp-root)
    (fs.remove-all temp-root))
  (fs.create-dirs temp-root)
  temp-root)

(fn camera-state-saves-loads-and-preserves-metadata []
  (local dir (reset-dir))
  (local persistence (GraphViewPersistence {:data-dir dir :map-id "main"}))
  (persistence:set-size {:key "node-a"} {:x 12 :y 8})
  (persistence:set-camera-state {:position [11 22 33] :rotation [1 0 0 0]})
  (persistence:persist {} true)
  (local decoded (json.loads (fs.read-file persistence.metadata-path)))
  (assert (= (. decoded.camera.position 1) 11)
          "camera position x should persist")
  (assert (= (. decoded.camera.position 2) 22)
          "camera position y should persist")
  (assert (= (. decoded.camera.position 3) 33)
          "camera position z should persist")
  (assert decoded.sizes.node-a
          "camera persistence should preserve existing size metadata")
  (local reloaded (GraphViewPersistence {:data-dir dir :map-id "main"}))
  (local camera-state (reloaded:saved-camera-state))
  (assert (= (. camera-state.position 1) 11)
          "saved-camera-state should return persisted position x")
  (assert (= (. camera-state.rotation 1) 1)
          "saved-camera-state should return persisted rotation w"))

(fn malformed-camera-state-fails-loudly []
  (local dir (reset-dir))
  (local persistence (GraphViewPersistence {:data-dir dir :map-id "main"}))
  (fs.create-dirs (fs.dirname persistence.metadata-path))
  (JsonUtils.write-json! persistence.metadata-path {:camera {:position ["bad" 2 3]}})
  (local (ok err) (pcall (fn [] (GraphViewPersistence {:data-dir dir :map-id "main"}))))
  (assert (not ok) "malformed camera metadata should fail")
  (assert (string.find (tostring err) "GraphViewPersistence" 1 true)
          "camera error should name GraphViewPersistence")
  (assert (string.find (tostring err) "main" 1 true)
          "camera error should name map id")
  (assert (string.find (tostring err) "camera" 1 true)
          "camera error should name camera field"))

(table.insert tests {:name "camera state saves loads and preserves metadata"
                     :fn camera-state-saves-loads-and-preserves-metadata})
(table.insert tests {:name "malformed camera state fails loudly"
                     :fn malformed-camera-state-fails-loudly})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-view-camera-persistence"
                       :tests tests})))

{:name "graph-view-camera-persistence"
 :tests tests
 :main main}
```

If `fs.dirname` is unavailable, use `fs.join-path` to create `graph/maps/main` explicitly.

- [ ] **Step 2: Register the new test in fast suite**

In `assets/lua/tests/fast.fnl`, add this module near other graph view tests:

```fennel
:tests.test-graph-view-camera-persistence
```

- [ ] **Step 3: Run the new test and verify failure**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-graph-view-camera-persistence.fnl --file assets/lua/tests/fast.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-camera-persistence:main
```

Expected: FAIL because `set-camera-state` and `saved-camera-state` do not exist.

- [ ] **Step 4: Add camera metadata storage and validation**

In `assets/lua/graph/view/persistence.fnl`:

Add `:camera nil` to the initial `persisted` table and a local variable:

```fennel
(var persisted-camera nil)
```

Add validation helpers:

```fennel
(fn assert-number-array [value count label]
  (assert (= (type value) :table)
          (string.format "GraphViewPersistence %s for %s camera must be a table" label map-id))
  (for [idx 1 count]
    (assert (finite-number? (rawget value idx))
            (string.format "GraphViewPersistence %s for %s camera has invalid value at %d" label map-id idx))))

(fn assert-valid-camera-state [value context]
  (when value
    (assert (= (type value) :table)
            (string.format "GraphViewPersistence %s for %s camera must be a table" context map-id))
    (assert-number-array value.position 3 (.. context " position"))
    (when value.rotation
      (assert-number-array value.rotation 4 (.. context " rotation")))))

(fn clone-camera-state [value]
  (when value
    (assert-valid-camera-state value "camera")
    (local cloned {:position [(rawget value.position 1)
                              (rawget value.position 2)
                              (rawget value.position 3)]})
    (when value.rotation
      (set cloned.rotation [(rawget value.rotation 1)
                            (rawget value.rotation 2)
                            (rawget value.rotation 3)
                            (rawget value.rotation 4)]))
    cloned))
```

During `load`, after decoding panels and extra panels:

```fennel
(local camera (and decoded decoded.camera))
(assert-valid-camera-state camera "load")
```

When assigning `persisted`, include `:camera (clone-camera-state camera)` and set `persisted-camera` to that value.

During `persist`, set:

```fennel
(set persisted.camera persisted-camera)
```

Add methods:

```fennel
(fn saved-camera-state [_self]
  (clone-camera-state persisted-camera))

(fn set-camera-state [_self camera-state]
  (set persisted-camera (clone-camera-state camera-state))
  (set persisted.camera persisted-camera)
  (set pending-save? true)
  true)
```

Export these methods in `self`.

- [ ] **Step 5: Run Task 2 validation**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/persistence.fnl --file assets/lua/tests/test-graph-view-camera-persistence.fnl --file assets/lua/tests/fast.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-camera-persistence:main
```

Expected: all pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add assets/lua/graph/view/persistence.fnl assets/lua/tests/test-graph-view-camera-persistence.fnl assets/lua/tests/fast.fnl
git commit -m "feat(graph): persist graph map camera metadata"
```

Commit body must include:

```text
Constraint impact: not applicable
Testing: tools.fennel-check graph camera persistence files; make constraints; tests.test-graph-view-camera-persistence passed.
```

---

### Task 3: Save and Restore Camera on Graph Map Switch

**Files:**
- Modify: `assets/lua/graph/view/init.fnl`
- Modify: `assets/lua/graph-activity-unit.fnl`
- Modify: `assets/lua/tests/test-graph-activity-slots.fnl`

**Interfaces:**
- Consumes: `GraphViewPersistence:saved-camera-state() -> table|nil`.
- Consumes: `GraphViewPersistence:set-camera-state(camera-state:table|nil) -> true`.
- Consumes: `ActivityCameraState.capture-camera(camera) -> table|nil`.
- Consumes: `ActivityCameraState.restore-camera!(camera, camera-state) -> true`.
- Produces: `GraphView:capture-camera-state!() -> table|nil`.
- Produces: map switching saves outgoing map camera and restores target map camera into the stable graph slot camera.

- [ ] **Step 1: Add failing graph map switch camera test**

In `assets/lua/tests/test-graph-activity-slots.fnl`, add `graph-map-cameras-save-and-restore-on-switch`. Use a runtime with two graph maps, `main` and `beta`, through `GraphMapManager`. The core flow must be:

```fennel
(Activities.activate-activity "graph")
(local graph-camera (. runtime.activity-cameras.canvas "graph"))
(graph-camera:set-position (glm.vec3 10 20 100))

(graph-map-manager:switch-to-map "beta")
(local main-persistence (GraphViewPersistence {:data-dir data-dir :map-id "main"}))
(local main-camera (main-persistence:saved-camera-state))
(assert (= (. main-camera.position 1) 10)
        "Switching away should persist main camera x")
(assert (= (. main-camera.position 2) 20)
        "Switching away should persist main camera y")

(graph-camera:set-position (glm.vec3 -30 -40 150))
(graph-map-manager:switch-to-map "main")
(assert (= graph-camera.position.x 10)
        "Switching back to main should restore main camera x")
(assert (= graph-camera.position.y 20)
        "Switching back to main should restore main camera y")

(graph-map-manager:switch-to-map "beta")
(assert (= graph-camera.position.x -30)
        "Switching back to beta should restore beta camera x")
(assert (= graph-camera.position.y -40)
        "Switching back to beta should restore beta camera y")
```

Require `GraphViewPersistence` at the top of the test file or locally inside the test.

- [ ] **Step 2: Run focused test and verify failure**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-graph-activity-slots.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

Expected: FAIL because per-map camera state is not captured/restored.

- [ ] **Step 3: Persist camera during GraphView capture/drop**

In `assets/lua/graph/view/init.fnl`, add:

```fennel
(local ActivityCameraState (require :activity-camera-state))
```

Add helper near other capture/persistence helpers:

```fennel
(fn capture-camera-state! []
  (when (and options.camera persistence persistence.set-camera-state)
    (local state (ActivityCameraState.capture-camera options.camera))
    (persistence:set-camera-state state)
    state))
```

Call `capture-camera-state!` immediately before each forced persistence write in `capture-state` and `drop`:

```fennel
(capture-camera-state!)
(persistence:persist registry.points true)
```

Expose on the returned GraphView object:

```fennel
:capture-camera-state! (fn [_self] (capture-camera-state!))
```

- [ ] **Step 4: Restore saved map camera on graph activation**

In `assets/lua/graph-activity-unit.fnl`, after graph view creation/installation and before returning `graph-view`, resolve saved camera state:

```fennel
(local saved-camera-state
  (and graph-view.persistence
       graph-view.persistence.saved-camera-state
       (graph-view.persistence:saved-camera-state)))
(when saved-camera-state
  (ActivityCameraState.restore-camera! slot-camera saved-camera-state))
```

Do not replace `slot.camera` or `runtime.activity-cameras.canvas.graph`; only restore into `slot-camera`.

- [ ] **Step 5: Ensure outgoing camera capture before map switch teardown**

In `capture-graph-view-state-for-key!` and `capture-graph-view-state!`, call the new method before `graph-view:capture-state` when present:

```fennel
(when graph-view.capture-camera-state!
  (graph-view:capture-camera-state!))
```

This ensures map switch, activity snapshot, deactivation, and drop paths capture the camera because those paths already call graph view state capture.

- [ ] **Step 6: Run Task 3 validation**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/init.fnl --file assets/lua/graph-activity-unit.fnl --file assets/lua/tests/test-graph-activity-slots.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

Expected: all pass.

- [ ] **Step 7: Commit Task 3**

```bash
git add assets/lua/graph/view/init.fnl assets/lua/graph-activity-unit.fnl assets/lua/tests/test-graph-activity-slots.fnl
git commit -m "feat(graph): restore graph map cameras on switch"
```

Commit body must include:

```text
Constraint impact: not applicable
Testing: tools.fennel-check graph view/activity files; make constraints; tests.test-graph-activity-slots passed.
```

---

### Task 4: One-Shot First Node Centering for Maps Without Saved Camera

**Files:**
- Modify: `assets/lua/graph/view/init.fnl`
- Modify: `assets/lua/graph-activity-unit.fnl`
- Modify: `assets/lua/tests/test-graph-view-camera-persistence.fnl`
- Modify: `assets/lua/tests/test-graph-activity-slots.fnl`

**Interfaces:**
- Produces: `GraphView:apply-initial-camera-policy!() -> true`.
- Produces: one-shot pending initial centering consumed by the first mounted graph node point when no point exists at activation time.
- Consumes: `GraphView:reveal-node(node-or-key, opts)` or the existing internal camera-centering helper.

- [ ] **Step 1: Add failing initial-centering tests**

In `assets/lua/tests/test-graph-view-camera-persistence.fnl`, add tests for:

1. no saved camera plus existing node centers that node;
2. no saved camera plus empty map keeps default camera until first node is added;
3. the first added node is centered once;
4. the second added node does not recenter.

Core assertions:

```fennel
(view:apply-initial-camera-policy!)
(assert (= camera.position.x 123)
        "initial camera policy should center existing node x")
(assert (= camera.position.y 456)
        "initial camera policy should center existing node y")

(empty-view:apply-initial-camera-policy!)
(assert (= empty-camera.position.x 0)
        "empty map should start from default camera x before first node")
(assert (= empty-camera.position.y 0)
        "empty map should start from default camera y before first node")

(graph-map:add-node first {:position (glm.vec3 20 30 0)})
(assert (= empty-camera.position.x 20)
        "first added node should consume pending initial center x")
(assert (= empty-camera.position.y 30)
        "first added node should consume pending initial center y")

(graph-map:add-node second {:position (glm.vec3 500 600 0)})
(assert (= empty-camera.position.x 20)
        "second added node should not recenter x")
(assert (= empty-camera.position.y 30)
        "second added node should not recenter y")
```

In `assets/lua/tests/test-graph-activity-slots.fnl`, extend the map-switch test so switching to a map without saved camera does not inherit the previous map camera and either centers the existing first node or waits for the first node.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-graph-view-camera-persistence.fnl --file assets/lua/tests/test-graph-activity-slots.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-camera-persistence:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

Expected: FAIL because `apply-initial-camera-policy!` does not exist and unsaved maps still inherit the previous camera.

- [ ] **Step 3: Add one-shot centering state in GraphView**

In `assets/lua/graph/view/init.fnl`, add state near other GraphView locals:

```fennel
(var pending-initial-center? false)
(var initial-center-consumed? false)
```

Add a helper after the camera centering helper is defined:

```fennel
(fn consume-initial-center! [node]
  (when (and pending-initial-center?
             (not initial-center-consumed?)
             node
             (. registry.points node))
    (center-camera-on-node! node)
    (set pending-initial-center? false)
    (set initial-center-consumed? true)
    true))
```

After each node is added and registered in the normal node-added path, call:

```fennel
(consume-initial-center! node)
```

- [ ] **Step 4: Add `apply-initial-camera-policy!` to GraphView**

Expose a method with this behavior:

```fennel
(set view.apply-initial-camera-policy!
     (fn [_self]
       (assert-not-dropped "apply-initial-camera-policy!")
       (if initial-center-consumed?
           true
           (do
             (var target-node nil)
             (each [node _point (pairs registry.points) &until target-node]
               (set target-node node))
             (if target-node
                 (do
                   (center-camera-on-node! target-node)
                   (set initial-center-consumed? true)
                   (set pending-initial-center? false))
                 (set pending-initial-center? true))
             true))))
```

If the graph exposes a reliable start-node lookup in this code path, prefer that node before the generic first point. If it does not, the first mounted point is the canonical first/start point for this task.

- [ ] **Step 5: Reset unsaved maps to default before initial centering**

In `assets/lua/graph-activity-unit.fnl`, replace the Task 3 saved-camera-only branch with:

```fennel
(if saved-camera-state
    (ActivityCameraState.restore-camera! slot-camera saved-camera-state)
    (do
      (ActivityCameraState.restore-camera! slot-camera {:position [0 0 100]})
      (when graph-view.apply-initial-camera-policy!
        (graph-view:apply-initial-camera-policy!))))
```

Required invariant: maps without saved camera must not inherit the previous graph map camera transform.

- [ ] **Step 6: Run Task 4 validation**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/init.fnl --file assets/lua/graph-activity-unit.fnl --file assets/lua/tests/test-graph-view-camera-persistence.fnl --file assets/lua/tests/test-graph-activity-slots.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-camera-persistence:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

Expected: all pass.

- [ ] **Step 7: Commit Task 4**

```bash
git add assets/lua/graph/view/init.fnl assets/lua/graph-activity-unit.fnl assets/lua/tests/test-graph-view-camera-persistence.fnl assets/lua/tests/test-graph-activity-slots.fnl
git commit -m "feat(graph): center new map camera once"
```

Commit body must include:

```text
Constraint impact: not applicable
Testing: tools.fennel-check graph camera policy files; make constraints; tests.test-graph-view-camera-persistence and tests.test-graph-activity-slots passed.
```

---

### Task 5: Documentation and Integrated Validation

**Files:**
- Modify: `docs/dev/graph-maps.md`
- Validate files changed by Tasks 1-4.

**Interfaces:**
- Consumes: implemented `camera` metadata key and graph initial camera policy.
- Produces: canonical documentation for graph map camera metadata and final validation evidence.

- [ ] **Step 1: Update graph map documentation**

In `docs/dev/graph-maps.md`, add or update a graph map metadata section with this content, using a normal Markdown paragraph and an indented Fennel example:

```markdown
Graph map camera state is interaction/view metadata, not graph topology. Each
map stores its camera transform in `graph/maps/<graph-map-id>/metadata.json`:

    :camera {:position [x y z]
             :rotation [w x y z]}

When switching maps, Graph captures the outgoing map camera and restores the
target map camera into the stable graph canvas slot camera. Maps without saved
camera state reset to the default camera and center the first/start node once.
```

- [ ] **Step 2: Run docs-focused text check**

Run:

```bash
rtk rg "camera|Graph map camera state|graph/maps/<graph-map-id>/metadata.json" docs/dev/graph-maps.md
```

Expected: output shows the new camera metadata documentation.

- [ ] **Step 3: Run complete focused Fennel validation**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/persistence.fnl --file assets/lua/graph/view/init.fnl --file assets/lua/graph-activity-unit.fnl --file assets/lua/tests/test-graph-view-camera-persistence.fnl --file assets/lua/tests/test-graph-activity-slots.fnl --file assets/lua/tests/fast.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-camera-state:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-camera-persistence:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-manager:main
```

Expected: all pass.

- [ ] **Step 4: Run broader suite**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: pass. This broader validation is required because activity switching, graph view teardown, persistence, and world/session snapshot behavior touch shared runtime surfaces.

- [ ] **Step 5: Commit Task 5**

```bash
git add docs/dev/graph-maps.md
git commit -m "docs(graph): document graph map camera metadata"
```

Commit body must include:

```text
Constraint impact: not applicable
Testing: rg graph map camera docs; tools.fennel-check touched camera files; make constraints; focused camera/graph tests; make test passed.
```

---

## Acceptance Criteria

- Board and Graph activity cameras are distinct objects.
- Moving Board camera does not mutate Graph camera, and moving Graph camera does not mutate Board camera.
- Each graph map persists its own `camera` metadata under `graph/maps/<map-id>/metadata.json`.
- Switching maps saves the outgoing map camera before teardown and restores the target map camera.
- Session/world snapshot paths capture the latest active graph map camera.
- Maps with no saved camera do not inherit the previous map camera.
- Maps with no saved camera center first/start node once, then stop auto-centering.
- Malformed persisted camera metadata fails loudly with an error mentioning graph view persistence, map id, and camera.
- Graph core topology files remain untouched for camera persistence.

## Final Handoff Requirements

- Every implementation task must pass implementer → reviewer before moving to the next task.
- Before implementation starts, validate the root-cause diagnosis with `debug-advisor` using the committed spec, this plan, and the read-only investigation findings.
- Every repository fix produced by validation failure must invoke systematic debugging before implementation.
- Final branch finishing must fetch `origin`, evaluate against current `origin/main`, safe-merge `origin/main` when needed and permitted, rerun required validation after integration, commit reviewed changes, verify a clean worktree, push the branch, create or update a PR targeting `main`, enable/enter merge queue when available, and poll until the PR is merged or an actionable blocker requires human input.
