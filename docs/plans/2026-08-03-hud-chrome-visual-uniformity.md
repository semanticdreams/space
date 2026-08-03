# HUD Chrome Visual Uniformity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the normal single-row HUD rails, control panel, status panel, and Sandbox toolbar visually uniform through shared natural-measurement metrics.

**Architecture:** Add a constants-only HUD chrome metrics module, keep the side rails as the visual source of truth, and consume those metrics from the existing rail, control/status panel, volume button, and Sandbox toolbar composition points. Wrap the Sandbox toolbar in the existing `Card + Padding + Flex` shell so it gains a solid background while all chrome continues to size naturally to children rather than fixed outer containers.

**Tech Stack:** Space Fennel UI widgets (`Button`, `Card`, `Padding`, `Flex`, `Layout`), Fennel test suites in `assets/lua/tests`, and project-native validation with `tools.fennel-check`, `make constraints`, focused `./build/space -m tests...` commands, and `tests.fast:main`.

## Global Constraints

- Preserve the left and right rails as the visual source of truth.
- Give the Sandbox toolbar a solid background consistent with the control and status panels.
- Make the normal single-row top control panel, bottom status panel, and Sandbox toolbar naturally measure to the same cross-axis size as the side rail width.
- Achieve sizing through shared child metrics, not fixed-size outer wrappers or HUD band constraints.
- Keep existing Sandbox toolbar behavior: labels, active variants, click handlers, state updates, and lifecycle disconnects.
- Keep changes localized to HUD chrome composition and tests.
- No redesign of theme color tokens.
- No global `Button` default changes that could affect dialogs or non-HUD UI.
- No fixed-size `Sized` wrappers or layout constraints around panels/toolbars.
- No HUD band allocation or dock topology changes.
- No expanded panel/dialog sizing changes.
- Builders return build closures.
- Composites own and drop their direct child widgets.
- Required build context should assert rather than silently fall back.
- Layout passes should write child transforms directly and mark only the shallowest appropriate layout dirty.
- Use `local` instead of `let` in touched Fennel code.
- When running direct Fennel tests, set `SPACE_ASSETS_PATH=$(pwd)/assets`, `FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"`, and `FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"`.
- Use `SPACE_DISABLE_AUDIO=1`, `SKIP_KEYRING_TESTS=1`, and `XDG_DATA_HOME=/tmp/space/tests/xdg-data` for CLI test runs.
- If `./build/space` is missing or stale, run `make build` with `timeout: 14400000` before direct runtime validation.

## Acceptance Criteria

- The left activity rail and right extended sidebar rail still use the same rail button metrics that make them look good today.
- The control panel's normal single-row natural height equals the collapsed side rail's natural width within the existing `MathUtils.approx` tolerance.
- The status panel's normal single-row natural height equals the collapsed side rail's natural width within the existing `MathUtils.approx` tolerance.
- The Sandbox toolbar's natural height equals the collapsed side rail's natural width within the existing `MathUtils.approx` tolerance.
- The Sandbox toolbar root exposes a `Card` background and still contains the three named toolbar buttons.
- Existing Sandbox toolbar label, variant, click, update, and drop tests continue to pass.
- No production HUD chrome file introduces `Sized`, fixed toolbar height/width constants, or HUD band allocation changes.

---

### Task 1: Shared Rail Metrics

**Files:**
- Create: `assets/lua/hud-chrome-metrics.fnl`
- Modify: `assets/lua/activity-dock-view.fnl`
- Modify: `assets/lua/hud-extended-sidebar-view.fnl`
- Modify: `assets/lua/tests/test-hud-extended-sidebar.fnl`
- Modify: `assets/lua/tests/test-drawing-sidebar.fnl`

**Interfaces:**
- Consumes: existing `Button` option keys `:padding` and `:icon-style`.
- Produces: module `hud-chrome-metrics` exporting:
  - `rail-button-padding` as `[0.4 0.25]`.
  - `rail-button-icon-style` as `{:scale 3.2}`.
  - `single-row-button-padding` as `[0.4 0.1]`.
  - `single-row-button-icon-style` as `{:scale 1.6}`.
  - `single-row-shell-padding` as `[0.6 0.3]`.
  - `control-row-spacing` as `0.5`.
  - `status-row-spacing` as `0.4`.
  - `status-column-edge-insets` as `[0.1 0.1]`.
  - `status-column-horizontal-padding` as `0.2`.

- [ ] **Step 1: Update rail metric tests to depend on the shared module**

  In `assets/lua/tests/test-hud-extended-sidebar.fnl`, add this require near the other local requires:

  ```fennel
  (local HudChromeMetrics (require :hud-chrome-metrics))
  ```

  In the existing rail metric test, replace the literal `3.2` scale assertion and reference button literals with shared metrics:

  ```fennel
  (assert (= rail-button.text.child.style.scale HudChromeMetrics.rail-button-icon-style.scale)
          "right rail icon style should match the shared HUD rail icon scale")
  (local reference-button
    ((Button {:padding HudChromeMetrics.rail-button-padding
              :focusable? false
              :icon :test_icon
              :icon-style HudChromeMetrics.rail-button-icon-style
              :name "reference-extended-sidebar-test"
              :focus-name "Test"
              :on-click (fn [_button _event] nil)
              :variant :secondary})
     ctx))
  ```

  In `assets/lua/tests/test-drawing-sidebar.fnl`, add the same require and replace the existing `3.2` icon-scale assertions with:

  ```fennel
  (assert (= graph-button.text.child.style.scale HudChromeMetrics.rail-button-icon-style.scale)
          "drawing sidebar graph button should use the shared HUD rail icon scale")
  (assert (= draw-button.text.child.style.scale HudChromeMetrics.rail-button-icon-style.scale)
          "drawing sidebar draw button should use the shared HUD rail icon scale")
  ```

- [ ] **Step 2: Run the focused tests and verify the intended failure**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-extended-sidebar:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-drawing-sidebar:main
  ```

  Expected: FAIL because `hud-chrome-metrics` does not exist yet.

- [ ] **Step 3: Create the shared metrics module**

  Create `assets/lua/hud-chrome-metrics.fnl` with exactly these constants:

  ```fennel
  {:rail-button-padding [0.4 0.25]
   :rail-button-icon-style {:scale 3.2}
   :single-row-button-padding [0.4 0.1]
   :single-row-button-icon-style {:scale 1.6}
   :single-row-shell-padding [0.6 0.3]
   :control-row-spacing 0.5
   :status-row-spacing 0.4
   :status-column-edge-insets [0.1 0.1]
   :status-column-horizontal-padding 0.2}
  ```

- [ ] **Step 4: Update the left activity rail to consume rail metrics**

  In `assets/lua/activity-dock-view.fnl`, add:

  ```fennel
  (local HudChromeMetrics (require :hud-chrome-metrics))
  ```

  Update `feature-button` so the `Button` uses:

  ```fennel
  :padding HudChromeMetrics.rail-button-padding
  :icon-style HudChromeMetrics.rail-button-icon-style
  ```

- [ ] **Step 5: Update the right extended sidebar rail to consume rail metrics**

  In `assets/lua/hud-extended-sidebar-view.fnl`, add:

  ```fennel
  (local HudChromeMetrics (require :hud-chrome-metrics))
  ```

  Update the rail `Button` options in `build-rail` so they use:

  ```fennel
  :padding HudChromeMetrics.rail-button-padding
  :icon-style HudChromeMetrics.rail-button-icon-style
  ```

- [ ] **Step 6: Run Task 1 validation**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/hud-chrome-metrics.fnl --file assets/lua/activity-dock-view.fnl --file assets/lua/hud-extended-sidebar-view.fnl --file assets/lua/tests/test-hud-extended-sidebar.fnl --file assets/lua/tests/test-drawing-sidebar.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-extended-sidebar:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-drawing-sidebar:main
  ```

  Expected: PASS. Constraint-impact note: this task centralizes literals and should not add new violations.

- [ ] **Step 7: Commit Task 1**

  ```bash
  git add assets/lua/hud-chrome-metrics.fnl assets/lua/activity-dock-view.fnl assets/lua/hud-extended-sidebar-view.fnl assets/lua/tests/test-hud-extended-sidebar.fnl assets/lua/tests/test-drawing-sidebar.fnl
  git commit -m "feat(ui): share HUD rail chrome metrics"
  ```

---

### Task 2: Control and Status Panel Natural Height

**Files:**
- Create: `assets/lua/tests/test-hud-chrome-uniformity.fnl`
- Modify: `assets/lua/tests/fast.fnl`
- Modify: `assets/lua/hud-control-panel.fnl`
- Modify: `assets/lua/hud-control-panel-layout.fnl`
- Modify: `assets/lua/hud-status-panel-layout.fnl`
- Modify: `assets/lua/volume-control.fnl`

**Interfaces:**
- Consumes: `HudChromeMetrics.single-row-button-padding`, `HudChromeMetrics.single-row-button-icon-style`, `HudChromeMetrics.single-row-shell-padding`, `HudChromeMetrics.control-row-spacing`, `HudChromeMetrics.status-row-spacing`, `HudChromeMetrics.status-column-edge-insets`, and `HudChromeMetrics.status-column-horizontal-padding`.
- Produces: `VolumeControl.make-volume-button(opts)` where `opts` is optional and supports canonical keys `:padding` and `:icon-style`; existing zero-argument callers still work.
- Produces: normal control/status panel rows that naturally measure to the collapsed rail width without fixed-size wrappers.

- [ ] **Step 1: Create the focused HUD chrome uniformity test file**

  Create `assets/lua/tests/test-hud-chrome-uniformity.fnl` with this scaffold:

  ```fennel
  (local tests [])
  (local _ (require :main))
  (local BuildContext (require :build-context))
  (local HudControlPanel (require :hud-control-panel))
  (local HudExtendedSidebar (require :hud-extended-sidebar))
  (local HudExtendedSidebarView (require :hud-extended-sidebar-view))
  (local {: StatusPanelLayout} (require :hud-status-panel-layout))
  (local Text (require :text))
  (local MathUtils (require :math-utils))
  (local approx (. MathUtils :approx))

  (fn make-clickables-stub []
    (local stub {})
    (set stub.register (fn [_self _obj] nil))
    (set stub.unregister (fn [_self _obj] nil))
    (set stub.register-right-click (fn [_self _obj] nil))
    (set stub.unregister-right-click (fn [_self _obj] nil))
    (set stub.register-double-click (fn [_self _obj] nil))
    (set stub.unregister-double-click (fn [_self _obj] nil))
    (set stub.register-left-click-void-callback (fn [_self _cb] nil))
    (set stub.unregister-left-click-void-callback (fn [_self _cb] nil))
    (set stub.register-right-click-void-callback (fn [_self _cb] nil))
    (set stub.unregister-right-click-void-callback (fn [_self _cb] nil))
    stub)

  (fn make-hoverables-stub []
    (local stub {})
    (set stub.register (fn [_self _obj] nil))
    (set stub.unregister (fn [_self _obj] nil))
    stub)

  (fn make-icons-stub []
    (local glyph {:advance 1
                  :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                  :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {4242 glyph}
                 :advance 1})
    (local stub {:font font})
    (set stub.resolve
         (fn [_self _name]
           {:type :font
            :codepoint 4242
            :font font}))
    stub)

  (fn ensure-themes []
    (local AppBootstrap (require :app-bootstrap))
    (AppBootstrap.init-themes))

  (fn make-test-ctx []
    (ensure-themes)
    (BuildContext {:theme (app.themes.get-active-theme)
                   :clickables (make-clickables-stub)
                   :hoverables (make-hoverables-stub)
                   :icons (make-icons-stub)
                   :pointer-target {}}))

  (fn measure-entity [entity]
    (entity.layout:measurer)
    entity.layout.measure)

  (fn make-reference-sidebar []
    (local sidebar (HudExtendedSidebar))
    (sidebar:register-entry {:id :test
                             :icon :test_icon
                             :label "Test"
                             :build-panel (fn [_ctx] nil)})
    sidebar)

  (fn reference-rail-width [ctx]
    (local sidebar (make-reference-sidebar))
    (local entity ((HudExtendedSidebarView sidebar) ctx))
    (local measured (measure-entity entity))
    (local width measured.x)
    (entity:drop)
    width)

  (fn assert-close [actual expected message]
    (assert (approx actual expected)
            (.. message "; expected " (tostring expected) ", got " (tostring actual))))

  (fn text-widget [value]
    (fn [ctx]
      ((Text {:text value}) ctx)))

  (fn hud-chrome-control-panel-height-matches-rail-width []
    (local ctx (make-test-ctx))
    (local rail-width (reference-rail-width ctx))
    (local panel (((. HudControlPanel :ControlPanel) {}) ctx))
    (local measured (measure-entity panel))
    (assert-close measured.y rail-width
                  "normal control panel natural height should match collapsed rail width")
    (panel:drop))

  (fn hud-chrome-status-panel-height-matches-rail-width []
    (local ctx (make-test-ctx))
    (local rail-width (reference-rail-width ctx))
    (local panel
      ((StatusPanelLayout {:commands-builder (text-widget "Ready")
                           :info-builder (text-widget "OK")})
       ctx))
    (local measured (measure-entity panel))
    (assert-close measured.y rail-width
                  "normal status panel natural height should match collapsed rail width")
    (panel:drop))

  (table.insert tests {:name "HUD chrome control panel height matches rail width"
                       :fn hud-chrome-control-panel-height-matches-rail-width})
  (table.insert tests {:name "HUD chrome status panel height matches rail width"
                       :fn hud-chrome-status-panel-height-matches-rail-width})

  (local main
    (fn []
      (local runner (require :tests/runner))
      (runner.run-tests {:name "hud-chrome-uniformity"
                         :tests tests})))

  {:name "hud-chrome-uniformity"
   :tests tests
   :main main}
  ```

- [ ] **Step 2: Register the focused test suite in `tests.fast`**

  Add this module to `assets/lua/tests/fast.fnl` near the other HUD tests:

  ```fennel
  :tests.test-hud-chrome-uniformity
  ```

- [ ] **Step 3: Run the new focused test and verify the intended failure**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-chrome-uniformity:main
  ```

  Expected: FAIL because the current control and status panel heights do not match the rail width.

- [ ] **Step 4: Apply shared shell metrics to the control panel layout**

  In `assets/lua/hud-control-panel-layout.fnl`, add:

  ```fennel
  (local HudChromeMetrics (require :hud-chrome-metrics))
  ```

  Replace hard-coded padding and spacing with:

  ```fennel
  (Padding
    {:edge-insets HudChromeMetrics.single-row-shell-padding
     :child
     (Flex
       {:axis 1
        :xspacing HudChromeMetrics.control-row-spacing
        :yalign :center
        :children children})})
  ```

- [ ] **Step 5: Apply shared button metrics to control panel buttons**

  In `assets/lua/hud-control-panel.fnl`, add:

  ```fennel
  (local HudChromeMetrics (require :hud-chrome-metrics))
  ```

  At the top of `make-button-row`, bind:

  ```fennel
  (local button-padding HudChromeMetrics.single-row-button-padding)
  (local button-icon-style HudChromeMetrics.single-row-button-icon-style)
  (local volume-button (VolumeControl.make-volume-button {:padding button-padding
                                                          :icon-style button-icon-style}))
  ```

  Update every `Button` created in the control row to use:

  ```fennel
  :padding button-padding
  :icon-style button-icon-style
  ```

- [ ] **Step 6: Make the volume button accept canonical per-call metrics**

  In `assets/lua/volume-control.fnl`, change the function header from:

  ```fennel
  (fn make-volume-button []
  ```

  to:

  ```fennel
  (fn make-volume-button [opts]
    (local options (or opts {}))
  ```

  Update the internal `Button` options to preserve old defaults for external zero-argument callers:

  ```fennel
  (Button {:variant :primary
           :padding (or options.padding [0.4 0.4])
           :icon-style options.icon-style
           :icon (volume-icon-name (current-master-volume) stored-muted?)
           :name "volume-control"})
  ```

- [ ] **Step 7: Apply shared shell and column metrics to the status panel layout**

  In `assets/lua/hud-status-panel-layout.fnl`, add:

  ```fennel
  (local HudChromeMetrics (require :hud-chrome-metrics))
  ```

  Replace the local metric constants with:

  ```fennel
  (local row-spacing HudChromeMetrics.status-row-spacing)
  (local column-edge-insets HudChromeMetrics.status-column-edge-insets)
  (local column-horizontal-padding HudChromeMetrics.status-column-horizontal-padding)
  ```

  Replace the panel shell padding with:

  ```fennel
  (Padding
    {:edge-insets HudChromeMetrics.single-row-shell-padding
     :child (fn [_child-ctx]
              row)})
  ```

- [ ] **Step 8: Run Task 2 validation**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-hud-chrome-uniformity.fnl --file assets/lua/tests/fast.fnl --file assets/lua/hud-control-panel.fnl --file assets/lua/hud-control-panel-layout.fnl --file assets/lua/hud-status-panel-layout.fnl --file assets/lua/volume-control.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-chrome-uniformity:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-control-panel:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-volume:main
  ```

  Expected: PASS. Constraint-impact note: shared metrics may reduce duplicated literals; no new baseline entries should be needed.

- [ ] **Step 9: Commit Task 2**

  ```bash
  git add assets/lua/tests/test-hud-chrome-uniformity.fnl assets/lua/tests/fast.fnl assets/lua/hud-control-panel.fnl assets/lua/hud-control-panel-layout.fnl assets/lua/hud-status-panel-layout.fnl assets/lua/volume-control.fnl
  git commit -m "feat(ui): align HUD panel chrome metrics"
  ```

---

### Task 3: Sandbox Toolbar Shell and Metrics

**Files:**
- Modify: `assets/lua/sandbox-toolbar-view.fnl`
- Modify: `assets/lua/tests/test-sandbox-toolbar-view.fnl`
- Modify: `assets/lua/tests/test-hud-chrome-uniformity.fnl`

**Interfaces:**
- Consumes: `HudChromeMetrics.single-row-button-padding`, `HudChromeMetrics.single-row-button-icon-style`, and `HudChromeMetrics.single-row-shell-padding`.
- Produces: `SandboxToolbarView(state) -> build(ctx) -> root entity` where the root is the `Card` stack entity and still has `update` and `drop` methods that preserve current state update/disconnect behavior.

- [ ] **Step 1: Extend Sandbox toolbar test traversal for wrapped trees**

  In `assets/lua/tests/test-sandbox-toolbar-view.fnl`, replace `find-entity-by-layout-name` with a traversal that also descends through single-child wrappers:

  ```fennel
  (fn find-entity-by-layout-name [root layout-name]
    "Walk the entity tree looking for a layout with the given name."
    (var found nil)
    (fn walk [entity]
      (when (and entity entity.layout (= entity.layout.name layout-name))
        (set found entity))
      (when (and entity entity.children (not found))
        (each [_ child (ipairs entity.children)]
          (when (and (= (type child) :table) child.element)
            (walk child.element))
          (walk child)))
      (when (and entity entity.child (not found))
        (walk entity.child)))
    (walk root)
    found)
  ```

- [ ] **Step 2: Add failing Sandbox toolbar uniformity/background tests**

  In `assets/lua/tests/test-hud-chrome-uniformity.fnl`, add these requires:

  ```fennel
  (local SandboxToolbarState (require :sandbox-toolbar-state))
  (local SandboxToolbarView (require :sandbox-toolbar-view))
  ```

  Add these test functions:

  ```fennel
  (fn hud-chrome-sandbox-toolbar-height-matches-rail-width []
    (local ctx (make-test-ctx))
    (local rail-width (reference-rail-width ctx))
    (local state (SandboxToolbarState {}))
    (local toolbar ((SandboxToolbarView state) ctx))
    (local measured (measure-entity toolbar))
    (assert-close measured.y rail-width
                  "Sandbox toolbar natural height should match collapsed rail width")
    (toolbar:drop))

  (fn hud-chrome-sandbox-toolbar-root-has-card-background []
    (local ctx (make-test-ctx))
    (local state (SandboxToolbarState {}))
    (local toolbar ((SandboxToolbarView state) ctx))
    (assert toolbar.background-color
            "Sandbox toolbar root should expose a Card background color")
    (assert (and toolbar.children (. toolbar.children 1))
            "Sandbox toolbar Card root should include a background rectangle child")
    (toolbar:drop))
  ```

  Register them with the existing `tests` table:

  ```fennel
  (table.insert tests {:name "HUD chrome Sandbox toolbar height matches rail width"
                       :fn hud-chrome-sandbox-toolbar-height-matches-rail-width})
  (table.insert tests {:name "HUD chrome Sandbox toolbar root has Card background"
                       :fn hud-chrome-sandbox-toolbar-root-has-card-background})
  ```

- [ ] **Step 3: Run the uniformity test and verify the intended Sandbox failure**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-chrome-uniformity:main
  ```

  Expected: FAIL because the Sandbox toolbar is still a bare `Flex` without a `Card` background and matching shell metrics.

- [ ] **Step 4: Wrap Sandbox toolbar content in `Card + Padding`**

  In `assets/lua/sandbox-toolbar-view.fnl`, add:

  ```fennel
  (local Card (require :card))
  (local Padding (require :padding))
  (local HudChromeMetrics (require :hud-chrome-metrics))
  ```

  Inside `build`, add this helper before creating button builders:

  ```fennel
  (fn toolbar-button [button-opts capture!]
    (fn [button-ctx]
      (local button ((Button button-opts) button-ctx))
      (capture! button)
      button))
  ```

  Replace each `Button` builder with a `toolbar-button` call that includes these metrics:

  ```fennel
  :padding HudChromeMetrics.single-row-button-padding
  :icon-style HudChromeMetrics.single-row-button-icon-style
  ```

  Replace the bare `Flex` root with:

  ```fennel
  (local row-builder
    (Flex {:axis 1
           :yalign :center
           :children
           [(FlexChild camera-btn-builder 0)
            (FlexChild object-move-btn-builder 0)
            (FlexChild drag-attachment-btn-builder 0)]}))

  (local root
    ((Card {:child
            (Padding {:edge-insets HudChromeMetrics.single-row-shell-padding
                      :child row-builder})})
     ctx))
  ```

  Remove the old extraction from `root.children` because the builders now capture `camera-btn`, `object-move-btn`, and `drag-attachment-btn` directly.

- [ ] **Step 5: Preserve project Fennel idioms and lifecycle behavior**

  In `update-camera-button`, replace the existing `let` binding with `local` bindings:

  ```fennel
  (local new-label (if (= state.camera-mode :grounded) "Grounded" "Flight"))
  (local text-widget (find-button-text-widget camera-btn))
  (when (and text-widget text-widget.set-text)
    (text-widget:set-text new-label {:mark-measure-dirty? true}))
  ```

  Keep the existing `state.changed` connect/disconnect wrapper on the new `Card` root:

  ```fennel
  (local changed-handler (fn [] (update root)))
  (state.changed:connect changed-handler)
  (set root.update update)
  (local original-drop root.drop)
  (set root.drop (fn [self]
                   (state.changed:disconnect changed-handler true)
                   (when original-drop
                     (original-drop self))))
  ```

- [ ] **Step 6: Run Task 3 validation**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/sandbox-toolbar-view.fnl --file assets/lua/tests/test-sandbox-toolbar-view.fnl --file assets/lua/tests/test-hud-chrome-uniformity.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-toolbar-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-chrome-uniformity:main
  ```

  Expected: PASS. Constraint-impact note: this task should reduce one `let` usage in touched code and should not add fixed-size wrappers.

- [ ] **Step 7: Commit Task 3**

  ```bash
  git add assets/lua/sandbox-toolbar-view.fnl assets/lua/tests/test-sandbox-toolbar-view.fnl assets/lua/tests/test-hud-chrome-uniformity.fnl
  git commit -m "feat(ui): wrap Sandbox toolbar in HUD chrome shell"
  ```

---

### Task 4: Final Local Validation

**Files:**
- Test: `assets/lua/hud-chrome-metrics.fnl`
- Test: `assets/lua/activity-dock-view.fnl`
- Test: `assets/lua/hud-extended-sidebar-view.fnl`
- Test: `assets/lua/hud-control-panel.fnl`
- Test: `assets/lua/hud-control-panel-layout.fnl`
- Test: `assets/lua/hud-status-panel-layout.fnl`
- Test: `assets/lua/sandbox-toolbar-view.fnl`
- Test: `assets/lua/tests/test-hud-chrome-uniformity.fnl`
- Test: `assets/lua/tests/test-sandbox-toolbar-view.fnl`

**Interfaces:**
- Consumes: all reviewed implementation commits from Tasks 1-3.
- Produces: final local validation evidence in the required Space Fennel order before finishing-branch integration.

- [ ] **Step 1: Run compile check first**

  ```bash
  make fennel-check
  ```

  Expected: PASS.

- [ ] **Step 2: Run constraints second**

  ```bash
  make constraints
  ```

  Expected: PASS.

- [ ] **Step 3: Run focused HUD chrome tests third**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-chrome-uniformity:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-control-panel:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-extended-sidebar:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-toolbar-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-drawing-sidebar:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-volume:main
  ```

  Expected: PASS.

- [ ] **Step 4: Run broader relevant local suite**

  This is justified because the shared metrics affect multiple HUD surfaces, activity rails, the volume button, and Sandbox toolbar behavior.

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  ```

  Expected: PASS.

- [ ] **Step 5: Check for fixed-size regressions in touched production chrome files**

  ```bash
  rg -n "\(require :sized\)|\bSized\b|top-toolbar-height|status-panel-height|sandbox-toolbar-height|fixed.*height|fixed.*width" assets/lua/activity-dock-view.fnl assets/lua/hud-extended-sidebar-view.fnl assets/lua/hud-control-panel.fnl assets/lua/hud-control-panel-layout.fnl assets/lua/hud-status-panel-layout.fnl assets/lua/sandbox-toolbar-view.fnl
  ```

  Expected: no matches.

- [ ] **Step 6: Confirm committed branch state**

  ```bash
  git status --porcelain
  ```

  Expected: clean tree before invoking finishing-a-development-branch.
