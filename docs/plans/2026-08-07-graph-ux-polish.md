# Graph UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize graph sidebar layout, add restrained theme-based graph/chrome backgrounds, and fix restored float graph map id creation.

**Architecture:** Keep graph ownership boundaries unchanged: `GraphMapManager` normalizes map manager state, `GraphMapSidebar` owns only sidebar presentation, and graph topology/persistence shape remains unchanged except for integer-like `next_map_id` normalization. Theme/chrome colors are resolved through a small shared helper in `widget-theme-utils.fnl`; graph activity applies `theme.graph.background` through the existing scene activity slot path.

**Tech Stack:** Space Fennel modules and tests under `assets/lua`, project-native Fennel validation via `tools.fennel-check`, constraints, focused Fennel test modules, and the CMake-built `./build/space` runtime.

## Global Constraints

- No global `Text` or `Button` overflow/truncation engine.
- No user-configurable graph sidebar width.
- No changes to graph topology or map persistence semantics beyond normalizing restored integer ids.
- No relaxing of `safe-map-id?`; map ids remain dot-free for metadata path safety.
- No broad theme redesign or pixel-perfect color tuning.
- GraphMap owns interaction context; GraphView owns visual state; graph core topology remains unchanged.
- Sidebar truncation must be display-only; search source labels and click/open callbacks keep full node data.
- Missing required graph/sidebar context remains an assertion failure.
- Graph activity background fallbacks must be neutral grey, not black.
- Use project-native Fennel validation only: `make fennel-check`, `make constraints`, and `./build/space -m ...` test commands with `FENNEL_PATH`, `FENNEL_MACRO_PATH`, `SPACE_ASSETS_PATH`, `SPACE_DISABLE_AUDIO=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, and `SKIP_KEYRING_TESTS=1` when applicable.
- If `./build/space` is missing or stale, run `make build` with a 4-hour timeout before direct runtime test commands.

---

## File Structure

- Modify `assets/lua/graph/map-manager.fnl`: normalize valid integral numeric `next_map_id` values to integer-like numbers in `ensure-int`; preserve strict id validation and captured state shape.
- Modify `assets/lua/tests/test-graph-map-manager.fnl`: add manager-level regression coverage for restored `next_map_id = 2.0`.
- Modify `assets/lua/graph/map-sidebar.fnl`: add fixed width, integer id formatting for `New`, local ellipsis for map/finder labels, finder/content stretching, and shared chrome panel background resolution.
- Modify `assets/lua/tests/test-graph-map-sidebar.fnl`: add sidebar regression coverage for `New`, fixed width, display labels, preserved full finder data, and empty finder layout.
- Modify `assets/lua/widget-theme-utils.fnl`: export a shared `resolve-chrome-background` helper for `:rail` and `:panel` backgrounds with conservative fallbacks.
- Modify `assets/lua/dark-theme.fnl` and `assets/lua/light-theme.fnl`: add `theme.graph.background`, `theme.chrome.rail-background`, and `theme.chrome.panel-background` tokens.
- Modify `assets/lua/activity-dock-view.fnl` and `assets/lua/hud-extended-sidebar-view.fnl`: route duplicated rail/panel background logic through the shared chrome resolver.
- Modify `assets/lua/tests/test-theme-widgets.fnl`: add shared chrome resolver token/fallback tests.
- Modify `assets/lua/graph-activity-unit.fnl`: apply active theme graph background to the graph scene activity slot before activation.
- Modify `assets/lua/tests/test-graph-activity-slots.fnl`: assert graph activation uses the theme graph background instead of black while preserving scene isolation.

---

### Task 1: Graph Map Manager Integer Normalization

**Files:**
- Modify: `assets/lua/graph/map-manager.fnl`
- Test: `assets/lua/tests/test-graph-map-manager.fnl`

**Interfaces:**
- Consumes: `GraphMapManager.GraphMapManager {:graph graph :state state}`.
- Produces: `manager.next-map-id` and `manager:capture-state().next_map_id` normalize integral numbers such as `2.0` to integer-like `2`; `safe-map-id?` remains strict.

- [ ] **Step 1: Write failing manager tests**

  Add these tests to `assets/lua/tests/test-graph-map-manager.fnl` near the existing restored-state or capture-state tests:

  ```fennel
  (fn manager-normalizes-integral-float-next-map-id []
      (local graph (Graph {:with-start false}))
      (local manager
        (GraphMapManager.GraphMapManager
          {:graph graph
           :state {:active_map_id "main"
                   :next_map_id 2.0
                   :maps [{:id "main" :name "Main" :nodes [] :edges []}]}}))
      (assert (= manager.next-map-id 2)
              "Restored integral float next_map_id should normalize to 2")
      (assert (= (tostring manager.next-map-id) "2")
              "Normalized next-map-id should stringify without .0")
      (manager:drop)
      (graph:drop))

  (fn manager-captures-normalized-next-map-id []
      (local graph (Graph {:with-start false}))
      (local manager
        (GraphMapManager.GraphMapManager
          {:graph graph
           :state {:active_map_id "main"
                   :next_map_id 2.0
                   :maps [{:id "main" :name "Main" :nodes [] :edges []}]}}))
      (local captured (manager:capture-state))
      (assert (= captured.next_map_id 2)
              "Captured next_map_id should remain integer-like")
      (assert (= (tostring captured.next_map_id) "2")
              "Captured next_map_id should stringify without .0")
      (manager:drop)
      (graph:drop))
  ```

  Register them with exact names:

  ```fennel
  (table.insert tests {:name "GraphMapManager normalizes integral float next-map-id"
                       :fn manager-normalizes-integral-float-next-map-id})
  (table.insert tests {:name "GraphMapManager captures normalized next-map-id"
                       :fn manager-captures-normalized-next-map-id})
  ```

- [ ] **Step 2: Run the focused manager test and confirm failure**

  ```bash
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  ./build/space -m tests.test-graph-map-manager:main
  ```

  Expected before implementation: the new normalization/stringification assertion fails for restored `2.0`.

- [ ] **Step 3: Implement integer normalization**

  In `assets/lua/graph/map-manager.fnl`, update `ensure-int` so valid integral numeric values return `(math.floor v)`:

  ```fennel
  (fn ensure-int [v default]
      (if (and (= (type v) :number)
               (>= v 1)
               (= v (math.floor v)))
          (math.floor v)
          default))
  ```

- [ ] **Step 4: Verify the manager test passes**

  Run the same `tests.test-graph-map-manager:main` command from Step 2.

  Expected: PASS, including the two new tests.

- [ ] **Step 5: Run Fennel gates for this task**

  ```bash
  make fennel-check
  make constraints
  ```

  Expected: both pass.

- [ ] **Step 6: Commit Task 1**

  ```bash
  git add assets/lua/graph/map-manager.fnl assets/lua/tests/test-graph-map-manager.fnl
  git commit -m "fix(graph): normalize restored graph map ids"
  ```

  Include a commit body with impact, what/why/how, focused test evidence, and `Constraint impact: not applicable` unless constraints report a meaningful effect.

---

### Task 2: Fixed Sidebar Width and Local Display Ellipsis

**Files:**
- Modify: `assets/lua/graph/map-sidebar.fnl`
- Test: `assets/lua/tests/test-graph-map-sidebar.fnl`

**Interfaces:**
- Consumes: normalized `manager.next-map-id` from Task 1; `GraphViewUtils.truncate-with-ellipsis(text, max-length)`.
- Produces: graph sidebar root measure/layout width remains fixed at `14.0`; `New` creates `map-2` not `map-2.0`; row display labels are truncated locally; finder search data preserves full labels.

- [ ] **Step 1: Write failing sidebar regression tests**

  Add helpers to `assets/lua/tests/test-graph-map-sidebar.fnl` after `contains-label?`:

  ```fennel
  (fn approx [a b]
      (< (math.abs (- a b)) 0.001))

  (fn layout-sidebar! [entity width height]
      (set entity.layout.size (glm.vec3 width height 0))
      (entity.layout:measurer)
      (entity.layout:layouter))

  (fn finder-layout [entity]
      (local stack-layout (. entity.layout.children 1))
      (local flex-layout (. stack-layout.children 2))
      (. flex-layout.children (length flex-layout.children)))
  ```

  Add these tests before the registration block:

  ```fennel
  (fn sidebar-new-button-uses-integer-map-id-after-restored-float []
      (local graph (Graph {:with-start false}))
      (local manager
        (GraphMapManager.GraphMapManager
          {:graph graph
           :state {:active_map_id "main"
                   :next_map_id 2.0
                   :maps [{:id "main" :name "Main" :nodes [] :edges []}]}}))
      (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                                :hoverables (make-hoverables-stub)}))
      (local entity ((GraphMapSidebar.GraphMapSidebar {:manager manager}) ctx))
      (entity:update)
      (local new-button (find-clickable-by-label "New"))
      (assert new-button "Sidebar should render a New button")
      (local (ok err) (pcall (fn [] (new-button:on-click {}))))
      (assert ok (.. "New button should not crash with restored next_map_id=2.0: " (tostring err)))
      (assert (= manager.active-map-id "map-2")
              "New button should switch to map-2, not map-2.0")
      (entity:drop)
      (manager:drop)
      (graph:drop))

  (fn sidebar-width-stays-fixed-with-long-labels []
      (local graph (Graph {:with-start false}))
      (graph:register-key-loader "test"
          (fn [key]
              (Graph.GraphNode {:key key
                                :label "A graph node label that is deliberately long enough to exceed the sidebar width by many characters"})))
      (local manager (GraphMapManager.GraphMapManager {:graph graph}))
      (manager:rename-map! "main" "A graph map name that is deliberately long enough to exceed the sidebar width by many characters")
      ((manager:get-active-map):load-by-key "test:long")
      (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                                :hoverables (make-hoverables-stub)}))
      (local entity ((GraphMapSidebar.GraphMapSidebar {:manager manager}) ctx))
      (entity:update)
      (entity.layout:measurer)
      (assert (approx entity.layout.measure.x 14.0)
              (.. "Sidebar measure should be fixed at 14.0, got " (tostring entity.layout.measure.x)))
      (layout-sidebar! entity 14.0 24.0)
      (assert (approx entity.layout.size.x 14.0)
              "Sidebar layout width should stay fixed at 14.0")
      (entity:drop)
      (manager:drop)
      (graph:drop))

  (fn sidebar-truncates-display-labels-and-preserves-finder-data []
      (local graph (Graph {:with-start false}))
      (local long-node-label "A finder node label that remains searchable in full but displays with an ellipsis")
      (graph:register-key-loader "test"
          (fn [key]
              (Graph.GraphNode {:key key :label long-node-label})))
      (local manager (GraphMapManager.GraphMapManager {:graph graph}))
      (manager:rename-map! "main" "A graph map name that displays with an ellipsis in the sidebar row")
      (local node ((manager:get-active-map):load-by-key "test:long"))
      (var revealed-label nil)
      (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                                :hoverables (make-hoverables-stub)}))
      (local entity
        ((GraphMapSidebar.GraphMapSidebar
           {:manager manager
            :node-reveal-handler (fn [clicked-node _event]
                                   (set revealed-label clicked-node.label))})
         ctx))
      (entity:update)
      (local labels (entity:visible-labels))
      (assert (contains-label? labels "A graph map name that di...")
              "Map row display label should be truncated with ellipsis")
      (assert (contains-label? labels "A finder node label tha...")
              "Finder row display label should be truncated with ellipsis")
      (local button (find-clickable-by-label "A finder node label tha..."))
      (assert button "Truncated finder row should be clickable")
      (button:on-click {:button 1})
      (assert (= revealed-label node.label)
              "Finder callback should receive node with full label")
      (entity:drop)
      (manager:drop)
      (graph:drop))

  (fn sidebar-empty-finder-fills-fixed-content-width []
      (local graph (Graph {:with-start false}))
      (local manager (GraphMapManager.GraphMapManager {:graph graph}))
      (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                                :hoverables (make-hoverables-stub)}))
      (local entity ((GraphMapSidebar.GraphMapSidebar {:manager manager}) ctx))
      (entity:update)
      (layout-sidebar! entity 14.0 24.0)
      (local layout (finder-layout entity))
      (assert (> layout.size.x 13.0)
              (.. "Finder area should fill fixed sidebar content width, got " (tostring layout.size.x)))
      (entity:drop)
      (manager:drop)
      (graph:drop))
  ```

  Register exact names:

  ```fennel
  (table.insert tests {:name "GraphMap sidebar New uses integer map id after restored float"
                       :fn sidebar-new-button-uses-integer-map-id-after-restored-float})
  (table.insert tests {:name "GraphMap sidebar width stays fixed with long labels"
                       :fn sidebar-width-stays-fixed-with-long-labels})
  (table.insert tests {:name "GraphMap sidebar truncates display labels and preserves finder data"
                       :fn sidebar-truncates-display-labels-and-preserves-finder-data})
  (table.insert tests {:name "GraphMap sidebar empty finder fills fixed content width"
                       :fn sidebar-empty-finder-fills-fixed-content-width})
  ```

- [ ] **Step 2: Run focused sidebar tests and confirm failure**

  ```bash
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  ./build/space -m tests.test-graph-map-sidebar:main
  ```

  Expected before implementation: at least the restored float `New` test or fixed-width assertions fail.

- [ ] **Step 3: Add sidebar imports, constants, and helpers**

  In `assets/lua/graph/map-sidebar.fnl`, add imports:

  ```fennel
  (local GraphViewUtils (require :graph/view/utils))
  ```

  Add constants near the `var` declarations:

  ```fennel
  (local sidebar-width 14.0)
  (local map-label-max-length 26)
  (local finder-label-max-length 24)
  ```

  Add helpers near `map-row-label`:

  ```fennel
  (fn ellipsize [label max-length]
      (GraphViewUtils.truncate-with-ellipsis (tostring (or label "")) max-length))

  (fn map-row-display-label [entry active-id]
      (ellipsize (map-row-label entry active-id) map-label-max-length))

  (fn finder-display-label [label]
      (ellipsize label finder-label-max-length))
  ```

- [ ] **Step 4: Fix New id formatting and display-only labels**

  Make these changes in `assets/lua/graph/map-sidebar.fnl`:

  ```fennel
  ;; handle-new-map
  (local sid (string.format "map-%d" (math.floor state.manager.next-map-id)))
  ```

  ```fennel
  ;; build-map-row
  (local label (record-label state (map-row-display-label entry active-id)))
  ```

  ```fennel
  ;; build-node-row
  (local node (. item 1))
  (local full-label (tostring (. item 2)))
  (local label (record-label state (finder-display-label full-label)))
  ((Button {:text label
            :padding [0.2 0.25]
            :focusable? true
            :variant :ghost
            :on-click (reveal-handler state node)
            :on-double-click (open-handler state node)})
   ic)
  ```

  Keep `active-node-items` as `[node (node-display-label node)]` so search/sort source data remains full label text.

- [ ] **Step 5: Fix sidebar width and finder stretch**

  In `assets/lua/graph/map-sidebar.fnl`, update layout behavior:

  ```fennel
  ;; build-content-flex options include stretch on the x axis if Flex supports it in this module.
  ((Flex {:axis 2
          :spacing 0.0
          :xalign :stretch
          :children (content-children state maps state.manager.active-map-id (length maps) selected-count)})
   ic)
  ```

  ```fennel
  ;; sidebar-measurer exports fixed width but preserves measured height/depth.
  (fn sidebar-measurer [state self]
      (if state.content-entity
          (do
              (state.content-entity.layout:measurer)
              (set self.measure (glm.vec3 sidebar-width
                                          state.content-entity.layout.measure.y
                                          state.content-entity.layout.measure.z)))
          (set self.measure (glm.vec3 sidebar-width 0 0))))
  ```

  ```fennel
  ;; sidebar-layouter never expands beyond fixed sidebar-width from child measure.
  (local allocated-size
      (glm.vec3 sidebar-width
                (math.max self.measure.y self-size.y)
                (math.max self.measure.z self-size.z)))
  ```

  If the first pass leaves the empty finder narrower than the fixed sidebar, add a local wrapper helper in `map-sidebar.fnl` and use it only around the finder builder:

  ```fennel
  (fn fixed-width-child [name width child-builder]
      (fn [ic]
          (local child (child-builder ic))
          (fn measurer [self]
              (child.layout:measurer)
              (set self.measure (glm.vec3 width child.layout.measure.y child.layout.measure.z)))
          (fn layouter [self]
              (set child.layout.position self.position)
              (set child.layout.size (glm.vec3 width self.size.y self.size.z))
              (set child.layout.rotation self.rotation)
              (set child.layout.clip-region self.clip-region)
              (set child.layout.depth-offset-index self.depth-offset-index)
              (child.layout:layouter))
          (local layout (Layout {:name name
                                 :measurer measurer
                                 :layouter layouter
                                 :children [child.layout]}))
          {:layout layout
           :drop (fn [_self]
                   (layout:drop)
                   (child:drop))})))
  ```

  Use it in `build-finder` with content width `(- sidebar-width 0.5)`, matching the left/right padding `[0.15 0.25 0.25 0.25]`. Do not change global `SearchView`, `Input`, `Text`, or `Button` overflow semantics for this task.

- [ ] **Step 6: Verify sidebar tests pass**

  Run the `tests.test-graph-map-sidebar:main` command from Step 2.

  Expected: PASS, including the four new tests and existing finder callback tests.

- [ ] **Step 7: Run Fennel gates for this task**

  ```bash
  make fennel-check
  make constraints
  ```

  Expected: both pass.

- [ ] **Step 8: Commit Task 2**

  ```bash
  git add assets/lua/graph/map-sidebar.fnl assets/lua/tests/test-graph-map-sidebar.fnl
  git commit -m "fix(ui): stabilize graph sidebar layout"
  ```

  Include focused test evidence and `Constraint impact: not applicable` unless constraints report a meaningful effect.

---

### Task 3: Shared Chrome Theme Tokens and Resolver

**Files:**
- Modify: `assets/lua/widget-theme-utils.fnl`
- Modify: `assets/lua/dark-theme.fnl`
- Modify: `assets/lua/light-theme.fnl`
- Modify: `assets/lua/activity-dock-view.fnl`
- Modify: `assets/lua/hud-extended-sidebar-view.fnl`
- Test: `assets/lua/tests/test-theme-widgets.fnl`

**Interfaces:**
- Consumes: theme tables and existing `glm.vec4` colors.
- Produces: `resolve-chrome-background(ctx-or-theme, kind, opts) -> glm.vec4`, `theme.chrome.rail-background`, `theme.chrome.panel-background`, and `theme.graph.background`.

- [ ] **Step 1: Write failing resolver tests**

  Update the import in `assets/lua/tests/test-theme-widgets.fnl`:

  ```fennel
  (local {: resolve-qr-colors : resolve-chrome-background} (require :widget-theme-utils))
  ```

  Add tests before the registration block:

  ```fennel
  (fn chrome-background-resolves-theme-tokens []
    (local rail (glm.vec4 0.11 0.12 0.13 1))
    (local panel (glm.vec4 0.21 0.22 0.23 1))
    (local theme {:chrome {:rail-background rail
                           :panel-background panel}
                  :card {:background (glm.vec4 0.31 0.32 0.33 1)}})
    (local ctx (make-test-ctx {:theme theme}))
    (assert (color= (resolve-chrome-background ctx :rail) rail)
            "Rail background should use theme.chrome.rail-background")
    (assert (color= (resolve-chrome-background ctx :panel) panel)
            "Panel background should use theme.chrome.panel-background"))

  (fn chrome-background-falls-back-without-black []
    (local card-bg (glm.vec4 0.4 0.41 0.42 1))
    (local ctx (make-test-ctx {:theme {:card {:background card-bg}}}))
    (local panel (resolve-chrome-background ctx :panel))
    (local rail (resolve-chrome-background nil :rail))
    (assert (color= panel card-bg)
            "Panel fallback should use theme.card.background when present")
    (assert (not (color= rail (glm.vec4 0 0 0 1)))
            "Missing theme rail fallback should not be black"))
  ```

  Register exact names:

  ```fennel
  (table.insert tests {:name "Chrome background resolves theme tokens"
                       :fn chrome-background-resolves-theme-tokens})
  (table.insert tests {:name "Chrome background falls back without black"
                       :fn chrome-background-falls-back-without-black})
  ```

- [ ] **Step 2: Run theme tests and confirm failure**

  ```bash
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  ./build/space -m tests.test-theme-widgets:main
  ```

  Expected before implementation: fails because `resolve-chrome-background` is not exported.

- [ ] **Step 3: Implement and export chrome background resolver**

  In `assets/lua/widget-theme-utils.fnl`, add:

  ```fennel
  (fn theme-from-ctx-or-theme [ctx-or-theme]
    (if (and ctx-or-theme ctx-or-theme.theme)
        ctx-or-theme.theme
        ctx-or-theme))

  (fn resolve-chrome-background [ctx-or-theme kind opts]
    (local options (or opts {}))
    (local theme (theme-from-ctx-or-theme ctx-or-theme))
    (local chrome (and theme theme.chrome))
    (local card (and theme theme.card))
    (local token
      (if (= kind :rail)
          (and chrome chrome.rail-background)
          (and chrome chrome.panel-background)))
    (or options.background-color
        token
        (and card card.background)
        (if (= kind :rail)
            (glm.vec4 0.08 0.1 0.14 0.96)
            (glm.vec4 0.12 0.14 0.18 0.96))))
  ```

  Add to the exported table:

  ```fennel
  :resolve-chrome-background resolve-chrome-background
  ```

- [ ] **Step 4: Add theme tokens**

  In `assets/lua/dark-theme.fnl`, add `:background` to the existing `:graph` table and add a top-level `:chrome` table. Preserve all existing graph keys (`edge-color`, `edge-thickness`, `label-color`, `label-target-pixels`, `label-min-scale`, and `selection-border-color`):

  ```fennel
  :graph {:background (glm.vec4 0.095 0.105 0.13 1)
          :edge-color (glm.vec4 0.36 0.45 0.68 0.9)
          :edge-thickness 4.0
          :label-color text-color
          :label-target-pixels 13.0
          :label-min-scale 4.0
          :selection-border-color (glm.vec4 0.2 0.55 0.95 0.95)}
  :chrome {:rail-background (glm.vec4 0.075 0.09 0.12 0.98)
           :panel-background (glm.vec4 0.12 0.13 0.18 0.98)}
  ```

  In `assets/lua/light-theme.fnl`, add `:background` to the existing `:graph` table and add a top-level `:chrome` table. Preserve all existing graph keys (`edge-color`, `edge-thickness`, `label-color`, `label-target-pixels`, `label-min-scale`, and `selection-border-color`):

  ```fennel
  :graph {:background (glm.vec4 0.91 0.925 0.95 1)
          :edge-color (glm.vec4 0.28 0.34 0.45 0.82)
          :edge-thickness 4.0
          :label-color (glm.vec4 0.22 0.27 0.35 0.95)
          :label-target-pixels 13.0
          :label-min-scale 4.0
          :selection-border-color (glm.vec4 0.18 0.5 0.9 0.9)}
  :chrome {:rail-background (glm.vec4 0.88 0.9 0.935 0.98)
           :panel-background (glm.vec4 0.945 0.958 0.978 0.98)}
  ```

- [ ] **Step 5: Replace duplicated chrome color logic**

  In `assets/lua/activity-dock-view.fnl` and `assets/lua/hud-extended-sidebar-view.fnl`, import the resolver:

  ```fennel
  (local {: resolve-chrome-background} (require :widget-theme-utils))
  ```

  Replace local rail/panel background derivation with calls to:

  ```fennel
  (resolve-chrome-background theme :rail)
  (resolve-chrome-background theme :panel)
  ```

  Remove now-unused `adjust` imports from those two files.

- [ ] **Step 6: Wire graph sidebar to resolver**

  In `assets/lua/graph/map-sidebar.fnl`, import the resolver:

  ```fennel
  (local {: resolve-chrome-background} (require :widget-theme-utils))
  ```

  Replace `panel-bg` body with:

  ```fennel
  (fn panel-bg [state]
      (resolve-chrome-background state.theme :panel))
  ```

- [ ] **Step 7: Verify theme/chrome tests pass**

  Run the `tests.test-theme-widgets:main` command from Step 2.

  Expected: PASS, including the two new chrome tests.

- [ ] **Step 8: Run adjacent HUD chrome tests**

  ```bash
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  ./build/space -m tests.test-hud-chrome-uniformity:main
  ```

  Expected: PASS.

- [ ] **Step 9: Run Fennel gates for this task**

  ```bash
  make fennel-check
  make constraints
  ```

  Expected: both pass.

- [ ] **Step 10: Commit Task 3**

  ```bash
  git add assets/lua/widget-theme-utils.fnl assets/lua/dark-theme.fnl assets/lua/light-theme.fnl assets/lua/activity-dock-view.fnl assets/lua/hud-extended-sidebar-view.fnl assets/lua/graph/map-sidebar.fnl assets/lua/tests/test-theme-widgets.fnl
  git commit -m "feat(ui): add graph chrome theme tokens"
  ```

  Include `assets/lua/graph/map-sidebar.fnl` because Step 6 routes the graph sidebar panel through the resolver.

---

### Task 4: Theme-Based Graph Activity Background

**Files:**
- Modify: `assets/lua/graph-activity-unit.fnl`
- Test: `assets/lua/tests/test-graph-activity-slots.fnl`

**Interfaces:**
- Consumes: `theme.graph.background` from Task 3 and existing scene activity slot state APIs.
- Produces: graph scene slot background uses the active theme graph background during graph activation; sandbox scene isolation and graph view state ownership remain unchanged.

- [ ] **Step 1: Update graph activity background test coverage**

  In `assets/lua/tests/test-graph-activity-slots.fnl`, ensure the local `test-theme` function/table used by this file has:

  ```fennel
  :graph {:background (glm.vec4 0.18 0.19 0.21 1)}
  ```

  In the existing `graph-activity-scene-isolation-prevents-sandbox-inheritance` test, replace the black-background assertion after graph activation with this exact themed assertion:

  ```fennel
  (local graph-background (test-theme).graph.background)
  (assert (and app.background-state
               (= (. app.background-state.color 1) graph-background.x)
               (= (. app.background-state.color 2) graph-background.y)
               (= (. app.background-state.color 3) graph-background.z))
          "Graph activation should apply theme graph background")
  ```

- [ ] **Step 2: Run graph activity tests and confirm failure**

  ```bash
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  ./build/space -m tests.test-graph-activity-slots:main
  ```

  Expected before implementation: `Graph activity scene isolation prevents sandbox inheritance` fails because activation still uses the empty/default black background.

- [ ] **Step 3: Add graph background helpers**

  In `assets/lua/graph-activity-unit.fnl`, add near `clone-table`:

  ```fennel
  (fn active-theme []
    (and app app.themes app.themes.get-active-theme
         (app.themes.get-active-theme)))

  (fn graph-background-state []
    (local theme (active-theme))
    (local background (or (and theme theme.graph theme.graph.background)
                          (glm.vec4 0.095 0.105 0.13 1)))
    {:color [background.x background.y background.z]})
  ```

- [ ] **Step 4: Apply background to graph scene slot before activation**

  In `activate-activity!`, after `(scene:ensure-activity-slot "graph")` and before `(scene:activate-activity-slot "graph")`, update only the graph slot scene background. Use the scene slot/state APIs already present in this file or in `scene.fnl`; preserve existing `panels`, `terrains`, `lights`, `skybox`, and `containment`.

  The implementation should have the effect of:

  ```fennel
  (local state (scene:capture-activity-slot-state "graph"))
  (set state.background (graph-background-state))
  (scene:restore-activity-slot-state "graph" state)
  (scene:activate-activity-slot "graph")
  ```

  If `capture-activity-slot-state` requires an already-active slot in the actual API, instead read the ensured graph slot's state directly and set only its background field before activation.

- [ ] **Step 5: Verify graph activity tests pass**

  Run the `tests.test-graph-activity-slots:main` command from Step 3.

  Expected: PASS, including `Graph activity scene isolation prevents sandbox inheritance`.

- [ ] **Step 6: Run Fennel gates for this task**

  ```bash
  make fennel-check
  make constraints
  ```

  Expected: both pass.

- [ ] **Step 7: Commit Task 4**

  ```bash
  git add assets/lua/graph-activity-unit.fnl assets/lua/tests/test-graph-activity-slots.fnl
  git commit -m "feat(graph): apply themed graph background"
  ```

  Include focused test evidence and `Constraint impact: not applicable` unless constraints report a meaningful effect.

---

### Task 5: Final Validation and Integration Handoff

**Files:**
- Validate: all files touched by Tasks 1-4.

**Interfaces:**
- Consumes: reviewed commits from Tasks 1-4.
- Produces: clean local validation evidence for finishing-a-development-branch and PR creation.

- [ ] **Step 1: Run compile check**

  ```bash
  make fennel-check
  ```

  Expected: PASS.

- [ ] **Step 2: Run constraints**

  ```bash
  make constraints
  ```

  Expected: PASS.

- [ ] **Step 3: Run focused graph/theme tests**

  ```bash
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  ./build/space -m tests.test-graph-map-manager:main
  ```

  ```bash
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  ./build/space -m tests.test-graph-map-sidebar:main
  ```

  ```bash
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  ./build/space -m tests.test-theme-widgets:main
  ```

  ```bash
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  ./build/space -m tests.test-graph-activity-slots:main
  ```

  Expected: all pass.

- [ ] **Step 4: Run broader relevant suite**

  Theme/chrome/activity changes touch adjacent UI surfaces, so run:

  ```bash
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  make test
  ```

  Expected: PASS.

- [ ] **Step 5: Verify acceptance criteria from tests and review**

  Confirm:
  - restored `next_map_id = 2.0` normalizes to integer-like `2`;
  - sidebar `New` creates and switches to `map-2`, never `map-2.0`;
  - `safe-map-id?` remains strict;
  - sidebar exported width is fixed at `14.0`;
  - long map row and finder row display labels use ellipsis;
  - finder callbacks still receive nodes with full labels;
  - empty finder content fills the fixed sidebar width;
  - dark and light themes expose `graph.background`, `chrome.rail-background`, and `chrome.panel-background`;
  - graph activity applies a non-black theme graph background;
  - dock/sidebar rails and panels resolve through `resolve-chrome-background`.

- [ ] **Step 6: Proceed to finishing-a-development-branch**

  After the implementer/reviewer loop passes and all reviewed changes are committed, invoke `finishing-a-development-branch`. That skill must fetch `origin`, evaluate against current `origin/main`, safe-merge `origin/main` if needed, rerun required validation, push the branch, create the PR targeting `main`, and monitor merge queue according to repository policy.

---

## Self-Review

- Spec coverage: Task 1 covers restored float id normalization; Task 2 covers fixed sidebar width, ellipsis, preserved finder data, empty finder width, and `New` formatting; Task 3 covers theme tokens/resolver and rails/panels; Task 4 covers graph canvas background; Task 5 covers validation/integration.
- Placeholder scan: no unresolved placeholders, deferred implementations, or unspecified tests remain.
- Type consistency: produced names are `resolve-chrome-background`, `theme.graph.background`, `theme.chrome.rail-background`, `theme.chrome.panel-background`, and fixed `sidebar-width 14.0`; task references use those same names throughout.
- Doctrine check: plan does not change graph topology, key loaders, or view/map ownership boundaries.
