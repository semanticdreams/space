# HUD Chrome Button-Owned Padding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the control panel and Sandbox toolbar use rail-like button-owned padding so their natural height matches rail width without outer shell padding.

**Architecture:** Split shared HUD chrome metrics so button-owned chrome and status text-row chrome no longer share one shell-padding value. Control/Sandbox keep `Card` backgrounds, but the wrapper padding becomes zero and the buttons carry the cross-axis padding that determines height.

**Tech Stack:** Space Fennel UI widgets (`Button`, `Card`, `Padding`, `Flex`), Fennel tests in `assets/lua/tests`, E2E PNG snapshots, validation via `tools.fennel-check`, `make constraints`, focused tests, `tests.fast:main`, and `make test-e2e`.

## Global Constraints

- Remove outer/shell padding as a sizing contributor from the top control panel.
- Remove outer/shell padding as a sizing contributor from the Sandbox Flight/Move/Anchor toolbar.
- Preserve the solid background for both surfaces.
- Keep the final natural height matched to the side rail width.
- Express matching through button/icon metrics, not fixed container sizes.
- Preserve the current status panel sizing and behavior.
- No changes to rail appearance or rail metrics.
- No changes to status panel metrics.
- No fixed `Sized` wrappers, fixed toolbar heights, or HUD band changes.
- No global `Button` default changes.
- No Sandbox toolbar behavior changes beyond visual sizing.
- Follow Space Fennel idioms: `local` instead of `let`, builders return closures, composite widgets own/drop direct children, and missing required context should assert.
- Validation order for Fennel/UI changes: compile check, constraints, focused Fennel tests, broader relevant suite, and E2E snapshots when visual goldens change.

---

### Task 1: Button-Owned Control and Sandbox Padding

**Files:**
- Modify: `assets/lua/hud-chrome-metrics.fnl`
- Modify: `assets/lua/hud-control-panel-layout.fnl`
- Modify: `assets/lua/sandbox-toolbar-view.fnl`
- Modify: `assets/lua/tests/test-hud-chrome-uniformity.fnl`
- Modify: `assets/lua/tests/data/snapshots/*.png` only if `make test-e2e` proves intentional snapshot changes.

**Interfaces:**
- Consumes: existing `HudChromeMetrics` table.
- Produces updated metrics:
  - `single-row-button-padding` remains the control/Sandbox button padding key and becomes `[0.4 0.4]`.
  - New `button-owned-shell-padding` is `[0 0]` and is used by control panel and Sandbox toolbar shells.
  - Existing `single-row-shell-padding` remains `[0.6 0.3]` for status/text-row chrome.

- [ ] **Step 1: Add failing test coverage for zero shell padding logic**

  In `assets/lua/tests/test-hud-chrome-uniformity.fnl`, require metrics:

  ```fennel
  (local HudChromeMetrics (require :hud-chrome-metrics))
  ```

  Add a test that proves button-owned chrome gets its cross-axis size from icon plus button padding, not shell padding:

  ```fennel
  (fn hud-chrome-button-owned-metrics-match-rail-cross-axis []
    (local icon-height HudChromeMetrics.single-row-button-icon-style.scale)
    (local button-padding-y (. HudChromeMetrics.single-row-button-padding 2))
    (local shell-padding-y (. HudChromeMetrics.button-owned-shell-padding 2))
    (local natural-height (+ icon-height (* 2 button-padding-y) (* 2 shell-padding-y)))
    (local rail-width (+ HudChromeMetrics.rail-button-icon-style.scale
                         (* 2 (. HudChromeMetrics.rail-button-padding 1))))
    (assert-close natural-height rail-width
                  "button-owned chrome metrics should match rail cross-axis without shell padding")
    (assert-close shell-padding-y 0
                  "button-owned chrome shell padding should not contribute to height"))
  ```

  Register it:

  ```fennel
  (table.insert tests {:name "HUD chrome button-owned metrics match rail cross-axis"
                       :fn hud-chrome-button-owned-metrics-match-rail-cross-axis})
  ```

- [ ] **Step 2: Run the focused test and verify RED**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-chrome-uniformity:main
  ```

  Expected: FAIL because `button-owned-shell-padding` does not exist yet, or because shell padding still contributes to height.

- [ ] **Step 3: Update shared metrics**

  Change `assets/lua/hud-chrome-metrics.fnl` to include:

  ```fennel
  :single-row-button-padding [0.4 0.4]
  :button-owned-shell-padding [0 0]
  :single-row-shell-padding [0.6 0.3]
  ```

  Keep rail metrics and status metrics unchanged.

- [ ] **Step 4: Use zero shell padding in the control panel**

  In `assets/lua/hud-control-panel-layout.fnl`, change the `Padding` around the row from:

  ```fennel
  :edge-insets HudChromeMetrics.single-row-shell-padding
  ```

  to:

  ```fennel
  :edge-insets HudChromeMetrics.button-owned-shell-padding
  ```

- [ ] **Step 5: Use zero shell padding in the Sandbox toolbar**

  In `assets/lua/sandbox-toolbar-view.fnl`, change the `Padding` around `row-builder` from:

  ```fennel
  :edge-insets HudChromeMetrics.single-row-shell-padding
  ```

  to:

  ```fennel
  :edge-insets HudChromeMetrics.button-owned-shell-padding
  ```

  Do not change state, button labels, variant logic, click handlers, update, or drop behavior.

- [ ] **Step 6: Run focused validation**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/hud-chrome-metrics.fnl --file assets/lua/hud-control-panel-layout.fnl --file assets/lua/sandbox-toolbar-view.fnl --file assets/lua/tests/test-hud-chrome-uniformity.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-chrome-uniformity:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-control-panel:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-toolbar-view:main
  ```

  Expected: PASS.

- [ ] **Step 7: Run broader visual validation and update goldens if needed**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e
  ```

  If E2E fails with intended HUD chrome snapshot differences, update only affected goldens using `SPACE_SNAPSHOT_UPDATE=<comma-separated-names>`, visually inspect updated PNGs, rerun `make test-e2e`, and do not commit `.actual.png` files.

- [ ] **Step 8: Commit Task 1**

  ```bash
  git add assets/lua/hud-chrome-metrics.fnl assets/lua/hud-control-panel-layout.fnl assets/lua/sandbox-toolbar-view.fnl assets/lua/tests/test-hud-chrome-uniformity.fnl assets/lua/tests/data/snapshots
  git commit -m "fix(ui): make HUD toolbar padding button-owned"
  ```

---

### Task 2: Final Validation

**Files:**
- Test: all files changed by Task 1.

**Interfaces:**
- Consumes: Task 1 implementation and any reviewed snapshot updates.
- Produces: final local validation evidence before PR integration.

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

- [ ] **Step 3: Run focused and broad tests**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-chrome-uniformity:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e
  ```

  Expected: PASS.

- [ ] **Step 4: Confirm no fixed-size regression and clean tree**

  ```bash
  rg -n "\(require :sized\)|\bSized\b|top-toolbar-height|sandbox-toolbar-height|fixed.*height|fixed.*width" assets/lua/hud-chrome-metrics.fnl assets/lua/hud-control-panel-layout.fnl assets/lua/sandbox-toolbar-view.fnl assets/lua/tests/test-hud-chrome-uniformity.fnl
  git status --porcelain
  ```

  Expected: no fixed-size matches and a clean tree.
