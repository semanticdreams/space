# Workflow Graph UX Design

## Context

The previous explicit-discovery cleanup removed hidden graph relationship hooks
and made workflow browsing hierarchical: `Workflows` opens selected workflow
definitions, and each workflow definition opens selected runs. That solved the
old implicit fan-out problem, but the resulting workflow UX is still too thin.

The graph is intended to be the primary power surface: visual editor,
inspector, and control panel. A graph node should expose what a user can do with
the represented thing in a friendly, uniform way. At the same time, each node
should remain focused on one logical thing. When a node would become a cramped
multi-purpose mini-application, it should expose separate graph-addressable UX
nodes or full node views instead.

The current gaps are visible in normal workflow use:

- A workflow definition node exposes `Start` and `New Step`, but does not give a
  useful way to explore, reveal, or edit the workflow's step topology.
- A workflow run node exposes `Show Details` / `Hide Details`; `Show Details`
  dumps multiple run-step and run-event nodes at once, and `Hide Details` does
  not remove the materialized details.
- Run event payloads, step code, errors, inputs, and outputs need real widgets
  such as multiline inputs or node views, not raw labels or opaque graph dumps.
- There is no shared graph UX doctrine that explains when to enrich a preview,
  when to open a separate operation/detail node, and when to open a full panel.

## Goals

- Define systematic graph UX guidelines for Space graph exposure.
- Make workflow definition nodes useful for both authoring and inspection:
  overview, steps, runs, and actions.
- Make workflow step nodes useful for editing step code and topology.
- Replace opaque run `Show Details` dumping with deliberate run inspection
  flows: timeline, run steps, events, failures, payloads, and cancellation where
  applicable.
- Use richer preview/view widgets where appropriate: `SearchView`, `TabView`,
  `ListView`, buttons, forms, and multiline input/editor widgets.
- Allow UX-purpose graph nodes for focused operations or detail surfaces when a
  domain node would become too complex.
- Support graph-as-control-panel interactions, including actions that operate on
  the active graph selection.
- Preserve graph doctrine: domain stores own records; graph nodes and UX nodes
  adapt/expose them; graph maps persist only explicitly materialized visible
  topology and panel state.
- Keep materialization explicit and user-directed; do not reintroduce hidden
  relationship hooks or graph trigger APIs.

## Non-Goals

- No return to automatic relationship expansion or `get-edges`-style discovery.
- No attempt to build every possible workflow feature in one pass. This design
  establishes the pattern and covers the core workflow authoring/run inspection
  flows first.
- No confirmation-dialog framework. Direct graph use is an all-powerful surface;
  destructive actions should be explicit graph actions, not modal prompts.
- No migration of workflow/domain ownership into graph map topology.
- No global redesign of all graph node types. The general guidelines should be
  documented, but implementation should focus on workflow graph UX.

## Approaches Considered

### A. Richer previews only

Add tabs, lists, and more buttons directly to existing workflow definition and
run previews. This is fast and keeps interactions local, but it risks turning
domain nodes into cramped mini-apps. It also does not establish a clean pattern
for operations that act on selected graph nodes or large payload inspection.

### B. Separate operation/detail nodes for everything

Keep previews tiny and move each operation to a dedicated graph node, such as a
workflow step explorer, run launcher, timeline, event filter, or selected-node
operation node. This keeps nodes focused and graph-native, but it can create too
many nodes for simple operations and may make common actions feel indirect.

### C. Three-tier graph UX model

Use focused domain nodes as anchors, richer previews for common local tasks,
explicit UX-purpose nodes for complex operations/detail flows, and full node
views/panels for dense editing or large payloads.

Chosen approach: **C**. It matches the graph's role as visual editor,
inspector, and control panel while keeping each node focused.

## General Graph UX Doctrine

### Node responsibility

Every graph node should answer these user questions:

- What is this thing?
- What is its current state?
- What can I inspect from here?
- What can I edit from here?
- What can I materialize into the graph from here?
- What graph selection or context, if any, can this node operate on?

A domain node should represent one logical domain thing. It may expose common
actions and short lists, but it should not become the only UI for every related
operation.

### Preview vs UX node vs full view

Use a **preview** for compact, high-frequency local actions:

- status summary;
- small action row;
- short searchable list;
- reveal one selected related node;
- open a dedicated operation/detail node;
- open a full view/panel.

Use a **UX-purpose graph node** when the interaction is focused but too complex
for the domain preview:

- step explorer;
- run browser;
- run launcher with graph-selection context;
- run timeline;
- event filter;
- selected-node operation surface;
- payload inspector launcher.

UX-purpose nodes own no workflow records. They are graph-addressable adapters
over the workflow store, code store, active graph map, and selected nodes.

Use a **full node view/panel** for dense content:

- source code editing;
- multiline logs/errors/output;
- JSON or Fennel payloads;
- input forms or schema-like structured data;
- long timelines or paginated event lists.

### Materialization semantics

Graph materialization remains explicit. A visible user operation creates graph
nodes/edges in the active graph map. No hidden relationship hook or automatic
fan-out may add topology.

Actions that materialize groups of nodes should expose exactly what they do:

- `Open Step Explorer` opens a focused UX node.
- `Reveal All Steps` materializes workflow-step nodes and canonical step edges.
- `Open Run Browser` opens a focused UX node for run history.
- `Reveal Failed Run Steps` materializes only failed run-step nodes.
- `Open Timeline` opens a timeline UX node or panel.

If an action offers an inverse such as hide/collapse, it must have real topology
semantics. Either it removes the nodes/edges that the action owns, or the action
should not exist. A button that only flips local state while leaving graph
topology unchanged is misleading.

### Graph-selection actions

Some controls may operate on currently selected graph nodes. Those actions must:

- read selection from the active `GraphMap` context;
- show what selection they will use;
- validate accepted node types;
- fail loudly or display an explicit graph-native error/status when selection is
  empty or invalid;
- materialize result nodes/edges that explain what happened.

Example: a run launcher can start a workflow using the currently selected graph
nodes as context. The created run should record the graph-map id and selected
node keys, then materialize the new run node connected to the workflow
definition.

### Destructive actions

Confirmation dialogs are not part of the desired graph UX. Destructive actions
should be explicit and graph-native:

- label them clearly (`Delete Workflow Step`, `Cancel Run`);
- scope them to the current node/selection;
- surface results through visible topology, status text, or domain events;
- fail loudly when required data or graph context is missing.

## Workflow User Flows

### 1. Discover and create workflows

The `Workflows` root remains the entry point.

- It shows a searchable list of workflow definitions.
- Selecting a definition materializes only that definition.
- `New Workflow` creates a definition, starter step, code entity, and visible
  graph topology after preflighting required graph dependencies.
- The preview should provide obvious entry points for workflow browsing but must
  not list or materialize all runs at the root.

### 2. Inspect a workflow definition

The workflow definition preview should become a structured inspector, likely
using tabs or clear sections:

- **Overview:** name/id/status metadata, step count, run count, latest run state.
- **Steps:** search/list workflow steps; reveal one step; reveal all steps; open
  a step explorer UX node.
- **Runs:** search/list runs for this definition; open one run; open a run
  browser UX node.
- **Actions:** start run, open run launcher, create step.

This preview may use `TabView` when space allows. If tabs make the card too
heavy, the preview can show compact sections and open dedicated UX nodes for
Steps/Runs/Launcher.

### 3. Edit workflow topology

Workflow topology is edited visually through step nodes and graph edges.

- A definition can `Reveal All Steps`, materializing workflow-step nodes and
  derived display edges for canonical workflow edges.
- Connecting compatible workflow-step nodes in the graph creates canonical
  workflow edges through the workflow store.
- Removing authored step edges from the graph removes the canonical workflow
  edge.
- Step nodes expose `Show Code` to materialize the linked code entity.
- Step nodes should show concise step metadata and provide entry points for code
  editing, step configuration, and run-history-for-this-step where available.

The graph map topology remains the user's visible working set. WorkflowStore
remains the canonical owner of workflow steps and edges.

### 4. Add and configure workflow steps

`New Step` remains available from a workflow definition, but the UX should make
the result immediately actionable.

- It creates the step and code entity only after required graph dependencies are
  available.
- It materializes the new workflow-step and code-entity nodes.
- It should connect the new step to the definition with visible context.
- It should make the next likely actions visible: edit code, connect step,
  configure step, or run workflow.

Step configuration that does not fit in the preview should open a step
configuration UX node or full panel.

### 5. Launch runs

Workflow definitions should support both quick and advanced run launch.

- **Quick Start:** starts a run with default context and materializes the run.
- **Run Launcher:** a UX-purpose node or full panel for selecting inputs,
  including active graph selection. It should show selected node keys/types and
  how they will be included in the run context.

Start actions must preflight graph materialization dependencies before durable
side effects or roll back cleanly on unexpected failure.

### 6. Browse workflow runs

Run browsing belongs under a workflow definition, not the root.

- The definition preview may show a compact run search.
- A run browser UX node can provide richer filters: status, date, text query,
  failed-only, latest, selected-node-related.
- Selecting a run materializes only that run node and a definition-to-run edge.

### 7. Inspect and manipulate a workflow run

The workflow run preview should stop using generic `Show Details` / `Hide
Details` dumping. It should expose deliberate actions:

- **Open Timeline:** open a timeline UX node or full panel with ordered events.
- **Show Run Steps:** materialize run-step nodes, optionally grouped or filtered.
- **Reveal Failed Steps:** materialize only failed run-step nodes.
- **Show Events:** open an event browser/filter rather than dumping every event.
- **Open Inputs/Outputs:** use multiline widgets or panels for payloads.
- **Cancel Run:** shown only when the run status is cancellable.

`Hide Details` should be removed unless materialization ownership is implemented
well enough to remove the exact nodes/edges created by a previous action.

### 8. Inspect run steps and events

Run-step and event nodes should be compact but useful.

Run-step preview:

- status, step label, timing/duration;
- linked workflow-step and code entry points;
- output/error summary;
- open payload/log panel;
- reveal related events.

Event preview:

- timestamp/kind/status;
- short summary;
- multiline payload/details panel for structured or long content;
- links to run and run-step where applicable.

Payloads must be rendered in proper widgets. Long strings, logs, JSON, Fennel
forms, inputs, outputs, and errors should use multiline input/editor-style
widgets or full node views, not single-line labels.

## Proposed First Implementation Slice

The first implementation should establish the pattern without trying to build
every advanced workflow feature:

1. Add graph UX doctrine docs and update workflow docs.
2. Upgrade workflow definition preview into a structured inspector with steps,
   runs, and actions sections or tabs.
3. Add explicit step exploration: reveal one step, reveal all steps, and keep
   `Show Code` / graph-authored step edges working.
4. Replace workflow run `Show Details`/`Hide Details` with granular actions:
   show run steps, reveal failed steps, open timeline/events browser, and open
   payload panels where available.
5. Add or stub focused UX-purpose nodes where needed to prevent previews from
   becoming too complex, prioritizing run browser/timeline if the preview would
   otherwise dump too many rows.
6. Add tests for the concrete user flows and for the absence of hidden
   relationship expansion.

## Error Handling

- Missing workflow store, code store, graph map, selected node data, or key
  loaders should fail loudly at action boundaries.
- Domain mutations that require graph materialization must preflight required
  graph dependencies before durable side effects, or roll back all domain and
  partial graph-map changes on failure.
- Selection-aware operations must reject invalid selections with explicit status
  or errors rather than silently ignoring them.
- Long or malformed payloads should remain inspectable in multiline widgets;
  rendering should not truncate the underlying payload data.

## Testing Strategy

- Focused workflow graph tests for definition step exploration:
  - definition preview lists/searches steps for that definition;
  - reveal one step materializes only that step;
  - reveal all steps materializes workflow steps and derived workflow edges;
  - cross-definition steps do not appear.
- Focused workflow graph tests for step authoring:
  - `New Step` still materializes step/code nodes;
  - `Show Code` opens the linked code entity;
  - graph step-edge authoring still updates canonical workflow edges.
- Focused run inspection tests:
  - run preview exposes granular actions instead of generic dump/hide details;
  - show run steps and reveal failed steps materialize the expected subset;
  - timeline/event browser opens without materializing every event by default;
  - payloads use multiline/input-style widgets or full views.
- Widget lifecycle tests for richer previews/UX nodes:
  - direct build context is required;
  - direct child widgets are owned and dropped;
  - tab/search/list widgets do not leak signals.
- Static no-leftover checks:
  - no graph `get-edges` relationship hook is reintroduced;
  - no graph trigger materialization API is reintroduced.

Validation should follow Space Fennel order: compile check first, constraints
second, focused Fennel tests third, and broader graph/workflow validation when
review or changed risk surface requires it.

## Acceptance Criteria

- Workflow definition nodes let users discover and materialize workflow steps,
  not only runs.
- Users can visually inspect and edit workflow topology through step nodes and
  graph edges.
- Workflow run nodes provide granular inspection actions instead of a generic
  `Show Details` dump.
- `Hide Details` is removed or replaced with a real topology cleanup action.
- Long payloads/logs/errors are displayed in multiline/panel widgets, not raw
  single-line labels.
- UX-purpose operation/detail nodes are used when a domain node would otherwise
  become too complex.
- Selection-aware graph actions have a documented and tested pattern.
- No hidden relationship expansion or graph trigger API returns.
- Docs define general graph UX guidelines and workflow-specific flows.
