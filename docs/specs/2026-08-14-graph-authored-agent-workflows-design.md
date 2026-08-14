# Graph-Authored Agent Workflows Design

## Purpose

Space should expose internal agent orchestration through the graph as a primary authoring and steering interface, while keeping workflows independent from any single world or graph map. Users should be able to build arbitrary agentic workflows, trigger them from the graph, watch runs unfold as graph-visible objects, and quickly identify running, waiting, failed, or human-input states.

The graph is one interface over the workflow system, not the owner of workflow data. Future interfaces such as sidebars, command palette actions, scripts, or APIs must be able to create and run the same workflows without depending on graph mode.

## Current Context

- The current agent runtime is app/user scoped. `main.fnl` creates `app.agent-runner` with sessions under `{app.user-data-dir}/agent-sessions` and artifacts under `{app.user-data-dir}/agent-artifacts`.
- `AgentRunner` owns agent sessions, active turns, callbacks, cancellation, and persistence. Individual agents own provider orchestration.
- The Space Agent sidebar stores only view-model state such as active agent, active session, expanded rows, and pending approval; persisted data remains in the app-scoped agent runtime.
- Code entities already provide graph-visible, user-authored code records persisted by their owning code entity store. They can be edited and run through existing graph code entity nodes and kernel infrastructure.
- Graph doctrine remains binding: graph node adapters expose domain objects; graph core persists topology only; owning systems persist domain data.
- Graph maps are user-facing interaction contexts over graph-visible objects. Layout, selection, focus, panels, and visual inclusion are graph-map/view concerns, but workflow topology itself is a workflow-domain concern.

## Design Direction

Use a dedicated, app/user-scoped workflow subsystem with code-entity-backed executable steps.

The canonical workflow model is a durable workflow definition plus durable workflow runs. The workflow store owns definitions, steps, edges, runs, run-step state, attempts, outputs, wait requests, and event history. The graph exposes these objects through key loaders and node adapters.

Executable workflow behavior comes from Fennel code entities. A workflow step references a code entity, and the workflow runner evaluates that code through the existing kernel/code-entity path to obtain a factory or step object implementing the workflow contract. The runner does not need separate built-in primitive executors for condition, loop, join, tool call, agent turn, or human input in the first design. Those behaviors are expressed in Fennel code using the same contract. Starter templates may later create common code entities, but they should not become special runner concepts unless a strong need emerges.

## Ownership Boundaries

### Workflow Store

Owns canonical workflow domain records:

- workflow definitions
- workflow steps
- workflow control/data edges
- workflow runs
- run-step state
- attempts and retry state
- wait requests
- run events/logs
- durable links to agent sessions, artifacts, graph-visible objects, and worlds

Workflow records are app/user scoped by default, orthogonal to worlds. Any world can load and run any workflow setup. A run may record contextual references such as `world-id`, `graph-map-id`, selected graph node keys, active activity, or repository path, but these are context links/snapshots, not ownership.

### Code Entity Store

Owns user-authored Fennel source used by workflow steps. Workflow steps reference code entities rather than embedding durable code bodies directly.

Workflow-specific metadata belongs on the workflow step record, not on the code entity record. This keeps code entities general-purpose and avoids coupling them to the workflow subsystem.

### Workflow Runner

Owns orchestration:

- schedules steps
- evaluates control/data edges
- invokes code-entity-backed step behavior
- persists status transitions
- handles waits, cancellation, failures, retries, loops, and resume
- emits run events
- records links to agent sessions or other side-effectful operations

`AgentRunner` remains the agent session/turn executor. Workflow code can call the agent runtime through full app access or convenience context helpers, but workflow orchestration state is owned by `WorkflowRunner`.

### Graph

Graph key loaders and node adapters expose workflow definitions, workflow steps, workflow runs, run steps, events, waits, code entities, and agent sessions. Graph nodes mutate workflow domain objects through explicit workflow-store or workflow-runner APIs.

When users author workflows through graph interactions, those interactions are domain operations by default. Connecting workflow step nodes creates or updates canonical workflow edges. Removing a canonical workflow edge deletes it from the workflow definition. Creating a step creates a workflow step record. This is not a separate edit mode.

Graph maps remain user-facing interaction contexts. Workflow nodes should not reason about which graph map owns them. If a workflow is triggered from a visible graph context, the run node appears immediately in that context as a graph-visible domain object, with a canonical definition-to-run relationship rendered as an edge. Moving nodes between graph maps is a later general graph-map feature, not workflow-specific behavior.

## Workflow Definition Model

Initial definition shape:

```fennel
{:id "wf-..."
 :name "..."
 :description ""
 :version 1
 :status :draft
 :parameters {}
 :steps [{:id "step-..."
          :name "..."
          :code-entity-id "code-..."
          :config {}
          :input-schema {}
          :output-schema {}
          :retry {:max-attempts 0}
          :timeout-ms nil}]
 :edges [{:id "edge-..."
          :kind :control
          :source-step-id "step-a"
          :target-step-id "step-b"
          :condition nil}
         {:id "edge-..."
          :kind :data
          :source-step-id "step-a"
          :source-port "result"
          :target-step-id "step-b"
          :target-port "input"}]
 :created-at 0
 :updated-at 0}
```

The schema includes ports now even though v1 graph edges can attach visually to node centers. A new step-to-step connection defaults to a control edge. Users can edit edge kind, condition, source port, and target port afterward. Later graph UI can expose visible preview-owned port handles and attach edge endpoints to those handles when previews are open.

## Workflow Run Model

Runs are explicit graph-visible domain objects separate from definitions.

```fennel
{:id "wfr-..."
 :definition-id "wf-..."
 :definition-version 1
 :status :queued|:running|:waiting|:succeeded|:failed|:cancelled
 :input {}
 :output {}
 :context {:world-id nil
           :graph-node-keys []
           :repo-path nil}
 :current-step-ids []
 :created-at 0
 :started-at nil
 :finished-at nil
 :error nil}
```

Run-step state:

```fennel
{:run-id "wfr-..."
 :step-id "step-..."
 :status :pending|:ready|:running|:waiting|:succeeded|:failed|:skipped|:cancelled
 :attempt 0
 :input {}
 :output {}
 :state {}
 :wait nil
 :started-at nil
 :finished-at nil
 :error nil}
```

The run graph projection should make status visible at a glance. Node colors should distinguish pending, ready/running, waiting for human input, failed, succeeded, skipped, and cancelled. A run node can toggle whether subsequent run-step/detail nodes are visible to avoid clutter.

## Fennel Workflow Code Contract

Workflow code uses code entities with `language = fennel`. The workflow code executor evaluates the referenced code entity through existing kernel infrastructure and adapts the result into the workflow contract.

Preferred source shape is a factory function returning a step object:

```fennel
(fn [opts]
  {:run
   (fn [self ctx input state]
     (ctx:succeed {:value 42}))
   :resume
   (fn [self ctx wait-result state]
     (ctx:succeed {:received wait-result}))
   :cancel
   (fn [self ctx state]
     (ctx:cancelled {:reason "cancelled by user"}))})
```

The factory receives workflow step options/config. The object may implement `:run`, `:resume`, `:cancel`, and later optional descriptive/schema methods.

The canonical result is always an outcome table. `ctx` helper methods create and validate those tables, but they should not secretly complete a step without a returned outcome.

Example outcome shapes:

```fennel
{:status :succeeded :output {...}}
{:status :failed :error {:message "..." :data {...}}}
{:status :waiting :wait-kind :human-input :request {...} :state {...}}
{:status :retry :delay-ms 1000 :state {...}}
{:status :cancelled :output {...}}
{:status :skipped :reason "..."}
```

Workflow code has full app/global access. The `ctx`, `input`, and `state` arguments are convenience and observability mechanisms rather than sandbox boundaries. Even with full access, workflow-visible progress must be reported through returned outcome tables and emitted events so runs remain inspectable.

## Control Flow and Data Flow

The workflow language supports full control, including branches, loops, joins, waits, retries, cancellation, and failure handling.

Control edges govern scheduling. Data edges copy outputs or selected ports from one step into another step's input. Conditions and loop decisions can be expressed by code-backed edge predicates or by step outcomes that direct subsequent control flow.

The runner should record enough event history to explain why a step is ready, running, waiting, skipped, retried, or failed. This event stream is essential for graph inspection and debugging.

## Graph Node Types

Candidate key schemes:

- `workflows`
- `workflow-definition:<definition-id>`
- `workflow-step:<definition-id>:<step-id>`
- `workflow-edge:<definition-id>:<edge-id>`
- `workflow-run:<run-id>`
- `workflow-run-step:<run-id>:<step-id>`
- `workflow-run-event:<run-id>:<event-id>`
- existing `code-entity:<id>` nodes for step source
- existing or future `agent-session:<session-id>` nodes for agent details

Definition nodes expand to step nodes, code entity links, and canonical workflow edges. Run nodes expand to run-step nodes, events, waits, outputs, and links to agent sessions/tool artifacts created during execution.

The definition-to-run relationship is canonical workflow domain data and should render as an edge when a run is created. Starting a workflow from the graph immediately creates and displays the run node in the current visible graph context.

## User Interactions

- Create workflow definition.
- Add workflow step, choosing or creating a code entity.
- Edit step config, retry policy, timeout, schemas, and display label.
- Connect steps; new connections default to control edges.
- Edit edge kind, condition, source port, and target port.
- Start workflow run from a definition node.
- Watch run node and run-step nodes update status/colors.
- Expand/collapse run details to manage clutter.
- Resume a waiting step with human input.
- Cancel a run or step.
- Open linked agent sessions, code entities, artifacts, and event logs.

## Error Handling

- Missing workflow definitions, code entities, runs, or steps fail loudly at mutation/execution boundaries.
- Key loaders return nil for missing records, following existing graph loader patterns.
- Unknown or invalid workflow code contract results fail the step with a structured error.
- Kernel/evaluation failures become step failure records and run events.
- Workflow code may have side effects because it has full access; the runner still records explicit workflow status and event evidence.
- Deleting a workflow step must handle dependent edges explicitly and should not silently corrupt existing run history.

## Testing and Validation

Focused implementation tests should cover:

- workflow store persistence independent of graph maps/worlds
- creating/updating/deleting definitions, steps, edges, runs, run-step states, and events
- code-entity-backed step contract normalization
- successful, failed, waiting, retrying, cancelled, branching, looping, and joining runs
- graph key loader resolution and missing-record nil behavior
- graph authoring operations mutating workflow store edges/steps directly
- run node creation and definition-to-run edge projection after triggering a workflow
- run detail expand/collapse behavior and status color mapping

Fennel validation must follow the project ladder: compile check first, constraints second, focused Fennel tests third, and broader `make test` when warranted by runtime/bootstrap/graph risk.

## Out of Scope for the First Implementation Plan

- Rich preview port handle rendering and edge endpoint anchoring.
- General node movement between graph maps.
- Sandboxing workflow code.
- External `.fnl` module storage as the primary workflow code mechanism.
- Replacing `AgentRunner`; it remains the agent session/turn system.
- Treating graph maps as canonical workflow storage.
