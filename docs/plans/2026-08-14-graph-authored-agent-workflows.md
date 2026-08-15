# Graph-Authored Agent Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a durable, app/user-scoped, code-entity-first workflow subsystem that can be authored, triggered, and inspected through graph nodes without making the graph or graph maps own workflow data.

**Architecture:** Add a Fennel workflow domain under `assets/lua/workflows/` with a durable store, strict outcome contract, code-entity executor adapter, and runner. Expose workflow definitions, steps, runs, run steps, and events through graph key loaders and node adapters; graph authoring operations mutate the workflow store and graph maps remain interaction contexts only. Wire app bootstrap to create `app.workflow-store` and `app.workflow-runner`, register graph loaders, and tick active workflow runs.

**Tech Stack:** Space Fennel modules, existing `entities/code` store, existing Fennel evaluator/kernel semantics, `json-utils` atomic JSON writes, graph key loaders/node adapters, graph-map APIs, Space Fennel test runner.

## Global Constraints

- Use a dedicated, app/user-scoped workflow subsystem with code-entity-backed executable steps.
- The canonical workflow model is a durable workflow definition plus durable workflow runs.
- The graph is one interface over the workflow system, not the owner of workflow data.
- Workflow records are app/user scoped by default, orthogonal to worlds.
- Workflow steps reference code entities rather than embedding durable code bodies directly.
- Workflow-specific metadata belongs on the workflow step record, not on the code entity record.
- The runner does not need separate built-in primitive executors for condition, loop, join, tool call, agent turn, or human input in the first design.
- Workflow code has full app/global access.
- The canonical result is always an outcome table.
- Graph maps are user-facing interaction contexts over graph-visible objects.
- Graph nodes mutate workflow domain objects through explicit workflow-store or workflow-runner APIs.
- Key loaders return nil for missing records, following existing graph loader patterns.
- Missing workflow definitions, code entities, runs, or steps fail loudly at mutation/execution boundaries.
- Unknown or invalid workflow code contract results fail the step with a structured error.
- Deleting a workflow step must handle dependent edges explicitly and should not silently corrupt existing run history.
- Do not treat graph maps as canonical workflow storage.
- Do not add built-in primitive executors for condition, loop, join, tool call, agent turn, or human input in v1.
- Do not sandbox workflow code in this plan.
- Do not replace `AgentRunner`; it remains the agent session/turn system.
- Use `assets/lua/json-utils.fnl` for atomic JSON writes.
- Fennel validation order is compile check first, constraints second, focused Fennel tests third.
- When delimiter or parse errors occur, inspect and repair the nearest enclosing form before rerunning the compile check.

---

## File Structure / Task Decomposition

- `assets/lua/workflows/store.fnl`: durable app/user-scoped workflow definitions, steps, edges, runs, run steps, waits, and events.
- `assets/lua/workflows/outcomes.fnl`: strict outcome table helpers and validation.
- `assets/lua/workflows/code-executor.fnl`: evaluates referenced code entities through existing Fennel evaluator semantics and adapts factory/step objects.
- `assets/lua/workflows/runner.fnl`: workflow orchestration, scheduling, data edges, waits, retries, cancellation, events.
- `assets/lua/workflows/graph-authoring.fnl`: graph edge authoring bridge for workflow step-to-step canonical edges.
- `assets/lua/graph/nodes/workflows.fnl`: root workflow list node.
- `assets/lua/graph/nodes/workflow-definition.fnl`: workflow definition node adapter.
- `assets/lua/graph/nodes/workflow-step.fnl`: workflow step node adapter.
- `assets/lua/graph/nodes/workflow-run.fnl`: workflow run node adapter.
- `assets/lua/graph/nodes/workflow-run-step.fnl`: workflow run-step node adapter.
- `assets/lua/graph/nodes/workflow-run-event.fnl`: workflow event node adapter.
- `assets/lua/graph/view/previews/workflow-definition.fnl`: compact workflow definition preview/actions.
- `assets/lua/graph/view/previews/workflow-run.fnl`: compact run status and show/hide details preview.
- `assets/lua/graph/key-loaders.fnl`: register workflow key schemes.
- `assets/lua/graph/map.fnl`: generalize derived edges and add `remove-edge` so workflow topology is not persisted as map topology.
- `assets/lua/main.fnl`: create/drop/tick app workflow runtime.
- `assets/lua/home-world.fnl`: pass workflow store/runner into graph key loaders.
- `assets/lua/tests/test-workflow-store.fnl`: store tests.
- `assets/lua/tests/test-workflow-code-executor.fnl`: outcome/executor tests.
- `assets/lua/tests/test-workflow-runner.fnl`: runner tests.
- `assets/lua/tests/test-workflow-graph.fnl`: graph loader/node/authoring tests.
- `assets/lua/tests/fast.fnl`: include new focused test modules.
- `docs/dev/features/workflows.md`: canonical developer documentation for workflow architecture, graph doctrine, store paths, and v1 scope.

## Observable Acceptance Criteria

- A workflow definition, steps, edges, run, run-step states, waits, and events persist under `{app.user-data-dir}/workflows/` and reload without any world or graph-map dependency.
- Workflow steps store `:code-entity-id` and never embed durable source code.
- A code entity factory returning a step object can succeed, fail, wait, retry, cancel, skip, branch, loop, and join via strict returned outcome tables.
- Invalid workflow code contracts create failed run-step state and run events instead of silent no-ops.
- Graph key loaders resolve `workflows`, `workflow-definition:<id>`, `workflow-step:<definition-id>:<step-id>`, `workflow-run:<run-id>`, `workflow-run-step:<run-id>:<step-id>`, and `workflow-run-event:<run-id>:<event-id>`.
- Missing workflow graph records resolve to nil.
- Connecting workflow step nodes creates a canonical workflow store edge that is not persisted as graph-map topology.
- Triggering a workflow from a visible definition node immediately creates a visible run node in that graph map and a definition-to-run edge.
- Run nodes expose status colors and can hide/show run details.
- Focused Space Fennel checks, constraints, focused tests, relevant full local suite, and PR CI are green.

---

### Task 1: Durable Workflow Store

**Files:**
- Create: `assets/lua/workflows/store.fnl`
- Test: `assets/lua/tests/test-workflow-store.fnl`

**Interfaces:**
- Consumes: `json-utils.write-json!`, `fs`, `uuid`, `signal`.
- Produces:

```fennel
(local {: WorkflowStore : get-default} (require :workflows/store))

(WorkflowStore {:base-dir string}) -> store

(store:create-definition opts) -> definition
(store:get-definition definition-id) -> definition|nil
(store:list-definitions) -> [definition]
(store:update-definition definition-id updates) -> definition
(store:delete-definition definition-id opts) -> definition

(store:add-step definition-id step) -> step
(store:update-step definition-id step-id updates) -> step
(store:delete-step definition-id step-id opts) -> step

(store:add-edge definition-id edge) -> edge
(store:update-edge definition-id edge-id updates) -> edge
(store:delete-edge definition-id edge-id) -> edge

(store:create-run definition-id input context) -> run
(store:get-run run-id) -> run|nil
(store:list-runs opts) -> [run]
(store:update-run run-id updates) -> run

(store:upsert-run-step run-id step-id updates) -> run-step
(store:get-run-step run-id step-id) -> run-step|nil
(store:list-run-steps run-id) -> [run-step]

(store:append-event run-id event) -> event
(store:list-events run-id) -> [event]
```

- [ ] **Step 1: Write failing store tests**

Add tests with these exact names in `assets/lua/tests/test-workflow-store.fnl`:

```fennel
(fn workflow-store-persists-definitions-app-scoped [])
(fn workflow-store-creates-updates-steps-and-edges [])
(fn workflow-store-delete-step-requires-dependent-edge-decision [])
(fn workflow-store-persists-runs-steps-events-and-waits [])
(fn workflow-store-signals-fire [])
```

Assertions:
- definitions persist under `<base-dir>/workflows/definitions/<id>.json`;
- runs persist under `<base-dir>/workflows/runs/<run-id>.json`;
- no test data path contains a world id or graph-map id unless passed as run context;
- `:code-entity-id` is required on steps;
- `delete-step` without `{:delete-dependent-edges? true}` errors when dependent edges exist;
- `delete-step` with `{:delete-dependent-edges? true}` removes dependent definition edges but leaves existing run history intact;
- signals emit once for created/updated/deleted definitions, run updates, run-step updates, and appended events.

- [ ] **Step 2: Run tests and verify they fail for missing module**

Prerequisite if `./build/space` is missing or stale:

```bash
make build
```

Focused command:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-store:main
```

Expected: failure because `workflows/store` does not exist.

- [ ] **Step 3: Implement `WorkflowStore`**

Create `assets/lua/workflows/store.fnl` with:
- constructor requiring `:base-dir`;
- `root-dir = fs.join-path base-dir "workflows"`;
- `definitions-dir = fs.join-path root-dir "definitions"`;
- `runs-dir = fs.join-path root-dir "runs"`;
- normalized definition shape from the spec;
- normalized run shape from the spec;
- nested run JSON containing `:steps`, `:events`, and run metadata;
- strict errors for missing definition, step, edge, or run at mutation boundaries;
- JSON writes through `JsonUtils.write-json!`;
- ids generated with `Uuid.v4` using prefixes `wf-`, `step-`, `edge-`, `wfr-`, and `event-`;
- signals named:

```fennel
:definition-created
:definition-updated
:definition-deleted
:run-created
:run-updated
:run-step-updated
:event-appended
```

- [ ] **Step 4: Run touched-file compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/workflows/store.fnl --file assets/lua/tests/test-workflow-store.fnl
```

Expected: pass. If parsing fails, inspect the nearest enclosing form around the reported line/column and repair that form before continuing.

- [ ] **Step 5: Run constraints second**

```bash
make constraints
```

Expected: pass.

- [ ] **Step 6: Run focused store tests third**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-store:main
```

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add assets/lua/workflows/store.fnl assets/lua/tests/test-workflow-store.fnl
git commit -m "feat(workflows): add durable workflow store"
```

---

### Task 2: Strict Outcome Contract and Code-Entity Executor

**Files:**
- Create: `assets/lua/workflows/outcomes.fnl`
- Create: `assets/lua/workflows/code-executor.fnl`
- Test: `assets/lua/tests/test-workflow-code-executor.fnl`

**Interfaces:**
- Consumes:

```fennel
(store:get-definition definition-id)
(store:get-run run-id)
(code-store:get-entity code-entity-id)
(FennelEvaluator.eval-source source)
```

- Produces:

```fennel
(local Outcomes (require :workflows/outcomes))
(Outcomes.make-context opts) -> ctx
(Outcomes.validate-outcome outcome context) -> normalized-outcome
(ctx:succeed output opts) -> {:status :succeeded :output output}
(ctx:fail message data) -> {:status :failed :error {:message message :data data}}
(ctx:wait wait-kind request state) -> {:status :waiting :wait-kind wait-kind :request request :state state}
(ctx:retry delay-ms state) -> {:status :retry :delay-ms delay-ms :state state}
(ctx:cancelled output) -> {:status :cancelled :output output}
(ctx:skip reason) -> {:status :skipped :reason reason}

(local {: WorkflowCodeExecutor} (require :workflows/code-executor))
(WorkflowCodeExecutor {:code-store code-store :app app}) -> executor
(executor:evaluate-step-object definition step) -> step-object
(executor:run-step definition step input state) -> outcome
(executor:resume-step definition step wait-result state) -> outcome
(executor:cancel-step definition step state) -> outcome
```

- [ ] **Step 1: Write failing executor tests**

Add these tests in `assets/lua/tests/test-workflow-code-executor.fnl`:

```fennel
(fn outcome-helpers-return-strict-tables [])
(fn invalid-outcomes-fail-loudly [])
(fn executor-evaluates-code-entity-factory-with-full-app-access [])
(fn executor-rejects-missing-code-entity [])
(fn ctx-helper-does-not-complete-without-returned-outcome [])
(fn executor-adapts-resume-and-cancel-methods [])
```

Assertions:
- only `:succeeded`, `:failed`, `:waiting`, `:retry`, `:cancelled`, and `:skipped` are accepted outcome statuses;
- helper methods return tables and do not mutate store or complete a step by side effect;
- a code entity source shaped as `(fn [opts] {:run (fn [self ctx input state] ...)})` is called as a factory with step config;
- a code entity source that evaluates directly to `{:run ...}` is accepted;
- `_G.app.workflow_executor_test_value` can be read by workflow code;
- missing code entity and non-Fennel language errors are explicit;
- a step method that calls `(ctx:succeed ...)` but returns `nil` is invalid.

- [ ] **Step 2: Run tests and verify they fail for missing modules**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-code-executor:main
```

Expected: failure because `workflows/outcomes` and `workflows/code-executor` do not exist.

- [ ] **Step 3: Implement outcomes**

Create `assets/lua/workflows/outcomes.fnl` with:
- exact helper method names from the interface;
- `validate-outcome` requiring a table with one allowed `:status`;
- structured failure normalization requiring `:error.message` for `:failed`;
- `:waiting` requiring `:wait-kind`;
- `:retry` requiring numeric `:delay-ms >= 0`;
- optional `:next-step-ids` accepted only as a table of strings for `:succeeded` and `:skipped`;
- errors that include the run id and step id when context supplies them.

- [ ] **Step 4: Implement code executor**

Create `assets/lua/workflows/code-executor.fnl` with:
- required `:code-store`;
- Fennel language acceptance for `"fnl"` and `"fennel"`;
- evaluation through `fennel-evaluator.eval-source`, which uses `_G` and therefore preserves full app/global access;
- factory adaptation:

```fennel
(if (= (type evaluated) "function")
    (evaluated (or step.config {}))
    evaluated)
```

- required `:run` function on the step object for run execution;
- optional `:resume` and `:cancel` functions;
- explicit structured errors for missing entity, bad language, evaluation failure, bad factory return, missing method, and invalid returned outcome.

- [ ] **Step 5: Run touched-file compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/workflows/outcomes.fnl --file assets/lua/workflows/code-executor.fnl --file assets/lua/tests/test-workflow-code-executor.fnl
```

Expected: pass.

- [ ] **Step 6: Run constraints second**

```bash
make constraints
```

Expected: pass.

- [ ] **Step 7: Run focused executor tests third**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-code-executor:main
```

Expected: pass.

- [ ] **Step 8: Commit**

```bash
git add assets/lua/workflows/outcomes.fnl assets/lua/workflows/code-executor.fnl assets/lua/tests/test-workflow-code-executor.fnl
git commit -m "feat(workflows): add code entity workflow contract"
```

---

### Task 3: Workflow Runner Orchestration

**Files:**
- Create: `assets/lua/workflows/runner.fnl`
- Test: `assets/lua/tests/test-workflow-runner.fnl`

**Interfaces:**
- Consumes:

```fennel
WorkflowStore methods from Task 1
WorkflowCodeExecutor methods from Task 2
```

- Produces:

```fennel
(local {: WorkflowRunner} (require :workflows/runner))
(WorkflowRunner {:store store :executor executor :app app}) -> runner

(runner:start-run definition-id input context) -> run
(runner:tick-run run-id opts) -> run
(runner:tick opts) -> [run]
(runner:resume-step run-id step-id wait-result) -> run-step
(runner:cancel-run run-id reason) -> run
```

- [ ] **Step 1: Write failing runner tests**

Add these tests in `assets/lua/tests/test-workflow-runner.fnl`:

```fennel
(fn runner-start-run-creates-run-steps-and-events [])
(fn runner-succeeds-linear-workflow-and-data-edge [])
(fn runner-fails-step-on-invalid-contract [])
(fn runner-waits-and-resumes-human-input [])
(fn runner-retries-with-attempt-state [])
(fn runner-cancels-run [])
(fn runner-branches-from-next-step-ids [])
(fn runner-loops-with-one-step-per-tick [])
(fn runner-joins-after-all-inbound-steps-succeed [])
```

Assertions:
- `start-run` creates run status `:queued`, pending run-step records, and a `:run-created` event;
- `tick-run` runs at most one ready step by default;
- data edges copy `source.output[source-port]` to target input `target-port`, and copy whole source output when ports are nil;
- invalid contract creates failed run-step state and failed run event;
- waiting outcome stores `:wait` on the run step and run status `:waiting`;
- resume calls step object `:resume`;
- retry increments attempt and appends `:step-retried`;
- cancel sets run status `:cancelled` and appends `:run-cancelled`;
- outcome `:next-step-ids` selects outgoing control targets for branch/loop behavior;
- join target runs only after all selected inbound control source steps are terminal.

- [ ] **Step 2: Run tests and verify they fail for missing runner**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-runner:main
```

Expected: failure because `workflows/runner` does not exist.

- [ ] **Step 3: Implement runner**

Create `assets/lua/workflows/runner.fnl` with:
- required `:store` and `:executor`;
- status transitions exactly using run statuses `:queued`, `:running`, `:waiting`, `:succeeded`, `:failed`, `:cancelled`;
- run-step statuses exactly using `:pending`, `:ready`, `:running`, `:waiting`, `:succeeded`, `:failed`, `:skipped`, `:cancelled`;
- event types:

```fennel
:run-created
:run-started
:step-ready
:step-started
:step-succeeded
:step-failed
:step-waiting
:step-retried
:step-skipped
:step-cancelled
:run-waiting
:run-succeeded
:run-failed
:run-cancelled
```

- no primitive executor table or built-in step kinds;
- scheduler that derives ready steps from control edges and existing run-step state;
- data-edge input builder from prior outputs;
- one-step-per-`tick-run` default with `opts.max-steps` override;
- explicit run failure when no ready work remains and unresolved pending steps exist.

- [ ] **Step 4: Run touched-file compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/workflows/runner.fnl --file assets/lua/tests/test-workflow-runner.fnl
```

Expected: pass.

- [ ] **Step 5: Run constraints second**

```bash
make constraints
```

Expected: pass.

- [ ] **Step 6: Run focused runner tests third**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-runner:main
```

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add assets/lua/workflows/runner.fnl assets/lua/tests/test-workflow-runner.fnl
git commit -m "feat(workflows): add workflow runner orchestration"
```

---

### Task 4: Workflow Graph Key Loaders and Node Adapters

**Files:**
- Create: `assets/lua/graph/nodes/workflows.fnl`
- Create: `assets/lua/graph/nodes/workflow-definition.fnl`
- Create: `assets/lua/graph/nodes/workflow-step.fnl`
- Create: `assets/lua/graph/nodes/workflow-run.fnl`
- Create: `assets/lua/graph/nodes/workflow-run-step.fnl`
- Create: `assets/lua/graph/nodes/workflow-run-event.fnl`
- Modify: `assets/lua/graph/key-loaders.fnl`
- Test: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes:

```fennel
WorkflowStore from Task 1
WorkflowRunner from Task 3
Graph.GraphNode
Graph.GraphEdge
```

- Produces:

```fennel
(workflows/register-loader graph {:store store :runner runner})
(workflow-definition/register-loader graph {:store store :runner runner})
(workflow-step/register-loader graph {:store store})
(workflow-run/register-loader graph {:store store :runner runner})
(workflow-run-step/register-loader graph {:store store})
(workflow-run-event/register-loader graph {:store store})

Workflow key schemes:
"workflows"
"workflow-definition:<definition-id>"
"workflow-step:<definition-id>:<step-id>"
"workflow-run:<run-id>"
"workflow-run-step:<run-id>:<step-id>"
"workflow-run-event:<run-id>:<event-id>"
```

- [ ] **Step 1: Extend graph tests with loader/node failures**

In `assets/lua/tests/test-workflow-graph.fnl`, add these failing tests:

```fennel
(fn workflow-key-loaders-resolve-all-workflow-keys [])
(fn workflow-key-loaders-return-nil-for-missing-records [])
(fn workflow-definition-node-expands-to-step-code-and-run-edges [])
(fn workflow-run-node-expands-to-definition-run-step-and-event-edges [])
(fn workflow-status-color-mapping-covers-all-statuses [])
```

Assertions:
- `graph:create-node-by-key "workflows"` returns a root node;
- definition, step, run, run-step, and event keys resolve only when store records exist;
- a definition node edge list includes step nodes, code-entity nodes, canonical workflow step edges, and definition-to-run edges;
- a run node edge list includes its definition edge always and run-step/event detail edges only when details are expanded;
- color mapping covers pending, ready/running, waiting, failed, succeeded, skipped, and cancelled.

- [ ] **Step 2: Run tests and verify they fail for missing loaders**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: failure because workflow graph node modules do not exist.

- [ ] **Step 3: Implement workflow node adapters**

Create node modules with these invariants:
- constructors require explicit store, and runner where actions start or resume runs;
- node adapters never persist workflow data;
- node adapters never store graph-map ownership;
- missing backing records cause loader nil, not constructor fallback;
- relationship projections are exposed through explicit preview/actions that load selected records into the active graph map;
- workflow step nodes expose `:workflow-definition-id`, `:workflow-step-id`, and `:workflow-store`;
- run nodes expose `:details-expanded?`, `:show-details`, `:hide-details`, and `:toggle-details`;
- status colors use one shared mapping exported from `workflow-run.fnl`.

- [ ] **Step 4: Register loaders in `graph/key-loaders.fnl`**

Modify `GraphKeyLoaders.register` to accept canonical option keys:

```fennel
:workflow-store
:workflow-runner
```

Register all workflow loaders after code-entity loader registration so step nodes can link to existing code entity nodes.

- [ ] **Step 5: Run icon availability check for planned actions**

```bash
rg "^(play_arrow|visibility|visibility_off|cancel)$" assets/material-design-icons/icons.txt
```

Expected: each icon name appears exactly as a line in the icon list.

- [ ] **Step 6: Run touched-file compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/workflows.fnl --file assets/lua/graph/nodes/workflow-definition.fnl --file assets/lua/graph/nodes/workflow-step.fnl --file assets/lua/graph/nodes/workflow-run.fnl --file assets/lua/graph/nodes/workflow-run-step.fnl --file assets/lua/graph/nodes/workflow-run-event.fnl --file assets/lua/graph/key-loaders.fnl --file assets/lua/tests/test-workflow-graph.fnl
```

Expected: pass.

- [ ] **Step 7: Run constraints second**

```bash
make constraints
```

Expected: pass.

- [ ] **Step 8: Run focused graph tests third**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: pass for Task 4 tests.

- [ ] **Step 9: Commit**

```bash
git add assets/lua/graph/nodes/workflows.fnl assets/lua/graph/nodes/workflow-definition.fnl assets/lua/graph/nodes/workflow-step.fnl assets/lua/graph/nodes/workflow-run.fnl assets/lua/graph/nodes/workflow-run-step.fnl assets/lua/graph/nodes/workflow-run-event.fnl assets/lua/graph/key-loaders.fnl assets/lua/tests/test-workflow-graph.fnl
git commit -m "feat(graph): expose workflows through graph nodes"
```

---

### Task 5: Graph Authoring and Triggering Semantics

**Files:**
- Create: `assets/lua/workflows/graph-authoring.fnl`
- Modify: `assets/lua/graph/map.fnl`
- Modify: `assets/lua/graph/nodes/workflow-definition.fnl`
- Modify: `assets/lua/graph/nodes/workflow-step.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes:

```fennel
WorkflowStore:add-edge
WorkflowStore:delete-edge
WorkflowRunner:start-run
GraphMap:add-edge
GraphMap:load-by-key
```

- Produces:

```fennel
(local GraphAuthoring (require :workflows/graph-authoring))
(GraphAuthoring.author-edge source-node target-node opts) -> graph-edge-opts|nil
(GraphAuthoring.delete-authored-edge edge opts) -> deleted-domain-edge|nil

(graph-map:remove-edge edge-or-key opts) -> edge|nil

(workflow-step-node:author-domain-edge edge edge-opts) -> {:from-workflow-edge edge-id}
(workflow-step-node:remove-domain-edge edge edge-opts) -> workflow-edge|nil

(workflow-definition-node:start-workflow-from-graph input context-opts) -> run
```

- [ ] **Step 1: Add failing graph authoring tests**

Extend `assets/lua/tests/test-workflow-graph.fnl` with:

```fennel
(fn graph-step-connection-creates-canonical-workflow-control-edge [])
(fn graph-map-capture-skips-workflow-derived-edges [])
(fn graph-remove-edge-deletes-canonical-workflow-edge [])
(fn start-definition-node-creates-visible-run-node-and-definition-run-edge [])
(fn start-context-captures-graph-map-and-selected-node-keys [])
```

Assertions:
- connecting two workflow step nodes in the same definition creates one store edge with `:kind :control`;
- the displayed edge has `edge._opts.from-workflow-edge`;
- `graph-map:capture-state` does not persist workflow-derived edges;
- `graph-map:remove-edge` for the displayed workflow edge deletes the canonical workflow edge from the store;
- starting from a definition node creates a run record immediately, loads `workflow-run:<run-id>` into the active graph map, and inserts a definition-to-run edge;
- run context includes `:graph-map-id` and `:graph-node-keys` from the active graph map selection.

- [ ] **Step 2: Run tests and verify authoring failures**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: new tests fail because authoring and `GraphMap:remove-edge` are absent.

- [ ] **Step 3: Generalize derived edge handling in `graph/map.fnl`**

Modify `derived-edge-id` so derived edges include:

```fennel
(or edge-opts.from-link-entity
    edge-opts.from-workflow-edge
    (and edge edge._opts edge._opts.from-link-entity)
    (and edge edge._opts edge._opts.from-workflow-edge))
```

Keep existing link-entity behavior unchanged.

- [ ] **Step 4: Add `GraphMap:remove-edge`**

Implement `remove-edge` to:
- accept an edge table or edge key string;
- remove the edge from `edges`, `edge-map`, and derived-edge keys;
- emit `edge-removed`;
- call `edge.source:remove-domain-edge edge edge._opts` when that method exists;
- return the removed edge or nil.

- [ ] **Step 5: Implement workflow graph authoring bridge**

Create `assets/lua/workflows/graph-authoring.fnl` with:
- `author-edge` requiring source and target workflow step nodes in the same definition;
- default new edge shape:

```fennel
{:kind :control
 :source-step-id source.workflow-step-id
 :target-step-id target.workflow-step-id
 :condition nil}
```

- explicit error when source and target are workflow steps from different definitions;
- `delete-authored-edge` deleting the store edge referenced by `edge._opts.from-workflow-edge`.

- [ ] **Step 6: Wire workflow nodes to authoring and triggering**

Modify:
- `workflow-step.fnl` to expose `author-domain-edge` and `remove-domain-edge`;
- `workflow-definition.fnl` to expose `start-workflow-from-graph`, create run through runner, load the run node through `self.graph:load-by-key`, and add a definition-to-run graph edge to the current graph-like context.

- [ ] **Step 7: Run touched-file compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/workflows/graph-authoring.fnl --file assets/lua/graph/map.fnl --file assets/lua/graph/nodes/workflow-definition.fnl --file assets/lua/graph/nodes/workflow-step.fnl --file assets/lua/tests/test-workflow-graph.fnl
```

Expected: pass.

- [ ] **Step 8: Run constraints second**

```bash
make constraints
```

Expected: pass.

- [ ] **Step 9: Run focused graph tests third**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: pass.

- [ ] **Step 10: Commit**

```bash
git add assets/lua/workflows/graph-authoring.fnl assets/lua/graph/map.fnl assets/lua/graph/nodes/workflow-definition.fnl assets/lua/graph/nodes/workflow-step.fnl assets/lua/tests/test-workflow-graph.fnl
git commit -m "feat(graph): author workflow edges through graph interactions"
```

---

### Task 6: Run Detail Previews and Status Visibility

**Files:**
- Create: `assets/lua/graph/view/previews/workflow-definition.fnl`
- Create: `assets/lua/graph/view/previews/workflow-run.fnl`
- Modify: `assets/lua/graph/nodes/workflow-definition.fnl`
- Modify: `assets/lua/graph/nodes/workflow-run.fnl`
- Modify: `assets/lua/graph/nodes/workflow-run-step.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes:

```fennel
WorkflowDefinitionNode:start-workflow-from-graph
WorkflowRunNode:toggle-details
Button
Flex
Text
```

- Produces:

```fennel
(require :graph/view/previews/workflow-definition) -> build closure
(require :graph/view/previews/workflow-run) -> build closure

WorkflowRunStatus.status-color status -> glm.vec4
WorkflowRunStatus.status-tone status -> :neutral|:info|:success|:warning|:danger
```

- [ ] **Step 1: Add failing preview/status tests**

Extend `assets/lua/tests/test-workflow-graph.fnl` with:

```fennel
(fn workflow-definition-preview-builds-with-start-action [])
(fn workflow-run-preview-builds-with-toggle-action [])
(fn workflow-run-details-toggle-changes-expanded-edge_projection [])
(fn workflow-run-step-status-colors-cover-all-run-step-statuses [])
```

Assertions:
- previews assert on missing build context rather than falling back silently;
- definition preview exposes a `Start` action that calls `start-workflow-from-graph`;
- run preview exposes `Show Details` when collapsed and `Hide Details` when expanded;
- toggling details controls whether explicit run-step and event detail actions materialize those records;
- all run-step statuses from the spec map to a non-nil color.

- [ ] **Step 2: Run tests and verify preview failures**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: new preview/status tests fail.

- [ ] **Step 3: Implement previews**

Create preview modules using existing widget conventions:
- widget constructors return build closures;
- builders require a renderer/build context;
- use `Flex`, `Button`, and `Text`;
- direct child widgets are dropped by the composite preview;
- no dirtying setters during layout passes.

- [ ] **Step 4: Wire previews onto nodes**

Modify workflow definition/run/run-step nodes so:
- `:preview` points to the new preview modules;
- labels include current status for run/run-step nodes;
- run node `actions` include start/cancel/toggle entries where applicable;
- run details default collapsed.

- [ ] **Step 5: Run touched-file compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/previews/workflow-definition.fnl --file assets/lua/graph/view/previews/workflow-run.fnl --file assets/lua/graph/nodes/workflow-definition.fnl --file assets/lua/graph/nodes/workflow-run.fnl --file assets/lua/graph/nodes/workflow-run-step.fnl --file assets/lua/tests/test-workflow-graph.fnl
```

Expected: pass.

- [ ] **Step 6: Run constraints second**

```bash
make constraints
```

Expected: pass.

- [ ] **Step 7: Run focused graph/UI tests third**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: pass.

- [ ] **Step 8: Commit**

```bash
git add assets/lua/graph/view/previews/workflow-definition.fnl assets/lua/graph/view/previews/workflow-run.fnl assets/lua/graph/nodes/workflow-definition.fnl assets/lua/graph/nodes/workflow-run.fnl assets/lua/graph/nodes/workflow-run-step.fnl assets/lua/tests/test-workflow-graph.fnl
git commit -m "feat(graph): show workflow run status and details"
```

---

### Task 7: App Bootstrap, Test Suite Registration, and Developer Documentation

**Files:**
- Modify: `assets/lua/main.fnl`
- Modify: `assets/lua/home-world.fnl`
- Modify: `assets/lua/tests/fast.fnl`
- Create: `docs/dev/features/workflows.md`
- Test: `assets/lua/tests/test-workflow-store.fnl`
- Test: `assets/lua/tests/test-workflow-code-executor.fnl`
- Test: `assets/lua/tests/test-workflow-runner.fnl`
- Test: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes:

```fennel
WorkflowStore.get-default {:base-dir app.user-data-dir}
WorkflowCodeExecutor.WorkflowCodeExecutor {:code-store app.code-store :app app}
WorkflowRunner.WorkflowRunner {:store app.workflow-store :executor app.workflow-code-executor :app app}
GraphKeyLoaders.register graph {:workflow-store app.workflow-store :workflow-runner app.workflow-runner}
```

- Produces:

```fennel
app.workflow-store
app.workflow-code-executor
app.workflow-runner
```

- [ ] **Step 1: Add failing bootstrap coverage**

Add assertions to existing focused tests:
- `test-workflow-store.fnl`: `get-default` uses app/user scoped base dir when passed `{:base-dir root}`.
- `test-workflow-graph.fnl`: `GraphKeyLoaders.register` with `:workflow-store` and `:workflow-runner` resolves `workflows`.
- `test-workflow-runner.fnl`: `runner:tick` advances active app-scoped runs.

- [ ] **Step 2: Run focused tests and verify bootstrap failures**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-store:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-runner:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: failures for missing app/bootstrap registration paths.

- [ ] **Step 3: Wire app runtime in `main.fnl`**

Modify `main.fnl` to:
- require workflow store, code executor, and runner near agent/runtime requires;
- create `app.workflow-store` after `app.user-data-dir` is available;
- create `app.workflow-code-executor` with app/global access;
- create `app.workflow-runner`;
- call `app.workflow-runner:tick` from the existing engine tick handler after `app.kernels:tick`;
- drop/clear workflow runtime in `app.drop`.

- [ ] **Step 4: Pass workflow dependencies into graph key loaders**

Modify `home-world.fnl` `GraphKeyLoaders.register` call to pass:

```fennel
:workflow-store app.workflow-store
:workflow-runner app.workflow-runner
```

- [ ] **Step 5: Register new focused tests in `fast.fnl`**

Add these modules near existing graph/workflow-adjacent tests:

```fennel
:tests.test-workflow-store
:tests.test-workflow-code-executor
:tests.test-workflow-runner
:tests.test-workflow-graph
```

- [ ] **Step 6: Create developer documentation**

Create `docs/dev/features/workflows.md` documenting:
- app/user-scoped store path `{app.user-data-dir}/workflows/`;
- definition/run/key shapes;
- code-entity-first executable step contract;
- strict outcome table statuses and optional `:next-step-ids`;
- graph doctrine: graph is exposure layer, graph maps are interaction contexts, workflow store owns topology;
- v1 exclusions: no primitive executors, no sandboxing, no graph-map workflow storage, no `AgentRunner` replacement;
- validation ladder for workflow changes.

- [ ] **Step 7: Run compile check first**

Because this task touches app bootstrap and multiple Fennel modules, run the broad compile check:

```bash
make fennel-check
```

Expected: pass.

- [ ] **Step 8: Run constraints second**

```bash
make constraints
```

Expected: pass.

- [ ] **Step 9: Run focused workflow tests third**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-store:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-code-executor:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-runner:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: all pass.

- [ ] **Step 10: Run complete relevant local suite**

This is justified because the task touches app bootstrap, graph key-loader registration, graph map edge semantics, and `tests.fast` membership.

Prerequisite if build output is stale:

```bash
make build
```

Complete relevant local suite:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: pass.

- [ ] **Step 11: Commit**

```bash
git add assets/lua/main.fnl assets/lua/home-world.fnl assets/lua/tests/fast.fnl assets/lua/tests/test-workflow-store.fnl assets/lua/tests/test-workflow-code-executor.fnl assets/lua/tests/test-workflow-runner.fnl assets/lua/tests/test-workflow-graph.fnl docs/dev/features/workflows.md
git commit -m "feat(workflows): bootstrap graph-authored workflows"
```

---

## Final Validation Ladder

1. Runtime/freshness prerequisite when `./build/space` may be missing or stale:

```bash
make build
```

2. Focused Fennel compile check first:

```bash
make fennel-check
```

3. Constraints second:

```bash
make constraints
```

4. Focused workflow tests third:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-store:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-code-executor:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-runner:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

5. Complete relevant local suite:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

6. Broader final gate: PR CI is the full integration gate. Do not claim ready-to-merge until PR CI is green.

## Explicitly Out of Scope

- Rich preview port handle rendering and edge endpoint anchoring.
- General node movement between graph maps.
- Sandboxing workflow code.
- External `.fnl` module storage as the primary workflow code mechanism.
- Replacing `AgentRunner`.
- Treating graph maps as canonical workflow storage.
- Built-in primitive executors for condition, loop, join, tool call, agent turn, or human input.
- Merge/push/PR creation from this planning task.
