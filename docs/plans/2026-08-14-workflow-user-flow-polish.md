# Workflow User Flow Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the graph-first workflow authoring path from Start → Workflows → New Workflow → edit step code → add steps → run → inspect details.

**Architecture:** Keep workflow data owned by `WorkflowStore` and code bodies owned by `CodeEntityStore`; graph nodes remain adapters that call store APIs and load graph-visible keys into the current `GraphMap`. Add a small workflow template helper for compound workflow/step/code creation with rollback, then expose it through node actions and preview buttons.

**Tech Stack:** Space Fennel modules under `assets/lua`, graph key loaders/maps/nodes, Fennel UI widgets (`Flex`, `Button`, `Text`), workflow/code entity stores, workflow runner/code executor, Space-native Fennel tests.

## Global Constraints

- The Start node includes a `Workflows` target whenever `app.workflow-store` is available.
- The Workflows root exposes `New Workflow`.
- `New Workflow` creates: a durable workflow definition; a starter workflow step; a linked Fennel code entity containing a valid workflow step template.
- Workflow definition nodes expose `New Step` to add additional template-backed workflow steps.
- Workflow step nodes expose `Show Code`, loading the linked `code-entity:<id>` node into the current graph context.
- Run-step and run-event nodes expose preview summaries so users can inspect what happened after toggling run details.
- `WorkflowStore` owns workflow definitions, steps, edges, runs, run steps, and events.
- `CodeEntityStore` owns Fennel source bodies.
- Graph nodes are adapters that call explicit workflow/code store APIs.
- Graph maps provide interaction context and visible nodes/edges; they do not own workflow data.
- This is not a primitive executor. It is ordinary user-editable Fennel code stored as a code entity.
- Missing workflow store, runner, or code store should fail loudly at action/mutation boundaries.
- Template code entity creation should roll back if adding the workflow step fails.
- Key loaders should continue returning nil for missing domain records.
- Preview widgets must require direct build context and own/drop direct child widgets.
- Run detail previews should summarize status, attempts, output, waits, errors, event kind, step id, and event payload compactly.
- Out of scope: Primitive executors for agent/tool/condition/human-input nodes.
- Out of scope: Sandboxing workflow code.
- Out of scope: Edge-kind, condition, and port editing UI.
- Out of scope: Rich node port handles or edge endpoint anchoring.
- Out of scope: Naming dialogs, delete confirmations, template galleries, and human-input resume UI.
- Out of scope: Moving nodes between graph maps.
- Validation order for Fennel-facing changes: `make fennel-check` or touched-file `tools.fennel-check` first, `make constraints` second, focused Fennel tests third, broader relevant suite only after focused checks pass.
- Runtime/freshness prerequisite: run `make build` first when `./build/space` is missing or stale.
- If Fennel delimiter or parse errors occur, inspect the nearest enclosing form around the reported location, simplify nested logic into helper functions, rerun compile check before constraints/tests.

---

## File Structure / Task Decomposition

- Create `assets/lua/workflows/templates.fnl`: template source and compound workflow/step/code creation helpers with rollback.
- Create `assets/lua/workflows/preview-summary.fnl`: compact string summaries for run-step and run-event previews.
- Modify `assets/lua/tests/test-workflow-graph.fnl`: focused tests for template creation, graph actions, node loading, previews, and generated workflow execution.
- Modify `assets/lua/graph/key-loaders.fnl`: pass `code-store` into workflow graph loaders.
- Modify `assets/lua/graph/nodes/start.fnl`: include Workflows target when `app.workflow-store` exists.
- Modify `assets/lua/graph/nodes/workflows.fnl`: add `New Workflow` action, preview, and create method.
- Create `assets/lua/graph/view/previews/workflows.fnl`: Workflows root preview with `New Workflow`.
- Modify `assets/lua/graph/nodes/workflow-definition.fnl`: add `New Step` action/create method and code-store wiring.
- Modify `assets/lua/graph/view/previews/workflow-definition.fnl`: add `New Step` button.
- Modify `assets/lua/graph/nodes/workflow-step.fnl`: add `Show Code` action, preview, and graph loading method.
- Create `assets/lua/graph/view/previews/workflow-step.fnl`: workflow step preview with `Show Code`.
- Modify `assets/lua/graph/nodes/workflow-run-step.fnl`: attach run-step preview.
- Modify `assets/lua/graph/nodes/workflow-run-event.fnl`: attach run-event preview.
- Create `assets/lua/graph/view/previews/workflow-run-step.fnl`: run-step summary preview.
- Create `assets/lua/graph/view/previews/workflow-run-event.fnl`: run-event summary preview.
- Modify `docs/dev/features/workflows.md`: document the complete supported user flow and exclusions.

## Observable Acceptance Criteria

- Searching/selecting from `start` can reveal `Workflows` only when `app.workflow-store` exists.
- Invoking `New Workflow` creates one persisted workflow definition, one persisted starter step, and one persisted linked Fennel code entity.
- The workflow step record contains `:code-entity-id` and does not embed source text.
- The newly created definition, starter step, and code entity nodes are visible in the active `GraphMap`.
- Invoking `New Step` on a definition creates and loads another template-backed step/code entity pair.
- Invoking `Show Code` on a step loads the linked `code-entity:<id>` node into the current graph context.
- The generated starter workflow runs successfully through `WorkflowRunner` + `WorkflowCodeExecutor`.
- Run-step and run-event previews build only with direct context, expose compact summaries, and drop owned child widgets.
- `docs/dev/features/workflows.md` describes the end-to-end user flow and explicitly preserves v1 exclusions.
- PR CI is the full integration gate.

---

### Task 1: Workflow Template Helper

**Files:**
- Create: `assets/lua/workflows/templates.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes: `WorkflowStore:create-definition(opts)`, `WorkflowStore:add-step(definition-id, step)`, `WorkflowStore:delete-definition(definition-id)`, `CodeEntityStore:create-entity(opts)`, `CodeEntityStore:delete-entity(id)`, `WorkflowRunner:start-run(definition-id, input, context)`, `WorkflowRunner:tick-run(run-id, opts)`.
- Produces:
  - `WorkflowTemplates.starter-source() -> string`
  - `WorkflowTemplates.create-template-code-entity(code-store, opts) -> code-entity`
  - `WorkflowTemplates.create-template-step(workflow-store, code-store, definition-id, opts) -> {:step step :code-entity code-entity}`
  - `WorkflowTemplates.create-template-workflow(workflow-store, code-store, opts) -> {:definition definition :step step :code-entity code-entity}`

- [ ] **Step 1: Add failing template creation/execution tests**

In `assets/lua/tests/test-workflow-graph.fnl`, add a test named `template-helper-creates-durable-workflow-step-and-code`. It must:

- create isolated `WorkflowStore` and `CodeEntityStore` instances under a temp dir;
- call `Templates.create-template-workflow workflow-store code-store {:name "Created from graph"}`;
- assert that the returned definition, step, and code entity exist;
- reload the definition and assert it has exactly one step;
- assert the step has `:code-entity-id` equal to the returned code entity id;
- assert the step has no `:source` field;
- reload the code entity and assert `language` is `"fnl"` and source contains `workflow step completed`;
- run the workflow through `WorkflowCodeExecutor` and `WorkflowRunner`;
- assert the run succeeds and the output includes `{:message "workflow step completed"}` and echoes input.

Register the test in the file’s test table.

- [ ] **Step 2: Run the focused test and verify it fails because the module does not exist**

Run, after `make build` if `./build/space` is missing or stale:

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: FAIL with a `workflows/templates` module-not-found error.

- [ ] **Step 3: Implement `assets/lua/workflows/templates.fnl`**

Implement:

```fennel
(local DEFAULT_WORKFLOW_NAME "Untitled Workflow")
(local DEFAULT_STEP_NAME "Start")
(local DEFAULT_CODE_NAME "Workflow Step")

(fn starter-source []
  "(fn [opts]\n  {:run\n   (fn [self ctx input state]\n     (ctx:succeed {:message \"workflow step completed\"\n                   :input input}))})")
```

Implement `create-template-code-entity` to assert `code-store` and `code-store.create-entity`, then create a code entity with `:language "fnl"` and `:source (starter-source)`.

Implement `create-template-step` to assert `workflow-store`, `code-store`, and `definition-id`; create the code entity; call `workflow-store:add-step`; if `add-step` fails, call `code-store:delete-entity` for the just-created code entity before rethrowing.

Implement `create-template-workflow` to create a workflow definition with no inline steps/edges, then call `create-template-step`; if step creation fails, call `workflow-store:delete-definition` for the just-created definition before rethrowing. Return the reloaded definition plus the step and code entity.

- [ ] **Step 4: Run touched-file compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/workflows/templates.fnl --file assets/lua/tests/test-workflow-graph.fnl
```

Expected: PASS.

- [ ] **Step 5: Run constraints second**

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 6: Run focused workflow graph test third**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add assets/lua/workflows/templates.fnl assets/lua/tests/test-workflow-graph.fnl
git commit -m "feat(workflows): add template workflow creation helper"
```

---

### Task 2: Start Workflows Target and Workflows Root New Workflow

**Files:**
- Modify: `assets/lua/graph/nodes/start.fnl`
- Modify: `assets/lua/graph/nodes/workflows.fnl`
- Create: `assets/lua/graph/view/previews/workflows.fnl`
- Modify: `assets/lua/graph/key-loaders.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes: `WorkflowTemplates.create-template-workflow(workflow-store, code-store, opts) -> {:definition :step :code-entity}` from Task 1, `GraphMap:load-by-key(key)`, `GraphMap:add-edge(edge)`.
- Produces:
  - `WorkflowsNode {:store workflow-store :runner workflow-runner :code-store code-store}`
  - `node:create-workflow-from-graph(opts) -> {:definition definition :step step :code-entity code-entity}`
  - Workflows root action `{:name "New Workflow" :icon "add" :fn fn}`
  - preview builder `graph/view/previews/workflows.fnl` exposing `widget.new-workflow-button`.

- [ ] **Step 1: Add failing tests for Start target and New Workflow**

In `assets/lua/tests/test-workflow-graph.fnl`, add tests named:

- `start-node-includes-workflows-when-workflow-store-exists`
- `workflows-root-new-workflow-creates-and-loads-graph-nodes`
- `workflows-preview-builds-with-new-workflow-action`

Assertions:
- with `app.workflow-store`, `app.workflow-runner`, and `app.code-store` temporarily set to test runtime stores, `StartNode:collect-targets` includes a target node with key `"workflows"` and label `"Workflows"`;
- loading `workflows` into a `GraphMap` returns a node with `New Workflow` action;
- `root:create-workflow-from-graph {:name "Graph Created Workflow"}` creates durable definition, step, and code entity records;
- the map contains `workflow-definition:<id>`, `workflow-step:<definition-id>:<step-id>`, and `code-entity:<id>`;
- the Workflows preview asserts on missing build context, exposes `new-workflow-button`, and clicking it creates a definition.

- [ ] **Step 2: Run focused test and verify failure**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: FAIL because Start omits Workflows and WorkflowsNode has no create action/preview.

- [ ] **Step 3: Wire `code-store` through workflow loaders**

In `assets/lua/graph/key-loaders.fnl`, pass canonical `:code-store code-store` into workflow loader registration for the Workflows root.

- [ ] **Step 4: Add Workflows target to Start**

In `assets/lua/graph/nodes/start.fnl`, require `WorkflowsNode` and append it in `collect-targets` only when `app.workflow-store` exists:

```fennel
(when (and app app.workflow-store)
  (local workflows-node
    (WorkflowsNode {:store app.workflow-store
                    :runner app.workflow-runner
                    :code-store app.code-store}))
  (table.insert produced [workflows-node (or workflows-node.label workflows-node.key)]))
```

- [ ] **Step 5: Add Workflows root creation method/action**

In `assets/lua/graph/nodes/workflows.fnl`:

- require `WorkflowTemplates`;
- require `graph/view/previews/workflows` and set `:preview`;
- store `node.code-store`;
- implement `create-workflow-from-graph` that asserts workflow store and code store, calls the template helper, then loads definition, step, and code entity nodes into `self.graph` and adds visible `definition`, `step`, and `code` edges;
- add action `New Workflow` with icon `add` that calls `node:create-workflow-from-graph {}`.

- [ ] **Step 6: Create Workflows preview**

Create `assets/lua/graph/view/previews/workflows.fnl` with:

- direct build context requirement only;
- `Text` title;
- `Button` text `"New Workflow"`;
- `view.new-workflow-button`;
- `drop` method that drops title, button, and flex.

- [ ] **Step 7: Run touched-file compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/start.fnl --file assets/lua/graph/nodes/workflows.fnl --file assets/lua/graph/view/previews/workflows.fnl --file assets/lua/graph/key-loaders.fnl --file assets/lua/tests/test-workflow-graph.fnl
```

Expected: PASS.

- [ ] **Step 8: Run constraints second**

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 9: Run focused workflow graph test third**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add assets/lua/graph/nodes/start.fnl assets/lua/graph/nodes/workflows.fnl assets/lua/graph/view/previews/workflows.fnl assets/lua/graph/key-loaders.fnl assets/lua/tests/test-workflow-graph.fnl
git commit -m "feat(workflows): expose new workflow from graph start"
```

---

### Task 3: Workflow Definition New Step and Step Show Code

**Files:**
- Modify: `assets/lua/graph/nodes/workflow-definition.fnl`
- Modify: `assets/lua/graph/key-loaders.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-definition.fnl`
- Modify: `assets/lua/graph/nodes/workflow-step.fnl`
- Create: `assets/lua/graph/view/previews/workflow-step.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes: `WorkflowTemplates.create-template-step(workflow-store, code-store, definition-id, opts) -> {:step :code-entity}` from Task 1.
- Produces:
  - `WorkflowDefinitionNode {:definition-id string :store workflow-store :runner workflow-runner :code-store code-store}`
  - `definition-node:create-step-from-graph(opts) -> {:step step :code-entity code-entity}`
  - definition action `New Step`
  - definition preview field `widget.new-step-button`
  - `workflow-step-node:show-code-from-graph() -> code-node`
  - step action `Show Code`
  - workflow step preview field `widget.show-code-button`.

- [ ] **Step 1: Add failing tests for New Step and Show Code**

Add tests named:

- `definition-new-step-creates-template-backed-step-and-loads-nodes`
- `workflow-definition-preview-builds-with-new-step-action`
- `workflow-step-show-code-loads-linked-code-node`
- `workflow-step-preview-builds-with-show-code-action`

Assertions:
- definition nodes expose `New Step` action and `create-step-from-graph`;
- `create-step-from-graph {:step-name "Added Step"}` creates durable step and code entity records without embedding source in the workflow step;
- the new workflow step and code entity nodes become visible in the graph map;
- definition preview has both `start-button` and `new-step-button`;
- workflow step nodes expose `Show Code` action and `show-code-from-graph`;
- `show-code-from-graph` loads `code-entity:<id>` into the map and adds a visible step-to-code edge;
- step preview asserts on missing direct build context and exposes `show-code-button`.

- [ ] **Step 2: Run focused test and verify failure**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: FAIL because definition nodes do not expose New Step and workflow steps do not expose Show Code/preview.

- [ ] **Step 3: Pass code-store to definition loader**

In `assets/lua/graph/key-loaders.fnl`, pass `:code-store code-store` into `register-workflow-definition-loader`.

- [ ] **Step 4: Implement definition node `create-step-from-graph`**

In `assets/lua/graph/nodes/workflow-definition.fnl`:

- require `workflows/templates`;
- accept/store `options.code-store`;
- add `create-step-from-graph` that asserts workflow store and code store, calls `WorkflowTemplates.create-template-step`, loads `workflow-step:<definition-id>:<step-id>` and `code-entity:<id>` into `self.graph`, and adds visible `step` and `code` edges;
- append a `New Step` action while preserving `Start Run`.

- [ ] **Step 5: Update definition preview with New Step button**

In `assets/lua/graph/view/previews/workflow-definition.fnl`, add a `New Step` button that calls `target:create-step-from-graph {}`, store it as `view.new-step-button`, include it in the flex, and drop it in `view.drop`.

- [ ] **Step 6: Add Show Code method/action to workflow step node**

In `assets/lua/graph/nodes/workflow-step.fnl`:

- require `graph/view/previews/workflow-step` and set `:preview`;
- add `show-code-from-graph` that finds current step, asserts `code-entity-id`, loads `code-entity:<id>` through `self.graph:load-by-key`, adds a visible `code` edge, and returns the code node;
- add action `Show Code` with icon `code`.

- [ ] **Step 7: Create workflow step preview**

Create `assets/lua/graph/view/previews/workflow-step.fnl` with direct build context requirement, title text, code id summary, Show Code button, `view.show-code-button`, and explicit child drops.

- [ ] **Step 8: Run touched-file compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/workflow-definition.fnl --file assets/lua/graph/key-loaders.fnl --file assets/lua/graph/view/previews/workflow-definition.fnl --file assets/lua/graph/nodes/workflow-step.fnl --file assets/lua/graph/view/previews/workflow-step.fnl --file assets/lua/tests/test-workflow-graph.fnl
```

Expected: PASS.

- [ ] **Step 9: Run constraints second**

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 10: Run focused workflow graph test third**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add assets/lua/graph/nodes/workflow-definition.fnl assets/lua/graph/key-loaders.fnl assets/lua/graph/view/previews/workflow-definition.fnl assets/lua/graph/nodes/workflow-step.fnl assets/lua/graph/view/previews/workflow-step.fnl assets/lua/tests/test-workflow-graph.fnl
git commit -m "feat(workflows): add graph step authoring actions"
```

---

### Task 4: Run Step and Run Event Preview Summaries

**Files:**
- Create: `assets/lua/workflows/preview-summary.fnl`
- Modify: `assets/lua/graph/nodes/workflow-run-step.fnl`
- Modify: `assets/lua/graph/nodes/workflow-run-event.fnl`
- Create: `assets/lua/graph/view/previews/workflow-run-step.fnl`
- Create: `assets/lua/graph/view/previews/workflow-run-event.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes: `WorkflowStore:get-run-step(run-id, step-id)`, workflow run event records.
- Produces:
  - `PreviewSummary.run-step-summary(run-step) -> string`
  - `PreviewSummary.run-event-summary(event) -> string`
  - run-step preview `graph/view/previews/workflow-run-step`
  - run-event preview `graph/view/previews/workflow-run-event`
  - preview widgets with `widget.summary-text`.

- [ ] **Step 1: Add failing summary and preview tests**

Add tests named:

- `workflow-run-step-and-event-summaries-include-details`
- `workflow-run-step-preview-builds-summary`
- `workflow-run-event-preview-builds-summary`

Assertions:
- run-step summary includes `Status:`, `Attempt:`, and `Output:` when output is present;
- event summary includes `Kind:` and `Step:` when a step id is present;
- run-step and run-event previews assert on missing direct build context;
- each preview exposes `widget.summary-text` containing useful status/kind text;
- each preview drops owned children.

- [ ] **Step 2: Run focused test and verify failure**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: FAIL because preview-summary and detail preview modules do not exist.

- [ ] **Step 3: Implement compact summary helper**

Create `assets/lua/workflows/preview-summary.fnl`:

- use `json.dumps` with `pcall` for table values;
- fallback to `tostring` for non-table values;
- `run-step-summary` includes `Status:`, `Attempt:`, `Output:`, `Wait:`, and `Error:` when values are present;
- `run-event-summary` includes `Kind:`, `Step:`, and `Payload:` for non-metadata event fields.

- [ ] **Step 4: Attach previews to run-step and run-event nodes**

In `workflow-run-step.fnl`, require and set `:preview WorkflowRunStepNodePreview`.

In `workflow-run-event.fnl`, require and set `:preview WorkflowRunEventNodePreview`.

- [ ] **Step 5: Create run-step and run-event preview modules**

Each preview module must:

- resolve `node` from direct argument or `opts.node`;
- error with `"requires a build context"` when `ctx` is missing;
- create `Text` title and summary;
- put them in a vertical `Flex`;
- set `view.summary-text`;
- drop title, summary, and flex.

- [ ] **Step 6: Run touched-file compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/workflows/preview-summary.fnl --file assets/lua/graph/nodes/workflow-run-step.fnl --file assets/lua/graph/nodes/workflow-run-event.fnl --file assets/lua/graph/view/previews/workflow-run-step.fnl --file assets/lua/graph/view/previews/workflow-run-event.fnl --file assets/lua/tests/test-workflow-graph.fnl
```

Expected: PASS.

- [ ] **Step 7: Run constraints second**

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 8: Run focused workflow graph test third**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add assets/lua/workflows/preview-summary.fnl assets/lua/graph/nodes/workflow-run-step.fnl assets/lua/graph/nodes/workflow-run-event.fnl assets/lua/graph/view/previews/workflow-run-step.fnl assets/lua/graph/view/previews/workflow-run-event.fnl assets/lua/tests/test-workflow-graph.fnl
git commit -m "feat(workflows): add run detail previews"
```

---

### Task 5: Workflow User Flow Documentation and Final Validation

**Files:**
- Modify: `docs/dev/features/workflows.md`

**Interfaces:**
- Consumes: completed user-facing behavior from Tasks 1–4.
- Produces: documented workflow user path and v1 exclusions in `docs/dev/features/workflows.md`.

- [ ] **Step 1: Update workflow docs with the complete user flow**

Add a `## Graph user flow` section to `docs/dev/features/workflows.md` containing these supported steps:

```markdown
## Graph user flow

1. Open Graph.
2. From `start`, search/select `Workflows`.
3. On the Workflows node, invoke `New Workflow`.
4. Open the generated workflow definition and starter step.
5. Use `Show Code` on the step to open the linked `code-entity:<id>` node.
6. Edit the Fennel code entity if desired.
7. Use `New Step` on the definition for additional steps.
8. Connect workflow step nodes; those connections create canonical workflow edges.
9. Click `Start` / `Start Run` on the workflow definition.
10. Open the run node, toggle `Show Details`, and inspect run-step and event previews.
```

Also state that workflow data remains in `WorkflowStore`, code remains in `CodeEntityStore`, and graph maps remain interaction context only.

- [ ] **Step 2: Verify docs mention required actions and exclusions**

Run:

```bash
rg "New Workflow|New Step|Show Code|Show Details|Primitive executors|Sandboxing workflow code|Edge-kind" docs/dev/features/workflows.md
```

Expected: all terms are present, with exclusions still documented.

- [ ] **Step 3: Run Fennel compile check first for all touched Fennel files**

```bash
make fennel-check
```

Expected: PASS.

- [ ] **Step 4: Run constraints second**

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 5: Run focused workflow tests third**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-code-executor:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-runner:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-store:main
```

Expected: PASS.

- [ ] **Step 6: Run broader relevant local suite**

Because this changes Start, graph key loaders, graph nodes, UI previews, and workflow execution UX, run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: PASS.

- [ ] **Step 7: Commit docs and validation evidence**

```bash
git add docs/dev/features/workflows.md
git commit -m "docs(workflows): document graph workflow user flow"
```

- [ ] **Step 8: Final integration gate**

Before claiming ready-to-merge, fetch and compare against `origin/main`, keep the tree clean, and rely on PR CI as the full integration gate.
