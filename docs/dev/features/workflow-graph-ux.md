# Workflow Graph UX

## First-slice scope

The first workflow graph UX slice makes workflow nodes work as visual editor, inspector, and control panel surfaces while preserving graph doctrine. Workflow definitions, steps, runs, run steps, events, and code entities remain owned by their domain stores. Graph nodes and UX-purpose nodes adapt those records into the active graph map only when a user asks for them.

This slice covers creating workflows, discovering steps, editing step code, authoring step edges in the graph, starting runs, starting runs with active graph selection as context, browsing runs, inspecting timelines/events/payloads, revealing failed steps, and cancelling runs only when the run status supports cancellation.

## Definition preview

Workflow definitions expose compact local controls for common authoring and inspection work:

- step search;
- run search;
- quick start with **Start**;
- **New Step**;
- **Reveal All Steps**;
- **Open Step Explorer**.

The preview is an anchor, not a mini-application. It may show concise workflow state and short searchable lists, but dense editing and broad browsing move to code views or UX-purpose nodes.

## Step explorer UX node

`workflow-step-explorer:<definition-id>` owns no workflow data. It is a focused UX-purpose graph node that adapts `WorkflowStore` for one workflow definition and helps users search, reveal, and inspect steps when the definition preview is too small.

The explorer may materialize selected workflow-step nodes or all workflow-step nodes through explicit actions. WorkflowStore remains the owner of workflow steps and canonical workflow edges.

## Run inspection

Workflow runs expose deliberate inspection actions instead of a generic details dump:

- **Show Run Steps** materializes run-step nodes when seeing all steps is useful.
- **Reveal Failed Steps** materializes only failed run-step nodes for targeted debugging.
- **Open Timeline** opens `workflow-run-timeline:<run-id>` for ordered event browsing.
- **Cancel Run** is shown only when the current run status is cancellable.

`workflow-run-timeline:<run-id>` browses events without materializing all events by default. Users can search or select one event to materialize it when graph context is useful.

## Payload panels

Run-step and event payloads are inspected through full node views using multiline widgets. Inputs, outputs, logs, errors, JSON, Fennel forms, and long strings must not be squeezed into single-line preview labels.

Step code is edited through linked code entity views opened from workflow-step nodes. Payload panels and code views handle dense content while graph previews remain compact.

## Action-boundary rules

Workflow graph materialization is explicit and map-local. Actions that add nodes or edges must state what they materialize and must use the active `GraphMap`.

Selection-aware run actions read active `GraphMap` selection, validate accepted node types, and fail loudly or display explicit status for empty or invalid selections. When selection context is accepted, the created run records the graph-map id and selected node keys when available.

Domain mutations that require graph materialization must preflight graph dependencies before durable side effects or roll back domain and partial graph-map changes on failure. Destructive operations, such as **Cancel Run** or removing workflow step edges, are explicit graph actions rather than confirmation-dialog flows.

No **Show Details** / **Hide Details** toggle is part of this slice. Those generic controls are replaced by granular actions such as **Show Run Steps**, **Reveal Failed Steps**, **Open Timeline**, and payload panels.

## Out of scope

- Hidden relationship expansion, `get-edges`-style discovery, and graph trigger APIs.
- Moving workflow definitions, steps, runs, run steps, or events into graph-map persistence.
- Confirmation-dialog framework work.
- Materializing every run event or run step by default.
- Legacy aliases for removed generic details actions.
