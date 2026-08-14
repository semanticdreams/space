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

## V1 exclusions

Version 1 intentionally does not include primitive workflow executors for conditions, loops, joins, tool calls, agent turns, or human input. It does not sandbox workflow code, store workflow data in graph maps, or replace `AgentRunner`.

## Validation ladder

For workflow changes, run validation in this order:

1. `make fennel-check`
2. `make constraints`
3. Focused workflow tests: store, code executor, runner, and graph
4. Broader relevant suite such as `make test` for app bootstrap or graph loader registration changes
