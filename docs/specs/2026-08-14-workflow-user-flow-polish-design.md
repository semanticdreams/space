# Workflow User Flow Polish Design

## Purpose

Graph-authored workflows now exist as durable app/user-scoped domain objects, but the first user path is still too hidden. Users should be able to start from the graph `start` node, discover Workflows, create a runnable workflow, edit its code-backed step, add more steps, connect them, run the workflow, and inspect run details without knowing raw graph keys or writing store snippets.

This polish intentionally stays within the code-entity-first v1 model. It improves discoverability and authoring ergonomics without adding primitive workflow executors, sandboxing, edge-kind editors, port handles, or a separate visual programming system.

## Current Context

- `start` targets are hard-coded in `assets/lua/graph/nodes/start.fnl` and currently omit Workflows.
- The `workflows` graph key loads a root/list node backed by `app.workflow-store`, but the node has no user-facing create action.
- Workflow definitions can already start runs through node action/preview.
- Workflow steps already reference code entities and graph step connections create canonical workflow store edges.
- Code entities already have graph-visible editing and execution UI.
- Workflow docs describe architecture and keys, but not the user flow.

## Design Direction

Implement a usable v1 graph workflow path:

1. The Start node includes a `Workflows` target whenever `app.workflow-store` is available.
2. The Workflows root exposes `New Workflow`.
3. `New Workflow` creates:
   - a durable workflow definition;
   - a starter workflow step;
   - a linked Fennel code entity containing a valid workflow step template.
4. Workflow definition nodes expose `New Step` to add additional template-backed workflow steps.
5. Workflow step nodes expose `Show Code`, loading the linked `code-entity:<id>` node into the current graph context.
6. Run-step and run-event nodes expose preview summaries so users can inspect what happened after toggling run details.
7. `docs/dev/features/workflows.md` documents the complete user flow.

## Architecture and Ownership

The existing ownership boundaries remain unchanged:

- `WorkflowStore` owns workflow definitions, steps, edges, runs, run steps, and events.
- `CodeEntityStore` owns Fennel source bodies.
- Graph nodes are adapters that call explicit workflow/code store APIs.
- Graph maps provide interaction context and visible nodes/edges; they do not own workflow data.

Creating a workflow or step from a graph action is a domain mutation through the owning stores. The action may also load the newly created graph-visible nodes into the current graph map for immediate usability.

## Template Behavior

Add a small workflow template helper module. The starter Fennel code entity should evaluate to a factory returning an object with a required `:run` method:

```fennel
(fn [opts]
  {:run
   (fn [self ctx input state]
     (ctx:succeed {:message "workflow step completed"
                   :input input}))})
```

This is not a primitive executor. It is ordinary user-editable Fennel code stored as a code entity.

If compound creation fails after creating a code entity but before adding the workflow step, the just-created code entity should be deleted to avoid orphaned starter code.

## User Flow

The documented and supported user path should be:

1. Open Graph.
2. From `start`, search/select `Workflows`.
3. On the Workflows node, invoke `New Workflow`.
4. Open the generated workflow definition and starter step.
5. Use `Show Code` on the step to open the linked code entity.
6. Edit the Fennel code entity if desired.
7. Use `New Step` on the definition for additional steps.
8. Connect workflow step nodes; those connections create canonical workflow edges.
9. Click `Start` / `Start Run` on the workflow definition.
10. Open the run node and use the granular run-inspection actions from the
    2026-08-16 workflow graph UX design: `Open Timeline`, `Show Run Steps`,
    `Reveal Failed Steps`, and run-step/event payload panels. The old generic
    `Show Details` / `Hide Details` toggle flow is superseded and must not be
    reintroduced except as explicitly deprecated wording.

## UI Details

- `Workflows` should appear in Start search only when workflow runtime is available.
- `New Workflow`, `New Step`, and `Show Code` should be exposed as node actions and, where useful, preview buttons.
- Preview widgets must require direct build context and own/drop direct child widgets.
- Run detail previews should summarize status, attempts, output, waits, errors, event kind, step id, and event payload compactly.

## Error Handling

- Missing workflow store, runner, or code store should fail loudly at action/mutation boundaries.
- Workflow root/definition actions should assert required stores rather than silently falling back to missing runtime.
- Template code entity creation should roll back if adding the workflow step fails.
- Key loaders should continue returning nil for missing domain records.

## Testing

Focused tests should cover:

- Start node includes Workflows when `app.workflow-store` exists.
- `New Workflow` creates a durable definition, starter step, and linked code entity without embedding source in the workflow step.
- New workflow creation loads definition, step, and code entity nodes into the active graph map.
- Definition `New Step` creates and loads a template-backed step/code entity.
- Step `Show Code` loads the linked code entity node.
- Generated starter workflow can run successfully through the existing workflow runner.
- Run-step and run-event previews expose useful summaries and obey widget lifecycle/context rules.
- Docs describe the end-to-end user flow.

Validation must follow Space Fennel order: compile check first, constraints second, focused workflow graph tests third. Because this touches Start, graph nodes, previews, and workflow UX, final validation should include the broader relevant suite.

## Out of Scope

- Primitive executors for agent/tool/condition/human-input nodes.
- Sandboxing workflow code.
- Edge-kind, condition, and port editing UI.
- Rich node port handles or edge endpoint anchoring.
- Naming dialogs, delete confirmations, template galleries, and human-input resume UI.
- Moving nodes between graph maps.
