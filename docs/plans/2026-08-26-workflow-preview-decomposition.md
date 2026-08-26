# Workflow Preview Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make workflow definition previews compact by moving step and run browsing into dedicated explicit explorer nodes.

**Architecture:** `WorkflowStore` remains the workflow data owner, while graph nodes adapt store records into map-visible controls. Add a definition-scoped `workflow-run-explorer:<id>` first so later preview changes are independently reviewable. Then convert `workflow-definition:<id>` into a compact summary/control card and move step reveal behavior to `workflow-step-explorer:<id>`.

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

- Create `assets/lua/graph/nodes/workflow-run-explorer.fnl`: definition-scoped run explorer adapter.
- Create `assets/lua/graph/view/previews/workflow-run-explorer.fnl`: definition-scoped run search preview.
- Modify `assets/lua/graph/key-loaders.fnl`: register the new run explorer loader with the workflow store.
- Modify `assets/lua/graph/nodes/workflow-definition.fnl`: add summary/open-run-explorer support and remove preview-facing direct reveal/run browse actions.
- Modify `assets/lua/graph/view/previews/workflow-definition.fnl`: rebuild as a compact summary/control card with no search widgets.
- Modify `assets/lua/graph/nodes/workflow-step-explorer.fnl` and `assets/lua/graph/view/previews/workflow-step-explorer.fnl`: keep step browsing/reveal behavior centered in the step explorer.
- Modify `assets/lua/tests/test-workflow-graph.fnl`: focused behavior and lifecycle coverage.
- Modify `assets/lua/tests/test-workflow-graph-action-boundaries.fnl`: missing-loader/rollback and selection-boundary coverage.
- Modify `docs/dev/features/workflows.md`, `docs/dev/features/workflow-graph-ux.md`, and `docs/user/workflows/edit-workflow-topology.md`: document explorer keys and user flow.

---

### Task 1: Workflow Run Explorer Node

**Files:**
- Create: `assets/lua/graph/nodes/workflow-run-explorer.fnl`
- Create: `assets/lua/graph/view/previews/workflow-run-explorer.fnl`
- Modify: `assets/lua/graph/key-loaders.fnl`
- Test: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes: `WorkflowStore:list-runs({:definition-id string}) -> table`, `WorkflowStore:get-definition(definition-id) -> table|nil`, `WorkflowStore:get-run(run-id) -> table|nil`, `GraphMap:load-by-key(key) -> GraphNode`, `GraphMap:add-edge(edge, opts)`.
- Produces: `WorkflowRunExplorerNode(opts) -> GraphNode`, `node:run-items() -> table`, `node:load-run-from-graph(run-or-id) -> GraphNode`, and `register-loader(graph, opts)` for `workflow-run-explorer:<definition-id>`.

- [ ] **Step 1: Write failing run explorer load/list tests**

  Add tests to `assets/lua/tests/test-workflow-graph.fnl`:

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
    (each [_ item (ipairs items)]
      (assert (= (. item 1 :definition-id) seeded.selected.id)
              "run explorer should exclude foreign definition runs"))
    (map:drop))
  ```

- [ ] **Step 2: Write failing preview selection and lifecycle tests**

  Add preview coverage to `test-workflow-graph.fnl`:

  ```fennel
  (fn workflow-run-explorer-preview-search-materializes-one-run-case [runtime]
    (local seeded (seed-two-definitions-with-runs runtime))
    (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-explorer-select-map"}))
    (local explorer (map:load-by-key (.. "workflow-run-explorer:" seeded.selected.id)))
    (local Preview (require :graph/view/previews/workflow-run-explorer))
    (assert-missing-build-context-with-fallbacks Preview explorer
                                                "workflow run explorer preview should not fall back to opts.ctx or graph.ctx")
    (local builder (Preview explorer {:node explorer}))
    (assert-missing-build-context builder "workflow run explorer preview should require direct build context")
    (local widget (builder (make-preview-ctx)))
    (each [_ field (ipairs [:title :summary-text :run-count-text :run-search :flex])]
      (assert (. widget field)
              (.. "workflow run explorer preview should expose " (tostring field))))
    (assert-contains (search-placeholder-string widget.run-search)
                     "Search workflow runs"
                     "run explorer search should use run search hint")
    (widget.run-search.submitted:emit (. (explorer:run-items) 1))
    (assert (map:lookup (.. "workflow-run:" seeded.selected-run.id))
            "run explorer search should load selected run")
    (assert (not (map:lookup (.. "workflow-run:" seeded.other-run.id)))
            "run explorer search should not load foreign runs")
    (widget:drop)
    (map:drop))
  ```

- [ ] **Step 3: Run the focused test to verify it fails**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  ```

  Expected: FAIL because `workflow-run-explorer` is not registered.

- [ ] **Step 4: Implement `workflow-run-explorer.fnl`**

  Create the node module using the step explorer pattern:

  ```fennel
  (local glm (require :glm))
  (local {:GraphNode GraphNode} (require :graph/node-base))
  (local {:GraphEdge GraphEdge} (require :graph/edge))
  (local GraphMapContext (require :graph/map-context))
  (local WorkflowRunExplorerPreview (require :graph/view/previews/workflow-run-explorer))

  (local EXPLORER_PURPLE (glm.vec4 0.56 0.42 0.9 1))
  (local EXPLORER_PURPLE_ACCENT (glm.vec4 0.68 0.52 1.0 1))

  (fn run-key [run-id]
    (.. "workflow-run:" run-id))

  (fn explorer-key [definition-id]
    (.. "workflow-run-explorer:" definition-id))

  (fn run-label [run]
    (.. (tostring run.id) " (" (tostring (if run.status run.status "pending")) ")"))
  ```

  Include `current-definition`, `load-required-node`, `add-visible-edge`, `assert-run-graph-dependencies`, `assert-run-loader`, and `load-owned-run-record` helpers. `load-owned-run-record` must assert that `run.definition-id` matches `self.workflow-definition-id`.

- [ ] **Step 5: Complete run explorer node methods and loader**

  `WorkflowRunExplorerNode` must set:

  ```fennel
  (set node.workflow-definition-id definition-id)
  (set node.workflow-store store)
  (set node.run-items
       (fn [self]
         (current-definition self "WorkflowRunExplorerNode.run-items")
         (icollect [_ run (ipairs (self.workflow-store:list-runs {:definition-id self.workflow-definition-id}))]
           [run (run-label run)])))
  (set node.load-run-from-graph
       (fn [self run-or-id]
         (assert-run-graph-dependencies self "WorkflowRunExplorerNode.load-run-from-graph")
         (assert-run-loader self "WorkflowRunExplorerNode.load-run-from-graph")
         (local run (load-owned-run-record self run-or-id "WorkflowRunExplorerNode.load-run-from-graph"))
         (local run-node (load-required-node self.graph (run-key run.id)))
         (add-visible-edge self.graph self run-node "run")
         run-node))
  ```

  Register keys with prefix `workflow-run-explorer:` and return `nil` for unknown/missing definitions.

- [ ] **Step 6: Implement run explorer preview**

  Create `assets/lua/graph/view/previews/workflow-run-explorer.fnl` based on `workflow-step-explorer.fnl`. It must require direct build context and expose `title`, `summary-text`, `run-count-text`, `run-search`, `flex`, and `__run-search-listener`. On drop, disconnect `run-search.submitted`, drop `title`, `run-count-text`, `run-search`, clear `flex.children`, and drop `flex`.

- [ ] **Step 7: Register the loader in key loaders**

  In `assets/lua/graph/key-loaders.fnl`, add:

  ```fennel
  ((. (require :graph/nodes/workflow-run-explorer) :register-loader)
   graph
   {:store workflow-store})
  ```

  Register it inside the `(when workflow-store ...)` block. It should not require `workflow-runner`.

- [ ] **Step 8: Run validation and commit Task 1**

  Run compile check first:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/workflow-run-explorer.fnl --file assets/lua/graph/view/previews/workflow-run-explorer.fnl --file assets/lua/graph/key-loaders.fnl --file assets/lua/tests/test-workflow-graph.fnl
  ```

  Run focused test:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  ```

  Expected: PASS.

  Commit:

  ```bash
  git add assets/lua/graph/nodes/workflow-run-explorer.fnl assets/lua/graph/view/previews/workflow-run-explorer.fnl assets/lua/graph/key-loaders.fnl assets/lua/tests/test-workflow-graph.fnl
  git commit -m "feat(graph): add workflow run explorer node"
  ```

---

### Task 2: Compact Definition Preview and Step Explorer Reveal

**Files:**
- Modify: `assets/lua/graph/nodes/workflow-definition.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-definition.fnl`
- Modify: `assets/lua/graph/nodes/workflow-step-explorer.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-step-explorer.fnl`
- Test: `assets/lua/tests/test-workflow-graph.fnl`
- Test: `assets/lua/tests/test-workflow-graph-action-boundaries.fnl`

**Interfaces:**
- Consumes: `workflow-run-explorer:<definition-id>` loader from Task 1, existing `WorkflowStepExplorerNode:reveal-all-steps-from-graph()`, and existing definition start/new-step behavior.
- Produces: compact definition preview with `open-steps-button` and `open-runs-button`, plus step explorer as the only preview surface exposing `reveal-all-steps-button`.

- [ ] **Step 1: Update failing compact preview tests**

  In `assets/lua/tests/test-workflow-graph.fnl`, update `workflow-definition-preview-builds-structured-inspector-case`:

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

- [ ] **Step 2: Move reveal-all test expectations to step explorer**

  Replace the old definition-preview reveal-all test with this step-explorer behavior:

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

- [ ] **Step 3: Add definition open-runs/open-steps button behavior tests**

  Add or update a definition preview button test so `open-steps-button` loads `workflow-step-explorer:<id>` and `open-runs-button` loads `workflow-run-explorer:<id>` without loading step/run payload nodes.

- [ ] **Step 4: Add action-boundary tests**

  In `test-workflow-graph-action-boundaries.fnl`, cover missing run-explorer loader and action placement:

  ```fennel
  (local (ok err) (pcall node.open-run-explorer-from-graph node))
  (assert (not ok) "Open run explorer without workflow-run-explorer loader should fail loudly")
  (assert (string.find (tostring err) "requires graph loader" 1 true)
          "missing workflow-run-explorer loader failure should explain the missing graph loader")
  (assert (not (action-named? (node:actions) "Reveal Steps"))
          "definition actions should not expose Reveal Steps")
  ```

- [ ] **Step 5: Run tests to verify they fail**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph-action-boundaries:main
  ```

  Expected: FAIL because the definition preview still exposes embedded searches and reveal-all.

- [ ] **Step 6: Add summary/open-run-explorer support to definition node**

  In `workflow-definition.fnl`, add `run-explorer-key`, `assert-run-explorer-loader`, and `open-run-explorer-from-graph`. Use the same `GraphMapContext.assert-graph-map`, `graph:load-by-key`, `graph:add-edge`, and `assert-graph-loader` pattern as `open-step-explorer-from-graph`.

  Add `workflow-summary` returning:

  ```fennel
  {:definition-id self.workflow-definition-id
   :name (if definition.name definition.name self.workflow-definition-id)
   :step-count (length (or definition.steps []))
   :run-count (length runs)
   :latest-run-status (latest-run-status-from-runs runs)}
  ```

  Implement `latest-run-status-from-runs` with the preview's existing created-at/id tie-breaker.

- [ ] **Step 7: Update definition actions**

  Keep **Start Run**, **Start With Selection**, **New Step**, and **Explore Steps**. Remove **Reveal Steps** from definition actions. Add **Explore Runs**:

  ```fennel
  {:name "Explore Runs"
   :icon "history"
   :fn (fn [_button _event]
         (node:open-run-explorer-from-graph))}
  ```

- [ ] **Step 8: Rebuild compact definition preview**

  In `workflow-definition` preview, remove `SearchView`, `step-items`, `run-items`, select handlers, reveal handler, and search listener teardown. Build only summary text plus four buttons. Expose fields `title`, `overview-text`, `summary-text`, `open-steps-button`, `open-runs-button`, `start-button`, `new-step-button`, and `flex`. Drop all owned child widgets exactly once and clear `flex.children` before dropping `flex`.

- [ ] **Step 9: Preserve step explorer reveal-all ownership**

  If step explorer already exposes `reveal-all-steps-button` and action **Reveal Steps**, keep it. Only adjust copy if tests require a clearer label. Do not move reveal-all behavior back into the definition preview.

- [ ] **Step 10: Run validation and commit Task 2**

  Run compile check first:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/workflow-definition.fnl --file assets/lua/graph/view/previews/workflow-definition.fnl --file assets/lua/graph/nodes/workflow-step-explorer.fnl --file assets/lua/graph/view/previews/workflow-step-explorer.fnl --file assets/lua/tests/test-workflow-graph.fnl --file assets/lua/tests/test-workflow-graph-action-boundaries.fnl
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

  Expected: PASS.

  Commit:

  ```bash
  git add assets/lua/graph/nodes/workflow-definition.fnl assets/lua/graph/view/previews/workflow-definition.fnl assets/lua/graph/nodes/workflow-step-explorer.fnl assets/lua/graph/view/previews/workflow-step-explorer.fnl assets/lua/tests/test-workflow-graph.fnl assets/lua/tests/test-workflow-graph-action-boundaries.fnl
  git commit -m "refactor(graph): compact workflow definition preview"
  ```

---

### Task 3: Documentation and Whole-Branch Validation

**Files:**
- Modify: `docs/dev/features/workflows.md`
- Modify: `docs/dev/features/workflow-graph-ux.md`
- Modify: `docs/user/workflows/edit-workflow-topology.md`
- Test: `assets/lua/tests/test-workflow-graph.fnl`
- Test: `assets/lua/tests/test-workflow-graph-action-boundaries.fnl`

**Interfaces:**
- Consumes: run explorer from Task 1 and compact definition/step explorer behavior from Task 2.
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

- [ ] **Step 3: Run documentation diff checks**

  Run:

  ```bash
  git diff --check
  ```

  Expected: PASS.

- [ ] **Step 4: Run full validation ladder**

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

- [ ] **Step 5: Commit Task 3**

  ```bash
  git add docs/dev/features/workflows.md docs/dev/features/workflow-graph-ux.md docs/user/workflows/edit-workflow-topology.md assets/lua/tests/test-workflow-graph.fnl assets/lua/tests/test-workflow-graph-action-boundaries.fnl
  git commit -m "docs(graph): document workflow explorer nodes"
  ```

- [ ] **Step 6: Prepare finishing handoff**

  Record validation evidence and constraint impact in the SDD progress ledger/report. Then enter finishing-a-development-branch: verify clean tree, fetch/evaluate against `origin/main`, rerun required validation on the current base if a safe merge occurs, push, create PR targeting `main`, enable auto-merge/queue, and poll until merged.
