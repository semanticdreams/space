# HUD Control Button Spacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove horizontal Flex gaps between visible HUD control-panel icon buttons and HUD world selector buttons while preserving button-owned sizing.

**Architecture:** Keep the change HUD-scoped: set the existing HUD control row spacing metric to zero, make the icon-button row consume that metric explicitly, and construct HUD world tabs with zero tab spacing. Add focused layout-measurement tests that compare row width to the sum of child widths, including the add-world button, without changing global widget defaults.

**Tech Stack:** Space Fennel widgets, `Flex`, `Button`, `WorldTabsWidget`, HUD chrome metrics, project-native Fennel test runner.

## Global Constraints

- The control panel icon buttons sit directly adjacent to each other, with no Flex spacing inserted between buttons.
- The world selector buttons sit directly adjacent to each other, including the add-world button.
- Button-owned padding remains unchanged, so each button keeps its current size, touch target, icon/text padding, and rail-height alignment.
- HUD shell padding, rail metrics, status panel metrics, toolbar metrics, and global `Button`/`Flex` defaults remain unchanged.
- Do not change global `Button`, `Flex`, or `WorldTabsWidget` defaults.
- Do not change button padding or heights.
- Do not change right/left rail metrics, toolbar height, HUD band allocation, or right-rail panel overlay positioning.
- Do not remove spacing from unrelated dialogs, lists, forms, or graph views.
- Do not include or revisit commit `531d7be1 fix(ui): bottom-anchor right-rail panels below toolbar reserve`; that reviewed fix is already on this branch and is out of scope for this plan.

---

### Task 1: HUD Button Group Zero Spacing

**Files:**
- Modify: `assets/lua/hud-chrome-metrics.fnl`
- Modify: `assets/lua/hud-control-panel.fnl`
- Modify: `assets/lua/main.fnl`
- Modify: `assets/lua/tests/test-hud-control-panel.fnl`
- Modify: `assets/lua/tests/test-world-tabs-widget.fnl`
- Modify: `assets/lua/tests/test-hud-chrome-uniformity.fnl`
- Test: `assets/lua/tests/test-hud-control-panel.fnl`
- Test: `assets/lua/tests/test-world-tabs-widget.fnl`
- Test: `assets/lua/tests/test-hud-chrome-uniformity.fnl`
- Reference only: `assets/lua/hud-control-panel-layout.fnl`

**Interfaces:**
- Consumes: `HudChromeMetrics.control-row-spacing : number`, `WorldTabsWidget(opts)` with existing `opts.tab-spacing : number|nil`.
- Produces: `HudChromeMetrics.control-row-spacing == 0`, control-panel icon row `Flex` explicitly using `:xspacing HudChromeMetrics.control-row-spacing`, and HUD world-tabs construction using `WorldTabsWidget` with `:tab-spacing 0`.

**Acceptance criteria:**
- Focused tests prove the control-panel visible icon-button row width equals the sum of its child button widths.
- Focused tests prove the HUD world selector row width equals the sum of all tab/add button widths and includes the add-world button.
- Tests assert current button-owned padding/icon metrics remain unchanged.
- `WorldTabsWidget` default spacing remains untouched; only HUD construction passes zero.
- No `Button`, `Flex`, rail, toolbar, or right-rail panel behavior changes.

- [ ] **Step 1: Write the RED control-panel spacing test.**

  In `assets/lua/tests/test-hud-control-panel.fnl`, add `HudChromeMetrics` and `MathUtils` imports, an `assert-close` helper, row measurement helpers, and a new test. The helper should locate the six visible icon-button row under the default `HudControlPanel.ControlPanel` and compare the row width to the sum of its child button widths.

  Example shape:

  ```fennel
  (local HudChromeMetrics (require :hud-chrome-metrics))
  (local MathUtils (require :math-utils))
  (local approx (. MathUtils :approx))

  (fn assert-close [actual expected message]
    (assert (approx actual expected)
            (.. message "; expected " (tostring expected) ", got " (tostring actual))))

  (fn icon-button-row? [node]
    (and node.children
         (= (length node.children) 6)
         (accumulate [ok true _ child (ipairs node.children)]
           (and ok child.element child.element.icon))))

  (fn sum-flex-element-widths [row]
    (accumulate [sum 0 _ child (ipairs row.children)]
      (do
        (child.element.layout:measurer)
        (+ sum child.element.layout.measure.x))))

  (fn control-panel-icon-button-row-has-zero-spacing []
    (local clickables (make-clickables-stub))
    (local hoverables (make-hoverables-stub))
    (local icons (make-icons-stub))
    (local ctx
      (BuildContext {:clickables clickables
                     :hoverables hoverables
                     :icons icons
                     :pointer-target {}}))
    (local panel (((. HudControlPanel :ControlPanel) {}) ctx))
    (local row (assert (find-table panel icon-button-row?)
                       "Control panel should expose the six-button icon row"))
    (row.layout:measurer)
    (assert (= HudChromeMetrics.control-row-spacing 0)
            "HUD control row spacing metric should be zero for visible icon clusters")
    (assert-close row.layout.measure.x
                  (sum-flex-element-widths row)
                  "Control panel icon-button row width should equal sum of child button widths")
    (panel:drop))
  ```

- [ ] **Step 2: Run the control-panel test and confirm RED.**

  If `./build/space` is missing or stale, first run `make build` with timeout `14400000`.

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
    SPACE_ASSETS_PATH=$(pwd)/assets \
    FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    ./build/space -m tests.test-hud-control-panel:main
  ```

  Expected: FAIL because `HudChromeMetrics.control-row-spacing` is still `0.5`, and the icon-button row currently falls back to `Flex` default xspacing unless production code explicitly supplies zero.

- [ ] **Step 3: Write the RED HUD world selector spacing test.**

  In `assets/lua/tests/test-world-tabs-widget.fnl`, add a focused test for HUD world selector construction. Prefer a small exported helper from `main.fnl` if needed so the test verifies the actual HUD call site passes zero spacing, not just `WorldTabsWidget` in isolation. The test should build two world tab buttons plus the add-world button, then assert the row width equals the sum of the three child widths.

  Example expected assertion shape:

  ```fennel
  (fn sum-layout-child-widths [row-layout]
    (accumulate [sum 0 _ child-layout (ipairs row-layout.children)]
      (do
        (child-layout:measurer)
        (+ sum child-layout.measure.x))))

  (fn hud-world-selector-buttons-have-zero-spacing []
    (local ctx (make-test-ctx))
    (local world-manager
      (make-world-manager [{:index 1 :id "alpha" :name "home" :active? true}
                           {:index 2 :id "beta" :name "home-2" :active? false}]))
    (local builder (assert Main.build-hud-world-tabs-widget
                           "main should export HUD world tabs builder for focused tests"))
    (local widget ((builder world-manager) ctx))
    (widget.layout:measurer)
    (local row-layout (assert (. widget.layout.children 1)
                              "WorldTabsWidget should own a row layout"))
    (assert (= (length row-layout.children) 3)
            "HUD world selector should include two world buttons plus add-world button")
    (assert-close row-layout.measure.x
                  (sum-layout-child-widths row-layout)
                  "HUD world selector row width should equal sum of tab and add-world button widths")
    (widget:drop))
  ```

- [ ] **Step 4: Run the world-tabs test and confirm RED.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
    SPACE_ASSETS_PATH=$(pwd)/assets \
    FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    ./build/space -m tests.test-world-tabs-widget:main
  ```

  Expected: FAIL because the HUD world-tabs call site still uses `:tab-spacing 0.1`, or because the test-only helper does not exist yet if that route is chosen.

- [ ] **Step 5: Add a metric-preservation test.**

  In `assets/lua/tests/test-hud-chrome-uniformity.fnl`, add a test that asserts the existing button-owned sizing metrics remain unchanged:

  ```fennel
  (fn hud-chrome-button-sizing-metrics-remain-unchanged []
    (assert (= (. HudChromeMetrics.single-row-button-padding 1) 0.4)
            "single-row button horizontal padding should remain 0.4")
    (assert (= (. HudChromeMetrics.single-row-button-padding 2) 0.25)
            "single-row button vertical padding should remain 0.25")
    (assert (= (. HudChromeMetrics.rail-button-padding 1) 0.4)
            "rail button horizontal padding should remain 0.4")
    (assert (= (. HudChromeMetrics.rail-button-padding 2) 0.25)
            "rail button vertical padding should remain 0.25")
    (assert-close HudChromeMetrics.single-row-button-icon-style.scale 3.2
                  "single-row button icon scale should remain 3.2")
    (assert-close HudChromeMetrics.rail-button-icon-style.scale 3.2
                  "rail button icon scale should remain 3.2")
    (assert (= (. HudChromeMetrics.button-owned-shell-padding 1) 0)
            "control panel shell horizontal padding should remain button-owned/zero")
    (assert (= (. HudChromeMetrics.button-owned-shell-padding 2) 0)
            "control panel shell vertical padding should remain button-owned/zero"))
  ```

- [ ] **Step 6: Implement the minimal production change.**

  In `assets/lua/hud-chrome-metrics.fnl`, change only the control row spacing value:

  ```fennel
  :control-row-spacing 0
  ```

  In `assets/lua/hud-control-panel.fnl`, make the visible icon-button row consume the HUD metric explicitly:

  ```fennel
  (Flex
    {:axis 1
     :xspacing HudChromeMetrics.control-row-spacing
     :yalign :largest
     :children [...]})
  ```

  In `assets/lua/main.fnl`, use zero tab spacing for HUD world tabs. A small helper is acceptable if it keeps the call site testable:

  ```fennel
  (fn build-hud-world-tabs-widget [world-manager]
    (assert world-manager "build-hud-world-tabs-widget requires world-manager")
    (WorldTabsWidget {:world-manager world-manager
                      :tab-spacing 0}))

  (fn world-tab-status-builder []
    (assert app.world-manager "world-tab-status-builder requires app.world-manager")
    (fn [ctx]
      ((build-hud-world-tabs-widget app.world-manager) ctx)))
  ```

  If a helper is added for tests, export it from the final module return table without changing `init`, `drop`, `snapshot`, or `restore` behavior.

  Do not edit `assets/lua/world-tabs-widget.fnl`; its default `(or options.tab-spacing 0.1)` must remain independent.

- [ ] **Step 7: Run GREEN focused tests.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
    SPACE_ASSETS_PATH=$(pwd)/assets \
    FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    ./build/space -m tests.test-hud-control-panel:main

  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
    SPACE_ASSETS_PATH=$(pwd)/assets \
    FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    ./build/space -m tests.test-world-tabs-widget:main

  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
    SPACE_ASSETS_PATH=$(pwd)/assets \
    FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    ./build/space -m tests.test-hud-chrome-uniformity:main
  ```

  Expected: PASS.

- [ ] **Step 8: Run the validation ladder in Space Fennel order.**

  Runtime/freshness prerequisite when `./build/space` is missing or stale:

  ```bash
  make build
  ```

  Focused compile check first:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets \
    FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    ./build/space -m tools.fennel-check:main -- --target files \
      --file assets/lua/hud-chrome-metrics.fnl \
      --file assets/lua/hud-control-panel.fnl \
      --file assets/lua/main.fnl \
      --file assets/lua/tests/test-hud-control-panel.fnl \
      --file assets/lua/tests/test-world-tabs-widget.fnl \
      --file assets/lua/tests/test-hud-chrome-uniformity.fnl
  ```

  Constraints second:

  ```bash
  make constraints
  ```

  Focused Fennel tests third: run the three commands from Step 7.

  Related HUD test:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
    SPACE_ASSETS_PATH=$(pwd)/assets \
    FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    ./build/space -m tests.test-hud-layout:main
  ```

  Broader fast regression suite, justified because `main.fnl` HUD construction and shared HUD metrics are touched:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
    SPACE_ASSETS_PATH=$(pwd)/assets \
    FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
    ./build/space -m tests.fast:main
  ```

  E2E is required only if implementation updates HUD snapshots/goldens:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e
  ```

  PR CI is the full integration gate; do not claim ready-to-merge until PR CI is green.

- [ ] **Step 9: Commit the implementation.**

  ```bash
  git add \
    assets/lua/hud-chrome-metrics.fnl \
    assets/lua/hud-control-panel.fnl \
    assets/lua/main.fnl \
    assets/lua/tests/test-hud-control-panel.fnl \
    assets/lua/tests/test-world-tabs-widget.fnl \
    assets/lua/tests/test-hud-chrome-uniformity.fnl

  git commit -m "fix(ui): remove HUD control button gaps"
  ```

## Plan Self-Review

- Spec coverage: the plan covers zero spacing for the control icon cluster and HUD world selector, while preserving padding, height, rail, toolbar, and global defaults.
- Placeholder scan: no unresolved placeholder markers remain.
- Type consistency: all named metrics and functions match existing inspected code or are introduced in this plan.
- Scope check: one coherent implementation task is sufficient; the already-reviewed right-rail panel fix remains separate and out of scope.
