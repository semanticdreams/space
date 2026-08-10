# Light Theme Layering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build subtle Material-style tonal layering for the Space light theme using existing Fennel theme tokens, with clear borders and no widget API changes.

**Architecture:** Recalibrate only the existing light-theme color tokens consumed by `widget-theme-utils`, `Card`, graph backgrounds, chrome rails/panels, and HUD panel borders. Add invariant-based Fennel tests that protect tonal ordering and visible-but-subtle gaps without snapshot churn. Document the token contract in a focused dev note because this changes the canonical visual behavior of the theme subsystem.

**Tech Stack:** Space Fennel, `glm.vec4` theme tokens, existing `widget-theme-utils` resolvers, Space Fennel test runner, `tools.fennel-check`, constraints.

## Global Constraints

- Improve visual separation in the light theme without redesigning the dark theme.
- Use a subtle tonal stack rather than heavy shadows or high-contrast chrome.
- Keep borders visible enough that panels, dialogs, rails, and cards do not disappear against adjacent surfaces.
- Fit existing Space Fennel UI architecture and theme-resolution patterns.
- Do not introduce a general public `surface`, `elevation`, shadow, or per-widget z-depth color API.
- Do not rewrite widget layout, rendering depth, or ownership behavior.
- Do not change dark-theme color behavior except where tests compare existing resolver contracts.
- Do not perform broad snapshot churn unless current tests require refreshed evidence.
- Missing theme context should continue to assert or use existing explicit resolver behavior; this work must not add silent fallbacks.
- The public token shape must remain compatible with current widget consumers.
- Fennel code must follow project idioms: `local` bindings, factory functions, direct resolver use, and no constructor-style `.new` additions.
- Runtime/freshness prerequisite: when `./build/space` may be missing or stale, run `make build` first with timeout `14400000`.

## File Structure

- Modify `assets/lua/light-theme.fnl`: define semantic local color names inside `LightTheme` and assign them to existing `:graph.background`, `:chrome.rail-background`, `:chrome.panel-background`, `:card.background`, and `:panel-border`.
- Modify `assets/lua/tests/test-theme-widgets.fnl`: add luminance helpers and one focused invariant test for the light-theme tonal stack.
- Create `docs/dev/notes/light-theme-layering.md`: document the existing-token layering contract and explicitly state that no public elevation API exists.
- Modify `docs/dev/subsystems/index.md`: link the Theming subsystem entry to the new dev note.
- Do not modify `assets/lua/widget-theme-utils.fnl`, `assets/lua/dark-theme.fnl`, widget layout files, renderers, or E2E golden snapshots.

## Task Right-Sizing

The code and test change are one task because the test is intentionally failing until the token calibration lands; committing the failing test separately would leave the branch red. Documentation is a separate task because it can be reviewed independently after the implementation contract is established. Final validation is its own task because theme token changes affect broad UI surfaces even though the production code diff is small.

## Validation Ladder

1. **Runtime/freshness prerequisite:** if `./build/space` is missing or stale, run:
   ```bash
   make build
   ```
   Use timeout `14400000`.
2. **Focused compile checks first:**
   ```bash
   SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/light-theme.fnl
   SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-theme-widgets.fnl
   ```
3. **Constraints second:**
   ```bash
   make constraints
   ```
4. **Focused Fennel test third:**
   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Light theme exposes Material-style tonal layering" ./build/space -m tests.test-theme-widgets:main
   ```
5. **Broader relevant local suite:** token changes affect many UI surfaces, so run the fast Fennel suite:
   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
   ```
6. **Manual visual smoke:** run the app, switch to the light theme with the existing theme toggle if needed, and inspect graph background, rails, panels, dialogs, toolbar/card-heavy views, and HUD borders:
   ```bash
   SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m main
   ```
7. **Full integration gate:** PR CI is the full integration gate. Do not claim ready-to-merge until PR CI is green.
8. **Fennel parse repair guidance:** if delimiter or parse errors occur, inspect the nearest enclosing form around the reported line, repair the smallest malformed form, and rerun the compile check before constraints or tests. If the form is deeply nested, move logic into helper functions instead of guessing at closing delimiters.

---

### Task 1: Light Theme Tonal Token Calibration

**Files:**
- Modify: `assets/lua/light-theme.fnl`
- Modify: `assets/lua/tests/test-theme-widgets.fnl`
- Test: `assets/lua/tests/test-theme-widgets.fnl`

**Interfaces:**
- Consumes: existing `LightTheme` builder from `assets/lua/light-theme.fnl`, existing `glm.vec4`, existing theme shape keys `theme.graph.background`, `theme.chrome.rail-background`, `theme.chrome.panel-background`, `theme.card.background`, and `theme.panel-border`.
- Produces: unchanged public theme map shape; calibrated existing tokens:
  - `theme.graph.background: glm.vec4`
  - `theme.chrome.rail-background: glm.vec4`
  - `theme.chrome.panel-background: glm.vec4`
  - `theme.card.background: glm.vec4`
  - `theme.panel-border: glm.vec4`

- [ ] **Step 1: Add the failing tonal invariant test**

  In `assets/lua/tests/test-theme-widgets.fnl`, add this require near the other top-level requires:

  ```fennel
  (local LightTheme (require :light-theme))
  ```

  Add these helpers after `color=`:

  ```fennel
  (fn luminance [color]
    (+ (* color.x 0.2126)
       (* color.y 0.7152)
       (* color.z 0.0722)))

  (fn assert-between [label value lower upper]
    (assert (<= lower value)
            (.. label " should be at least " lower ", got " value))
    (assert (<= value upper)
            (.. label " should be at most " upper ", got " value)))
  ```

  Add this test function before the existing `table.insert` test registrations:

  ```fennel
  (fn light-theme-exposes-tonal-layering []
    (local theme (LightTheme))
    (local rail theme.chrome.rail-background)
    (local background theme.graph.background)
    (local panel theme.chrome.panel-background)
    (local card theme.card.background)
    (local border theme.panel-border)
    (local rail-luminance (luminance rail))
    (local background-luminance (luminance background))
    (local panel-luminance (luminance panel))
    (local card-luminance (luminance card))
    (local border-luminance (luminance border))
    (local rail-background-gap (- background-luminance rail-luminance))
    (local background-panel-gap (- panel-luminance background-luminance))
    (local panel-card-gap (- card-luminance panel-luminance))
    (assert (< rail-luminance background-luminance)
            "Light rail surface should be darker than graph/background")
    (assert (< background-luminance panel-luminance)
            "Light panel surface should be lighter than graph/background")
    (assert (< panel-luminance card-luminance)
            "Light card/dialog surface should be lighter than panel surface")
    (assert-between "Light rail/background luminance gap"
                    rail-background-gap 0.018 0.055)
    (assert-between "Light background/panel luminance gap"
                    background-panel-gap 0.014 0.045)
    (assert-between "Light panel/card luminance gap"
                    panel-card-gap 0.012 0.04)
    (assert (<= 0.95 border.w)
            "Light panel border should be mostly opaque")
    (assert (< border-luminance panel-luminance)
            "Light panel border should be darker than panel surface")
    (assert (< border-luminance card-luminance)
            "Light panel border should be darker than card surface")
    (assert (<= 0.12 (- panel-luminance border-luminance))
            "Light panel border should visibly separate panels")
    (assert (<= 0.14 (- card-luminance border-luminance))
            "Light panel border should visibly separate cards/dialogs")
    true)
  ```

  Register it near the other theme-widget tests:

  ```fennel
  (table.insert tests {:name "Light theme exposes Material-style tonal layering"
                       :fn light-theme-exposes-tonal-layering})
  ```

- [ ] **Step 2: Verify the new test fails for the current token set**

  If `./build/space` is missing or stale, run:

  ```bash
  make build
  ```

  Compile the touched test file first:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-theme-widgets.fnl
  ```

  Then run the focused test:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Light theme exposes Material-style tonal layering" ./build/space -m tests.test-theme-widgets:main
  ```

  Expected result: FAIL because the current `theme.chrome.panel-background` and `theme.card.background` have the same RGB values, so the card surface is not lighter than the panel surface.

- [ ] **Step 3: Calibrate existing light-theme tokens with semantic local names**

  In `assets/lua/light-theme.fnl`, inside `LightTheme` after the existing `input-base` local, add:

  ```fennel
  (local rail-surface (glm.vec4 0.885 0.902 0.93 0.98))
  (local app-background (glm.vec4 0.918 0.932 0.955 1))
  (local chrome-panel-surface (glm.vec4 0.948 0.958 0.976 0.98))
  (local card-surface (glm.vec4 0.975 0.982 0.992 1))
  (local panel-outline (glm.vec4 0.74 0.79 0.87 0.98))
  ```

  Replace only these token assignments:

  ```fennel
  :graph {:background app-background
  ```

  ```fennel
  :chrome {:rail-background rail-surface
           :panel-background chrome-panel-surface}
  ```

  ```fennel
  :panel-border panel-outline
  ```

  ```fennel
  :card {:background card-surface
         :foreground text-color}
  ```

  Do not change `assets/lua/dark-theme.fnl`, `assets/lua/widget-theme-utils.fnl`, widget APIs, layout behavior, rendering behavior, or snapshot assets.

- [ ] **Step 4: Run the focused Space Fennel validation ladder**

  Compile changed files:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/light-theme.fnl
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-theme-widgets.fnl
  ```

  Run constraints:

  ```bash
  make constraints
  ```

  Run the focused test:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Light theme exposes Material-style tonal layering" ./build/space -m tests.test-theme-widgets:main
  ```

  Expected result: all commands PASS.

- [ ] **Step 5: Confirm dark theme and resolver APIs were not changed**

  Run:

  ```bash
  git diff -- assets/lua/dark-theme.fnl assets/lua/widget-theme-utils.fnl
  ```

  Expected result: no diff output.

- [ ] **Step 6: Commit the code and test change**

  ```bash
  git add assets/lua/light-theme.fnl assets/lua/tests/test-theme-widgets.fnl
  git commit -m "feat(ui): calibrate light theme tonal layers"
  ```

---

### Task 2: Theme Layering Dev Documentation

**Files:**
- Create: `docs/dev/notes/light-theme-layering.md`
- Modify: `docs/dev/subsystems/index.md`
- Test: documentation text search

**Interfaces:**
- Consumes: calibrated token contract from Task 1:
  - `theme.graph.background`
  - `theme.chrome.rail-background`
  - `theme.chrome.panel-background`
  - `theme.card.background`
  - `theme.panel-border`
- Produces: canonical dev note for light-theme layering decisions at `docs/dev/notes/light-theme-layering.md`.

- [ ] **Step 1: Create the focused dev note**

  Create `docs/dev/notes/light-theme-layering.md` with:

  ```markdown
  # Light Theme Layering

  The light theme uses existing theme tokens to create subtle Material-style tonal layering without introducing a public elevation or surface API.

  ## Token contract

  The intended light-theme luminance order is:

  1. `theme.chrome.rail-background` — rail surface, slightly darker/cooler than the graph background.
  2. `theme.graph.background` — quiet cool off-white app/graph baseline.
  3. `theme.chrome.panel-background` — panel chrome, slightly lighter than the app background.
  4. `theme.card.background` — card, dialog, and toolbar surface, slightly lighter than panel chrome.
  5. `theme.panel-border` — mostly opaque outline, visibly darker than panel and card surfaces.

  Widgets should continue to consume these through existing resolvers and theme maps:
  `resolve-chrome-background`, `resolve-card-colors`, `Card`, and existing HUD panel border handling.

  ## Non-goals

  Do not add public `surface`, `elevation`, shadow, z-depth, or per-widget layering APIs for this behavior. If future work needs those concepts, it should introduce a separate design spec instead of overloading this note.
  ```

- [ ] **Step 2: Link the note from the subsystem index**

  In `docs/dev/subsystems/index.md`, replace the Theming bullet with:

  ```markdown
  - **Theming** — Dark/light theme system with widget-level utilities. See [Light Theme Layering](/dev/notes/light-theme-layering)
  ```

- [ ] **Step 3: Validate the documentation links and wording**

  Run:

  ```bash
  rg "Light Theme Layering|resolve-chrome-background|panel-border|Theming" docs/dev/notes/light-theme-layering.md docs/dev/subsystems/index.md
  ```

  Expected result: matches in both files, including the subsystem link and the token names.

- [ ] **Step 4: Commit the documentation change**

  ```bash
  git add docs/dev/notes/light-theme-layering.md docs/dev/subsystems/index.md
  git commit -m "docs(ui): document light theme layering tokens"
  ```

---

### Task 3: Broader Validation and Visual Smoke

**Files:**
- Test: `assets/lua/light-theme.fnl`
- Test: `assets/lua/tests/test-theme-widgets.fnl`
- Test: `docs/dev/notes/light-theme-layering.md`
- Test: `docs/dev/subsystems/index.md`

**Interfaces:**
- Consumes: Task 1 calibrated light-theme tokens and Task 2 dev documentation.
- Produces: validation evidence for compile checks, constraints, focused tests, broader fast Fennel suite, docs search, manual visual smoke, and PR CI handoff.

- [ ] **Step 1: Ensure the runtime is fresh**

  If `./build/space` is missing or stale, run:

  ```bash
  make build
  ```

  Use timeout `14400000`.

- [ ] **Step 2: Run compile checks first**

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/light-theme.fnl
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-theme-widgets.fnl
  ```

  Expected result: PASS.

- [ ] **Step 3: Run constraints second**

  ```bash
  make constraints
  ```

  Expected result: PASS.

- [ ] **Step 4: Run the focused theme-widget test third**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Light theme exposes Material-style tonal layering" ./build/space -m tests.test-theme-widgets:main
  ```

  Expected result: PASS.

- [ ] **Step 5: Run the broader relevant fast Fennel suite**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  ```

  Expected result: PASS. This is justified because the changed light-theme tokens feed broad UI surfaces through existing theme resolvers.

- [ ] **Step 6: Recheck docs**

  ```bash
  rg "Light Theme Layering|theme.chrome.rail-background|theme.chrome.panel-background|theme.card.background|theme.panel-border" docs/dev/notes/light-theme-layering.md docs/dev/subsystems/index.md
  ```

  Expected result: matches for the new note and subsystem link.

- [ ] **Step 7: Run manual light-theme visual smoke**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m main
  ```

  In the running app, switch to the light theme with the existing contrast/theme toggle if needed. Inspect graph background, rails, panels, dialogs, toolbar/card-heavy views, and HUD borders.

  Expected result: rails, graph background, panels, cards/dialogs/toolbars, and borders read as distinct light layers without harsh chrome or heavy shadows.

- [ ] **Step 8: Confirm final diff scope**

  ```bash
  git diff --stat origin/main...HEAD
  git diff --name-only origin/main...HEAD
  git diff -- assets/lua/dark-theme.fnl assets/lua/widget-theme-utils.fnl
  ```

  Expected result: changed files are limited to the planned files; `dark-theme.fnl` and `widget-theme-utils.fnl` show no diff.

- [ ] **Step 9: Record PR CI as the full integration gate**

  Do not refresh E2E snapshots unless a current test requires it. Do not claim ready-to-merge until PR CI is green.
