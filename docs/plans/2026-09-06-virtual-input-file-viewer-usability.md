# VirtualInput File Viewer Usability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Space lazy file editor `VirtualInput` usability regressions so filesystem “View text” editors support Vim/text-state routing, allocated viewport clipping, horizontal caret visibility, and focused unit/E2E coverage.

**Architecture:** Keep the production fix localized to `VirtualInput` as the file-scale editor facade over `LazyTextBuffer`; do not change global `TextState`/`InsertState` routing unless a reviewer proves the localized facade cannot satisfy the existing state contracts. `VirtualInput` will expose the small input-model compatibility surface that modal states already consume, compute visible viewport dimensions from allocated layout size, create a local clip region for all children, and keep horizontal scroll synchronized with caret movement. Filesystem file viewer production code remains unchanged because the bug belongs to the widget contract, and E2E will prove the existing `FsFileViewerNodeView` path works.

**Tech Stack:** Space Fennel widgets, `LazyTextBuffer`, `InputStateRouter`, `TextState`, `InsertState`, layout/clip utilities, graph filesystem nodes, project-native Fennel/runtime tests, Space E2E harness.

## Global Constraints

- During implementation, edit only the files listed for the active task unless reviewer-confirmed evidence proves an additional scoped file is required.
- Use active project skills during implementation: `subagent-driven-development`, `test-driven-development`, `space-fennel`, `space-fennel-ui`, and `space-testing-runtime`.
- Tests-first for every implementation task: add failing tests before changing production code.
- Fennel validation ladder: compile check first, then constraints, focused tests, broader suite when justified by behavioral surface and risk.
- Use project-native tools only; do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e`.
- Direct test runs must set `SPACE_ASSETS_PATH=$(pwd)/assets`, `FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"`, `FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"`, `SPACE_DISABLE_AUDIO=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, and `SKIP_KEYRING_TESTS=1`.
- `make build` is the runtime/freshness prerequisite when `./build/space` may be missing or stale; when invoking via tool, set timeout to `14400000` ms.
- Fennel idioms: use `local` instead of `let`, multi-branch `if`, factory functions instead of `.new`, and fail loudly for missing required data.
- UI invariants: widgets own/drop direct children, use `Layout`, write transforms directly during layout, mark the shallowest appropriate layout dirty, and pass explicit clip regions to rendered children.
- Preserve lazy loading and UTF-8-safe byte boundaries; do not introduce whole-file reads or raw-byte caret movement fallbacks.
- PR CI is the full integration gate; do not claim ready-to-merge until PR CI is green.

## File Structure

- Modify `assets/lua/virtual-input.fnl`
  - Add `TextState`/`InsertState` compatibility facade fields and methods.
  - Add allocation-aware visible viewport sizing.
  - Add local clip-region creation/intersection.
  - Add horizontal scroll/caret visibility maintenance.
- Modify `assets/lua/tests/test-virtual-input.fnl`
  - Add focused RED/GREEN unit tests for modal routing, viewport clipping, and horizontal caret visibility.
- Create `assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl`
  - Add non-snapshot E2E coverage for actual filesystem file viewer integration.
- Modify `assets/lua/tests/e2e.fnl`
  - Register the new E2E test in the aggregate E2E suite.
- Modify `docs/dev/features/lazy-text-buffer-virtual-input.md`
  - Document `VirtualInput` modal-state compatibility, allocated clipping, and horizontal viewport invariants.

## Validation Ladder

Use this ladder after each task, narrowing the touched-file compile command to files modified in that task:

1. Runtime/freshness prerequisite when `./build/space` is missing or stale:

   ```bash
   make build
   ```

   Tool timeout: `14400000` ms.

2. Focused compile check first:

   ```bash
   SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/virtual-input.fnl --file assets/lua/tests/test-virtual-input.fnl
   ```

3. Constraints second:

   ```bash
   make constraints
   ```

4. Focused unit tests third:

   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
   ```

5. Focused E2E test after Task 4:

   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.e2e.test-fs-file-viewer-virtual-input:main
   ```

6. Complete relevant local suite for final implementation because this changes Fennel input routing, widget layout, graph file viewer behavior, and E2E registration:

   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
   ```

7. Broader local E2E check because `assets/lua/tests/e2e.fnl` is changed:

   ```bash
   SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e
   ```

8. Full integration gate:

   Acceptance requires PR CI green. GitHub reads, PR creation, auto-merge, merge-queue polling, and PR check watching are supervisor capability-boundary work and must go through the configured GitHub operator wrapper, not ad-hoc direct `gh` commands from implementer tasks.

If Fennel delimiter or parse errors occur, inspect the nearest enclosing form around the reported line, repair the smallest malformed form, and rerun the compile check before constraints or tests.

---

### Task 1: Input-State Compatibility for VirtualInput

**Files:**
- Modify: `assets/lua/virtual-input.fnl`
- Modify: `assets/lua/tests/test-virtual-input.fnl`

**Interfaces:**
- Consumes: existing `InputStateRouter.active-input`, `TextState:on-key-down`, `InsertState:on-key-down`, `LazyTextBuffer:move-caret-horizontal(delta:number)`, `LazyTextBuffer:move-caret-to-byte(byte:number)`, `LazyTextBuffer:move-caret-to-line-column(line:number, column:number)`.
- Produces: `VirtualInput` instances exposing `model:table`, `lines:table`, `cursor-index:number`, `cursor-line:number`, `cursor-column:number`, `mode:keyword`, `multiline?:boolean`, `move-caret-to(self, position:number):boolean`, numeric `move-caret(self, delta:number, opts:table|nil):boolean`, `enter-insert-mode(self):boolean`, `enter-normal-mode(self):boolean`, and `submit(self, payload:table|nil):boolean`.

- [ ] **Step 1: Add RED unit tests for `TextState` routing.**

  In `assets/lua/tests/test-virtual-input.fnl`, require the modal states near the existing requires:

  ```fennel
  (local TextState (require :text-state))
  (local InsertState (require :insert-state))
  ```

  Add helper functions below `set-test-states`:

  ```fennel
  (fn with-virtual-input-states [body]
    (local original-states app.states)
    (local states (States))
    (local text-state (TextState))
    (local insert-state (InsertState))
    (states:add-state :normal {})
    (states:add-state :text text-state)
    (states:add-state :insert insert-state)
    (states:set-state :normal)
    (StateSystemBindings.bind-states-host states)
    (local (ok result)
      (pcall body {:states states
                   :text-state text-state
                   :insert-state insert-state}))
    (InputState.reset)
    (StateSystemBindings.bind-states-host original-states)
    (when states.drop
      (states:drop))
    (if ok
        result
        (error result)))
  ```

  Add these test functions:

  ```fennel
  (fn virtual-input-text-state-i-enters-insert-mode []
    (with-virtual-input-states
      (fn [env]
        (local buffer (lazy-buffer "text-state-insert" "abc\ndef"))
        (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
        (input:on-click {:row-index 1 :column 0})
        (assert (= ((. env :states):active-name) :text) "click should enter text state")
        (assert (((. env :text-state):on-key-down {:key (string.byte "i")}))
                "TextState i should be handled for VirtualInput")
        (assert (= input.mode :insert) "VirtualInput should enter insert mode")
        (assert (= ((. env :states):active-name) :insert) "states host should enter insert")
        (input:drop))))

  (fn virtual-input-text-state-h-l-move-without-numeric-delta-error []
    (with-virtual-input-states
      (fn [env]
        (local buffer (lazy-buffer "text-state-horizontal" "abcd"))
        (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
        (input:on-click {:row-index 1 :column 1})
        (assert (((. env :text-state):on-key-down {:key (string.byte "l")}))
                "TextState l should move right")
        (assert (= buffer.cursor-byte 2) "l should move one UTF-8 codepoint right")
        (assert (((. env :text-state):on-key-down {:key (string.byte "h")}))
                "TextState h should move left")
        (assert (= buffer.cursor-byte 1) "h should move one UTF-8 codepoint left")
        (input:drop))))

  (fn virtual-input-text-state-j-k-move-using-lazy-rows []
    (with-virtual-input-states
      (fn [env]
        (local buffer (lazy-buffer "text-state-vertical" "aa\nbb\ncc"))
        (local input (build-input {:buffer buffer :line-count 3 :column-count 8}))
        (input:on-click {:row-index 1 :column 1})
        (assert (((. env :text-state):on-key-down {:key (string.byte "j")}))
                "TextState j should move down")
        (assert (= input.cursor-line 1) "j should move to second lazy row")
        (assert (= input.cursor-column 1) "j should preserve preferred column")
        (assert (((. env :text-state):on-key-down {:key (string.byte "k")}))
                "TextState k should move up")
        (assert (= input.cursor-line 0) "k should move back to first lazy row")
        (input:drop))))

  (fn virtual-input-text-state-x-deletes-and-clamps []
    (with-virtual-input-states
      (fn [env]
        (local buffer (lazy-buffer "text-state-delete" "abc"))
        (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
        (input:on-click {:row-index 1 :column 2})
        (assert (((. env :text-state):on-key-down {:key (string.byte "x")}))
                "TextState x should delete at cursor")
        (assert (= (snapshot-text buffer) "ab") "x should delete the current character")
        (assert (<= input.cursor-column 1) "caret should clamp inside remaining line")
        (input:drop))))
  ```

  Register the tests at the bottom of the file with explicit names.

- [ ] **Step 2: Run the new tests and verify RED.**

  ```bash
  make build
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```

  Expected RED: failures mention missing `enter-normal-mode`/`enter-insert-mode`, unsupported numeric caret move, or unchanged cursor after `j`/`k`.

- [ ] **Step 3: Implement the compatibility facade in `assets/lua/virtual-input.fnl`.**

  Add helper logic that synchronizes a lightweight model adapter after every viewport refresh and caret/edit operation:

  - `sync-model-state(self, snapshot)` sets:
    - `self.model` to a stable table.
    - `self.model.lines` to the current viewport rows with `newline-length` copied from `newline-bytes`.
    - `self.lines`, `self.cursor-line`, `self.cursor-column`, and `self.cursor-index`.
    - `self.model.cursor-line`, `self.model.cursor-column`, and `self.model.cursor-index`.
  - `move-caret-to(self, position)` interprets `position` against the current adapter rows and maps it to a UTF-8-safe byte target via row `column-byte-offsets`.
  - Existing `move-caret(self, delta, opts)` accepts numeric deltas by delegating to `apply-horizontal-caret-move`.
  - `enter-insert-mode(self)` sets `self.mode` to `:insert`, marks caret dirty, and returns `true`.
  - `enter-normal-mode(self)` sets `self.mode` to `:normal`, marks caret dirty, and returns `true`.
  - `submit(self, payload)` calls `self.on-submit` when provided and otherwise returns `false`.

  Add these fields in the built input table: `:model`, `:lines`, `:cursor-index`, `:cursor-line`, `:cursor-column`, `:mode :normal`, `:multiline? true`, `:on-submit options.on-submit`, `:move-caret-to move-caret-to`, `:enter-insert-mode enter-insert-mode`, `:enter-normal-mode enter-normal-mode`, `:submit submit`.

- [ ] **Step 4: Run focused compile, constraints, and unit tests.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/virtual-input.fnl --file assets/lua/tests/test-virtual-input.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```

- [ ] **Step 5: Reviewer gate.**

  Ask reviewer to confirm:
  - No changes were made to `TextState` or `InsertState`.
  - `VirtualInput` compatibility methods fail loudly for missing required buffer APIs.
  - Numeric movement remains UTF-8-safe through `LazyTextBuffer:move-caret-horizontal`.
  - Existing `Input`/`InputModel` behavior is untouched.

- [ ] **Step 6: Prepare Task 1 for reviewer handoff.**

  Do not commit from the implementer handoff. Report the changed files, RED evidence, GREEN validation evidence, and coverage rationale. The supervisor will dispatch the reviewer and commit only after reviewer pass.

---

### Task 2: Allocation-Aware Viewport Sizing and Local Clipping

**Files:**
- Modify: `assets/lua/virtual-input.fnl`
- Modify: `assets/lua/tests/test-virtual-input.fnl`

**Interfaces:**
- Consumes: Task 1 `VirtualInput` synchronized viewport/model state.
- Produces: `VirtualInput.visible-line-count:number`, `VirtualInput.visible-column-count:number`, `VirtualInput.local-clip-region:table`, and viewport refresh requests bounded by allocated layout size.

- [ ] **Step 1: Add RED layout/clipping unit test.**

  Add this test function in `assets/lua/tests/test-virtual-input.fnl`:

  ```fennel
  (fn virtual-input-narrow-layout-requests-visible-columns-and-local-clip []
    (local buffer (make-buffer {:rows [(row 0 "abcdefghij" 0)
                                       (row 1 "klmnopqrst" 11)]}))
    (local input (build-input {:buffer buffer :line-count 2 :column-count 10}))
    (input.layout:measurer)
    (local narrow-width (+ (* 2 input.padding.x) (* 3 input.column-width)))
    (local one-line-height (+ (* 2 input.padding.y) input.line-height))
    (set input.layout.position (glm.vec3 1 2 0))
    (set input.layout.size (glm.vec3 narrow-width one-line-height 0))
    (set input.layout.clip-region {:id 9001
                                   :bounds {:position (glm.vec3 0 0 0)
                                            :rotation (glm.quat 1 0 0 0)
                                            :size (glm.vec3 100 100 0)}})
    (input.layout:layouter)
    (local last-view (. buffer.state.viewport-calls (length buffer.state.viewport-calls)))
    (assert (= input.visible-column-count 3) "allocated width should reduce visible columns")
    (assert (= input.visible-line-count 1) "allocated height should reduce visible rows")
    (assert (= last-view.columns 3) "refresh should request allocated visible columns")
    (assert (= last-view.lines 1) "refresh should request allocated visible rows")
    (assert input.local-clip-region "VirtualInput should create a local clip region")
    (assert (= (. input.rows 1 :layout :clip-region) input.local-clip-region)
            "visible row should receive local clip")
    (assert (= input.caret.layout.clip-region input.local-clip-region)
            "caret should receive local clip")
    (assert (<= input.local-clip-region.bounds.size.x input.layout.size.x)
            "local clip width should not exceed allocated input width")
    (input:drop))
  ```

  Register it with name `"VirtualInput narrow layout requests visible columns and local clip"`.

- [ ] **Step 2: Run the test and verify RED.**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```

  Expected RED: viewport requests still use configured `column-count 10`/`line-count 2`, and child layouts receive the inherited parent clip instead of a `VirtualInput` local clip.

- [ ] **Step 3: Implement allocated viewport sizing in `virtual-input.fnl`.**

  Add stable configured counts and visible counts:
  - Keep constructor options as `configured-line-count` and `configured-column-count`.
  - Initialize `visible-line-count` and `visible-column-count` to configured values.
  - `refresh-viewport` must request `self.visible-line-count` and `self.visible-column-count`.
  - Row codepoint clipping must use `self.visible-column-count`.

  Add layout helper:
  - `visible-count-for-size(available:number, unit:number, configured:number):number`.
  - `update-visible-viewport-size(self, size)` computes inner width/height from allocated `layout.size`, padding, `column-width`, and `line-height`, clamps to at least `1`, clamps to configured counts, and refreshes viewport/model state when counts change.

- [ ] **Step 4: Implement local clip region in `virtual-input.fnl`.**

  Require `ClipUtils` and `BoundsUtils` at the top. Add `next-virtual-input-clip-region-id` and `update-local-clip-region(input, layout)` using the same contract as `ScrollArea`:
  - Bounds are the `VirtualInput` allocated layout bounds.
  - If parent clip exists, intersect parent bounds with input bounds via `BoundsUtils.bounds-aabb-in-parent`.
  - Call `ClipUtils.update-region`.
  - Store on `input.local-clip-region`.

  In `layout-virtual-input`, call `update-visible-viewport-size` before `refresh-viewport`, compute `local-clip`, and pass `local-clip` to background, row widgets, and caret.

- [ ] **Step 5: Run focused validation.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/virtual-input.fnl --file assets/lua/tests/test-virtual-input.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```

- [ ] **Step 6: Reviewer gate.**

  Ask reviewer to confirm:
  - No dynamic child creation/drop is added during layout.
  - `measure-virtual-input` remains a preferred size and layout allocation controls visible viewport.
  - Children receive the local clip region, not only inherited parent clip.
  - Viewport requests shrink under narrow allocation without changing file viewer production code.

- [ ] **Step 7: Prepare Task 2 for reviewer handoff.**

  Do not commit from the implementer handoff. Report the changed files, RED evidence, GREEN validation evidence, and coverage rationale. The supervisor will dispatch the reviewer and commit only after reviewer pass.

---

### Task 3: Horizontal Caret Visibility

**Files:**
- Modify: `assets/lua/virtual-input.fnl`
- Modify: `assets/lua/tests/test-virtual-input.fnl`

**Interfaces:**
- Consumes: Task 1 numeric/modal caret movement and Task 2 `visible-column-count`.
- Produces: `VirtualInput.scroll-column` updated by caret movement, refreshed viewport start column matching `scroll-column`, and visible caret layout inside input bounds for long lines.

- [ ] **Step 1: Add RED horizontal visibility unit test.**

  Add this test function in `assets/lua/tests/test-virtual-input.fnl`:

  ```fennel
  (fn virtual-input-long-line-horizontal-navigation-keeps-caret-visible []
    (with-virtual-input-states
      (fn [env]
        (local buffer (lazy-buffer "horizontal-visible" "abcdefghijklmnopqrstuvwxyz"))
        (local input (build-input {:buffer buffer :line-count 1 :column-count 4}))
        (input.layout:measurer)
        (set input.layout.size (+ (glm.vec3 (* 2 input.padding.x)
                                           (* 2 input.padding.y)
                                           0)
                                  (glm.vec3 (* 4 input.column-width)
                                            input.line-height
                                            0)))
        (input.layout:layouter)
        (input:on-click {:row-index 1 :column 0})
        (for [_ 1 8]
          (((. env :text-state):on-key-down {:key (string.byte "l")}))
          (input.layout:layouter))
        (assert (> input.scroll-column 0) "moving right past visible columns should scroll horizontally")
        (assert input.caret.visible? "caret should remain visible after horizontal scroll")
        (local local-x (- input.caret.layout.position.x input.layout.position.x))
        (assert (>= local-x input.padding.x) "caret x should stay inside left input padding")
        (assert (<= local-x (- input.layout.size.x input.padding.x))
                "caret x should stay inside right input padding")
        (local last-view (. buffer.state.viewport-calls (length buffer.state.viewport-calls)))
        (assert (= last-view.column input.scroll-column)
                "viewport request should use updated horizontal scroll column")
        (input:drop))))
  ```

  Register it with name `"VirtualInput long-line horizontal navigation keeps caret visible"`.

- [ ] **Step 2: Run the test and verify RED.**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```

  Expected RED: `scroll-column` remains `0`, the caret is hidden after moving beyond the clipped row, or caret x exceeds the allocated input width.

- [ ] **Step 3: Implement horizontal keep-visible logic.**

  In `assets/lua/virtual-input.fnl`:
  - Add `keep-column-visible(self, column)` mirroring `keep-line-visible`:
    - If `column < self.scroll-column`, set `self.scroll-column` to `column`.
    - If `column >= self.scroll-column + self.visible-column-count`, set `self.scroll-column` to `column - (self.visible-column-count - 1)`.
    - Clamp to `0`.
  - Add `locate-caret-line-column(self)` that can find the caret even when the current visible row is clipped:
    - First use the current viewport rows.
    - If the cursor byte is outside clipped row byte ranges, request a bounded one-line viewport at column `0` for the inferred/current line with columns `math.max(self.configured-column-count, (+ self.scroll-column self.visible-column-count 1))`.
    - Return absolute lazy row line and codepoint column without reading the whole file.
  - Call `keep-column-visible` after `apply-horizontal-caret-move`, `apply-caret-byte`, `apply-caret-line-column`, `move-caret-to`, and deletion clamp paths before refreshing the viewport.
  - Ensure `layout-caret` shows the caret when the located column is inside `[scroll-column, scroll-column + visible-column-count]`; hide only when the caret line cannot be located or is vertically outside the viewport.

- [ ] **Step 4: Preserve UTF-8 safety.**

  Confirm the implementation never computes byte offsets by adding/subtracting raw bytes for horizontal movement. All horizontal movement must continue to call `buffer:move-caret-horizontal(delta)` or map through row `column-byte-offsets`.

- [ ] **Step 5: Run focused validation.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/virtual-input.fnl --file assets/lua/tests/test-virtual-input.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```

- [ ] **Step 6: Reviewer gate.**

  Ask reviewer to confirm:
  - Long-line movement updates `scroll-column`.
  - Lazy bounded viewport requests remain bounded by visible/configured columns.
  - Caret visibility logic does not hide a valid caret merely because the old clipped viewport did not include it.
  - Existing UTF-8 navigation tests still pass.

- [ ] **Step 7: Prepare Task 3 for reviewer handoff.**

  Do not commit from the implementer handoff. Report the changed files, RED evidence, GREEN validation evidence, and coverage rationale. The supervisor will dispatch the reviewer and commit only after reviewer pass.

---

### Task 4: Filesystem File Viewer Integration E2E and Developer Documentation

**Files:**
- Create: `assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl`
- Modify: `assets/lua/tests/e2e.fnl`
- Modify: `docs/dev/features/lazy-text-buffer-virtual-input.md`

**Interfaces:**
- Consumes: Task 1 modal compatibility, Task 2 allocated clipping, Task 3 horizontal caret visibility, existing `FsFileViewerNode`, existing `FsFileViewerNodeView`, existing E2E `Harness`.
- Produces: focused E2E module `tests.e2e.test-fs-file-viewer-virtual-input:main`, aggregate E2E registration, and docs describing the fixed `VirtualInput` contract.

- [ ] **Step 1: Create RED E2E test module.**

  Create `assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl` with this structure:

  ```fennel
  (local Harness (require :tests.e2e.harness))
  (local fs (require :fs))
  (local glm (require :glm))
  (local InputState (require :input-state-router))
  (local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
  (local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))

  (var temp-counter 0)
  (local temp-root (fs.join-path "/tmp/space/tests" "e2e-fs-file-viewer-virtual-input"))

  (fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (local dir (fs.join-path temp-root (.. "viewer-" (os.time) "-" temp-counter)))
    (when (fs.exists dir)
      (fs.remove-all dir))
    (fs.create-dirs dir)
    dir)

  (fn write-temp-file [dir]
    (local path (fs.join-path dir "viewer.txt"))
    (fs.write-file path "abcdefghijklmnopqrstuvwxyz\nsecond line\n")
    (fs.absolute path))

  (fn active-key-down [payload]
    (local state (assert (app.states:active-state) "E2E requires active app state"))
    (assert state.on-key-down "E2E active state requires on-key-down")
    (state:on-key-down payload))

  (fn active-text-input [payload]
    (local state (assert (app.states:active-state) "E2E requires active app state"))
    (assert state.on-text-input "E2E active state requires on-text-input")
    (state:on-text-input payload))

  (fn text-of [text-widget]
    (table.concat
      (icollect [_ codepoint (ipairs (text-widget:get-codepoints))]
                (utf8.char codepoint))
      ""))

  (fn status-string [view]
    (text-of view.status-text))

  (fn assert-caret-inside-input [input]
    (input.layout:layouter)
    (assert input.caret.visible? "file viewer caret should be visible")
    (local local-x (- input.caret.layout.position.x input.layout.position.x))
    (assert (>= local-x input.padding.x) "caret should be inside left input edge")
    (assert (<= local-x (- input.layout.size.x input.padding.x))
            "caret should be inside right input edge"))

  (fn run [ctx]
    (local dir (make-temp-dir))
    (local file (write-temp-file dir))
    (local node (FsFileViewerNode {:path file}))
    (var view nil)
    (local target
      (Harness.make-screen-target
        {:width ctx.width
         :height ctx.height
         :world-units-per-pixel ctx.units-per-pixel
         :builder (fn [child-ctx]
                    (set view ((FsFileViewerNodeView node {}) child-ctx))
                    view)}))
    (target:update)
    (assert view "E2E should build FsFileViewerNodeView")
    (assert view.virtual-input "file viewer should expose VirtualInput")
    (set view.virtual-input.layout.size
         (glm.vec3 (+ (* 2 view.virtual-input.padding.x)
                      (* 6 view.virtual-input.column-width))
                   (+ (* 2 view.virtual-input.padding.y)
                      (* 3 view.virtual-input.line-height))
                   0))
    (view.virtual-input.layout:layouter)
    (view.virtual-input:on-click {:row-index 1 :column 0})
    (assert (= (InputState.active-input) view.virtual-input)
            "click should focus file viewer VirtualInput")
    (assert (= (app.states:active-name) :text)
            "click should enter text state")
    (assert (active-key-down {:key (string.byte "i")})
            "Vim i should enter insert through active state")
    (assert (= (app.states:active-name) :insert)
            "active state should become insert")
    (assert (active-text-input {:text "!"})
            "insert text should route through active insert state")
    (assert (active-key-down {:key 27})
            "escape should return to text mode")
    (assert (= (app.states:active-name) :text)
            "escape should return to text state")
    (for [_ 1 12]
      (active-key-down {:key (string.byte "l")}))
    (assert (> view.virtual-input.scroll-column 0)
            "long-line navigation should scroll horizontally")
    (assert-caret-inside-input view.virtual-input)
    (assert (active-key-down {:key (string.byte "s") :mod 64})
            "Ctrl+S should save through file viewer key route")
    (assert (= (fs.read-file file) "!abcdefghijklmnopqrstuvwxyz\nsecond line\n")
            "saved file should contain routed insert edit")
    (assert (string.find (status-string view) "Saved" 1 true)
            "status should report saved")
    (Harness.cleanup-target target)
    (node:drop)
    (fs.remove-all dir))

  (fn main []
    (Harness.with-app {:width 960 :height 720}
                      (fn [ctx]
                        (run ctx)))
    (print "E2E fs file viewer VirtualInput usability complete"))

  {:run run
   :main main}
  ```

- [ ] **Step 2: Register the E2E module.**

  In `assets/lua/tests/e2e.fnl`:
  - Add near the other requires:

    ```fennel
    (local FsFileViewerVirtualInputTest (require :tests.e2e.test-fs-file-viewer-virtual-input))
    ```

  - Add to `run-all` before `RenderCaptureTest.main`:

    ```fennel
    (FsFileViewerVirtualInputTest.main)
    ```

- [ ] **Step 3: Run focused E2E and verify RED if Task 1-3 are absent or incomplete.**

  ```bash
  make build
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.e2e.test-fs-file-viewer-virtual-input:main
  ```

  Expected RED before the production fixes: modal routing errors, unchanged insert content, `scroll-column` remaining `0`, hidden/out-of-bounds caret, or save not reflecting routed edits.

- [ ] **Step 4: Update developer documentation.**

  In `docs/dev/features/lazy-text-buffer-virtual-input.md`, update the `VirtualInput widget` section to state:
  - `VirtualInput` exposes a bounded `Input`-compatible facade for `TextState` and `InsertState`.
  - The facade supports `i`, `h`, `j`, `k`, `l`, `x`, Escape, Return for multiline insertion, and Ctrl+S file viewer save routing.
  - Allocated layout size controls visible rows/columns while configured counts remain preferred maximums.
  - All `VirtualInput` rendered children receive a local clip region intersected with parent clip bounds.
  - Horizontal caret movement updates `scroll-column` to keep the caret visible without eager whole-file reads.

- [ ] **Step 5: Run focused compile, constraints, unit, and E2E validation.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/virtual-input.fnl --file assets/lua/tests/test-virtual-input.fnl --file assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl --file assets/lua/tests/e2e.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.e2e.test-fs-file-viewer-virtual-input:main
  ```

- [ ] **Step 6: Reviewer gate.**

  Ask reviewer to confirm:
  - E2E exercises `FsFileViewerNodeView` with a real temporary file.
  - Keyboard commands route through the active app state where possible.
  - Assertions are behavioral and non-snapshot-based.
  - Temporary files are removed on successful test completion.
  - Documentation matches implemented invariants.

- [ ] **Step 7: Prepare Task 4 for reviewer handoff.**

  Do not commit from the implementer handoff. Report the changed files, RED evidence, GREEN validation evidence, and coverage rationale. The supervisor will dispatch the reviewer and commit only after reviewer pass.

---

## Final Validation and Integration

- [ ] **Step 1: Ensure the branch is current against `origin/main`.**

  The supervisor must use the `git-integrator` capability wrapper for fetch/current-branch status and any safe merge from `origin/main`. If the branch is behind `origin/main` and remote integration would be rejected, merge `origin/main` safely through the wrapper, resolve conflicts through implementer and reviewer gates, and rerun validation.

- [ ] **Step 2: Run full relevant local validation.**

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/virtual-input.fnl --file assets/lua/tests/test-virtual-input.fnl --file assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl --file assets/lua/tests/e2e.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.e2e.test-fs-file-viewer-virtual-input:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e
  ```

- [ ] **Step 3: Run final reviewer gate.**

  Reviewer must check:
  - The diff is limited to the files listed in this plan.
  - No whole-file lazy-buffer reads were introduced.
  - No global modal-state behavior changed.
  - `VirtualInput` owns and drops all existing children correctly.
  - Clip regions are updated, not recreated in an unbounded way during normal layout.
  - All new tests fail against the old behavior and pass with the fix.

- [ ] **Step 4: Commit reviewed fixes.**

  The supervisor commits only reviewed changes after reviewer pass. Use scope `ui`:

  ```bash
  git add assets/lua/virtual-input.fnl assets/lua/tests/test-virtual-input.fnl assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl assets/lua/tests/e2e.fnl docs/dev/features/lazy-text-buffer-virtual-input.md
  git commit -m "fix(ui): stabilize virtual input file viewer usability"
  ```

  Run this only if there are reviewed post-task fixes not already committed.

- [ ] **Step 5: Push and open PR after clean validation.**

  The supervisor must verify a clean worktree, then use `git-integrator` to push the current branch and `github-operator` to create the PR targeting `main`, enable the configured integration path, and monitor PR/merge-queue status. PR CI is the full integration gate.

## Observable Acceptance Criteria

- Clicking a filesystem file viewer `VirtualInput` focuses it and enters text mode.
- Vim `i` routes through `TextState` and enters insert mode without errors.
- Vim `h`/`l` route through `TextState` and move the lazy buffer caret with numeric deltas without raw-byte movement.
- Vim `j`/`k` route through `TextState` and move vertically across lazy rows.
- Vim `x` deletes at the caret and clamps the caret safely.
- Insert-state Escape returns to text mode and moves the caret safely.
- Insert-state Return inserts `"\n"` because `VirtualInput` is multiline.
- Narrow allocated layouts reduce requested viewport rows/columns and clip all rows/caret/background to a local clip region.
- Long-line horizontal navigation updates `scroll-column` and keeps the caret visible inside input bounds.
- File viewer E2E proves real temp-file edit, modal routing, horizontal caret visibility, save, status, and disk content.
- `docs/dev/features/lazy-text-buffer-virtual-input.md` documents the new behavior and invariants.

## Out of Scope

- Syntax highlighting.
- Undo/redo history.
- Whole-file search/replace.
- Multi-cursor editing.
- Binary file viewing/editing.
- Snapshot golden updates for this feature.
- Replacing `Input`/`InputModel` for small in-memory controls.
- Global redesign of `TextState`, `InsertState`, or `InputStateRouter`.
- Eager full-file line indexing or whole-file reads for navigation.
- New graph node types or filesystem interaction labels.

## Self-Review Checklist

- [ ] Every task starts with RED tests before production changes.
- [ ] Every task is independently reviewable and has focused validation.
- [ ] Production behavior is localized to `VirtualInput`.
- [ ] E2E covers actual filesystem file viewer integration.
- [ ] Validation commands use project-native tools and required environment variables.
- [ ] `make build` is included before direct runtime checks when `./build/space` may be missing or stale.
- [ ] Fennel compile check precedes constraints, and constraints precede focused tests.
- [ ] No silent fallbacks were added for required buffer/layout data.
- [ ] Lazy loading and UTF-8-safe caret movement are preserved.
- [ ] `docs/dev/features/lazy-text-buffer-virtual-input.md` is updated for behavior and operational assumptions.
- [ ] PR CI is named and treated as the full integration gate.
