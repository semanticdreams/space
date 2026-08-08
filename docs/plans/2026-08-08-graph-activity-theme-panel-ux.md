# Graph Activity Theme and Panel UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix graph activity edge theme responsiveness, bounded focused-open node panels, theme-stable graph-map sidebar visibility, and compact inline card titles.

**Architecture:** Keep graph topology and domain persistence untouched. Resolve visual defaults in graph view/layout/presentation code, centralize graph node panel sizing in a small graph-view helper, and repair activity dock lifecycle with an explicit dock-change signal that is independent of workspace-shell activity transitions.

**Tech Stack:** Space Fennel modules under `assets/lua`, project-native `tools.fennel-check`, `make constraints`, focused Fennel test modules run through `./build/space -m tests.<module>:main`.

## Global Constraints

- The graph remains an adaptor layer over graph-addressable domain objects; do not change graph topology ownership or node-view domain adapters.
- Default graph edges follow `theme.graph.edge-color`; explicit per-edge colors continue to override the theme edge color.
- Focused-Enter full node-view panels use the same bounded default sizing policy as inline compact panels unless existing persisted panel size metadata is being restored.
- Graph activity must never be active without the graph-map management sidebar being derivable/displayable from the active activity's dock builder.
- Compact inline panel title truncation is display-only; the full node label remains available in node data and finder/search behavior.
- Fennel validation must use Space-native `tools.fennel-check`, `make constraints`, and focused Fennel tests. Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- Use `local` instead of `let`; use multi-branch `if` forms rather than nested `if` when practical; use factory functions rather than `.new` constructors.
- Missing required graph view, node-view, sidebar, or activity dock context must fail loudly through assertions rather than silent no-ops.

---

## File Structure

- Modify `assets/lua/graph/edge.fnl` so `GraphEdge` stores `:color` only when the caller provides an explicit color.
- Keep `assets/lua/graph/view/layout.fnl` on its existing nil-color fallback contract: `ensure-glm-vec4 edge.color default-edge-color` is the intended behavior.
- Create `assets/lua/graph/view/panel-bounds.fnl` to own graph expanded-card/default panel size constants and return defensive `glm.vec3` copies.
- Modify `assets/lua/graph/view/init.fnl` to consume the shared graph panel bounds helper for inline expanded cards.
- Modify `assets/lua/graph/view/node-views.fnl` to supply the shared default full-panel size when opening a new canvas float panel without persisted size metadata.
- Modify `assets/lua/graph/view/presentation.fnl` to add a truncated title text element to compact inline card headers.
- Modify `assets/lua/main.fnl`, `assets/lua/activities.fnl`, and `assets/lua/activity-dock-view.fnl` to expose, emit, listen to, and clean up an `app.activity-dock-changed` signal for dock-builder changes that can occur while workspace-shell events are intentionally suppressed.
- Modify focused tests:
  - `assets/lua/tests/test-graph-view.fnl` for edge theme fallback and compact title header behavior.
  - `assets/lua/tests/test-hackernews-graph-view-node-views.fnl` for default/restored node-view panel size behavior.
  - `assets/lua/tests/test-main-events.fnl` for activity dock signal behavior without transient workspace-shell events.
  - `assets/lua/tests/test-graph-activity-slots.fnl` for the real graph activity theme-switch sidebar invariant.

---

### Task 1: Theme-responsive default graph edges

**Files:**
- Modify: `assets/lua/graph/edge.fnl`
- Modify only when the Task 1 test demonstrates a fallback bug after the `GraphEdge` change: `assets/lua/graph/view/layout.fnl:17-31,212-229,251-265`
- Test: `assets/lua/tests/test-graph-view.fnl`

**Interfaces:**
- Consumes: `Graph.GraphEdge {:source node-a :target node-b :color optional-vec4}` from `assets/lua/graph/init.fnl` exports.
- Produces: `GraphEdge(opts)` records where `edge.color` is nil when `opts.color` is nil, and a `glm.vec4` when `opts.color` is provided.
- Produces: `GraphViewLayout:add-edge(edge)` continues to call `make-line` with `:color` set to explicit `edge.color` or the `options.edge-color` fallback.

- [ ] **Step 1: Add failing edge color tests**

In `assets/lua/tests/test-graph-view.fnl`, add helper functions near `edge-produces-triangles`:

```fennel
(fn make-capturing-line-factory [state]
  (fn [_ctx opts]
    (table.insert state.colors opts.color)
    {:update (fn [_self _start _end] true)
     :drop (fn [_self] true)}))

(fn edge-color-approx [actual expected]
  (and actual expected
       (< (math.abs (- actual.x expected.x)) 1e-4)
       (< (math.abs (- actual.y expected.y)) 1e-4)
       (< (math.abs (- actual.z expected.z)) 1e-4)
       (< (math.abs (- actual.w expected.w)) 1e-4)))
```

Then add this test function:

```fennel
(fn graph-edge-default-color-uses-layout-theme-color []
  (local ctx (make-ctx))
  (local theme-color (glm.vec4 0.12 0.34 0.56 1))
  (local explicit-color (glm.vec4 0.9 0.8 0.7 1))
  (local state {:colors []})
  (local layout (GraphViewLayout {:ctx ctx
                                  :edge-color theme-color
                                  :make-line (make-capturing-line-factory state)}))
  (local a (Graph.GraphNode {:key "edge-theme-a"}))
  (local b (Graph.GraphNode {:key "edge-theme-b"}))
  (layout:add-node a (glm.vec3 0 0 0))
  (layout:add-node b (glm.vec3 10 0 0))
  (layout:add-edge (Graph.GraphEdge {:source a :target b}))
  (assert (edge-color-approx (. state.colors 1) theme-color)
          "Default graph edge should use the layout/theme edge color")
  (layout:add-edge (Graph.GraphEdge {:source a :target b :color explicit-color}))
  (assert (edge-color-approx (. state.colors 2) explicit-color)
          "Explicit graph edge color should override the layout/theme edge color"))
```

Register it near the existing test registrations:

```fennel
(table.insert tests {:name "Graph edge default color uses layout theme color"
                     :fn graph-edge-default-color-uses-layout-theme-color})
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
```

Expected: FAIL on `Default graph edge should use the layout/theme edge color` because `GraphEdge` currently hardcodes a default color.

- [ ] **Step 3: Implement the edge color contract**

In `assets/lua/graph/edge.fnl`, change `GraphEdge` so it only sets color when an explicit color exists:

```fennel
(fn GraphEdge [opts]
    (local options (or opts {}))
    (local edge {:source options.source
                 :target options.target
                 :label (or options.label "")})
    (when (not (= options.color nil))
        (set edge.color (Utils.ensure-glm-vec4 options.color)))
    edge)
```

Do not add a replacement hardcoded default in `GraphEdge`. The fallback belongs in `GraphViewLayout` through `default-edge-color`.

- [ ] **Step 4: Run focused validation for Task 1**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/edge.fnl --file assets/lua/graph/view/layout.fnl --file assets/lua/tests/test-graph-view.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
```

Expected: all three commands pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add assets/lua/graph/edge.fnl assets/lua/graph/view/layout.fnl assets/lua/tests/test-graph-view.fnl
git commit -m "fix(graph): use theme color for default edges"
```

Commit body must include:

```text
Constraint impact: not applicable
Testing: tools.fennel-check touched graph edge/layout/test files; make constraints; tests.test-graph-view passed.
```

---

### Task 2: Bounded focused-open graph node panels

**Files:**
- Create: `assets/lua/graph/view/panel-bounds.fnl`
- Modify: `assets/lua/graph/view/init.fnl:538-547`
- Modify: `assets/lua/graph/view/node-views.fnl:1-69,85-105`
- Test: `assets/lua/tests/test-hackernews-graph-view-node-views.fnl`

**Interfaces:**
- Produces: `PanelBounds.inline-card-bounds()` returns a table with `:default-size`, `:min-size`, `:max-size`, and `:resize-max-size` as fresh `glm.vec3` values.
- Produces: `PanelBounds.default-panel-size()` returns a fresh `glm.vec3 32.0 18.0 0`, matching the inline card default size.
- Consumes: `GraphViewNodeViews.resolve-panel-placement(target, panel)` sets `placement.size` to `PanelBounds.default-panel-size()` only for new canvas float opens where `placement.size` is nil.

- [ ] **Step 1: Add failing node-view panel size tests**

In `assets/lua/tests/test-hackernews-graph-view-node-views.fnl`, extend the existing canvas placement area with these tests:

```fennel
{:name "graph view node-views default canvas placement uses bounded size"
 :fn (fn []
       (local ctx (make-ctx))
       (local target (make-view-target ctx))
       (set target.interaction-surface :canvas)
       (set target.default-panel-location "float")
       (set target.camera {:position (glm.vec3 12 34 99)})
       (local node {:key "canvas-size-node"
                    :label "Canvas Size Node"
                    :view (fn [_node]
                            (fn [_builder-ctx _opts]
                              (make-simple-view)))})
       (local views (GraphViewNodeViews {:ctx ctx :view-target target}))
       (views:open node)
       (local size (and target.last-add-panel-opts target.last-add-panel-opts.size))
       (assert size "new canvas node view should pass bounded default size")
       (assert (= size.x 32.0) "default canvas panel width should match inline card default")
       (assert (= size.y 18.0) "default canvas panel height should match inline card default")
       (assert (= size.z 0) "default canvas panel z size should be zero")
       (views:drop-all))}
```

Add a restored-size guard near the persistence restore test:

```fennel
{:name "graph view node-views restored canvas placement preserves persisted size"
 :fn (fn []
       (local ctx (make-ctx))
       (local target (make-view-target ctx))
       (set target.interaction-surface :canvas)
       (set target.default-panel-location "float")
       (local node {:key "canvas-restored-size-node"
                    :label "Canvas Restored Size Node"
                    :view (fn [_node]
                            (fn [_builder-ctx _opts]
                              (make-simple-view)))})
       (local graph {:id "main" :nodes {}})
       (set (. graph.nodes node.key) node)
       (set graph.lookup (fn [_self key] (. graph.nodes key)))
       (local views (GraphViewNodeViews {:ctx ctx :graph-map graph :view-target target}))
       (views:restore-state {:open-views [{:node-key node.key
                                           :graph-map-id "main"
                                           :panel {:layer "float"
                                                   :size [44 22 0]}}]})
       (local size (and target.last-add-panel-opts target.last-add-panel-opts.size))
       (assert size "restored canvas node view should pass restored size")
       (assert (= size.x 44) "restored canvas panel width should come from persisted size")
       (assert (= size.y 22) "restored canvas panel height should come from persisted size")
       (views:drop-all))}
```

- [ ] **Step 2: Run the focused test and verify the new-open test fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hackernews-graph-view-node-views:main
```

Expected: FAIL on `new canvas node view should pass bounded default size` because new canvas opens currently pass nil `:size`.

- [ ] **Step 3: Create the shared bounds helper**

Create `assets/lua/graph/view/panel-bounds.fnl`:

```fennel
(local glm (require :glm))

(local default-size (glm.vec3 32.0 18.0 0))
(local min-size (glm.vec3 24.0 12.0 0))
(local max-size (glm.vec3 52.0 34.0 0))
(local resize-max-size (glm.vec3 90.0 60.0 0))

(fn copy-vec3 [value]
  (glm.vec3 value.x value.y value.z))

(fn inline-card-bounds []
  {:default-size (copy-vec3 default-size)
   :min-size (copy-vec3 min-size)
   :max-size (copy-vec3 max-size)
   :resize-max-size (copy-vec3 resize-max-size)})

(fn default-panel-size []
  (copy-vec3 default-size))

{:inline-card-bounds inline-card-bounds
 :default-panel-size default-panel-size}
```

- [ ] **Step 4: Use shared bounds in inline card construction**

In `assets/lua/graph/view/init.fnl`, require the helper near other graph view requires:

```fennel
(local PanelBounds (require :graph/view/panel-bounds))
```

In `build-expanded-presentation`, insert `(local bounds (PanelBounds.inline-card-bounds))` immediately before the `GraphNodePresentation.card-builder` call. Replace only these four key/value lines in the existing card-builder table:

```fennel
:default-size bounds.default-size
:min-size bounds.min-size
:max-size bounds.max-size
:resize-max-size bounds.resize-max-size
```

Keep all existing callbacks and colors unchanged.

- [ ] **Step 5: Apply bounded default size to new canvas float panel opens**

In `assets/lua/graph/view/node-views.fnl`, require the helper:

```fennel
(local PanelBounds (require :graph/view/panel-bounds))
```

Add a helper before `resolve-panel-placement`:

```fennel
(fn new-canvas-float-panel? [target placement panel]
    (and (= (and target target.interaction-surface) :canvas)
         (= placement.location :float)
         (= placement.size nil)
         (= (and panel panel.size) nil)))
```

Then extend `resolve-panel-placement`:

```fennel
(when (new-canvas-float-panel? target placement panel)
    (set placement.size (PanelBounds.default-panel-size)))
```

Place this after `placement` is created and before it is returned. Preserve the existing camera-centered position logic.

- [ ] **Step 6: Run focused validation for Task 2**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/panel-bounds.fnl --file assets/lua/graph/view/init.fnl --file assets/lua/graph/view/node-views.fnl --file assets/lua/tests/test-hackernews-graph-view-node-views.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hackernews-graph-view-node-views:main
```

Expected: all three commands pass.

- [ ] **Step 7: Commit Task 2**

```bash
git add assets/lua/graph/view/panel-bounds.fnl assets/lua/graph/view/init.fnl assets/lua/graph/view/node-views.fnl assets/lua/tests/test-hackernews-graph-view-node-views.fnl
git commit -m "fix(graph): bound focused node view panels"
```

Commit body must include:

```text
Constraint impact: not applicable
Testing: tools.fennel-check touched graph node-view files; make constraints; tests.test-hackernews-graph-view-node-views passed.
```

---

### Task 3: Compact inline card title label

**Files:**
- Modify: `assets/lua/graph/view/presentation.fnl:1-9,69-94,196-198`
- Test: `assets/lua/tests/test-graph-view.fnl:1219-1258,1831-1855,2740-2955`

**Interfaces:**
- Consumes: existing `graph/view/utils.truncate-with-ellipsis(text, max-length)` helper.
- Produces: expanded card object fields `header-title` and `header-title-text` for test/debug observability.
- Produces: `build-header-bar` header children order `[title, spacer, collapse, open, menu]`.

- [ ] **Step 1: Add failing compact title test**

In `assets/lua/tests/test-graph-view.fnl`, add this test near other expanded-card presentation tests:

```fennel
(fn graph-expanded-card-header-shows-truncated-node-label []
  (local ctx (make-ctx))
  (local long-label "This graph node label is long enough to be truncated in compact expanded card headers")
  (local node (Graph.GraphNode {:key "compact-title-node"
                                :label long-label
                                :preview (tracked-preview {})}))
  (local GraphNodePresentation (require :graph/view/presentation))
  (local card-builder (GraphNodePresentation.card-builder
                       {:node node
                        :position (glm.vec3 0 0 0)
                        :default-size (glm.vec3 32 18 0)
                        :on-collapse (fn [] nil)
                        :on-open (fn [_] nil)
                        :on-menu (fn [_] nil)}))
  (local card (card-builder ctx))
  (assert card.header-title "Expanded card should expose a title text widget")
  (assert card.header-title-text "Expanded card should expose the display title string")
  (assert (string.find card.header-title-text (string.char 46 46 46) 1 true)
          "Expanded card display title should truncate long labels with an ellipsis")
  (assert (string.find long-label card.header-title-text 1 true)
          "Truncation should not mutate the source node label")
  (assert (= (length card.header-bar.children) 5)
          "Expanded card header should have title, spacer, and three buttons")
  (card:drop))
```

Register it near the other graph expanded-card test registrations:

```fennel
(table.insert tests {:name "Graph expanded card header shows truncated node label"
                     :fn graph-expanded-card-header-shows-truncated-node-label})
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
```

Expected: FAIL because `card.header-title` and `card.header-title-text` do not exist and the header has only four children.

- [ ] **Step 3: Add title support to presentation header**

In `assets/lua/graph/view/presentation.fnl`, add requires:

```fennel
(local Text (require :text))
(local GraphViewUtils (require :graph/view/utils))
```

Inside `card-builder`, before `build-header-bar`, compute a display title:

```fennel
(local title-source (tostring (or node.label node.key "node")))
(local title-text (GraphViewUtils.truncate-with-ellipsis title-source 42))
```

Inside `build-header-bar`, create a title builder before the spacer builder:

```fennel
(fn title-builder [child-ctx]
  ((Text {:text title-text :scale 0.8}) child-ctx))
```

Change the `Flex` children from four entries to five entries. Keep the three existing Button forms unchanged except for their new positions in the vector:

```fennel
:children [(FlexChild title-builder 0)
           (FlexChild spacer-builder 1)
           existing-collapse-button-flex-child
           existing-open-button-flex-child
           existing-menu-button-flex-child]
```

The implementer must move the existing close-fullscreen, open-in-new, and more-vert Button table bodies already present in `build-header-bar`; no button callback or variant changes belong in this task.

After `(local header-bar (build-header-bar ctx))`, set the new observability fields:

```fennel
(set card.header-bar header-bar)
(set card.header-title (. header-bar.children 1 :element))
(set card.header-title-text title-text)
```

Update existing tests that index header buttons because the button positions shift by one:

- collapse button: child `2` becomes child `3`.
- open button: child `3` becomes child `4`.
- menu button: child `4` becomes child `5`.
- header child-count assertions: `4` becomes `5`.
- spacer child: child `1` becomes child `2`.

- [ ] **Step 4: Run focused validation for Task 3**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/presentation.fnl --file assets/lua/tests/test-graph-view.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
```

Expected: all three commands pass.

- [ ] **Step 5: Commit Task 3**

```bash
git add assets/lua/graph/view/presentation.fnl assets/lua/tests/test-graph-view.fnl
git commit -m "fix(graph): show compact panel titles"
```

Commit body must include:

```text
Constraint impact: not applicable
Testing: tools.fennel-check graph presentation/test files; make constraints; tests.test-graph-view passed.
```

---

### Task 4: Theme-stable graph activity sidebar lifecycle

**Files:**
- Modify: `assets/lua/main.fnl:78-82,1360-1363`
- Modify: `assets/lua/activities.fnl:69-86,128-151`
- Modify: `assets/lua/activity-dock-view.fnl:60-65,181-211`
- Test: `assets/lua/tests/test-main-events.fnl:70-85,857-884`
- Test: `assets/lua/tests/test-graph-activity-slots.fnl:817-904`

**Interfaces:**
- Produces: `app.activity-dock-changed` as a `Signal` initialized by main app setup and `install-app-shell!`.
- Produces: `Activities.apply-activity-hooks!` emits `app.activity-dock-changed` with `{:reason "activity-hooks" :previous-left-dock-builder previous :current-left-dock-builder current}` whenever the left-dock builder value changes.
- Produces: `Activities.clear-activity-runtime-hooks!` emits the same signal when clearing a non-nil left-dock builder.
- Consumes: `ActivityDockView` connects to `app.activity-dock-changed`, requests rebuild, and disconnects on drop.

- [ ] **Step 1: Add failing main-event signal tests**

In `assets/lua/tests/test-main-events.fnl`, add these requires near the existing requires:

```fennel
(local Signal (require :signal))
(local {: Layout} (require :layout))
```

Add `:activity-dock-changed` to `bind-state-keys`.

Extend `theme-reapply-does-not-emit-transient-activity-events` so it also checks dock-change signaling:

```fennel
(set app.activity-dock-changed (Signal))
(var dock-events [])
(local dock-handler
  (app.activity-dock-changed:connect
    (fn [payload]
      (table.insert dock-events payload))))
```

Change the registered graph activity to install a left dock builder:

```fennel
(Activities.register-activity
  {:id "graph"
   :label "Graph"
   :activate (fn [ctx]
               (ctx:set-left-dock-builder!
                 (fn [_dock-ctx]
                   {:layout (Layout {:name "test-graph-dock"})
                    :drop (fn [_self] true)}))
               {})})
```

After `ThemeActions.apply-theme :dark`, disconnect both handlers and assert:

```fennel
(app.activity-dock-changed:disconnect dock-handler true)
(assert (> (# dock-events) 0)
        "Theme reapply should emit activity-dock-changed for dock hook restoration")
(assert app.activity-left-dock-builder
        "Theme reapply should restore graph activity left dock builder")
```

Keep the existing assertion that `workspace-shell-changed` event count remains zero.

- [ ] **Step 2: Add failing real graph activity sidebar invariant test**

In `assets/lua/tests/test-graph-activity-slots.fnl`, update `install-theme-switch-rail-check!` to capture the dock entity it builds:

```fennel
(local state {:checked? false :dock nil})
;; inside app.apply-active-world-hud-contrib, immediately after
;; `(local dock ((ActivityDockView {}) (make-theme-switch-hud-ctx)))`:
(set state.dock dock)
```

Do not drop `dock` inside `app.apply-active-world-hud-contrib`; drop it in `with-graph-theme-switch-env` cleanup after `f` returns:

```fennel
(when (and rail-state.dock rail-state.dock.drop)
  (rail-state.dock:drop))
```

Extend `graph-activity-theme-switch-rebuilds-label-colors` after `ThemeActions.apply-theme :light`:

```fennel
(assert app.activity-left-dock-builder
        "graph activity theme switch should restore the graph sidebar dock builder")
(assert rail-state.dock
        "graph activity theme switch test should keep the rebuilt activity dock")
(rail-state.dock:update)
(assert (rail-state.dock:active-dock-entity)
        "activity dock should rebuild to include graph sidebar after graph theme switch")
```

- [ ] **Step 3: Run focused tests and verify failure**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-main-events:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

Expected: one or both tests fail because no explicit activity dock changed signal exists and `ActivityDockView` cannot rebuild when workspace-shell events are suppressed and final shell state is unchanged.

- [ ] **Step 4: Add the activity dock signal and listener**

In `assets/lua/main.fnl`, initialize the signal beside `workspace-shell-changed`:

```fennel
(set app.activity-dock-changed (Signal))
```

In `install-app-shell!`, ensure tests and shell reinstall get the signal:

```fennel
(set app.activity-dock-changed (or app.activity-dock-changed (Signal)))
```

In `assets/lua/activities.fnl`, add a local emitter:

```fennel
(fn emit-activity-dock-changed! [reason previous current]
  (when (and app.activity-dock-changed
             (not (= previous current)))
    (app.activity-dock-changed:emit {:reason reason
                                     :previous-left-dock-builder previous
                                     :current-left-dock-builder current}))
  current)
```

In `clear-activity-runtime-hooks!`, capture the previous builder before clearing:

```fennel
(local previous-left-dock-builder app.activity-left-dock-builder)
```

After `(set app.activity-left-dock-builder nil)`, emit the change:

```fennel
(emit-activity-dock-changed! "activity-hooks" previous-left-dock-builder nil)
```

In `apply-activity-hooks!`, capture previous builder before setting hooks:

```fennel
(local previous-left-dock-builder app.activity-left-dock-builder)
```

Keep the existing hook assignments. After `(set app.activity-left-dock-builder hooks.left-dock-builder)`, emit after all hook fields are assigned and before returning `true`:

```fennel
(set app.activity-left-dock-builder hooks.left-dock-builder)
(emit-activity-dock-changed! "activity-hooks" previous-left-dock-builder app.activity-left-dock-builder)
```

In `assets/lua/activity-dock-view.fnl`, add a handler variable near the existing `workspace-shell-changed-handler` and `activities-changed-handler` locals:

```fennel
(var activity-dock-changed-handler nil)
```

Connect to the signal near the existing signal connections:

```fennel
(when app.activity-dock-changed
  (set activity-dock-changed-handler
       (app.activity-dock-changed:connect
         (fn [_payload]
           (request-rebuild!)))))
```

Expose the active dock entity as a method in the returned table:

```fennel
:active-dock-entity (fn [_self] active-dock-entity)
```

Disconnect the handler in `:drop` before dropping content:

```fennel
(when activity-dock-changed-handler
  (app.activity-dock-changed:disconnect activity-dock-changed-handler true)
  (set activity-dock-changed-handler nil))
```

Use a method function for `active-dock-entity` rather than exposing the mutable local directly.

- [ ] **Step 5: Adjust the real sidebar test to use the observability method**

Replace the direct layout child-count assertion with this exact assertion:

```fennel
(rail-state.dock:update)
(assert (rail-state.dock:active-dock-entity)
        "activity dock should rebuild to include graph sidebar after graph theme switch")
```

- [ ] **Step 6: Run focused validation for Task 4**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/main.fnl --file assets/lua/activities.fnl --file assets/lua/activity-dock-view.fnl --file assets/lua/tests/test-main-events.fnl --file assets/lua/tests/test-graph-activity-slots.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-main-events:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

Expected: all four commands pass.

- [ ] **Step 7: Commit Task 4**

```bash
git add assets/lua/main.fnl assets/lua/activities.fnl assets/lua/activity-dock-view.fnl assets/lua/tests/test-main-events.fnl assets/lua/tests/test-graph-activity-slots.fnl
git commit -m "fix(ui): rebuild activity dock on hook changes"
```

Commit body must include:

```text
Constraint impact: not applicable
Testing: tools.fennel-check activity dock/theme files; make constraints; tests.test-main-events and tests.test-graph-activity-slots passed.
```

---

### Task 5: Integrated graph UX validation

**Files:**
- No new source edits expected.
- Validate all files changed by Tasks 1-4.

**Interfaces:**
- Consumes: successful commits from Tasks 1-4.
- Produces: evidence that graph view theme/panel/sidebar/title behavior works together and satisfies the spec.

- [ ] **Step 1: Run touched-file Fennel compile check**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/edge.fnl --file assets/lua/graph/view/layout.fnl --file assets/lua/graph/view/panel-bounds.fnl --file assets/lua/graph/view/init.fnl --file assets/lua/graph/view/node-views.fnl --file assets/lua/graph/view/presentation.fnl --file assets/lua/main.fnl --file assets/lua/activities.fnl --file assets/lua/activity-dock-view.fnl --file assets/lua/tests/test-graph-view.fnl --file assets/lua/tests/test-hackernews-graph-view-node-views.fnl --file assets/lua/tests/test-main-events.fnl --file assets/lua/tests/test-graph-activity-slots.fnl
```

Expected: PASS.

- [ ] **Step 2: Run constraints**

Run:

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 3: Run focused graph and activity tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hackernews-graph-view-node-views:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-main-events:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

Expected: all commands pass.

- [ ] **Step 4: Run broader local validation for shared activity/theme lifecycle risk**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: PASS. This broader suite is required because Task 4 changes main shell/activity dock lifecycle behavior.

- [ ] **Step 5: Commit validation note only when no code changed during validation**

Do not create a validation-only commit if Step 1-4 required no file changes. If validation forced a repository fix, route that fix through a new implementer/reviewer pass, then commit the fix with a `fix(scope)` or `test(scope)` subject that names the behavior corrected.

---

## Final Handoff Requirements

- Every implementation task must pass implementer → reviewer before moving to the next task.
- Every repository fix produced by validation failure must invoke systematic debugging before implementation.
- Final branch finishing must fetch `origin`, evaluate against current `origin/main`, perform only a safe merge from `origin/main` when permitted and necessary, rerun required validation after integration, commit reviewed changes, verify a clean worktree, push the branch, create a PR targeting `main`, enable/enter merge queue when available, and poll until the PR is merged or an actionable blocker requires human input.
