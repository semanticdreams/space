# Right Sidebar Rail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the right HUD sidebar rail visually match the left activity rail while sizing and anchoring from its measured button contents.

**Architecture:** Keep the existing HUD layout and extended sidebar ownership model. Remove the fixed right dock sizing wrapper from `hud-layout.fnl`, let `hud-extended-sidebar-view.fnl` measure its rail entity naturally, and anchor the rail at the right edge with the expanded panel directly to its left.

**Tech Stack:** Fennel widgets in `assets/lua/`, existing `Layout`, `Flex`, `Stack`, `Button`, `Rectangle`, `BuildContext`, and Fennel tests run through `./build/space`.

## Global Constraints

- Right rail buttons use `:padding [0.4 0.25]`.
- Right rail buttons use `:icon-style {:scale 3.2}`.
- Right rail buttons keep `:focusable? false`.
- The existing `panel-width 38` remains unchanged.
- Collapsed right sidebar root width equals the measured rail width.
- Expanded right sidebar root width equals `panel-width + measured rail width`.
- The expanded panel remains directly left of the rail.
- Do not change left activity dock behavior.
- Do not make the expanded Terminal/Space Agent panel naturally measured or resizable.
- Do not introduce a shared dock button abstraction in this change.
- Do not change sidebar entry registration, persistence, focus semantics, or panel lifecycle semantics.
- In Fennel layouters, assign child layout `position`, `rotation`, `size`, `depth-offset-index`, and `clip-region` directly; do not call `set-position` or `set-rotation` during layout.
- Do not add dependencies or new widget modules.

---

## File Structure

- Modify `assets/lua/hud-layout.fnl`: remove the fixed-width right dock `Sized` wrapper and insert the right dock as a natural `FlexChild`, matching the left dock pattern.
- Modify `assets/lua/hud-extended-sidebar-view.fnl`: update rail button metrics, remove the fixed `rail-width`, measure the rail entity, and right-anchor panel/rail layout.
- Modify `assets/lua/main.fnl`: stop passing `hud-opts.right-dock-width` in production HUD wiring.
- Modify `assets/lua/tests/test-hud-layout.fnl`: replace fixed-width right dock expectations with natural measured width expectations.
- Modify `assets/lua/tests/test-hud-extended-sidebar.fnl`: add focused tests for right rail button metrics, collapsed measurement, expanded measurement, and right-edge layout anchoring.
- Modify `docs/dev/notes/agent-hud-panel-design.md`: update the HUD integration note so it no longer documents fixed right dock rail width.

## Invariants and Compatibility Requirements

- Existing right sidebar select, toggle, collapse, focus clearing, panel caching, panel update, and drop behavior must remain unchanged.
- Existing left activity dock behavior and styling must remain unchanged.
- The right expanded panel width remains exactly `38` HUD units.
- Right sidebar child order remains panel first and rail last when expanded, rail only when collapsed.
- The right rail remains visible even when no entry is active.
- Button names remain `(string.format equivalent) "extended-sidebar-" .. id`; focus names remain entry labels.
- Right dock support remains optional in `HudLayout.make-hud-builder`.
- Existing callers that do not pass `right-dock-builder` continue to produce no right dock.
- Existing callers that still pass `right-dock-width` after this change receive no special behavior; no compatibility alias or shim is added.

## Observable Acceptance Criteria

- A right rail icon button measures the same as a reference button using `:padding [0.4 0.25]` and `:icon-style {:scale 3.2}`.
- `HudLayout.make-hud-builder` lays out a right dock using the dock widget's measured width, not `42`, `6`, or any `right-dock-width` option.
- A collapsed `HudExtendedSidebarView` root measures to the rail entity's measured width.
- An expanded `HudExtendedSidebarView` root measures to `38 + rail measured width`.
- In expanded layout, the rail's right edge equals the allocated root right edge, and the panel's right edge equals the rail's left edge.
- `rg -n "right-dock-width|default-right-dock-width|rail-width" assets/lua --glob '!tests/**'` finds no remaining right rail fixed-width implementation references.
- Focused HUD layout and extended sidebar tests pass.
- The full fast suite and full repository test command pass.

## Validation Ladder

1. Focused tests during implementation:
   ```sh
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-extended-sidebar:main
   ```
2. Complete relevant Fennel fast suite:
   ```sh
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.fast:main
   ```
3. Broader final checks justified by HUD layout risk:
   ```sh
   rg -n "right-dock-width|default-right-dock-width|rail-width" assets/lua --glob '!tests/**'
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
   ```

## Out of Scope

- No changes to left activity dock code.
- No resizable or naturally measured expanded Terminal/Space Agent panel.
- No shared dock button abstraction.
- No changes to sidebar data model, persistence, focus semantics, panel lifecycle, or registration APIs.
- No E2E snapshot updates unless existing snapshots fail and the human explicitly approves golden updates.

---

### Task 1: HUD Layout Uses Natural Right Dock Width

**Files:**
- Modify: `assets/lua/tests/test-hud-layout.fnl`
- Modify: `assets/lua/hud-layout.fnl`

**Interfaces:**
- Consumes: Existing `HudLayout.make-hud-builder(opts) -> builder`, existing `FlexChild(widget, flex)`, existing test helpers `fixed-widget`.
- Produces: `HudLayout.make-hud-builder` treats `opts.right-dock-builder` as a natural fixed-size `FlexChild`; `opts.right-dock-width` is no longer consumed.

- [ ] **Step 1: Replace the fixed-width right dock test with a natural-width test**

In `assets/lua/tests/test-hud-layout.fnl`, replace the existing `right-dock-width-is-in-hud-units` function with:

```fennel
(fn right-dock-uses-natural-measured-width []
  (local hud {:world-units-per-pixel 0.05
              :margin-px 0
              :half-width 50
              :half-height 15})
  (local ctx (BuildContext {:pointer-target hud}))
  (local builder
    (HudLayout.make-hud-builder
      {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
       :status-builder (fixed-widget "status" (glm.vec3 8 2 0))
       :right-dock-width 99
       :right-dock-builder (fixed-widget "right-dock" (glm.vec3 5 4 0))}))
  (local entity (builder ctx))
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 0 0 0))
  (set entity.layout.size entity.layout.measure)
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)
  (assert (= entity.right-dock-root.layout.size.x 5)
          "right dock should use its natural measured width, ignoring right-dock-width")
  (assert (= entity.tiles-root.layout.size.x 95)
          "tiles should reserve exactly the natural right dock width")
  (entity:drop))
```

Also update the test registration near the bottom from:

```fennel
(table.insert tests {:name "Hud layout right dock width is in HUD units"
                     :fn right-dock-width-is-in-hud-units})
```

to:

```fennel
(table.insert tests {:name "Hud layout right dock uses natural measured width"
                     :fn right-dock-uses-natural-measured-width})
```

- [ ] **Step 2: Run the focused HUD layout test and verify it fails for the current fixed wrapper**

Run:

```sh
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
```

Expected: FAIL with the natural width assertion because the current right dock is wrapped in `Sized`.

- [ ] **Step 3: Remove fixed right dock sizing from HUD layout**

In `assets/lua/hud-layout.fnl`:

1. Remove the unused import:

```fennel
(local Sized (require :sized))
```

2. Remove this constant:

```fennel
(local default-right-dock-width 42)
```

3. Replace the current right dock insertion block:

```fennel
(when right-dock
  (local right-dock-width (or options.right-dock-width default-right-dock-width))
  (table.insert base-children
                (FlexChild (fn [_ctx] ((Sized {:size (glm.vec3 right-dock-width 0 0)
                                                :child (fn [_ctx] right-dock)})
                                       _ctx)))))
```

with:

```fennel
(when right-dock
  (table.insert base-children (FlexChild (fn [_ctx] right-dock))))
```

Do not add a compatibility path for `options.right-dock-width`.

- [ ] **Step 4: Run the focused HUD layout test and verify it passes**

Run:

```sh
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
```

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```sh
git add assets/lua/tests/test-hud-layout.fnl assets/lua/hud-layout.fnl
git commit -m "feat(ui): use natural right dock width"
```

---

### Task 2: Extended Sidebar Rail Measures and Anchors Naturally

**Files:**
- Modify: `assets/lua/tests/test-hud-extended-sidebar.fnl`
- Modify: `assets/lua/hud-extended-sidebar-view.fnl`

**Interfaces:**
- Consumes: Existing `HudExtendedSidebarView(sidebar) -> builder`, `HudExtendedSidebar`, `Button`, `Layout`, and `BuildContext`.
- Produces: `HudExtendedSidebarView` root measurement and layout contract:
  - collapsed measure: `(glm.vec3 rail-measured-width 0 0)`
  - expanded measure: `(glm.vec3 (+ 38 rail-measured-width) 0 0)`
  - layouter positions rail at `self.position + self.rotation:rotate(glm.vec3 (- allocated-width rail-width) 0 0)`
  - layouter positions panel immediately left of rail with width `38`.

- [ ] **Step 1: Add required test imports**

In `assets/lua/tests/test-hud-extended-sidebar.fnl`, add these imports after the existing imports:

```fennel
(local Button (require :button))
(local MathUtils (require :math-utils))
(local approx (. MathUtils :approx))
```

- [ ] **Step 2: Add the rail button metric test**

Add this test function before the test registration section:

```fennel
(fn view-rail-button-matches-activity-button-metrics []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))})
  (local ctx (make-widget-ctx))
  (local entity ((HudExtendedSidebarView sidebar) ctx))
  (entity.layout:measurer)
  (local rail-button (. ctx.clickables.left-click-objects 1))
  (assert rail-button "right rail should register a clickable button")
  (assert (= rail-button.icon :test_icon) "right rail button should keep the entry icon")
  (assert (= rail-button.text.child.style.scale 3.2)
          "right rail icon style should match activity dock icon scale")
  (local reference-button
    ((Button {:padding [0.4 0.25]
              :focusable? false
              :icon :test_icon
              :icon-style {:scale 3.2}
              :name "reference-extended-sidebar-test"
              :focus-name "Test"
              :on-click (fn [_button _event] nil)
              :variant :secondary})
     ctx))
  (reference-button.layout:measurer)
  (assert (approx rail-button.layout.measure.x reference-button.layout.measure.x)
          "right rail button width should match the activity-style reference button")
  (assert (approx rail-button.layout.measure.y reference-button.layout.measure.y)
          "right rail button height should match the activity-style reference button")
  (reference-button:drop)
  (entity:drop))
```

- [ ] **Step 3: Add collapsed and expanded measurement tests**

Add these test functions after the rail button metric test:

```fennel
(fn view-collapsed-width-equals-measured-rail-width []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))})
  (local ctx (make-widget-ctx))
  (local entity ((HudExtendedSidebarView sidebar) ctx))
  (entity.layout:measurer)
  (local rail-layout (. entity.layout.children 1))
  (assert rail-layout "collapsed sidebar should contain the rail layout")
  (assert (approx entity.layout.measure.x rail-layout.measure.x)
          "collapsed sidebar width should equal measured rail width")
  (entity:drop))

(fn view-expanded-width-equals-panel-plus-measured-rail-width []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))})
  (sidebar:select :test)
  (local ctx (make-widget-ctx))
  (local entity ((HudExtendedSidebarView sidebar) ctx))
  (entity.layout:measurer)
  (local panel-layout (. entity.layout.children 1))
  (local rail-layout (. entity.layout.children 2))
  (assert panel-layout "expanded sidebar should contain the active panel layout")
  (assert rail-layout "expanded sidebar should contain the rail layout")
  (assert (approx entity.layout.measure.x (+ 38 rail-layout.measure.x))
          "expanded sidebar width should equal panel width plus measured rail width")
  (entity:drop))
```

- [ ] **Step 4: Add the right-edge anchoring layout test**

Add this test function after the measurement tests:

```fennel
(fn view-expanded-layout-anchors-rail-to-right-edge []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))})
  (sidebar:select :test)
  (local ctx (make-widget-ctx))
  (local entity ((HudExtendedSidebarView sidebar) ctx))
  (entity.layout:measurer)
  (local panel-layout (. entity.layout.children 1))
  (local rail-layout (. entity.layout.children 2))
  (local allocated-width (+ entity.layout.measure.x 5))
  (set entity.layout.position (glm.vec3 10 20 0))
  (set entity.layout.size (glm.vec3 allocated-width 12 0))
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)
  (local rail-width rail-layout.measure.x)
  (local expected-rail-x (+ 10 (- allocated-width rail-width)))
  (local expected-panel-x (- expected-rail-x 38))
  (assert (approx rail-layout.position.x expected-rail-x)
          "rail should be positioned at the right edge of the allocated sidebar area")
  (assert (approx rail-layout.size.x rail-width)
          "rail layout width should equal measured rail width")
  (assert (approx panel-layout.position.x expected-panel-x)
          "panel should be immediately left of the rail")
  (assert (approx panel-layout.size.x 38)
          "expanded panel width should remain fixed at 38 HUD units")
  (entity:drop))
```

- [ ] **Step 5: Register the new extended sidebar tests**

Add these registrations before `local main`:

```fennel
(table.insert tests {:name "view rail button matches activity button metrics"
                     :fn view-rail-button-matches-activity-button-metrics})
(table.insert tests {:name "view collapsed width equals measured rail width"
                     :fn view-collapsed-width-equals-measured-rail-width})
(table.insert tests {:name "view expanded width equals panel plus measured rail width"
                     :fn view-expanded-width-equals-panel-plus-measured-rail-width})
(table.insert tests {:name "view expanded layout anchors rail to right edge"
                     :fn view-expanded-layout-anchors-rail-to-right-edge})
```

- [ ] **Step 6: Run the focused extended sidebar test and verify it fails**

Run:

```sh
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-extended-sidebar:main
```

Expected: FAIL because the current rail uses `:padding [0.4 0.2]`, `:icon-style {:scale 2.4}`, fixed `rail-width 6`, and left-origin layout.

- [ ] **Step 7: Update right rail button styling**

In `assets/lua/hud-extended-sidebar-view.fnl`, change the `Button` options in `build-rail` from:

```fennel
(Button {:padding [0.4 0.2]
         :focusable? false
         :icon entry.icon
         :icon-style {:scale 2.4}
```

to:

```fennel
(Button {:padding [0.4 0.25]
         :focusable? false
         :icon entry.icon
         :icon-style {:scale 3.2}
```

Keep existing `:name`, `:focus-name`, `:on-click`, and `:variant` expressions unchanged.

- [ ] **Step 8: Remove the fixed rail width constant**

In `assets/lua/hud-extended-sidebar-view.fnl`, remove:

```fennel
(local rail-width 6)
```

Keep:

```fennel
(local panel-width 38)
```

- [ ] **Step 9: Add local measurement helpers**

Inside the `build` closure in `assets/lua/hud-extended-sidebar-view.fnl`, after the existing local state variables, add:

```fennel
(fn rail-measure []
  (or (and rail-entity rail-entity.layout rail-entity.layout.measure)
      (glm.vec3 0 0 0)))

(fn rail-measured-width []
  (. (rail-measure) 1))

(fn allocated-root-width [self]
  (math.max (or (and self.measure self.measure.x) 0)
            (or (and self.size self.size.x) 0)))
```

- [ ] **Step 10: Update the root measurer to use rail measurement**

Replace the existing `measurer` function body:

```fennel
(each [_ child (ipairs (or self.children []))]
  (child:measurer))
(local total-width (if (and sidebar.expanded? sidebar.active-id active-panel-entity)
                       (+ rail-width panel-width)
                       rail-width))
(set self.measure (glm.vec3 total-width 0 0))
```

with:

```fennel
(each [_ child (ipairs (or self.children []))]
  (child:measurer))
(local current-rail-width (rail-measured-width))
(local total-width (if (and sidebar.expanded? sidebar.active-id active-panel-entity)
                       (+ panel-width current-rail-width)
                       current-rail-width))
(set self.measure (glm.vec3 total-width 0 0))
```

- [ ] **Step 11: Update the root layouter to right-anchor the rail**

Replace the existing `layouter` function body with:

```fennel
(local base-position self.position)
(local base-rotation self.rotation)
(local base-depth (or self.depth-offset-index 0))
(local height (or (and self.size self.size.y) 0))
(local current-rail-width (rail-measured-width))
(local allocated-width (allocated-root-width self))
(set self.size (glm.vec3 allocated-width height 0))
(local rail-offset (glm.vec3 (- allocated-width current-rail-width) 0 0))
(local rail-position (+ base-position (base-rotation:rotate rail-offset)))
(when active-panel-entity
  (local panel-offset (glm.vec3 (- allocated-width current-rail-width panel-width) 0 0))
  (set active-panel-entity.layout.position (+ base-position (base-rotation:rotate panel-offset)))
  (set active-panel-entity.layout.size (glm.vec3 panel-width height 0))
  (set active-panel-entity.layout.rotation base-rotation)
  (set active-panel-entity.layout.clip-region self.clip-region)
  (set active-panel-entity.layout.depth-offset-index (+ base-depth 1))
  (active-panel-entity.layout:layouter))
(when rail-entity
  (set rail-entity.layout.position rail-position)
  (set rail-entity.layout.size (glm.vec3 current-rail-width height 0))
  (set rail-entity.layout.rotation base-rotation)
  (set rail-entity.layout.clip-region self.clip-region)
  (set rail-entity.layout.depth-offset-index (+ base-depth 1))
  (rail-entity.layout:layouter))
```

- [ ] **Step 12: Run the focused extended sidebar test and verify it passes**

Run:

```sh
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-extended-sidebar:main
```

Expected: PASS.

- [ ] **Step 13: Re-run HUD layout focused tests to catch integration regressions**

Run:

```sh
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
```

Expected: PASS.

- [ ] **Step 14: Commit Task 2**

```sh
git add assets/lua/tests/test-hud-extended-sidebar.fnl assets/lua/hud-extended-sidebar-view.fnl
git commit -m "feat(ui): measure right sidebar rail naturally"
```

---

### Task 3: Production Wiring and Developer Documentation

**Files:**
- Modify: `assets/lua/main.fnl`
- Modify: `docs/dev/notes/agent-hud-panel-design.md`

**Interfaces:**
- Consumes: Task 1's `HudLayout.make-hud-builder` natural right dock behavior and Task 2's `HudExtendedSidebarView` measured rail behavior.
- Produces: Production HUD setup passes only `:right-dock-builder`; developer docs describe the current right rail natural sizing contract.

- [ ] **Step 1: Remove production `right-dock-width` assignment**

In `assets/lua/main.fnl`, inside `apply-active-world-hud-contrib`, change:

```fennel
(when app.agent-runner
  (ensure-extended-sidebar!)
  (set hud-opts.right-dock-builder (HudExtendedSidebarView app.extended-sidebar))
  (set hud-opts.right-dock-width 6))
```

to:

```fennel
(when app.agent-runner
  (ensure-extended-sidebar!)
  (set hud-opts.right-dock-builder (HudExtendedSidebarView app.extended-sidebar)))
```

- [ ] **Step 2: Update the developer note's HUD layout text**

In `docs/dev/notes/agent-hud-panel-design.md`, update the "Layout" section so it no longer says the right dock should receive a stable fixed width. Replace the fixed-width guidance with:

```markdown
The right dock is an extended sidebar: a naturally measured rail on the right and,
when expanded, a fixed-width panel immediately to the rail's left. The rail width
comes from its activity-style icon buttons; message text, session names, and tool
names do not affect rail width. The expanded panel keeps the HUD sidebar panel
width contract owned by `hud-extended-sidebar-view.fnl`.

Initial sizing:

- Rail: measured from icon button contents.
- Expanded panel: fixed HUD logical width from `hud-extended-sidebar-view.fnl`.
- Height: fill the middle band between the existing control panel and status panel.
- Depth: use the same dock depth layer pattern as the left dock; transcript rows
  should use child depth offsets instead of fighting with the dock background.
```

Keep the existing "HUD Integration" section's recommendation to use `right-dock-builder`.

- [ ] **Step 3: Verify no right dock width wiring remains in Fennel assets**

Run:

```sh
rg -n "right-dock-width|default-right-dock-width|rail-width" assets/lua --glob '!tests/**'
```

Expected: no production implementation matches. The HUD layout test may still mention `right-dock-width` to prove the option is ignored.

- [ ] **Step 4: Run focused HUD tests after production wiring removal**

Run:

```sh
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-extended-sidebar:main
```

Expected: both PASS.

- [ ] **Step 5: Commit Task 3**

```sh
git add assets/lua/main.fnl docs/dev/notes/agent-hud-panel-design.md
git commit -m "docs(ui): document measured right sidebar rail"
```

---

### Task 4: Final Validation and Integration Check

**Files:**
- Test: `assets/lua/tests/test-hud-layout.fnl`
- Test: `assets/lua/tests/test-hud-extended-sidebar.fnl`
- Test: `assets/lua/tests/fast.fnl`
- Test: repository test suite via `make test`

**Interfaces:**
- Consumes: All production and test changes from Tasks 1-3.
- Produces: Verified implementation ready for review.

- [ ] **Step 1: Run the two focused suites**

```sh
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-extended-sidebar:main
```

Expected: both PASS.

- [ ] **Step 2: Run the fast suite**

```sh
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.fast:main
```

Expected: PASS.

- [ ] **Step 3: Run the repository-wide final test command from AGENTS.md**

```sh
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: PASS.

- [ ] **Step 4: Run implementation invariant greps**

```sh
rg -n "right-dock-width|default-right-dock-width|rail-width" assets/lua --glob '!tests/**'
rg -n ":icon-style \{:scale 2\.4\}|:padding \[0\.4 0\.2\]" assets/lua/hud-extended-sidebar-view.fnl
```

Expected: no production implementation matches.

- [ ] **Step 5: Inspect git status**

```sh
git status --short
```

Expected: clean working tree after Task 1, Task 2, and Task 3 commits.
