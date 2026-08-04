# HUD Right-Rail Transparent Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the expanded HUD right rail reserve only rail width in parent layout while projecting the active panel left of the rail below the toolbar reserve.

**Architecture:** Keep `HudExtendedSidebarView` as the owner of expanded panel placement. Change its natural measurement to rail-only, leaving `hud-layout` unchanged so the parent naturally reserves only the child's measured rail width. Add focused sidebar contract coverage and HUD-layout integration coverage for the rail-only reservation invariant.

**Tech Stack:** Space Fennel widgets, custom `Layout` measurer/layouter, `HudLayout.make-hud-builder`, project-native `tools.fennel-check`, constraints, and Fennel runtime tests via `./build/space`.

## Global Constraints

- Use the rail as the only in-flow width for `HudExtendedSidebarView`.
- In expanded state the terminal/chat panel remains a child of the extended sidebar, but it is laid out as a flyout projected to the left of the rail, below the toolbar reserve.
- The parent HUD layout should reserve only the rail width in the middle flex band whether the panel is collapsed or expanded.
- No behavior change is intended in `assets/lua/hud-layout.fnl`.
- No new runtime fallback paths are introduced.
- Missing required context continues to surface through existing assertions/errors.
- The fix must avoid legacy aliases or compatibility shims and must not change behavior outside the transparent-strip bug.
- Scope is limited to `assets/lua/hud-extended-sidebar-view.fnl`, `assets/lua/tests/test-hud-extended-sidebar.fnl`, and `assets/lua/tests/test-hud-layout.fnl`.
- Supervisor must not edit production or test code; implementation must run through implementer, then reviewer, and the supervisor commits only after reviewer pass.

---

## File Structure

- `assets/lua/hud-extended-sidebar-view.fnl`
  - Responsibility: Own extended sidebar child construction, measurement, and layout.
  - Change: `measurer` reports measured rail width only, regardless of expanded state.
  - Preserve: active panel remains a child while expanded; rail remains full-height at the right edge; panel keeps fixed `panel-width` and uses existing top reserve handling.

- `assets/lua/tests/test-hud-extended-sidebar.fnl`
  - Responsibility: Direct contract tests for sidebar state, measurement, layout, culling, render-resource cleanup, and toolbar reserve behavior.
  - Change: Replace the expanded width expectation from `panel + rail` to `rail` and tighten layout coverage for natural rail-width allocation projecting the panel left of root bounds.

- `assets/lua/tests/test-hud-layout.fnl`
  - Responsibility: HUD parent layout contract tests.
  - Change: Add integration coverage proving an expanded `HudExtendedSidebarView` used as the right dock causes top toolbar/center content to reserve rail width only.

## Acceptance Criteria

- Expanded `HudExtendedSidebarView` measured width equals rail width, not rail plus panel width.
- Expanded panel is laid out immediately left of the rail when the root is allocated only rail width.
- Expanded panel continues honoring `top-reserve-height-provider` vertically.
- HUD layout reserves only the expanded right sidebar's measured rail width, preserving top toolbar center-column render space.
- No production changes are made to `assets/lua/hud-layout.fnl`.

## Validation Ladder

Runtime/freshness prerequisite when `./build/space` is missing or stale:

```bash
make build
```

Focused checks, in required Fennel order:

1. Compile touched files first:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/hud-extended-sidebar-view.fnl --file assets/lua/tests/test-hud-extended-sidebar.fnl --file assets/lua/tests/test-hud-layout.fnl
```

2. Run constraints:

```bash
make constraints
```

3. Run focused Fennel tests:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-extended-sidebar:main
```

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
```

The two focused HUD suites above are the complete relevant local suite for this bounded change. Do not run full `make test` by default unless reviewer evidence shows broader HUD/runtime risk.

Fennel repair guidance: if delimiter or parse errors occur, inspect the nearest enclosing form around the reported location first; if the form is deeply nested, move logic into a helper instead of guessing at closing delimiters.

---

### Task 1: Rail-Only Expanded Sidebar Measurement and HUD Integration Tests

**Files:**
- Modify: `assets/lua/hud-extended-sidebar-view.fnl`
- Test: `assets/lua/tests/test-hud-extended-sidebar.fnl`
- Test: `assets/lua/tests/test-hud-layout.fnl`

**Interfaces:**
- Consumes: existing `HudExtendedSidebarView(sidebar, opts?) -> build(ctx) -> entity` contract, existing `Layout:measurer`, existing `Layout:layouter`, existing `HudLayout.make-hud-builder(opts)`.
- Produces: `HudExtendedSidebarView` natural measurement invariant: `entity.layout.measure.x == measured rail width` in collapsed and expanded states.

- [ ] **Step 1: Update the direct expanded-width test before production code**

  In `assets/lua/tests/test-hud-extended-sidebar.fnl`, replace the existing function named `view-expanded-width-equals-panel-plus-measured-rail-width` with this rail-only expectation:

  ```fennel
  (fn view-expanded-width-equals-measured-rail-width []
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
    (assert (approx entity.layout.measure.x rail-layout.measure.x)
            "expanded sidebar width should equal measured rail width")
    (assert (not (approx entity.layout.measure.x (+ 38 rail-layout.measure.x)))
            "expanded sidebar width should not include panel width")
    (entity:drop))
  ```

  Update the matching table registration from:

  ```fennel
  (table.insert tests {:name "view expanded width equals panel plus measured rail width"
                       :fn view-expanded-width-equals-panel-plus-measured-rail-width})
  ```

  to:

  ```fennel
  (table.insert tests {:name "view expanded width equals measured rail width"
                       :fn view-expanded-width-equals-measured-rail-width})
  ```

- [ ] **Step 2: Tighten the direct layout projection test before production code**

  In `assets/lua/tests/test-hud-extended-sidebar.fnl`, update `view-expanded-layout-anchors-rail-to-right-edge` so the allocated width is the sidebar's natural measured width, not measured width plus extra space:

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
    (local allocated-width entity.layout.measure.x)
    (set entity.layout.position (glm.vec3 10 20 0))
    (set entity.layout.size (glm.vec3 allocated-width 12 0))
    (set entity.layout.rotation (glm.quat 1 0 0 0))
    (set entity.layout.clip-region nil)
    (set entity.layout.depth-offset-index 0)
    (entity.layout:layouter)
    (local rail-width rail-layout.measure.x)
    (local expected-rail-x 10)
    (local expected-panel-x (- expected-rail-x 38))
    (assert (approx allocated-width rail-width)
            "natural allocated sidebar width should equal rail width")
    (assert (approx rail-layout.position.x expected-rail-x)
            "rail should be positioned at the right edge of the rail-width sidebar area")
    (assert (approx rail-layout.size.x rail-width)
            "rail layout width should equal measured rail width")
    (assert (approx panel-layout.position.x expected-panel-x)
            "panel should project left of the rail-width sidebar root")
    (assert (approx panel-layout.size.x 38)
            "expanded panel width should remain fixed at 38 HUD units")
    (entity:drop))
  ```

- [ ] **Step 3: Add HUD-layout integration test before production code**

  In `assets/lua/tests/test-hud-layout.fnl`, add these requires near the top if the file does not already require them:

  ```fennel
  (local HudExtendedSidebar (require :hud-extended-sidebar))
  (local HudExtendedSidebarView (require :hud-extended-sidebar-view))
  (local Intersectables (require :intersectables))
  (local Clickables (require :clickables))
  (local Hoverables (require :hoverables))
  (local MathUtils (require :math-utils))
  (local approx (. MathUtils :approx))
  ```

  Add these helpers after the existing `captured-widget` helper if equivalent helpers do not already exist:

  ```fennel
  (fn make-test-theme []
    {:font nil
     :card {:background (glm.vec4 0.1 0.12 0.16 0.96)}})

  (fn make-icons-stub []
    (local glyph {:advance 1})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {4242 glyph}
                 :advance 1})
    {:font font
     :resolve (fn [_self _name]
                {:type :font
                 :codepoint 4242
                 :font font})
     :get (fn [_self _name] 4242)})

  (fn make-hud-widget-ctx [hud]
    (local intersector (Intersectables))
    (local clickables (assert (Clickables {:intersectables intersector}) "HUD layout test context requires clickables"))
    (local hoverables (assert (Hoverables {:intersectables intersector}) "HUD layout test context requires hoverables"))
    (BuildContext {:pointer-target hud
                   :clickables clickables
                   :hoverables hoverables
                   :icons (make-icons-stub)
                   :theme (make-test-theme)}))
  ```

  Add this test function before the table inserts:

  ```fennel
  (fn right-dock-expanded-sidebar-reserves-rail-width-only []
    (local hud {:world-units-per-pixel 1
                :margin-px 0
                :half-width 50
                :half-height 20})
    (local sidebar (HudExtendedSidebar))
    (sidebar:register-entry {:id :test
                              :icon :test_icon
                              :label "Test"
                              :build-panel (fixed-widget "right-panel" (glm.vec3 38 10 0))})
    (sidebar:select :test)
    (local ctx (make-hud-widget-ctx hud))
    (local builder
      (HudLayout.make-hud-builder
        {:control-builder (fixed-widget "control" (glm.vec3 100 3 0))
         :status-builder (fixed-widget "status" (glm.vec3 100 2 0))
         :right-dock-builder (HudExtendedSidebarView sidebar)
         :top-toolbar-builder (fixed-widget "toolbar" (glm.vec3 20 4 0))}))
    (local entity (builder ctx))
    (entity.layout:measurer)
    (set entity.layout.position (glm.vec3 0 0 0))
    (set entity.layout.size entity.layout.measure)
    (set entity.layout.rotation (glm.quat 1 0 0 0))
    (set entity.layout.clip-region nil)
    (set entity.layout.depth-offset-index 0)
    (entity.layout:layouter)
    (local right-dock entity.right-dock-root)
    (local rail-layout (. right-dock.layout.children 2))
    (assert rail-layout "expanded sidebar right dock should contain the rail as its second child")
    (local rail-width rail-layout.measure.x)
    (assert (approx right-dock.layout.measure.x rail-width)
            "expanded right sidebar dock should measure as rail width only")
    (assert (approx right-dock.layout.size.x rail-width)
            "HUD layout should allocate only measured rail width to the right dock")
    (assert (approx entity.top-toolbar-root.layout.size.x (- 100 rail-width))
            "top toolbar should reserve only rail width for the expanded right sidebar")
    (entity:drop))
  ```

  Register it near the other right-dock HUD layout tests:

  ```fennel
  (table.insert tests {:name "Hud layout expanded right sidebar reserves rail width only"
                       :fn right-dock-expanded-sidebar-reserves-rail-width-only})
  ```

- [ ] **Step 4: Run focused tests and verify they fail for the current bug**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-extended-sidebar:main
  ```

  Expected: FAIL on rail-only expanded measurement/layout expectations.

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
  ```

  Expected: FAIL because the expanded right dock still measures as panel plus rail.

- [ ] **Step 5: Implement the rail-only measurement**

  In `assets/lua/hud-extended-sidebar-view.fnl`, replace the current `measurer` body:

  ```fennel
  (fn measurer [self]
    (each [_ child (ipairs (or self.children []))]
      (child:measurer))
    (local rail-w (rail-measured-w))
    (local total-width (if (and sidebar.expanded? sidebar.active-id active-panel-entity)
                           (+ panel-width rail-w)
                           rail-w))
    (set self.measure (glm.vec3 total-width 0 0)))
  ```

  with:

  ```fennel
  (fn measurer [self]
    (each [_ child (ipairs (or self.children []))]
      (child:measurer))
    (local rail-w (rail-measured-w))
    (set self.measure (glm.vec3 rail-w 0 0)))
  ```

  Do not change `panel-width`, `layouter`, child ordering, culling, focus clearing, or rebuild behavior unless a focused test demonstrates a defect in those existing paths.

- [ ] **Step 6: Run compile check for touched files**

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/hud-extended-sidebar-view.fnl --file assets/lua/tests/test-hud-extended-sidebar.fnl --file assets/lua/tests/test-hud-layout.fnl
  ```

  Expected: PASS.

- [ ] **Step 7: Run constraints**

  ```bash
  make constraints
  ```

  Expected: PASS. Constraint-impact note for handoff: changed Fennel UI/layout behavior; no constraint baseline changes expected.

- [ ] **Step 8: Run focused tests and verify they pass**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-extended-sidebar:main
  ```

  Expected: PASS.

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
  ```

  Expected: PASS.

- [ ] **Step 9: Report implementation and validation evidence without committing**

  Append the full handoff to the SDD report file. Include:
  - Tests that failed before production change and their expected failure reason.
  - Compile-check command and result.
  - Constraints command and result, with constraint-impact note.
  - Focused test commands and results.
  - Confirmation that only the three scoped files were modified.
  - Do not commit; the supervisor will commit reviewed changes after reviewer pass.

## Explicitly Out of Scope

- Editing `assets/lua/hud-layout.fnl`.
- Moving the HUD toolbar or changing parent HUD layout architecture.
- Adding compatibility aliases, feature flags, or fallback layout paths.
- Changing panel width, visual styling, button metrics, culling semantics, focus behavior, or render-resource cleanup.
- Running broad local `make test` unless reviewer evidence or unexpected failures expand the risk surface.
