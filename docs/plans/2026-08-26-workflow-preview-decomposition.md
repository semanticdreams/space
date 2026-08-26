# Workflow Preview Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make workflow definition previews compact by moving step and run browsing into dedicated explicit explorer nodes.

**Architecture:** `WorkflowStore` remains the workflow data owner, while graph nodes adapt store records into map-visible controls. `workflow-definition:<id>` becomes a summary/control card; `workflow-step-explorer:<id>` and the new `workflow-run-explorer:<id>` own browsing and explicit materialization. `GraphMap` continues to own only map-local topology, so no steps, runs, run steps, or events appear without a user action.

**Tech Stack:** Space Fennel graph nodes/previews, `GraphMap`, key loaders, `WorkflowStore`, `SearchView`, `Button`, `Text`, `Flex`, focused Fennel workflow graph tests.

## Global Constraints

- Follow `docs/specs/2026-08-26-workflow-preview-decomposition-design.md`.
- Workflow definition preview must expose concise summary plus **Start**, **New Step**, **Open Steps**, and **Open Runs**.
- Workflow definition preview must not expose embedded `step-search`, embedded `run-search`, or **Reveal All Steps**.
- `workflow-step-explorer:<definition-id>` owns step search and **Reveal All Steps**.
- Add `workflow-run-explorer:<definition-id>` for run search/listing.
- Selecting a run from the run explorer explicitly materializes only the selected `workflow-run:<run-id>` in the active `GraphMap`.
- All materialization remains explicit and map-local; do not add hidden expansion, `get-edges`, trigger discovery, or generic details toggles.
- Missing stores, definitions, graph maps, key loaders, and foreign-definition records fail loudly.
- Fennel widgets require direct build context, own direct child widgets, and disconnect/drop listener state.
- Use project Fennel idioms: `local`, factory-style builders, direct multiple-value bindings, and no `let`.

---

## File Structure

- Modify `assets/lua/graph/nodes/workflow-definition.fnl`: remove definition-level browsing helpers/actions from the preview-facing surface, add compact summary support, and add `open-run-explorer-from-graph`.
- Modify `assets/lua/graph/view/previews/workflow-definition.fnl`: rebuild as a compact summary/control card with no search widgets.
- Modify `assets/lua/graph/nodes/workflow-step-explorer.fnl`: keep step list/search behavior and make it the only owner of reveal-all step materialization.
- Modify `assets/lua/graph/view/previews/workflow-step-explorer.fnl`: ensure **Reveal All Steps** remains exposed and lifecycle tests still pass.
- Create `assets/lua/graph/nodes/workflow-run-explorer.fnl`: definition-scoped run explorer adapter.
- Create `assets/lua/graph/view/previews/workflow-run-explorer.fnl`: definition-scoped run search preview.
- Modify `assets/lua/graph/key-loaders.fnl`: register the new run explorer loader with the workflow store.
- Modify `assets/lua/tests/test-workflow-graph.fnl`: focused behavior and lifecycle coverage.
- Modify `assets/lua/tests/test-workflow-graph-action-boundaries.fnl`: missing-loader/rollback and selection-boundary coverage.
- Modify `docs/dev/features/workflows.md` and `docs/dev/features/workflow-graph-ux.md`: document explorer keys and user flow.
- Modify `docs/user/workflows/edit-workflow-topology.md`: explain that step browsing/reveal lives under **Open Steps** and run browsing under **Open Runs**.

---

### Task 1: Compact Workflow Definition Preview

**Files:**
- Modify: `assets/lua/graph/nodes/workflow-definition.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-definition.fnl`
- Test: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes: existing `WorkflowDefinitionNode:start-workflow-from-graph(input, context-opts)`, `WorkflowDefinitionNode:create-step-from-graph(opts)`, `WorkflowDefinitionNode:open-step-explorer-from-graph()`.
- Produces: `WorkflowDefinitionNode:workflow-summary() -> table`, `WorkflowDefinitionNode:open-run-explorer-from-graph() -> GraphNode`; the method must fail loudly when the run-explorer loader is unavailable and succeed after Task 3 registers it.

- [ ] **Step 1: Update failing preview structure test**

  In `assets/lua/tests/test-workflow-graph.fnl`, update `workflow-definition-preview-builds-structured-inspector-case` so it asserts the compact fields:

  ```fennel
  (each [_ field (ipairs [:title :overview-text :summary-text
                          :open-steps-button :open-runs-button
                          :start-button :new-step-button :flex])]
    (assert (. widget field)
            (.. "workflow definition compact preview should expose " (tostring field))))
  (each [_ field (ipairs [:step-search :run-search :reveal-all-steps-button
                          :step-count-text :run-count-text])]
    (assert (not (. widget field))
            (.. "workflow definition compact preview should not expose " (tostring field))))
  ```

- [ ] **Step 2: Run the focused test to verify it fails**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  ```

  Expected: FAIL because the existing preview still exposes embedded searches and lacks `open-runs-button`.

- [ ] **Step 3: Add summary and run-explorer open method on the definition node**

  In `assets/lua/graph/nodes/workflow-definition.fnl`, add helpers matching the existing loader assertion style:

  ```fennel
  (fn run-explorer-key [definition-id]
    (.. "workflow-run-explorer:" definition-id))

  (fn assert-run-explorer-loader [self action]
    (assert-graph-loader self.graph
                         (run-explorer-key self.workflow-definition-id)
                         action
                         "workflow-run-explorer"))
  ```

  Add methods on `node`:

  ```fennel
  (set node.workflow-summary
       (fn [self]
         (local definition (current-definition self "WorkflowDefinitionNode.workflow-summary"))
         (local runs (self.workflow-store:list-runs {:definition-id self.workflow-definition-id}))
         {:definition-id self.workflow-definition-id
          :name (if definition.name definition.name self.workflow-definition-id)
          :step-count (length (or definition.steps []))
          :run-count (length runs)
          :latest-run-status (latest-run-status-from-runs runs)}))

  (set node.open-run-explorer-from-graph
       (fn [self]
         (local action "WorkflowDefinitionNode.open-run-explorer-from-graph")
         (GraphMapContext.assert-graph-map self.graph action)
         (assert self.graph.load-by-key (.. action " requires graph:load-by-key"))
         (assert self.graph.add-edge (.. action " requires graph:add-edge"))
         (assert-run-explorer-loader self action)
         (local explorer-node (load-required-node self.graph (run-explorer-key self.workflow-definition-id)))
         (add-visible-edge self.graph self explorer-node "runs")
         explorer-node))
  ```

  If `latest-run-status-from-runs` does not already exist in the node file, implement it with the same `created-at`/id tie-breaker currently used by the preview.

- [ ] **Step 4: Update definition actions**

  In `workflow-definition-actions`, replace the direct **Reveal Steps** action with **Explore Runs**:

  ```fennel
  {:name "Explore Runs"
   :icon "history"
   :fn (fn [_button _event]
         (node:open-run-explorer-from-graph))}
  ```

  Keep **Explore Steps**, **Start Run**, **Start With Selection**, and **New Step**.

- [ ] **Step 5: Rebuild the preview as a compact card**

  In `assets/lua/graph/view/previews/workflow-definition.fnl`, remove `SearchView` import and search listener code. Build only text and four buttons. Use direct context only:

  ```fennel
  (fn summary-label [summary]
    (.. "Definition: " summary.definition-id
        "\nName: " (tostring summary.name)
        "\nSteps: " (tostring summary.step-count)
        "\nRuns: " (tostring summary.run-count)
        "\nLatest: " (tostring summary.latest-run-status)))
  ```

  Add click helpers for `open-steps-button` and `open-runs-button`, then assign fields:

  ```fennel
  (set view.open-steps-button open-steps-button)
  (set view.open-runs-button open-runs-button)
  (set view.start-button start-button)
  (set view.new-step-button new-step-button)
  ```

  Do not set `view.step-search`, `view.run-search`, or `view.reveal-all-steps-button`.

- [ ] **Step 6: Update drop lifecycle test and implementation**

  Update `workflow-definition-preview-drops-owned-children-and-search-listeners-body` into a compact-preview drop test. It should wrap `:title`, `:overview-text`, `:open-steps-button`, `:open-runs-button`, `:start-button`, `:new-step-button`, and `:flex`; it should not emit old search signals.

- [ ] **Step 7: Run compile check and focused tests**

  Run:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/workflow-definition.fnl --file assets/lua/graph/view/previews/workflow-definition.fnl --file assets/lua/tests/test-workflow-graph.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  ```

  Expected: tests may still fail only for missing `workflow-run-explorer` loader until Task 3.

- [ ] **Step 8: Commit Task 1**

  Commit only Task 1 files if they are passing or failing solely for the expected Task 3 dependency:

  ```bash
  git add assets/lua/graph/nodes/workflow-definition.fnl assets/lua/graph/view/previews/workflow-definition.fnl assets/lua/tests/test-workflow-graph.fnl
  git commit -m "refactor(graph): compact workflow definition preview"
  ```

---

### Task 2: Step Explorer Owns Reveal-All Step Browsing

**Files:**
- Modify: `assets/lua/graph/nodes/workflow-step-explorer.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-step-explorer.fnl`
- Test: `assets/lua/tests/test-workflow-graph.fnl`
- Test: `assets/lua/tests/test-workflow-graph-action-boundaries.fnl`

**Interfaces:**
- Consumes: existing `WorkflowStepExplorerNode:step-items()`, `WorkflowStepExplorerNode:load-step-from-graph(step-or-id)`, `WorkflowStepExplorerNode:reveal-all-steps-from-graph()`.
- Produces: step explorer as the only preview surface exposing `reveal-all-steps-button`.

- [ ] **Step 1: Move reveal-all behavior expectations from definition preview tests**

  Replace the old definition-preview reveal-all test with a step-explorer test:

  ```fennel
  (fn workflow-step-explorer-reveal-all-button-materializes-steps-case [runtime]
    (local seeded (seed-two-definitions-with-steps runtime))
    (local map (GraphMap.GraphMap {:graph runtime.graph :id "step-explorer-reveal-map"}))
    (local explorer (map:load-by-key (.. "workflow-step-explorer:" seeded.selected.id)))
    (local Preview (require :graph/view/previews/workflow-step-explorer))
    (local widget ((Preview explorer {:node explorer}) (make-preview-ctx)))
    (widget.reveal-all-steps-button:on-click {:source :test})
    (assert (map:lookup (.. "workflow-step:" seeded.selected.id ":step-a")))
    (assert (map:lookup (.. "workflow-step:" seeded.selected.id ":step-b")))
    (assert (not (map:lookup (.. "workflow-step:" seeded.other.id ":other-step"))))
    (widget:drop)
    (map:drop))
  ```

- [ ] **Step 2: Assert definition preview no longer has reveal-all**

  In the compact definition preview test, keep this assertion:

  ```fennel
  (assert (not widget.reveal-all-steps-button)
          "workflow definition preview should move Reveal All Steps to step explorer")
  ```

- [ ] **Step 3: Verify step explorer behavior needs no broad rewrite**

  If `workflow-step-explorer.fnl` already owns `reveal-all-steps-from-graph` and the preview already exposes `reveal-all-steps-button`, avoid refactoring it. Only adjust labels/copy if needed.

- [ ] **Step 4: Add action-boundary coverage for definition missing old reveal action**

  In `test-workflow-graph-action-boundaries.fnl`, update action assertions so the definition node no longer exposes an action named `Reveal Steps`, while the step explorer does:

  ```fennel
  (assert (not (action-named? (definition-node:actions) "Reveal Steps"))
          "definition actions should not expose Reveal Steps")
  (assert (action-named? (explorer-node:actions) "Reveal Steps")
          "step explorer actions should expose Reveal Steps")
  ```

- [ ] **Step 5: Run focused validation**

  Run:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/workflow-step-explorer.fnl --file assets/lua/graph/view/previews/workflow-step-explorer.fnl --file assets/lua/tests/test-workflow-graph.fnl --file assets/lua/tests/test-workflow-graph-action-boundaries.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph-action-boundaries:main
  ```

  Expected: pass, except failures depending on Task 3 run explorer may remain if Task 3 has not landed.

- [ ] **Step 6: Commit Task 2**

  ```bash
  git add assets/lua/graph/nodes/workflow-step-explorer.fnl assets/lua/graph/view/previews/workflow-step-explorer.fnl assets/lua/tests/test-workflow-graph.fnl assets/lua/tests/test-workflow-graph-action-boundaries.fnl
  git commit -m "refactor(graph): move workflow step reveal into explorer"
  ```

---

### Task 3: Workflow Run Explorer Node

**Files:**
- Create: `assets/lua/graph/nodes/workflow-run-explorer.fnl`
- Create: `assets/lua/graph/view/previews/workflow-run-explorer.fnl`
- Modify: `assets/lua/graph/key-loaders.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`
- Modify: `assets/lua/tests/test-workflow-graph-action-boundaries.fnl`

**Interfaces:**
- Consumes: `WorkflowStore:list-runs({:definition-id string}) -> table`, `WorkflowStore:get-definition(definition-id) -> table|nil`, `WorkflowStore:get-run(run-id) -> table|nil`, `GraphMap:load-by-key(key) -> GraphNode`, `GraphMap:add-edge(edge, opts)`.
- Produces: `WorkflowRunExplorerNode(opts) -> GraphNode`, `node:run-items() -> table`, `node:load-run-from-graph(run-or-id) -> GraphNode`, and `register-loader(graph, opts)` for `workflow-run-explorer:<definition-id>`.

- [ ] **Step 1: Write failing run explorer tests**

  Add tests to `test-workflow-graph.fnl` for key loading and scoped run listing:

  ```fennel
  (fn workflow-run-explorer-lists-only-definition-runs-case [runtime]
    (local seeded (seed-two-definitions-with-runs runtime))
    (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-explorer-list-map"}))
    (local explorer (map:load-by-key (.. "workflow-run-explorer:" seeded.selected.id)))
    (assert explorer "workflow-run-explorer key should load")
    (local items (explorer:run-items))
    (assert (= (length items) 1) "run explorer should list selected definition runs")
    (assert (= (. items 1 1 :id) seeded.selected-run.id)
            "run explorer should include selected run")
    (map:drop))
  ```

  Add selecting-one-run coverage:

  ```fennel
  (fn workflow-run-explorer-search-materializes-one-run-case [runtime]
    (local seeded (seed-two-definitions-with-runs runtime))
    (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-explorer-select-map"}))
    (local explorer (map:load-by-key (.. "workflow-run-explorer:" seeded.selected.id)))
    (local Preview (require :graph/view/previews/workflow-run-explorer))
    (local widget ((Preview explorer {:node explorer}) (make-preview-ctx)))
    (widget.run-search.submitted:emit (. (explorer:run-items) 1))
    (assert (map:lookup (.. "workflow-run:" seeded.selected-run.id))
            "run explorer search should load selected run")
    (assert (not (map:lookup (.. "workflow-run:" seeded.other-run.id)))
            "run explorer search should not load foreign runs")
    (widget:drop)
    (map:drop))
  ```

- [ ] **Step 2: Run tests to verify missing module/loader failure**

  Run the focused test command from Task 1. Expected: FAIL because `workflow-run-explorer` does not exist yet.

- [ ] **Step 3: Implement `workflow-run-explorer.fnl`**

  Use the existing step explorer as the pattern. The node should include these helpers and methods:

  ```fennel
  (local {:GraphNode GraphNode} (require :graph/node-base))
  (local {:GraphEdge GraphEdge} (require :graph/edge))
  (local GraphMapContext (require :graph/map-context))
  (local WorkflowRunExplorerPreview (require :graph/view/previews/workflow-run-explorer))

  (fn run-key [run-id] (.. "workflow-run:" run-id))
  (fn explorer-key [definition-id] (.. "workflow-run-explorer:" definition-id))

  (fn load-owned-run-record [self run-or-id action]
    (local id (if (= (type run-or-id) :table)
                  (assert run-or-id.id (.. action " requires run id"))
                  (assert run-or-id (.. action " requires run id"))))
    (local run (self.workflow-store:get-run id))
    (assert run (.. action " missing workflow run: " (tostring id)))
    (assert (= run.definition-id self.workflow-definition-id)
            (.. action " run " (tostring id)
                " does not belong to workflow definition " (tostring self.workflow-definition-id)))
    run)
  ```

  `WorkflowRunExplorerNode` should set `workflow-definition-id`, `workflow-store`, `run-items`, and `load-run-from-graph`. `run-items` should use `workflow-store:list-runs {:definition-id self.workflow-definition-id}` and labels equivalent to the existing run label format in `workflow-definition.fnl`.

- [ ] **Step 4: Implement run explorer preview**

  Create `assets/lua/graph/view/previews/workflow-run-explorer.fnl` based on `workflow-step-explorer.fnl` but with run names:

  ```fennel
  (local {: Flex : FlexChild} (require :flex))
  (local SearchView (require :search-view))
  (local Text (require :text))
  ```

  Required exposed fields: `title`, `summary-text`, `run-count-text`, `run-search`, `flex`, and `__run-search-listener`. Search field hint text: `Search workflow runs`. On submit, call `(target:load-run-from-graph (. item 1))`.

- [ ] **Step 5: Register loader**

  In `assets/lua/graph/key-loaders.fnl`, require/register the new loader alongside existing workflow loaders:

  ```fennel
  ((. (require :graph/nodes/workflow-run-explorer) :register-loader)
   graph
   {:store workflow-store})
  ```

  Register it whenever `workflow-store` is available. It should not require a runner.

- [ ] **Step 6: Add action-boundary tests**

  In `test-workflow-graph-action-boundaries.fnl`, add coverage mirroring the step explorer loader failure:

  ```fennel
  (local (ok err) (pcall node.open-run-explorer-from-graph node))
  (assert (not ok) "Open run explorer without workflow-run-explorer loader should fail loudly")
  (assert (string.find (tostring err) "requires graph loader" 1 true)
          "missing workflow-run-explorer loader failure should explain the missing graph loader")
  ```

  Also assert failed open does not leave a `workflow-run-explorer:` node in the map.

- [ ] **Step 7: Run focused validation**

  Run:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/workflow-run-explorer.fnl --file assets/lua/graph/view/previews/workflow-run-explorer.fnl --file assets/lua/graph/key-loaders.fnl --file assets/lua/tests/test-workflow-graph.fnl --file assets/lua/tests/test-workflow-graph-action-boundaries.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph-action-boundaries:main
  ```

  Expected: pass.

- [ ] **Step 8: Commit Task 3**

  ```bash
  git add assets/lua/graph/nodes/workflow-run-explorer.fnl assets/lua/graph/view/previews/workflow-run-explorer.fnl assets/lua/graph/key-loaders.fnl assets/lua/tests/test-workflow-graph.fnl assets/lua/tests/test-workflow-graph-action-boundaries.fnl
  git commit -m "feat(graph): add workflow run explorer node"
  ```

---

### Task 4: Documentation and Final Validation

**Files:**
- Modify: `docs/dev/features/workflows.md`
- Modify: `docs/dev/features/workflow-graph-ux.md`
- Modify: `docs/user/workflows/edit-workflow-topology.md`
- Test: `assets/lua/tests/test-workflow-graph.fnl`
- Test: `assets/lua/tests/test-workflow-graph-action-boundaries.fnl`

**Interfaces:**
- Consumes: compact definition preview, step explorer reveal-all, and run explorer from Tasks 1-3.
- Produces: user/developer docs matching the shipped graph UX and final validation evidence.

- [ ] **Step 1: Update developer workflow graph docs**

  In `docs/dev/features/workflows.md` and `docs/dev/features/workflow-graph-ux.md`, document graph-visible keys:

  ```text
  workflows
  workflow-definition:<definition-id>
  workflow-step-explorer:<definition-id>
  workflow-step:<definition-id>:<step-id>
  workflow-run-explorer:<definition-id>
  workflow-run:<run-id>
  workflow-run-step:<run-id>:<step-id>
  workflow-run-timeline:<run-id>
  workflow-run-event:<run-id>:<event-id>
  ```

  State that explorer selections explicitly materialize related nodes in the active graph map and that definitions do not auto-expand.

- [ ] **Step 2: Update user workflow docs**

  In `docs/user/workflows/edit-workflow-topology.md`, describe the new flow:

  ```text
  Open a workflow definition node. Use Open Steps to browse or reveal steps. Use Open Runs to browse past runs. The definition preview stays focused on starting the workflow and creating steps.
  ```

- [ ] **Step 3: Run full validation ladder**

  Run compile check first:

  ```bash
  make fennel-check
  ```

  Run constraints second:

  ```bash
  make constraints
  ```

  Run focused tests third:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph-action-boundaries:main
  ```

  Because key-loader registration changes can affect graph loading broadly, run the broader relevant suite before final integration:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 4: Commit Task 4**

  ```bash
  git add docs/dev/features/workflows.md docs/dev/features/workflow-graph-ux.md docs/user/workflows/edit-workflow-topology.md assets/lua/tests/test-workflow-graph.fnl assets/lua/tests/test-workflow-graph-action-boundaries.fnl
  git commit -m "docs(graph): document workflow explorer nodes"
  ```

- [ ] **Step 5: Prepare finishing handoff**

  Record validation evidence and constraint impact in the SDD progress ledger/report. Then enter finishing-a-development-branch: verify clean tree, fetch/evaluate against `origin/main`, rerun required validation on the current base if a safe merge occurs, push, create PR targeting `main`, enable auto-merge/queue, and poll until merged.
