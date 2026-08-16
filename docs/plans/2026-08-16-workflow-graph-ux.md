# Workflow Graph UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first systematic workflow graph UX slice so workflow nodes work as visual editor, inspector, and control panel surfaces.

**Architecture:** Keep workflow/code stores as domain owners and use graph nodes as explicit `GraphMap` adapters. Existing workflow domain nodes remain anchors; richer previews handle common local tasks; UX-purpose graph nodes handle focused step/run exploration; full node views handle dense payloads.

**Tech Stack:** Space Fennel, `GraphMap`, workflow graph key loaders, workflow graph node previews/views, Space UI widgets (`SearchView`, `ListView`, `Input`, `Flex`, `Button`, `Text`), project-native Fennel tests.

## Global Constraints

- The graph is an exposure/adaptor layer, not the owner of domain objects.
- Graph core persists topology only; owning systems persist workflow definitions, workflow steps, workflow runs, run steps, run events, and code entities.
- Key loaders adapt owning stores/systems into graph node adapters.
- `GraphMap` owns interaction context over shared graph-addressable objects.
- Keep materialization explicit and user-directed; do not reintroduce hidden relationship hooks or graph trigger APIs.
- No return to automatic relationship expansion or `get-edges`-style discovery.
- No confirmation-dialog framework; destructive actions must be explicit graph actions.
- UX-purpose nodes own no workflow records.
- Actions that materialize groups of nodes must expose exactly what they do.
- `Hide Details` / `Show Details` generic toggle behavior must be removed; no compatibility alias may preserve it.
- Missing workflow store, code store, graph map, selected node data, or key loaders must fail loudly at action boundaries.
- Domain mutations that require graph materialization must preflight required graph dependencies before durable side effects, or roll back all domain and partial graph-map changes on failure.
- Long strings, logs, JSON, Fennel forms, inputs, outputs, and errors must use multiline input/editor-style widgets or full node views, not single-line labels.
- Fennel/UI work must follow Space order: compile check first, constraints second, focused Fennel tests third.
- Fennel widgets must require direct build context, own/drop direct child widgets, and disconnect owned signal listeners.
- Use `local` instead of `let`; use factory functions instead of constructors; use multi-branch `if` forms instead of deeply nested `if` where practical.
- No new dependencies.
- User-facing workflow documentation must be goal-oriented and scenario-based, not control-name-based.
- User-facing workflow documentation must collectively demonstrate every workflow graph feature delivered by this plan.

---

## File Structure

- Create: `docs/dev/features/workflow-graph-ux.md` — canonical workflow graph UX flows and first-slice behavior.
- Create: `docs/user/workflows/index.md` — user-facing workflow graph guide index.
- Create: `docs/user/workflows/create-help-desk-workflow.md` — end-to-end creation/topology/code/run scenario.
- Create: `docs/user/workflows/debug-failed-workflow-run.md` — find a failed run, reveal failed step, inspect payloads, edit code, rerun.
- Create: `docs/user/workflows/use-graph-selection-as-run-context.md` — start a workflow from selected graph nodes and inspect captured context.
- Create: `docs/user/workflows/inspect-run-timeline-and-payloads.md` — timeline/event/payload inspection without graph flooding.
- Create: `docs/user/workflows/monitor-and-cancel-running-workflow.md` — monitor a running workflow and cancel when supported.
- Create: `docs/user/workflows/edit-workflow-topology.md` — reveal steps, connect/remove step edges, edit code, validate topology.
- Modify: `docs/user/index.md` — link the workflow user docs section.
- Modify: `docs/dev/notes/graph.md` — general preview vs UX-purpose node vs full-view doctrine.
- Modify: `docs/dev/graph-maps.md` — workflow materialization and UX-purpose node topology semantics.
- Modify: `assets/lua/graph/nodes/workflow-definition.fnl` — definition step item APIs, selected/all step materialization, step explorer materialization.
- Create: `assets/lua/graph/nodes/workflow-step-explorer.fnl` — UX-purpose node for exploring one workflow definition's steps.
- Create: `assets/lua/graph/view/previews/workflow-step-explorer.fnl` — searchable step explorer preview.
- Modify: `assets/lua/graph/view/previews/workflow-definition.fnl` — structured definition inspector.
- Modify: `assets/lua/graph/nodes/workflow-run.fnl` — granular run inspection methods/actions.
- Create: `assets/lua/graph/nodes/workflow-run-timeline.fnl` — UX-purpose timeline/event browser node for one run.
- Create: `assets/lua/graph/view/previews/workflow-run-timeline.fnl` — searchable timeline/event browser preview.
- Modify: `assets/lua/graph/view/previews/workflow-run.fnl` — granular run action buttons.
- Modify: `assets/lua/graph/nodes/workflow-run-step.fnl` — attach full node view and record accessor for payload inspection.
- Modify: `assets/lua/graph/nodes/workflow-run-event.fnl` — attach full node view and record accessor for payload inspection.
- Create: `assets/lua/graph/view/views/workflow-run-step.fnl` — multiline run-step payload panel.
- Create: `assets/lua/graph/view/views/workflow-run-event.fnl` — multiline event payload panel.
- Modify: `assets/lua/graph/view/previews/workflow-run-step.fnl` — compact summary with full-view guidance.
- Modify: `assets/lua/graph/view/previews/workflow-run-event.fnl` — compact summary with full-view guidance.
- Modify: `assets/lua/graph/key-loaders.fnl` — register step explorer and run timeline key loaders.
- Modify/Test: `assets/lua/tests/test-workflow-graph.fnl` — workflow UX behavior, preview lifecycle, static no-leftover checks.
- Modify/Test: `assets/lua/tests/test-workflow-graph-action-boundaries.fnl` — loader/graph-map preflight boundaries for new actions.

---

### Task 1: Graph UX Doctrine and Workflow UX Docs

**Files:**
- Create: `docs/user/workflows/index.md`
- Create: `docs/user/workflows/create-help-desk-workflow.md`
- Create: `docs/user/workflows/debug-failed-workflow-run.md`
- Create: `docs/user/workflows/use-graph-selection-as-run-context.md`
- Create: `docs/user/workflows/inspect-run-timeline-and-payloads.md`
- Create: `docs/user/workflows/monitor-and-cancel-running-workflow.md`
- Create: `docs/user/workflows/edit-workflow-topology.md`
- Modify: `docs/user/index.md`
- Create: `docs/dev/features/workflow-graph-ux.md`
- Modify: `docs/dev/notes/graph.md`
- Modify: `docs/dev/graph-maps.md`

**Interfaces:**
- Consumes: committed spec `docs/specs/2026-08-16-workflow-graph-ux-design.md`.
- Produces documented doctrine for later implementation tasks:
  - preview = compact local controls;
  - UX-purpose graph node = focused operation/detail surface;
  - full node view/panel = dense content and long payloads;
  - workflow graph materialization remains explicit and map-local.
- Produces user-facing workflow docs that demonstrate every first-slice workflow graph feature through functional goals:
  - create workflow;
  - reveal/search steps;
  - edit step code;
  - connect/remove workflow step edges;
  - start a run;
  - start a run using active graph selection as context;
  - browse runs;
  - inspect run timeline/events/payloads;
  - reveal failed run steps;
  - cancel or monitor runs when the run status supports it.

- [ ] **Step 1: Run documentation baseline searches.**

  Run:

  ```bash
  rg "Preview vs UX node vs full view" docs/dev/notes/graph.md docs/dev/features || true
  rg "workflow-step-explorer" docs/dev || true
  rg "workflow-run-timeline" docs/dev || true
  rg "Find and fix the workflow step that caused a failed run" docs/user || true
  rg "Use selected graph nodes as workflow run context" docs/user || true
  ```

  Expected: at least one search misses the new doctrine because these docs do not exist yet.

- [ ] **Step 2: Create user workflow docs index and link it.**

  Create `docs/user/workflows/index.md` with this structure:

  ```markdown
  # Workflow User Flows

  Workflows are edited, run, and inspected from the graph. These guides are scenario-based: each page starts from a real goal and shows the graph actions that accomplish it.

  ## Build and edit workflows
  - [Create a help desk workflow from scratch](./create-help-desk-workflow)
  - [Edit workflow topology with graph step nodes](./edit-workflow-topology)

  ## Run workflows
  - [Use selected graph nodes as workflow run context](./use-graph-selection-as-run-context)

  ## Debug and inspect runs
  - [Find and fix the workflow step that caused a failed run](./debug-failed-workflow-run)
  - [Inspect a run timeline and payloads without flooding the graph](./inspect-run-timeline-and-payloads)
  - [Monitor and cancel a running workflow](./monitor-and-cancel-running-workflow)
  ```

  Add a link to `docs/user/index.md`:

  ```markdown
  - [Workflow User Flows](/user/workflows/) — create, edit, run, inspect, and debug graph workflows
  ```

- [ ] **Step 3: Create `create-help-desk-workflow.md`.**

  The page must be titled `# Create a help desk workflow from scratch` and demonstrate:
  - opening Start -> Workflows;
  - using `New Workflow`;
  - finding the workflow definition node;
  - using `New Step`;
  - opening a step's code entity with `Show Code`;
  - editing code in the code view;
  - revealing all steps;
  - connecting steps with graph edges;
  - using `Start` to create a run;
  - opening the run and inspecting result state.

- [ ] **Step 4: Create `edit-workflow-topology.md`.**

  The page must be titled `# Edit workflow topology with graph step nodes` and demonstrate:
  - opening an existing workflow definition;
  - using step search to reveal one step;
  - using `Reveal All Steps` for visual topology;
  - using `Open Step Explorer` when the definition preview is too small;
  - connecting workflow-step nodes to create canonical workflow edges;
  - removing a step edge to remove the canonical workflow edge;
  - opening linked code nodes for surgical edits;
  - confirming the visible derived workflow edges show the current topology.

- [ ] **Step 5: Create `debug-failed-workflow-run.md`.**

  The page must be titled `# Find and fix the workflow step that caused a failed run` and demonstrate:
  - opening a workflow definition and using run search to find the failed run;
  - opening the run node;
  - using `Reveal Failed Steps` instead of dumping all details;
  - opening the failed run-step payload panel;
  - following the failed run-step to the workflow step and linked code entity;
  - editing the step code;
  - starting a new run;
  - comparing the new run timeline/status against the failed run.

- [ ] **Step 6: Create `use-graph-selection-as-run-context.md`.**

  The page must be titled `# Use selected graph nodes as workflow run context` and demonstrate:
  - selecting graph nodes that should become run context;
  - starting a workflow from the definition node;
  - confirming the created run records graph-map id and selected node keys when available;
  - opening the run timeline or payload panel to verify the workflow used that context;
  - handling invalid or empty selections as explicit graph-native failures/status, not silent no-ops.

- [ ] **Step 7: Create `inspect-run-timeline-and-payloads.md`.**

  The page must be titled `# Inspect a run timeline and payloads without flooding the graph` and demonstrate:
  - opening a workflow run from a definition's run search;
  - using `Open Timeline` to open `workflow-run-timeline:<run-id>` without materializing every event;
  - using timeline event search to materialize one event;
  - using `Show Run Steps` when all run steps are useful;
  - using run-step and event full views for multiline payloads/logs/errors;
  - using `Cancel Run` only when the run status supports cancellation;
  - removing graph nodes manually when the visible working set becomes too dense.

- [ ] **Step 8: Create `docs/dev/features/workflow-graph-ux.md`.**
- [ ] **Step 8: Create `monitor-and-cancel-running-workflow.md`.**

  The page must be titled `# Monitor and cancel a running workflow` and demonstrate:
  - starting or opening an in-progress workflow run;
  - reading run status from the workflow run node;
  - opening the timeline to watch progress without materializing every event;
  - revealing current run steps when the user needs graph context;
  - using `Cancel Run` only when the run status supports cancellation;
  - verifying cancellation through the run node status and timeline events;
  - recognizing completed/non-cancellable runs where cancellation is not shown.

- [ ] **Step 9: Create `docs/dev/features/workflow-graph-ux.md`.**

  Include these exact headings:

  ```markdown
  # Workflow Graph UX
  ## First-slice scope
  ## Definition preview
  ## Step explorer UX node
  ## Run inspection
  ## Payload panels
  ## Action-boundary rules
  ## Out of scope
  ```

  The document must state:
  - workflow definitions expose step search, run search, quick start, new step, reveal all steps, and open step explorer;
  - `workflow-step-explorer:<definition-id>` owns no workflow data and only adapts `WorkflowStore`;
  - workflow runs expose `Show Run Steps`, `Reveal Failed Steps`, `Open Timeline`, and cancellable `Cancel Run`;
  - `workflow-run-timeline:<run-id>` browses events without materializing all events by default;
  - run-step/event payloads are inspected through full node views using multiline widgets;
  - no `Show Details` / `Hide Details` toggle is part of this slice.

- [ ] **Step 3: Update `docs/dev/notes/graph.md`.**
- [ ] **Step 10: Update `docs/dev/notes/graph.md`.**

  Add a subsection named `Preview vs UX node vs full view` with these rules:
  - previews expose compact state, high-frequency local actions, and short search/list controls;
  - UX-purpose graph nodes expose one focused operation/detail surface and own no domain records;
  - full node views/panels handle dense content, long payloads, and editor-style interactions;
  - graph-selection actions must read active `GraphMap` selection, validate accepted node types, and fail loudly on invalid selection;
  - destructive actions must be explicit graph actions rather than confirmation-dialog flows.

- [ ] **Step 4: Update `docs/dev/graph-maps.md`.**
- [ ] **Step 11: Update `docs/dev/graph-maps.md`.**

  Add workflow materialization guidance:
  - workflow-derived display edges can be added by explicit actions and marked with `from-workflow-edge` so capture skips them;
  - UX-purpose nodes are graph-map topology only and do not own records;
  - hidden relationship expansion and graph trigger APIs are forbidden.

- [ ] **Step 5: Validate documentation searches.**
- [ ] **Step 12: Validate documentation searches.**

  Run:

  ```bash
  rg "Preview vs UX node vs full view" docs/dev/notes/graph.md
  rg "workflow-step-explorer" docs/dev/features/workflow-graph-ux.md docs/dev/graph-maps.md
  rg "workflow-run-timeline" docs/dev/features/workflow-graph-ux.md docs/dev/graph-maps.md
  rg "Show Details" docs/dev/features/workflow-graph-ux.md
  rg "Hide Details" docs/dev/features/workflow-graph-ux.md
  rg "Create a help desk workflow from scratch" docs/user/workflows/index.md docs/user/workflows/create-help-desk-workflow.md
  rg "Find and fix the workflow step that caused a failed run" docs/user/workflows/index.md docs/user/workflows/debug-failed-workflow-run.md
  rg "Use selected graph nodes as workflow run context" docs/user/workflows/index.md docs/user/workflows/use-graph-selection-as-run-context.md
  rg "Inspect a run timeline and payloads without flooding the graph" docs/user/workflows/index.md docs/user/workflows/inspect-run-timeline-and-payloads.md
  rg "Edit workflow topology with graph step nodes" docs/user/workflows/index.md docs/user/workflows/edit-workflow-topology.md
  rg "Monitor and cancel a running workflow" docs/user/workflows/index.md docs/user/workflows/monitor-and-cancel-running-workflow.md
  ```

  Expected: the first three searches find doctrine; the last two find only text explaining that the generic toggle is removed.

- [ ] **Step 13: Commit.**

  ```bash
  git add docs/user/index.md docs/user/workflows/index.md docs/user/workflows/create-help-desk-workflow.md docs/user/workflows/debug-failed-workflow-run.md docs/user/workflows/use-graph-selection-as-run-context.md docs/user/workflows/inspect-run-timeline-and-payloads.md docs/user/workflows/monitor-and-cancel-running-workflow.md docs/user/workflows/edit-workflow-topology.md docs/dev/features/workflow-graph-ux.md docs/dev/notes/graph.md docs/dev/graph-maps.md
  git commit -m "docs(graph): define workflow graph UX doctrine"
  ```

---

### Task 2: Workflow Definition Step Exploration APIs and Step Explorer Node

**Files:**
- Modify: `assets/lua/graph/nodes/workflow-definition.fnl`
- Create: `assets/lua/graph/nodes/workflow-step-explorer.fnl`
- Create: `assets/lua/graph/view/previews/workflow-step-explorer.fnl`
- Modify: `assets/lua/graph/key-loaders.fnl`
- Test: `assets/lua/tests/test-workflow-graph.fnl`
- Test: `assets/lua/tests/test-workflow-graph-action-boundaries.fnl`

**Interfaces:**
- Consumes:
  - `GraphMap:load-by-key(key: string) -> node|nil`
  - `GraphMap:add-edge(edge, opts?: table) -> edge`
  - `Graph:has-key-loader-for-key(key: string) -> boolean`
  - `WorkflowStore:get-definition(definition-id: string) -> table|nil`
- Produces:
  - `WorkflowDefinitionNode:step-items() -> table`
  - `WorkflowDefinitionNode:load-step-from-graph(step-or-id: table|string) -> table`
  - `WorkflowDefinitionNode:reveal-all-steps-from-graph() -> table`
  - `WorkflowDefinitionNode:open-step-explorer-from-graph() -> table`
  - `WorkflowStepExplorerNode:step-items() -> table`
  - `WorkflowStepExplorerNode:load-step-from-graph(step-or-id: table|string) -> table`
  - `WorkflowStepExplorerNode:reveal-all-steps-from-graph() -> table`
  - key loader for `workflow-step-explorer:<definition-id>`.

- [ ] **Step 1: Write failing workflow graph tests for definition step exploration.**

  Add tests to `assets/lua/tests/test-workflow-graph.fnl` named:
  - `workflow-definition-step-items-filter-to-definition`
  - `workflow-definition-load-step-materializes-one-selected-step`
  - `workflow-definition-reveal-all-steps-materializes-steps-and-derived-workflow-edges`
  - `workflow-definition-open-step-explorer-materializes-ux-node`
  - `workflow-step-explorer-preview-search-selects-one-step`

  Test behavior:

  ```fennel
  ;; expected interface under test
  (local items (definition-node:step-items))
  (definition-node:load-step-from-graph selected-step)
  (definition-node:reveal-all-steps-from-graph)
  (definition-node:open-step-explorer-from-graph)
  ```

  Assert that step lists are filtered by definition id, selecting one step does not load siblings, reveal-all loads all steps and derived workflow edges, derived workflow edges are skipped by graph-map capture, and the explorer preview requires direct build context.

- [ ] **Step 2: Write failing action-boundary tests.**

  Add tests to `assets/lua/tests/test-workflow-graph-action-boundaries.fnl` named:
  - `definition-reveal-all-steps-without-step-loader-does-not-materialize`
  - `definition-open-step-explorer-without-loader-does-not-materialize`

  Expected assertions:
  - failure message contains `requires graph loader`;
  - graph node and edge counts do not increase beyond the already-loaded definition node;
  - no `workflow-step:` or `workflow-step-explorer:` keys remain in the map.

- [ ] **Step 3: Run the failing focused tests.**

  Run:

  ```bash
  make build
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph-action-boundaries:main
  ```

  Expected: new tests fail because methods/loaders do not exist.

- [ ] **Step 4: Add step exploration methods to `workflow-definition.fnl`.**

  Implement the produced methods with this shape:

  ```fennel
  (fn self.step-items []
    ;; return search rows for steps belonging to self.workflow-definition-id
    )

  (fn self.load-step-from-graph [step-or-id]
    ;; validate step ownership, load workflow-step:<definition-id>:<step-id>, add visible edge
    )

  (fn self.reveal-all-steps-from-graph []
    ;; preflight workflow-step loader, load all steps, add definition->step and derived workflow edges
    )

  (fn self.open-step-explorer-from-graph []
    ;; preflight workflow-step-explorer loader, load workflow-step-explorer:<definition-id>, add visible edge
    )
  ```

  `reveal-all-steps-from-graph` must pass `{:from-workflow-edge workflow-edge.id}` when adding canonical workflow display edges so graph-map capture skips those derived edges.

- [ ] **Step 5: Create `workflow-step-explorer.fnl`.**

  Implement a `GraphNode` adapter with:
  - key `workflow-step-explorer:<definition-id>`;
  - label `Step explorer <definition-name-or-id>`;
  - preview module `graph/view/previews/workflow-step-explorer`;
  - no workflow record ownership;
  - methods `step-items`, `load-step-from-graph`, and `reveal-all-steps-from-graph`.

- [ ] **Step 6: Create the step explorer preview.**

  The build closure must require direct `ctx`. It must own/drop:
  - `title`
  - `step-count-text`
  - `step-search`
  - `reveal-all-steps-button`
  - `flex`

  It must disconnect the `SearchView.submitted` listener during `drop`.

- [ ] **Step 7: Register the new key loader.**

  Modify `assets/lua/graph/key-loaders.fnl` to require `graph/nodes/workflow-step-explorer` and register it whenever `workflow-store` is present.

- [ ] **Step 8: Validate in Fennel order.**

  Run:

  ```bash
  make build
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph-action-boundaries:main
  ```

- [ ] **Step 9: Commit.**

  ```bash
  git add assets/lua/graph/nodes/workflow-definition.fnl assets/lua/graph/nodes/workflow-step-explorer.fnl assets/lua/graph/view/previews/workflow-step-explorer.fnl assets/lua/graph/key-loaders.fnl assets/lua/tests/test-workflow-graph.fnl assets/lua/tests/test-workflow-graph-action-boundaries.fnl
  git commit -m "feat(graph): add workflow step explorer"
  ```

---

### Task 3: Richer Workflow Definition Preview

**Files:**
- Modify: `assets/lua/graph/view/previews/workflow-definition.fnl`
- Test: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes:
  - `WorkflowDefinitionNode:step-items()`
  - `WorkflowDefinitionNode:load-step-from-graph(step-or-id)`
  - `WorkflowDefinitionNode:reveal-all-steps-from-graph()`
  - `WorkflowDefinitionNode:open-step-explorer-from-graph()`
  - existing `WorkflowDefinitionNode:run-items()`
  - existing `WorkflowDefinitionNode:load-run-from-graph(run-or-id)`
  - existing `WorkflowDefinitionNode:start-workflow-from-graph(input, context-opts)`
  - existing `WorkflowDefinitionNode:create-step-from-graph(opts)`
- Produces `WorkflowDefinitionNodePreview` fields:
  - `title`
  - `overview-text`
  - `step-count-text`
  - `run-count-text`
  - `step-search`
  - `run-search`
  - `reveal-all-steps-button`
  - `open-step-explorer-button`
  - `start-button`
  - `new-step-button`
  - `flex`

- [ ] **Step 1: Update failing preview tests.**

  Add or update tests in `assets/lua/tests/test-workflow-graph.fnl` named:
  - `workflow-definition-preview-builds-structured-inspector`
  - `workflow-definition-preview-step-search-reveals-one-step`
  - `workflow-definition-preview-reveal-all-and-step-explorer-buttons`
  - `workflow-definition-preview-drops-owned-children-and-search-listeners`

  Expected assertions:
  - direct build context is required;
  - `overview-text` contains `Steps: 2`, `Runs: 1`, and latest run status;
  - `step-search.submitted:emit` loads only the selected step;
  - `run-search.submitted:emit` still loads only runs for this definition;
  - reveal-all button loads all steps;
  - open-step-explorer button loads `workflow-step-explorer:<definition-id>`;
  - `drop` disconnects both search listeners and drops all owned widgets.

- [ ] **Step 2: Run focused test to confirm failure.**

  Run:

  ```bash
  make build
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  ```

  Expected: new preview field/action assertions fail.

- [ ] **Step 3: Implement compact structured preview sections.**

  Keep one compact `Flex` preview in this slice. Use sections for overview, steps, runs, and actions rather than making the domain node a large tabbed mini-app.

- [ ] **Step 4: Add preview controls.**

  Controls must include:
  - title from node label;
  - overview text with definition id/name, step count, run count, latest run state;
  - step search placeholder `Search workflow steps`;
  - run search placeholder `Search workflow runs`;
  - buttons `Reveal All Steps`, `Open Step Explorer`, `Start`, and `New Step`.

- [ ] **Step 5: Wire actions with loud assertions.**

  Missing target methods must assert with these messages:
  - `Workflow definition preview requires step-items`
  - `Workflow definition preview requires load-step-from-graph`
  - `Workflow definition preview requires reveal-all-steps-from-graph`
  - `Workflow definition preview requires open-step-explorer-from-graph`

- [ ] **Step 6: Implement lifecycle cleanup.**

  Store separate listener handles for step search and run search. `drop` must disconnect both listeners with the force flag, set listener fields to `nil`, drop every owned child widget, and drop the flex.

- [ ] **Step 7: Validate in Fennel order.**

  Run:

  ```bash
  make build
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  ```

- [ ] **Step 8: Commit.**

  ```bash
  git add assets/lua/graph/view/previews/workflow-definition.fnl assets/lua/tests/test-workflow-graph.fnl
  git commit -m "feat(graph): enrich workflow definition preview"
  ```

---

### Task 4: Granular Workflow Run Inspection and Timeline UX Node

**Files:**
- Modify: `assets/lua/graph/nodes/workflow-run.fnl`
- Create: `assets/lua/graph/nodes/workflow-run-timeline.fnl`
- Create: `assets/lua/graph/view/previews/workflow-run-timeline.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-run.fnl`
- Modify: `assets/lua/graph/key-loaders.fnl`
- Test: `assets/lua/tests/test-workflow-graph.fnl`
- Test: `assets/lua/tests/test-workflow-graph-action-boundaries.fnl`

**Interfaces:**
- Consumes:
  - `WorkflowStore:get-run(run-id)`
  - `WorkflowStore:list-run-steps(run-id)`
  - `WorkflowStore:list-events(run-id)`
  - `GraphMap:load-by-key(key)`
  - `GraphMap:add-edge(edge, opts?)`
- Produces:
  - `WorkflowRunNode:load-run-steps-from-graph(opts?: table) -> table`
  - `WorkflowRunNode:reveal-failed-run-steps-from-graph() -> table`
  - `WorkflowRunNode:open-timeline-from-graph() -> table`
  - `WorkflowRunTimelineNode:event-items() -> table`
  - `WorkflowRunTimelineNode:load-event-from-graph(event-or-id: table|string) -> table`
  - key loader for `workflow-run-timeline:<run-id>`.

- [ ] **Step 1: Rewrite failing run behavior tests.**

  Replace old details-toggle tests in `assets/lua/tests/test-workflow-graph.fnl` with:
  - `workflow-run-node-exposes-granular-inspection-actions`
  - `workflow-run-show-run-steps-materializes-all-run-steps-only`
  - `workflow-run-reveal-failed-steps-materializes-failed-subset`
  - `workflow-run-open-timeline-materializes-timeline-node-only`
  - `workflow-run-timeline-preview-search-materializes-one-event`
  - `workflow-run-preview-exposes-granular-buttons-without-details-toggle`

  Expected assertions:
  - node actions include `Show Run Steps`, `Reveal Failed Steps`, and `Open Timeline`;
  - node actions do not include `Show Details` or `Hide Details`;
  - preview exposes `show-run-steps-button`, `reveal-failed-steps-button`, and `open-timeline-button`;
  - show run steps loads run-step nodes and run-to-step edges only;
  - reveal failed steps loads only run steps with failed status;
  - open timeline loads `workflow-run-timeline:<run-id>` and no `workflow-run-event:` nodes;
  - timeline preview search loads only the selected event.

- [ ] **Step 2: Add action-boundary tests.**

  Add tests to `assets/lua/tests/test-workflow-graph-action-boundaries.fnl` named:
  - `workflow-run-show-steps-without-run-step-loader-does-not-materialize`
  - `workflow-run-open-timeline-without-loader-does-not-materialize`

  Expected assertions:
  - failure message contains `requires graph loader`;
  - no partial `workflow-run-step:` or `workflow-run-timeline:` nodes remain;
  - edge count does not increase.

- [ ] **Step 3: Run focused tests to confirm failure.**

  Run:

  ```bash
  make build
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph-action-boundaries:main
  ```

- [ ] **Step 4: Refactor `workflow-run.fnl` to granular actions.**

  Remove `details-expanded?` toggle semantics and implement methods with this shape:

  ```fennel
  (fn self.load-run-steps-from-graph [opts]
    ;; preflight workflow-run-step loader, load all or failed-only run-step nodes, add run step edges
    )

  (fn self.reveal-failed-run-steps-from-graph []
    (self:load-run-steps-from-graph {:failed-only? true}))

  (fn self.open-timeline-from-graph []
    ;; preflight workflow-run-timeline loader, load one timeline node, add timeline edge
    )
  ```

- [ ] **Step 5: Create `workflow-run-timeline.fnl`.**

  Implement a UX-purpose node with:
  - key `workflow-run-timeline:<run-id>`;
  - label `Timeline <run-id>`;
  - preview module `graph/view/previews/workflow-run-timeline`;
  - `event-items` returning ordered events with labels containing event kind and step id when present;
  - `load-event-from-graph` loading `workflow-run-event:<run-id>:<event-id>` and adding visible edge label `event`.

- [ ] **Step 6: Create timeline preview.**

  The build closure must require direct `ctx`. It must own/drop:
  - `title`
  - `event-count-text`
  - `event-search`
  - `flex`

  It must disconnect the `SearchView.submitted` listener during `drop`.

- [ ] **Step 7: Update run preview.**

  Replace generic details controls with buttons:
  - `Show Run Steps`
  - `Reveal Failed Steps`
  - `Open Timeline`

  Expose fields:
  - `show-run-steps-button`
  - `reveal-failed-steps-button`
  - `open-timeline-button`

- [ ] **Step 8: Register timeline key loader.**

  Modify `assets/lua/graph/key-loaders.fnl` to require and register `workflow-run-timeline` whenever `workflow-store` is present.

- [ ] **Step 9: Validate in Fennel order.**

  Run:

  ```bash
  make build
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph-action-boundaries:main
  ```

- [ ] **Step 10: Commit.**

  ```bash
  git add assets/lua/graph/nodes/workflow-run.fnl assets/lua/graph/nodes/workflow-run-timeline.fnl assets/lua/graph/view/previews/workflow-run-timeline.fnl assets/lua/graph/view/previews/workflow-run.fnl assets/lua/graph/key-loaders.fnl assets/lua/tests/test-workflow-graph.fnl assets/lua/tests/test-workflow-graph-action-boundaries.fnl
  git commit -m "feat(graph): add granular workflow run inspection"
  ```

---

### Task 5: Run-Step and Event Payload Panels

**Files:**
- Modify: `assets/lua/graph/nodes/workflow-run-step.fnl`
- Modify: `assets/lua/graph/nodes/workflow-run-event.fnl`
- Create: `assets/lua/graph/view/views/workflow-run-step.fnl`
- Create: `assets/lua/graph/view/views/workflow-run-event.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-run-step.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-run-event.fnl`
- Test: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes:
  - generic graph node open/view behavior for nodes with `:view`;
  - `Input` widget with `:multiline? true` and `:focusable? false`;
  - `assets/lua/json-utils.fnl` for stable payload rendering when a payload is a table.
- Produces:
  - `WorkflowRunStepNode.view = graph/view/views/workflow-run-step`
  - `WorkflowRunEventNode.view = graph/view/views/workflow-run-event`
  - `WorkflowRunStepNode:get-run-step() -> table`
  - `WorkflowRunEventNode:get-event() -> table`
  - run-step view fields: `title`, `payload-input`, `scroll-view`, `flex`
  - event view fields: `title`, `payload-input`, `scroll-view`, `flex`

- [ ] **Step 1: Add failing tests for payload views.**

  Add tests to `assets/lua/tests/test-workflow-graph.fnl` named:
  - `workflow-run-step-node-has-payload-view`
  - `workflow-run-event-node-has-payload-view`
  - `workflow-run-step-view-renders-payload-in-multiline-input`
  - `workflow-run-event-view-renders-payload-in-multiline-input`

  Expected assertions:
  - run-step and event nodes have `node.view`;
  - view builder requires direct build context;
  - built view exposes `payload-input`;
  - `payload-input.multiline?` is true;
  - payload text contains complete output/error/payload content;
  - preview summary remains compact and includes `Open node for payload panel` when payload details exist.

- [ ] **Step 2: Run focused test to confirm failure.**

  Run:

  ```bash
  make build
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  ```

- [ ] **Step 3: Attach full views to run-step and event nodes.**

  In node constructors, require the matching view module and set `:view` in the final `GraphNode` literal.

- [ ] **Step 4: Add retrieval methods.**

  Implement:

  ```fennel
  (fn self.get-run-step []
    ;; fetch run step by self.workflow-run-id and self.workflow-step-id; assert if missing
    )

  (fn self.get-event []
    ;; fetch event by self.workflow-run-id and self.event-id; assert if missing
    )
  ```

- [ ] **Step 5: Create run-step full view.**

  Build a direct-context-only view with:
  - `Text` title;
  - `Input` using `{:multiline? true :focusable? false :min-lines 6 :max-lines 16}`;
  - `ScrollView`;
  - owned child drop behavior.

  Payload text must include labels and serialized values for status, attempt, output, wait, and error.

- [ ] **Step 6: Create event full view.**

  Build a direct-context-only view with:
  - `Text` title;
  - multiline, non-focusable `Input`;
  - `ScrollView`;
  - owned child drop behavior.

  Payload text must include event id, kind, step id when present, created-at when present, and all non-metadata payload fields.

- [ ] **Step 7: Update compact previews.**

  Keep previews compact. Add a short `Text` child saying `Open node for payload panel` when payload/error/output/event details are present. Do not place long JSON into single-line labels.

- [ ] **Step 8: Validate in Fennel order.**

  Run:

  ```bash
  make build
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  ```

- [ ] **Step 9: Commit.**

  ```bash
  git add assets/lua/graph/nodes/workflow-run-step.fnl assets/lua/graph/nodes/workflow-run-event.fnl assets/lua/graph/view/views/workflow-run-step.fnl assets/lua/graph/view/views/workflow-run-event.fnl assets/lua/graph/view/previews/workflow-run-step.fnl assets/lua/graph/view/previews/workflow-run-event.fnl assets/lua/tests/test-workflow-graph.fnl
  git commit -m "feat(graph): add workflow run payload panels"
  ```

---

### Task 6: Lifecycle, Static No-Leftover Checks, and First-Slice Regression Pass

**Files:**
- Modify: `assets/lua/tests/test-workflow-graph.fnl`
- Modify: `assets/lua/tests/test-workflow-graph-action-boundaries.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-definition.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-step-explorer.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-run.fnl`
- Modify: `assets/lua/graph/view/previews/workflow-run-timeline.fnl`
- Modify: `assets/lua/graph/view/views/workflow-run-step.fnl`
- Modify: `assets/lua/graph/view/views/workflow-run-event.fnl`

**Interfaces:**
- Consumes: all interfaces produced by Tasks 2-5.
- Produces:
  - updated static no-leftover file list including new workflow UX nodes;
  - regression coverage proving no generic details dump, no hidden graph expansion, and correct preview/view lifecycle cleanup.

- [ ] **Step 1: Extend static no-leftover coverage.**

  Add these files to the existing static discovery file list in `test-workflow-graph.fnl`:
  - `assets/lua/graph/nodes/workflow-step-explorer.fnl`
  - `assets/lua/graph/nodes/workflow-run-timeline.fnl`

- [ ] **Step 2: Add regression test for no generic details UX.**

  Assert:
  - run node actions do not include `Show Details` or `Hide Details`;
  - run preview has no `show-details-button` or `hide-details-button`;
  - `assets/lua/graph/nodes/workflow-run.fnl` source does not contain `details-expanded?`.

- [ ] **Step 3: Add lifecycle assertions for all new previews/views.**

  For each new widget builder, assert:
  - missing direct context fails with `requires a build context`;
  - owned child drops are called;
  - search listeners are disconnected on drop for step explorer and run timeline.

- [ ] **Step 4: Add action-boundary regression assertions.**

  Confirm all graph-materializing methods fail loudly without a mounted `GraphMap`:

  ```fennel
  (definition-node:load-step-from-graph step-id)
  (definition-node:reveal-all-steps-from-graph)
  (definition-node:open-step-explorer-from-graph)
  (run-node:load-run-steps-from-graph)
  (run-node:open-timeline-from-graph)
  (timeline-node:load-event-from-graph event-id)
  ```

- [ ] **Step 5: Run focused tests to expose missed lifecycle issues.**

  Run:

  ```bash
  make build
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph-action-boundaries:main
  ```

- [ ] **Step 6: Repair lifecycle/action-boundary defects found by the new tests.**

  Repair only the affected files listed in this task. Keep the removed details toggle removed; do not add aliases for old details APIs.

- [ ] **Step 7: Validate in Fennel order plus relevant graph view coverage.**

  Run:

  ```bash
  make build
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph-action-boundaries:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  ```

- [ ] **Step 8: Commit.**

  ```bash
  git add assets/lua/tests/test-workflow-graph.fnl assets/lua/tests/test-workflow-graph-action-boundaries.fnl assets/lua/graph/view/previews/workflow-definition.fnl assets/lua/graph/view/previews/workflow-step-explorer.fnl assets/lua/graph/view/previews/workflow-run.fnl assets/lua/graph/view/previews/workflow-run-timeline.fnl assets/lua/graph/view/views/workflow-run-step.fnl assets/lua/graph/view/views/workflow-run-event.fnl
  git commit -m "test(graph): cover workflow graph UX lifecycle"
  ```

---

## Observable Acceptance Criteria

- Workflow definition nodes expose step discovery and materialization, not only runs.
- Definition preview shows overview, step search, run search, reveal all steps, open step explorer, start, and new step controls.
- Selecting one step materializes only that step.
- Reveal all steps materializes all steps and workflow-derived display edges without persisting derived edges as explicit map topology.
- `workflow-step-explorer:<definition-id>` opens as a UX-purpose graph node and owns no workflow records.
- Workflow run nodes expose granular actions instead of `Show Details` / `Hide Details`.
- Show run steps and reveal failed steps materialize the expected subsets.
- `workflow-run-timeline:<run-id>` opens without materializing every event by default.
- Selecting one timeline event materializes only that event.
- Run-step and event nodes have full node views using multiline inputs for payloads/logs/errors/output.
- New previews/views require direct build context and drop owned children/listeners.
- Static checks confirm no `get-edges` relationship hook or graph trigger materialization API returns.
- Docs under `docs/dev/**` describe the doctrine and workflow-specific behavior.
- User docs under `docs/user/workflows/**` provide goal-oriented pages that collectively demonstrate every first-slice workflow feature.

## Final Validation Scope

After all tasks pass review, final whole-branch validation must include:

```bash
make fennel-check
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph-action-boundaries:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
```

Run `make build` first with timeout `14400000` when `./build/space` is missing or stale.

The finishing branch workflow must evaluate against current `origin/main`, run required validation on a clean/current tree, push the branch, create a PR targeting `main`, enable auto-merge or merge queue when allowed, and poll until the PR is merged.

## Out of Scope

- Advanced run browser filters beyond first-slice timeline/event search.
- Full run launcher UX node beyond existing quick start and existing graph selection context capture.
- Confirmation-dialog framework.
- Automatic relationship expansion, hidden `get-edges`, or graph trigger APIs.
- Migration of workflow/domain ownership into graph map topology.
- Global redesign of non-workflow graph node types.
- Broad refactor of graph map persistence or graph view internals.

## Risks and Task Ordering Caveats

- Tasks 2 and 4 must land before previews that consume their new methods.
- Removing `Show Details` / `Hide Details` is intentional; preserving compatibility shims would keep the bad UX alive.
- Derived workflow edges must be marked with `from-workflow-edge` so `GraphMap:capture-state` skips them.
- Timeline and step explorer nodes are UX-purpose graph nodes; they must not create or persist workflow records.
- If Fennel parse errors appear, inspect and repair the nearest enclosing form before broader restructuring.
