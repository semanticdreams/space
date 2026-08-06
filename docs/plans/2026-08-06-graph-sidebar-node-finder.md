# Graph Sidebar Node Finder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a graph map sidebar node finder and an always-visible idempotent `Add Start` recovery action.

**Architecture:** `GraphMapSidebar` renders active-map membership controls and receives callbacks for view behavior. `graph-activity-unit.fnl` owns runtime wiring to the active `GraphView`. `GraphView` exposes public reveal/open methods that select, focus, center, and open nodes without loading new graph nodes.

**Tech Stack:** Space Fennel, existing widget system (`Button`, `Flex`, `SearchView`), graph map/view modules, project-native `make fennel-check`, constraints, and focused Fennel tests through `./build/space`.

## Global Constraints

- Preserve graph doctrine: `GraphMap` owns map-local graph membership and interaction context; `GraphView` owns visual state such as layout, focus, selection, camera positioning, labels, and opened panels.
- Removing nodes from a map remains non-destructive.
- `Add Start` is always visible and standalone; it is not a special finder row or warning state.
- `Add Start` is idempotent and calls the active map's `load-by-key` for `"start"`.
- If `start` exists in the active map, it appears in the finder like any other node.
- Finder results are derived only from nodes currently present in the active `GraphMap`.
- Single-clicking a finder result selects, focuses, and centers the node.
- Double-clicking a finder result opens the node panel/view after the same reveal behavior.
- GraphView reveal/open methods do not load graph map nodes; they assert on missing nodes or missing required context.
- Do not add direct `app.graph-view` references inside `graph/map-sidebar.fnl`.
- Fennel style: use `local` instead of `let`, prefer multi-branch `if`, use factory functions instead of `.new`, and assert missing required context instead of silently falling back.
- Validation order for Fennel work: compile check, constraints, focused tests, broader relevant suite when required.

---

## File Structure

- `assets/lua/graph/view/init.fnl`: add `view.camera`, `view:reveal-node`, and `view:open-node`. Reuse existing registry, selection, focus nodes, and `bounds-for-presentation` helper.
- `assets/lua/tests/test-graph-view.fnl`: add focused tests for reveal/open behavior.
- `assets/lua/graph/map-sidebar.fnl`: render `Add Start`; collect active-map node rows; build searchable finder rows; invoke reveal/open callbacks.
- `assets/lua/tests/test-graph-map-sidebar.fnl`: add focused tests for `Add Start`, finder contents, map switching, and finder click callbacks.
- `assets/lua/graph-activity-unit.fnl`: pass sidebar callbacks that route to the active `GraphView`.
- `assets/lua/tests/test-graph-activity-slots.fnl`: run the existing graph activity slot suite after wiring callbacks.
- `docs/dev/graph-maps.md`: document the implemented sidebar finder and `Add Start` semantics.

---

### Task 1: GraphView Reveal and Open APIs

**Files:**
- Modify: `assets/lua/graph/view/init.fnl`
- Test: `assets/lua/tests/test-graph-view.fnl`

**Interfaces:**
- Consumes: `graph-map:lookup(key)`, `selection:set-selection(nodes)`, `focus-node:request-focus()`, `views:open(node)`, `bounds-for-presentation(presentation)`, `options.camera`.
- Produces: `view.camera`, `view:reveal-node(node-or-key, opts) -> table`, `view:open-node(node-or-key, opts) -> boolean`.

- [ ] **Step 1: Add a camera test helper in `test-graph-view.fnl`**

  Add this helper near other graph-view test helpers:

  ```fennel
  (fn make-test-camera [position]
      (local camera {:position (or position (glm.vec3 10 20 100))})
      (set camera.set-position
           (fn [self next-position]
               (set self.position next-position)))
      camera)
  ```

- [ ] **Step 2: Add a focused failing reveal test**

  Add this test function after nearby GraphView construction tests:

  ```fennel
  (fn graph-view-reveal-node-selects-focuses-and-centers []
      (local graph (Graph {:with-start false}))
      (local graph-map (GraphMap.GraphMap {:graph graph :id "main" :name "Main"}))
      (local node (Graph.GraphNode {:key "test:alpha" :label "Alpha"}))
      (graph-map:add-node node)
      (local camera (make-test-camera (glm.vec3 10 20 100)))
      (local ctx (make-ctx))
      (local view (GraphView {:graph-map graph-map
                              :ctx ctx
                              :camera camera
                              :data-dir "/tmp/space/tests/graph-view-reveal"}))
      (local point (. view.points node))
      (assert point "GraphView should create a presentation for the node")
      (point:set-position (glm.vec3 42 24 0))
      (view:reveal-node node)
      (assert (= (length view.selection.selected-nodes) 1)
              "reveal-node should select exactly one node")
      (assert (= (. view.selection.selected-nodes 1) node)
              "reveal-node should select the requested node")
      (assert (= (ctx.focus.manager:get-focused-node) (. view.focus-nodes node))
              "reveal-node should request focus for the requested node")
      (assert (= camera.position.x 42) "reveal-node should center camera x on compact node")
      (assert (= camera.position.y 24) "reveal-node should center camera y on compact node")
      (assert (= camera.position.z 100) "reveal-node should preserve camera z")
      (view:drop)
      (graph-map:drop)
      (graph:drop))
  ```

- [ ] **Step 3: Register and run the reveal test to verify it fails**

  Add the registration near the other `table.insert tests` calls:

  ```fennel
  (table.insert tests {:name "GraphView reveal-node selects focuses and centers"
                       :fn graph-view-reveal-node-selects-focuses-and-centers})
  ```

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  ```

  Expected: FAIL because `reveal-node` is not defined.

- [ ] **Step 4: Add a focused failing open test**

  Add this test function after the reveal test:

  ```fennel
  (fn graph-view-open-node-reveals-and-opens []
      (var opened-count 0)
      (fn TestNodeView [_node]
          (fn [_ctx]
              (set opened-count (+ opened-count 1))
              {:layout (Layout {:name "test-node-view"})
               :drop (fn [_self])}))
      (local graph (Graph {:with-start false}))
      (local graph-map (GraphMap.GraphMap {:graph graph :id "main" :name "Main"}))
      (local node (Graph.GraphNode {:key "test:open" :label "Open Me" :view TestNodeView}))
      (graph-map:add-node node)
      (local camera (make-test-camera (glm.vec3 0 0 75)))
      (local ctx (make-ctx))
      (local view (GraphView {:graph-map graph-map
                              :ctx ctx
                              :camera camera
                              :data-dir "/tmp/space/tests/graph-view-open"}))
      (local result (view:open-node "test:open"))
      (assert (= result true) "open-node should return true when it opens a node")
      (assert (= (length view.selection.selected-nodes) 1)
              "open-node should reveal/select the node before opening")
      (assert (= (. view.selection.selected-nodes 1) node)
              "open-node should select the opened node")
      (assert (= opened-count 1) "open-node should build the node view once")
      (view:drop)
      (graph-map:drop)
      (graph:drop))
  ```

- [ ] **Step 5: Register and run the open test to verify it fails**

  Add:

  ```fennel
  (table.insert tests {:name "GraphView open-node reveals and opens"
                       :fn graph-view-open-node-reveals-and-opens})
  ```

  Run the same `tests.test-graph-view:main` command. Expected: FAIL because `open-node` is not defined.

- [ ] **Step 6: Add node resolution and center helpers in `graph/view/init.fnl`**

  Add helper functions near the existing public method setup, before `(set view.remove-nodes ...)`:

  ```fennel
  (fn resolve-view-node [node-or-key]
      (local node
          (if (= (type node-or-key) :string)
              (graph-map:lookup node-or-key)
              node-or-key))
      (assert node "GraphView reveal/open requires an existing graph-map node")
      (assert (. registry.points node)
              (.. "GraphView reveal/open requires mounted node: " (tostring node.key)))
      node)

  (fn presentation-center [presentation]
      (local bounds (bounds-for-presentation presentation))
      (assert bounds "GraphView reveal/open requires presentation bounds")
      (local position bounds.position)
      (local size bounds.size)
      (glm.vec3 (+ position.x (* size.x 0.5))
                (+ position.y (* size.y 0.5))
                (+ position.z (* size.z 0.5))))

  (fn center-camera-on-node! [node]
      (local camera options.camera)
      (assert camera "GraphView reveal-node requires :camera")
      (assert camera.position "GraphView reveal-node requires camera.position")
      (assert camera.set-position "GraphView reveal-node requires camera:set-position")
      (local center (presentation-center (. registry.points node)))
      (camera:set-position (glm.vec3 center.x center.y camera.position.z)))
  ```

- [ ] **Step 7: Add `camera`, `reveal-node`, and `open-node` to the view object**

  In the `view` literal, add:

  ```fennel
  :camera options.camera
  ```

  Add public methods near `remove-selected-nodes`:

  ```fennel
  (set view.reveal-node
       (fn [_self node-or-key opts]
           (assert-not-dropped "reveal-node")
           (local options (or opts {}))
           (local node (resolve-view-node node-or-key))
           (when (not (= options.select? false))
               (selection:set-selection [node]))
           (when (not (= options.focus? false))
               (local focus-node (. focus-nodes node))
               (assert focus-node "GraphView reveal-node requires focus node")
               (focus-node:request-focus))
           (when (not (= options.center? false))
               (center-camera-on-node! node))
           node))

  (set view.open-node
       (fn [self node-or-key opts]
           (assert-not-dropped "open-node")
           (local node (self:reveal-node node-or-key opts))
           (views:open node)
           true))
  ```

- [ ] **Step 8: Run Task 1 validation**

  Run:

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  ```

  If `./build/space` is missing or stale, run `make build` with timeout `14400000` before direct runtime tests.

---

### Task 2: Sidebar Add Start Button and Node Finder

**Files:**
- Modify: `assets/lua/graph/map-sidebar.fnl`
- Test: `assets/lua/tests/test-graph-map-sidebar.fnl`

**Interfaces:**
- Consumes: `manager:get-active-map() -> GraphMap`, `GraphMap.nodes`, `GraphMap:load-by-key(key) -> node|nil`, `SearchView`, `Button:on-click`, `Button:on-double-click`, optional `node-reveal-handler(node, event)`, optional `node-open-handler(node, event)`.
- Produces: sidebar-visible `Add Start`, sidebar-visible `Find Node`, searchable active-map node rows, single-click reveal callback, double-click open callback.

- [ ] **Step 1: Add a sidebar start-loader test helper**

  In `test-graph-map-sidebar.fnl`, add this helper near existing test helpers:

  ```fennel
  (fn register-start-loader [graph]
      (when (not (graph:has-key-loader-for-key "start"))
          (graph:register-key-loader "start"
              (fn [_key]
                  (Graph.GraphNode {:key "start" :label "start"})))))
  ```

- [ ] **Step 2: Add a failing `Add Start` test**

  Add:

  ```fennel
  (fn sidebar-add-start-is-visible-and-idempotent []
      (local graph (Graph {:with-start false}))
      (register-start-loader graph)
      (local manager (GraphMapManager.GraphMapManager {:graph graph}))
      (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                                :hoverables (make-hoverables-stub)}))
      (local entity ((GraphMapSidebar.GraphMapSidebar {:manager manager}) ctx))
      (entity:update)
      (assert (contains-label? (entity:visible-labels) "Add Start")
              "Sidebar should expose Add Start")
      (local button (find-clickable-by-label "Add Start"))
      (assert button "Add Start should be a clickable button")
      (local active (manager:get-active-map))
      (assert (= (active:lookup "start") nil) "start should begin absent")
      (button:on-click {})
      (entity:update)
      (assert (active:lookup "start") "Add Start should load start")
      (local count-after-first (active:node-count))
      (button:on-click {})
      (entity:update)
      (assert (= (active:node-count) count-after-first)
              "Add Start should not duplicate existing start")
      (entity:drop)
      (manager:drop)
      (graph:drop))
  ```

- [ ] **Step 3: Register and run the Add Start test to verify it fails**

  Add:

  ```fennel
  (table.insert tests {:name "GraphMap sidebar Add Start is visible and idempotent"
                       :fn sidebar-add-start-is-visible-and-idempotent})
  ```

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-sidebar:main
  ```

  Expected: FAIL because `Add Start` is not rendered.

- [ ] **Step 4: Add a failing finder contents and map switch test**

  Add:

  ```fennel
  (fn sidebar-node-finder-lists-active-map-nodes []
      (local graph (Graph {:with-start false}))
      (graph:register-key-loader "test"
          (fn [key]
              (Graph.GraphNode {:key key :label (.. "Node " key)})))
      (local manager (GraphMapManager.GraphMapManager {:graph graph}))
      (local active (manager:get-active-map))
      (active:load-by-key "test:a")
      (active:load-by-key "test:b")
      (manager:create-map! "empty" "Empty")
      (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                                :hoverables (make-hoverables-stub)}))
      (local entity ((GraphMapSidebar.GraphMapSidebar {:manager manager}) ctx))
      (entity:update)
      (assert (contains-label? (entity:visible-labels) "Find Node")
              "Sidebar should expose Find Node")
      (assert (contains-label? (entity:visible-labels) "Node test:a")
              "Finder should include first active-map node")
      (assert (contains-label? (entity:visible-labels) "Node test:b")
              "Finder should include second active-map node")
      (manager:switch-map! "empty")
      (entity:update)
      (assert (not (contains-label? (entity:visible-labels) "Node test:a"))
              "Finder should drop nodes from previous active map")
      (entity:drop)
      (manager:drop)
      (graph:drop))
  ```

- [ ] **Step 5: Register and run the finder contents test to verify it fails**

  Add:

  ```fennel
  (table.insert tests {:name "GraphMap sidebar node finder lists active map nodes"
                       :fn sidebar-node-finder-lists-active-map-nodes})
  ```

  Run the same `tests.test-graph-map-sidebar:main` command. Expected: FAIL because `Find Node` is not rendered.

- [ ] **Step 6: Add a failing finder click callback test**

  Add:

  ```fennel
  (fn sidebar-node-finder-clicks-route_callbacks []
      (local graph (Graph {:with-start false}))
      (graph:register-key-loader "test"
          (fn [key]
              (Graph.GraphNode {:key key :label "Clickable Node"})))
      (local manager (GraphMapManager.GraphMapManager {:graph graph}))
      (local active (manager:get-active-map))
      (local node (active:load-by-key "test:click"))
      (var revealed-key nil)
      (var opened-key nil)
      (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                                :hoverables (make-hoverables-stub)}))
      (local entity
          ((GraphMapSidebar.GraphMapSidebar
             {:manager manager
              :node-reveal-handler (fn [clicked-node _event]
                                     (set revealed-key clicked-node.key))
              :node-open-handler (fn [clicked-node _event]
                                   (set opened-key clicked-node.key))})
           ctx))
      (entity:update)
      (local button (find-clickable-by-label "Clickable Node"))
      (assert button "Finder row should render a clickable button")
      (button:on-click {:button 1})
      (assert (= revealed-key node.key) "Single click should route reveal callback")
      (button:on-double-click {:button 1})
      (assert (= opened-key node.key) "Double click should route open callback")
      (entity:drop)
      (manager:drop)
      (graph:drop))
  ```

- [ ] **Step 7: Register and run the callback test to verify it fails**

  Add:

  ```fennel
  (table.insert tests {:name "GraphMap sidebar node finder clicks route callbacks"
                       :fn sidebar-node-finder-clicks-route_callbacks})
  ```

  Run the same `tests.test-graph-map-sidebar:main` command. Expected: FAIL because finder rows do not exist.

- [ ] **Step 8: Add imports and callback options in `graph/map-sidebar.fnl`**

  Add at the top:

  ```fennel
  (local SearchView (require :search-view))
  ```

  Add after `selected-count-provider`:

  ```fennel
  (local node-reveal-handler options.node-reveal-handler)
  (local node-open-handler options.node-open-handler)
  ```

- [ ] **Step 9: Add active-map node helpers in `graph/map-sidebar.fnl`**

  Add inside `build`, near `current-selected-count`:

  ```fennel
  (fn node-display-label [node]
      (tostring (or node.label node.key)))

  (fn active-node-items []
      (local items [])
      (when active-map
          (each [_ node (pairs (or active-map.nodes {}))]
              (when node
                  (table.insert items [node (node-display-label node)]))))
      (table.sort items
                  (fn [a b]
                      (< (tostring (. a 2)) (tostring (. b 2)))))
      items)
  ```

- [ ] **Step 10: Add the standalone `Add Start` builder**

  Add inside `rebuild-children`, near other local builder functions:

  ```fennel
  (fn build-add-start []
      (build-action-button
        "Add Start"
        (fn [_button _event]
            (local current-map (assert (manager:get-active-map)
                                       "Add Start requires an active graph map"))
            (local node (current-map:load-by-key "start"))
            (assert node "Add Start failed to load graph key: start")
            (request-rebuild {:cause :add-start}))
        true))
  ```

- [ ] **Step 11: Add finder row and finder section builders**

  Add inside `rebuild-children`, after `build-add-start`:

  ```fennel
  (fn build-node-row [item ic]
      (local node (. item 1))
      (local label (tostring (. item 2)))
      (record-label label)
      ((Button {:text label
                :padding [0.2 0.25]
                :focusable? true
                :variant :ghost
                :on-click (fn [_button event]
                            (when node-reveal-handler
                                (node-reveal-handler node event)))
                :on-double-click (fn [_button event]
                                   (when node-open-handler
                                       (node-open-handler node event)))})
       ic))

  (fn build-finder []
      (fn [ic]
          ((Padding {:edge-insets [0.15 0.25 0.25 0.25]
                     :child (fn [ic2]
                              ((SearchView {:items (active-node-items)
                                            :placeholder "Find node"
                                            :items-per-page 8
                                            :show-head false
                                            :builder (fn [item row-ctx]
                                                       (build-node-row item row-ctx))})
                               ic2))})
            ic)))
  ```

  The custom builder signature matches `SearchView`, which calls custom builders as `(builder item child-ctx)`.

- [ ] **Step 12: Insert Add Start and finder rows into sidebar content**

  Update `content-children` assembly so the order is title, map actions, switch title, map rows, separator, `Add Start`, selected count, `Find Node`, finder:

  ```fennel
  (table.insert content-children (FlexChild (build-separator) 0))
  (table.insert content-children (FlexChild (build-add-start) 0))
  (table.insert content-children (FlexChild (build-selected-count) 0))
  (table.insert content-children
                (FlexChild (fn [ic]
                             ((Padding {:edge-insets [0.05 0.25 0.1 0.25]
                                        :child (text-builder "Find Node" muted-color 0.72)})
                              ic))
                           0))
  (table.insert content-children (FlexChild (build-finder) 1))
  ```

  Remove the old direct insertion that placed selected count immediately after the separator.

- [ ] **Step 13: Run Task 2 validation**

  Run:

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-sidebar:main
  ```

  If layout-order tests fail because the sidebar now contains more rows, update only the expected child indices in `sidebar-map-rows-do-not-stretch-to-full-panel-height` so the map row still asserts against the active map row.

---

### Task 3: Activity Wiring and Graph Maps Documentation

**Files:**
- Modify: `assets/lua/graph-activity-unit.fnl`
- Modify: `docs/dev/graph-maps.md`
- Test: existing `assets/lua/tests/test-graph-activity-slots.fnl` suite

**Interfaces:**
- Consumes: `GraphMapSidebar.GraphMapSidebar {:manager manager :selected-count-provider fn :node-reveal-handler fn :node-open-handler fn}`, `GraphView:reveal-node(node-or-key, opts) -> table`, `GraphView:open-node(node-or-key, opts) -> boolean`.
- Produces: activity-owned callbacks that connect finder row clicks to the active graph view.

- [ ] **Step 1: Add local active graph view helper in `graph-activity-unit.fnl`**

  Add near `active-graph-map`:

  ```fennel
  (fn active-graph-view []
    (local world-runtime app.active-world-runtime)
    (or (and world-runtime world-runtime.graph-view)
        app.graph-view))
  ```

- [ ] **Step 2: Pass reveal/open callbacks to `GraphMapSidebar`**

  In `graph-left-dock-builder`, extend the options table:

  ```fennel
  :node-reveal-handler
  (fn [node _event]
    (local graph-view (assert (active-graph-view)
                              "Graph sidebar reveal requires active graph view"))
    (graph-view:reveal-node node {:select? true :focus? true :center? true}))
  :node-open-handler
  (fn [node _event]
    (local graph-view (assert (active-graph-view)
                              "Graph sidebar open requires active graph view"))
    (graph-view:open-node node {:select? true :focus? true :center? true}))
  ```

- [ ] **Step 3: Keep activity wiring tests at the existing suite boundary**

  Do not add brittle assertions against private sidebar storage in `test-graph-activity-slots.fnl`. The callback contract is covered by `test-graph-map-sidebar.fnl`; this suite remains the activity activation guard. Run it after Step 2 to catch syntax errors, missing helper references, and graph slot regressions:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
  ```

- [ ] **Step 4: Update `docs/dev/graph-maps.md` sidebar UX section**

  In `## Sidebar UX`, add bullets after active map stats / selected count:

  ```markdown
  - `Add Start` action, always visible and idempotent; it adds the `start` node to the active map when absent and does not duplicate it when present.
  - `Find Node` search/list for nodes in the active map.
  - Finder single-click reveals a node by selecting, focusing, and centering it in the active GraphView.
  - Finder double-click opens the node panel/view after reveal behavior.
  ```

  In `## Action Semantics`, add:

  ```markdown
  `Add Start` is map membership recovery, not automatic start-node re-seeding. It uses the `start` key loader through the active `GraphMap` and does not delete or mutate backing domain objects.
  ```

- [ ] **Step 5: Run Task 3 validation**

  Run:

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-sidebar:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  ```

---

### Task 4: Broader Graph UX Validation

**Files:**
- Modify: none
- Test: graph and fast Fennel suites

**Interfaces:**
- Consumes: completed Task 1, Task 2, and Task 3 changes.
- Produces: validation evidence for the branch handoff and PR readiness.

- [ ] **Step 1: Run compile check first**

  Run:

  ```bash
  make fennel-check
  ```

  Expected: PASS.

- [ ] **Step 2: Run constraints second**

  Run:

  ```bash
  make constraints
  ```

  Expected: PASS.

- [ ] **Step 3: Run focused graph tests**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-sidebar:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
  ```

  Expected: PASS.

- [ ] **Step 4: Run broader relevant local suite**

  Because this change touches public `GraphView` APIs, graph activity wiring, and sidebar widgets, run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  ```

  Expected: PASS.

- [ ] **Step 5: Record validation evidence**

  In the implementation handoff, report commands and results in this order:

  ```text
  Fennel compile: make fennel-check -> PASS
  Constraints: make constraints -> PASS
  Focused tests: tests.test-graph-view:main, tests.test-graph-map-sidebar:main, tests.test-graph-activity-slots:main -> PASS
  Broader graph/UI confidence: tests.fast:main -> PASS
  Constraint impact: not applicable unless baseline data changed
  ```
