# Workflows

Space workflows are durable, app/user-scoped automation records that can be authored and inspected through graph nodes. The workflow subsystem owns workflow definitions, topology, runs, run steps, and events; graph maps are interaction contexts over those records, not storage for them.

## Runtime and storage scope

App bootstrap creates:

- `app.workflow-store`
- `app.workflow-code-executor`
- `app.workflow-runner`

The default store is rooted at `{app.user-data-dir}/workflows/` and is independent of active worlds and graph maps. Definitions persist under `workflows/definitions/`; runs persist under `workflows/runs/`. Run context may record a world id, graph map id, or selected graph node keys for provenance, but those values do not determine storage ownership.

## Records and keys

Definitions use `wf-...` ids and contain metadata plus executable step records and canonical workflow edges. Steps use `step-...` ids and reference a code entity through `:code-entity-id`; workflow-specific config, schemas, retry settings, and timeouts live on the step. Edges use `edge-...` ids with `:source-step-id`, `:target-step-id`, and optional data/control routing metadata.

Runs use `wfr-...` ids and record definition id/version, status, input/output, context, current steps, nested run steps, and events. Run steps are addressed by run id plus step id. Events use `event-...` ids.

Graph-visible keys include `workflows`, `workflow-definition:<id>`, `workflow-step:<definition-id>:<step-id>`, `workflow-run:<run-id>`, `workflow-run-step:<run-id>:<step-id>`, and `workflow-run-event:<run-id>:<event-id>`.

## Executable step contract

Workflow execution is code-entity-first. Durable workflow steps reference code entities; they do not embed durable source bodies. The code executor evaluates the referenced Fennel code entity with full app/global access and expects a step object with a required `:run` method plus optional `:resume` and `:cancel` methods.

Every execution result must be an outcome table. Valid statuses are `:succeeded`, `:failed`, `:waiting`, `:retry`, `:skipped`, and `:cancelled`. `:succeeded` and `:skipped` outcomes may include `:next-step-ids` to select downstream control-flow targets; omitting it selects all normal downstream continuations. Invalid or unknown outcomes fail the step with structured error data.

## Graph doctrine

The graph exposes workflow records through key loaders and node adapters. Graph maps provide user-facing interaction context, visible nodes, and display edges. Workflow definitions remain the canonical owner of workflow topology, so authoring workflow connections mutates the workflow store rather than persisting those derived edges as graph-map topology.

Workflow discovery is explicit and hierarchical:

```text
Workflows root -> selected workflow definition -> selected workflow run -> run details
```

The `Workflows` root browse/search surface lists workflow definitions only. Runs are browsed from a selected workflow definition, and run steps/events are materialized from an explicit run detail control. This avoids root-level fan-out of all runs and keeps graph-map topology limited to records the user has chosen to reveal.

## Graph user flow

1. Open Graph.
2. From `start`, search/select `Workflows`.
3. Browse/search workflow definitions from the `Workflows` root, or invoke `New Workflow`.
4. Open a workflow definition to browse/search that definition's runs and to reveal its steps.
5. Use `Show Code` on a step to open the linked `code-entity:<id>` node.
6. Edit the Fennel code entity if desired.
7. Use `New Step` on the definition for additional steps.
8. Connect workflow step nodes; those connections create canonical workflow edges.
9. Click `Start` / `Start Run` on the workflow definition to create and reveal a run node in the active graph map.
10. Open the run node, use `Show Details`, and inspect the explicitly materialized run-step and event previews.

Workflow data remains in `WorkflowStore`: definitions, steps, edges, runs, run steps, and events are owned there. Fennel source bodies remain in `CodeEntityStore`. Graph nodes and actions adapt those stores into the current interaction context, and graph maps only provide visibility, selection, and interaction context; they do not own workflow data or code bodies.

## Agent sessions

Sidebar agent chats are workflow-backed sessions: one chat is one long-lived workflow run, and each user turn resumes a waiting agent workflow step. The workflow subsystem owns the run, steps, and events; `llm.agent.workflow-runner` adapts those records to the existing sidebar runner API.

Agent transcript/status/session state is projected from workflow events such as `:agent-session-created`, `:agent-status-changed`, and agent item events. Graph workflow nodes expose the same run and event records as the sidebar. See [Workflow-backed agent sessions](./workflow-backed-agent-sessions.md) for the event schema and migration command.

## V1 exclusions

Version 1 intentionally does not include generic primitive workflow executors for conditions, loops, joins, tool calls, arbitrary agent nodes, or general-purpose human input UI. Sidebar chats use the dedicated workflow-backed agent runner described above; the generic scheduler does not become a provider streaming runtime. V1 also does not sandbox workflow code or store workflow data in graph maps.

- Generic primitive executors for agent/tool/condition/human-input nodes are out of scope.
- Sandboxing workflow code is out of scope.
- Edge-kind, condition, and port editing UI are out of scope.
- Rich node port handles and edge endpoint anchoring are out of scope.
- Naming dialogs, delete confirmations, template galleries, and human-input resume UI are out of scope.
- Moving nodes between graph maps is out of scope.

## Validation ladder

For workflow changes, run validation in this order:

1. `make fennel-check`
2. `make constraints`
3. Focused workflow tests: store, code executor, runner, and graph
4. Broader relevant suite such as `make test` for app bootstrap or graph loader registration changes
