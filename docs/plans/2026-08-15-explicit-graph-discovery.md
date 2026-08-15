# Explicit Graph Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove graph `get-edges` materialization and make workflow discovery explicit, searchable, and hierarchical.

**Architecture:** Graph topology records only visible objects that a user explicitly materializes through node preview/view controls. Workflow root previews browse workflow definitions only; workflow definition previews browse runs for that definition; workflow run previews explicitly materialize details. The old hidden relationship hook and graph trigger APIs are removed so there is one discovery mechanism.

**Tech Stack:** Space Fennel graph nodes/maps, Fennel UI previews using `SearchView`, `Button`, `Text`, and `Flex`, `WorkflowStore`, `GraphMap`, project-native Fennel tests and constraints.

## Global Constraints

- Remove `get-edges` from graph production code and focused tests.
- Remove graph `trigger` APIs whose sole behavior is to call node relationship hooks and bulk-add edges.
- Make workflow browsing explicit and hierarchical.
- `Workflows` root browses/searches workflow definitions only.
- A workflow definition browses/searches its own runs.
- Workflow steps expose their code through `Show Code`.
- Workflow runs expose details/steps/events through explicit run controls.
- Prevent root-level fan-out of all workflow runs.
- Preserve graph doctrine: stores own domain records; graph map topology records only user-materialized visible nodes/edges.
- Provide tests that fail if the old relationship hook or graph trigger path is reintroduced.
- No new automatic graph expansion behavior.
- No global graph search redesign beyond workflow browsing needed for this cleanup.
- No performance cache for workflow lists; use store listing and preview-side search/filtering for now.
- No changes to non-graph timer/debouncer code that happens to use ordinary words like “trigger”; this cleanup is about the graph relationship hook and graph trigger APIs.
- Existing creation actions (`New Workflow`, `New Step`, `Show Code`, `Start`) must keep working.
- Missing graph dependencies must fail loudly at action boundaries.
- Preview widgets must require direct build context and own/drop direct child widgets.
- For Fennel-facing changes, run compile checks first, constraints second, focused Fennel tests third.
- Run `make build` with timeout `14400000` first when `./build/space` is missing or stale.
- Direct Fennel test commands must set `SPACE_ASSETS_PATH=$(pwd)/assets`, `FENNEL_PATH`, and `FENNEL_MACRO_PATH` to `$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl`.
- Test hygiene: use `SPACE_DISABLE_AUDIO=1`, `SKIP_KEYRING_TESTS=1`, and `XDG_DATA_HOME=/tmp/space/tests/xdg-data` for direct test runs.
- PR CI is the full integration gate.

---

## File Structure / Task Decomposition

- Modify `assets/lua/graph/nodes/workflows.fnl`: replace bulk existing loader with selected-definition loader and remove root run exposure.
- Modify `assets/lua/graph/view/previews/workflows.fnl`: add searchable definition browser and remove bulk show-everything button.
- Modify `assets/lua/graph/nodes/workflow-definition.fnl`: add selected-run loader and stop relying on relationship hook for runs.
- Modify `assets/lua/graph/view/previews/workflow-definition.fnl`: add searchable run browser while preserving `Start` and `New Step`.
- Modify `assets/lua/graph/nodes/workflow-run.fnl`: add explicit detail loading method/action if needed, replacing relationship-hook detail materialization.
- Modify `assets/lua/graph/view/previews/workflow-run.fnl`: ensure `Show Details` invokes explicit materialization of run steps/events.
- Modify `assets/lua/graph/nodes/workflow-step.fnl`, `workflow-run-step.fnl`, and `workflow-run-event.fnl`: remove relationship hook assignments and preserve explicit actions/loaders.
- Modify `assets/lua/graph/node-base.fnl`: remove default relationship hook.
- Modify `assets/lua/graph/core.fnl` and `assets/lua/graph/map.fnl`: remove graph trigger materialization APIs that call the relationship hook.
- Modify `assets/lua/tests/test-workflow-graph.fnl`: replace relationship-hook tests with explicit browse/action tests and no-leftovers assertions.
- Modify docs that describe the old relationship hook as current architecture, especially `docs/plans/2026-08-14-graph-authored-agent-workflows.md` if needed for search cleanliness, and current graph/workflow docs if they mention the hook.

## Observable Acceptance Criteria

- Searching the Workflows root preview for a definition and selecting it loads only that `workflow-definition:<id>` node and a Workflows -> definition edge.
- Workflows root preview does not load or list runs directly.
- Searching a workflow definition preview for a run and selecting it loads only that `workflow-run:<id>` node and a definition -> run edge.
- Workflow run `Show Details` explicitly loads run steps/events without using the removed relationship hook.
- `New Workflow`, `New Step`, `Show Code`, and `Start` continue to work.
- `rg "get-edges" assets/lua/graph assets/lua/tests/test-workflow-graph.fnl` returns no matches.
- `rg "node:get-edges|\.get-edges|set node.get-edges" assets/lua` returns no matches.
- Graph `trigger` materialization APIs that called the hook are removed from `assets/lua/graph/core.fnl` and `assets/lua/graph/map.fnl`.

---

### Task 1: Workflows Root Searches Definitions Only

**Files:**
- Modify: `assets/lua/graph/nodes/workflows.fnl`
- Modify: `assets/lua/graph/view/previews/workflows.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes: `WorkflowStore:list-definitions()`, graph map `load-by-key`, graph map `add-edge`, `SearchView` build closure pattern.
- Produces:
  - `WorkflowsNode:load-definition-from-graph(definition-or-id) -> node`
  - `WorkflowsNode:definition-items() -> [definition label][]`
  - Workflows preview fields `definition-search`, `definition-count-text`, and existing `new-workflow-button`.

- [ ] **Step 1: Add failing root browse tests**

In `assets/lua/tests/test-workflow-graph.fnl`, replace the bulk existing-workflows test with tests named:

- `workflows-preview-search-selects-one-definition-only`
- `workflows-root-does-not-load-runs-directly`

Set up two workflow definitions and at least one run. Build the Workflows preview, submit/select the row for one definition, and assert only `workflow-definition:<selected-id>` is loaded with a Workflows -> definition edge. Assert no `workflow-run:<id>` node is loaded by the Workflows root preview/action.

- [ ] **Step 2: Run focused test and verify failure**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: FAIL because Workflows preview still exposes bulk `Show Existing Workflows` behavior and lacks a definition search selector.

- [ ] **Step 3: Implement selected-definition loader**

In `assets/lua/graph/nodes/workflows.fnl`, replace bulk `load-existing-workflows` behavior with:

- `definition-items` returning `[definition label]` pairs sorted by existing `WorkflowStore:list-definitions` order;
- `load-definition-from-graph` that preflights `self.graph`, `graph.load-by-key`, and `graph.add-edge`, loads `workflow-definition:<id>`, adds Workflows -> definition edge, and returns the loaded node;
- no method/action that lists or loads workflow runs from Workflows root.

- [ ] **Step 4: Implement searchable Workflows preview**

In `assets/lua/graph/view/previews/workflows.fnl`, use `SearchView` to render definition rows. Keep `New Workflow`. Add a compact count text such as `"Definitions: N"`. Row submission must call `target:load-definition-from-graph(definition)`. Preview `drop` must drop direct child widgets and the search view.

- [ ] **Step 5: Validate**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/workflows.fnl --file assets/lua/graph/view/previews/workflows.fnl --file assets/lua/tests/test-workflow-graph.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: all PASS for root browse behavior.

- [ ] **Step 6: Commit**

```bash
git add assets/lua/graph/nodes/workflows.fnl assets/lua/graph/view/previews/workflows.fnl assets/lua/tests/test-workflow-graph.fnl
git commit -m "feat(graph): browse workflow definitions explicitly"
```

---

### Task 2: Workflow Definitions Search Their Own Runs

**Files:**
- Modify: `assets/lua/graph/nodes/workflow-definition.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-definition.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes: `WorkflowStore:list-runs({:definition-id definition-id})`, graph map `load-by-key`, graph map `add-edge`, existing `start-workflow-from-graph`, existing `create-step-from-graph`.
- Produces:
  - `WorkflowDefinitionNode:run-items() -> [run label][]`
  - `WorkflowDefinitionNode:load-run-from-graph(run-or-id) -> node`
  - Workflow definition preview fields `run-search`, `run-count-text`, plus existing `start-button` and `new-step-button`.

- [ ] **Step 1: Add failing definition run browse tests**

In `assets/lua/tests/test-workflow-graph.fnl`, add tests:

- `workflow-definition-preview-search-selects-one-run`
- `workflow-definition-run-search-filters-to-definition`

Create two definitions with runs for both. Build a preview for one definition, submit/select one run, and assert only that run node is loaded and edged from the definition. Assert runs from the other definition are absent from the search items and not loaded.

- [ ] **Step 2: Run focused test and verify failure**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: FAIL because definition previews do not expose a run search selector.

- [ ] **Step 3: Implement definition run loader**

In `assets/lua/graph/nodes/workflow-definition.fnl`, add `run-items` and `load-run-from-graph`. `run-items` must filter with `{:definition-id self.workflow-definition-id}`. `load-run-from-graph` must preflight graph dependencies, load `workflow-run:<id>`, add definition -> run edge, and return the loaded node.

- [ ] **Step 4: Implement searchable run section in preview**

In `assets/lua/graph/view/previews/workflow-definition.fnl`, keep `Start` and `New Step`, add run count text and `SearchView` rows for runs. Row submission calls `target:load-run-from-graph(run)`. Preview `drop` must drop all direct child widgets and the search view.

- [ ] **Step 5: Validate**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/workflow-definition.fnl --file assets/lua/graph/view/previews/workflow-definition.fnl --file assets/lua/tests/test-workflow-graph.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add assets/lua/graph/nodes/workflow-definition.fnl assets/lua/graph/view/previews/workflow-definition.fnl assets/lua/tests/test-workflow-graph.fnl
git commit -m "feat(graph): browse workflow runs from definitions"
```

---

### Task 3: Replace Run Detail Hook with Explicit Detail Materialization

**Files:**
- Modify: `assets/lua/graph/nodes/workflow-run.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-run.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes: `WorkflowStore:list-run-steps(run-id)`, `WorkflowStore:list-events(run-id)`, graph map `load-by-key`, graph map `add-edge`.
- Produces:
  - `WorkflowRunNode:load-details-from-graph() -> {:run-step-count number :event-count number}`
  - `WorkflowRunNode:hide-details-from-graph() -> true` if existing hide behavior needs to remain as node state only.
  - Run preview `show-details-button` calls explicit materialization instead of toggling relationship-hook output.

- [ ] **Step 1: Add failing explicit detail tests**

Update the existing run details tests in `assets/lua/tests/test-workflow-graph.fnl` so they no longer call the relationship hook. Add/rename a test `workflow-run-preview-show-details-loads-step-and-event-nodes` that clicks/submits the preview button and asserts run-step and run-event nodes/edges are visible.

- [ ] **Step 2: Run focused test and verify failure**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: FAIL because details are still materialized through the relationship hook.

- [ ] **Step 3: Implement explicit detail loader**

In `assets/lua/graph/nodes/workflow-run.fnl`, add `load-details-from-graph` that preflights graph dependencies, loads each `workflow-run-step:<run-id>:<step-id>` and `workflow-run-event:<run-id>:<event-id>`, and adds visible edges from the run node. Keep loading the backing definition only if an explicit action needs it; do not rely on a relationship hook.

- [ ] **Step 4: Update run preview button behavior**

In `assets/lua/graph/view/previews/workflow-run.fnl`, make `Show Details` call `target:load-details-from-graph()`. If `Hide Details` remains, it may only update node UI state or label; it must not depend on relationship-hook output to remove or add edges.

- [ ] **Step 5: Validate**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/workflow-run.fnl --file assets/lua/graph/view/previews/workflow-run.fnl --file assets/lua/tests/test-workflow-graph.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add assets/lua/graph/nodes/workflow-run.fnl assets/lua/graph/view/previews/workflow-run.fnl assets/lua/tests/test-workflow-graph.fnl
git commit -m "feat(graph): materialize workflow run details explicitly"
```

---

### Task 4: Remove Relationship Hook and Graph Trigger APIs

**Files:**
- Modify: `assets/lua/graph/node-base.fnl`
- Modify: `assets/lua/graph/core.fnl`
- Modify: `assets/lua/graph/map.fnl`
- Modify: `assets/lua/graph/nodes/workflows.fnl`
- Modify: `assets/lua/graph/nodes/workflow-definition.fnl`
- Modify: `assets/lua/graph/nodes/workflow-step.fnl`
- Modify: `assets/lua/graph/nodes/workflow-run.fnl`
- Modify: `assets/lua/graph/nodes/workflow-run-step.fnl`
- Modify: `assets/lua/graph/nodes/workflow-run-event.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes: explicit loaders/actions from Tasks 1-3.
- Produces: graph code with no `get-edges` hook and no graph trigger materialization API.

- [ ] **Step 1: Add failing no-leftovers test/search**

In `assets/lua/tests/test-workflow-graph.fnl`, add a test `graph-discovery-has-no-relationship-hook-leftovers` that reads relevant graph files and asserts they do not contain the removed hook string. Include at minimum:

- `assets/lua/graph/node-base.fnl`
- `assets/lua/graph/core.fnl`
- `assets/lua/graph/map.fnl`
- all workflow graph node files listed in this task.

Also update/remove any existing tests that call `node:get-edges`.

- [ ] **Step 2: Run focused test and verify failure**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: FAIL while old hook assignments/calls remain.

- [ ] **Step 3: Remove default hook and trigger APIs**

Remove the default hook assignment from `graph/node-base.fnl`. Remove `Graph:trigger` and `GraphMap:trigger` methods that call the hook. Keep unrelated non-graph timer/debouncer trigger code untouched.

- [ ] **Step 4: Remove workflow node hook assignments**

Delete `set node.get-edges` assignments from workflow graph node files. Replace any remaining relationship materialization with explicit methods created in Tasks 1-3. Workflow-step code exposure must continue through `show-code-from-graph`; workflow-run-step/event reverse links should not auto-materialize.

- [ ] **Step 5: Update tests away from hook calls**

Rewrite focused workflow graph tests that directly called the hook to use explicit preview actions/methods. Remove tests whose only purpose was generic graph trigger behavior. Add assertions that explicit methods produce the expected visible graph nodes/edges.

- [ ] **Step 6: Validate no leftovers with search**

Run:

```bash
rg "get-edges" assets/lua/graph assets/lua/tests/test-workflow-graph.fnl
rg "node:get-edges|\.get-edges|set node.get-edges" assets/lua
```

Expected: both commands return no matches.

- [ ] **Step 7: Validate Fennel/tests**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/node-base.fnl --file assets/lua/graph/core.fnl --file assets/lua/graph/map.fnl --file assets/lua/graph/nodes/workflows.fnl --file assets/lua/graph/nodes/workflow-definition.fnl --file assets/lua/graph/nodes/workflow-step.fnl --file assets/lua/graph/nodes/workflow-run.fnl --file assets/lua/graph/nodes/workflow-run-step.fnl --file assets/lua/graph/nodes/workflow-run-event.fnl --file assets/lua/tests/test-workflow-graph.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add assets/lua/graph/node-base.fnl assets/lua/graph/core.fnl assets/lua/graph/map.fnl assets/lua/graph/nodes/workflows.fnl assets/lua/graph/nodes/workflow-definition.fnl assets/lua/graph/nodes/workflow-step.fnl assets/lua/graph/nodes/workflow-run.fnl assets/lua/graph/nodes/workflow-run-step.fnl assets/lua/graph/nodes/workflow-run-event.fnl assets/lua/tests/test-workflow-graph.fnl
git commit -m "refactor(graph): remove implicit edge discovery"
```

---

### Task 5: Documentation and Final Validation

**Files:**
- Modify: `docs/dev/notes/graph.md`
- Modify: `docs/dev/graph-maps.md`
- Modify: `docs/dev/features/workflows.md`
- Modify if still mentioning current hook behavior: `docs/plans/2026-08-14-graph-authored-agent-workflows.md`

**Interfaces:**
- Consumes: explicit discovery behavior from Tasks 1-4.
- Produces: documentation that describes explicit preview/action materialization as current graph behavior and does not teach the removed hook as a current mechanism.

- [ ] **Step 1: Update graph doctrine docs**

Document that graph maps contain user-materialized visible topology. Node previews/actions/search rows are the way to add related objects. Do not describe hidden relationship hook expansion as current behavior.

- [ ] **Step 2: Update workflow docs**

Document the workflow browse hierarchy:

```text
Workflows root -> selected workflow definition -> selected workflow run -> run details
```

Mention that root browse lists definitions only; runs are browsed from a specific workflow definition.

- [ ] **Step 3: Remove stale current-behavior mentions**

Run:

```bash
rg "get-edges|node relationship hook|implicit edge discovery" docs/dev docs/plans/2026-08-14-graph-authored-agent-workflows.md docs/plans/2026-08-15-explicit-graph-discovery.md docs/specs/2026-08-15-explicit-graph-discovery-design.md
```

Expected: no current docs describe the removed hook as active behavior. The explicit-discovery spec/plan may mention the removed name only as historical cleanup context.

- [ ] **Step 4: Run final no-leftovers code search**

```bash
rg "get-edges" assets/lua/graph assets/lua/tests/test-workflow-graph.fnl
rg "node:get-edges|\.get-edges|set node.get-edges" assets/lua
```

Expected: both return no matches.

- [ ] **Step 5: Run final compile check first**

```bash
make fennel-check
```

Expected: PASS.

- [ ] **Step 6: Run constraints second**

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 7: Run focused graph/workflow tests third**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
```

Expected: both PASS.

- [ ] **Step 8: Run broader suite if touched graph core/map behavior warrants it**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add docs/dev/notes/graph.md docs/dev/graph-maps.md docs/dev/features/workflows.md docs/plans/2026-08-14-graph-authored-agent-workflows.md
git commit -m "docs(graph): document explicit graph discovery"
```

---

## Final Review and Finishing Notes

After Task 5 passes, run a final whole-branch review through subagent-driven-development. Then use the finishing-a-development-branch skill. The branch must be clean, current with `origin/main`, validated with required local checks, pushed, opened as a PR targeting `main`, and polled through merge queue until merged. Do not claim ready-to-merge until PR CI is green.
