# Workflow-Backed Agent Sessions Design

## Summary

Sidebar agent chats should converge with graph-authored workflows instead of
remaining a separate orchestration mechanism. A chat session will be represented
as one long-lived workflow run. User turns are human-input wait/resume cycles
inside that run. The existing agent chat side panel keeps the same user-facing
behavior by talking to a runner-compatible facade, but the durable source of
truth becomes `WorkflowStore` run data and workflow events.

The migration is explicit and test-driven. Existing `agent-sessions/*.json`
files are converted by a command-line tool into workflow-backed runs, provider
continuity metadata is preserved, and migrated source files are archived after
successful conversion. The app runtime does not carry a permanent startup
migration or dual-reader path.

## Goals

- Make sidebar-created agent sessions workflow-native so agent behavior can be
  edited through the workflow graph.
- Preserve the existing chat side panel behavior from the user's perspective:
  create/list/select sessions, send messages, stream transcript updates, cancel
  active work, show approvals, and inspect artifacts as before.
- Model one chat session as one long-lived workflow run, with multiple user
  turns represented as wait/resume cycles and transcript/status changes recorded
  as workflow events.
- Preserve provider continuity for migrated sessions: OpenCode/provider session
  ids, runtime context, artifact/report paths, timestamps, and other existing
  session metadata must survive migration so the next message continues the same
  provider conversation unless the provider itself is stale under current
  semantics.
- Keep transcript source of truth simple in v1: project chat sessions directly
  from workflow events; do not add a dedicated transcript cache/projection table.
- Make migration explicit, inspectable, idempotent, and removable after cutover.
- Test the migration and compatibility behavior before implementation changes.

## Non-Goals

- No startup migration path.
- No permanent compatibility shim that keeps reading old `agent-sessions/*.json`
  files at runtime.
- No dedicated transcript cache in v1.
- No deletion of the old implementation modules merely for cleanup in the first
  pass; unused fallback code can be removed later after confidence is established.
- No new provider stale-session semantics. Migration preserves data; existing
  provider validation/recovery behavior handles externally stale provider state.
- No broad workflow editor redesign beyond exposing/editing the workflow
  definition/code through existing workflow graph mechanisms.
- No artifact directory renaming requirement. Existing artifact/report paths may
  remain stable even if the session is re-identified as a workflow run.

## Current State

The current agent system persists sessions as JSON files shaped like:

```fennel
{:id :agent-id :status :items [] :data {} :created-at :updated-at}
```

`AgentRunner` owns the active-turn map, appends user and provider transcript
items, persists status changes, manages cancellation, initializes artifact paths,
and passes callbacks into the selected agent implementation. The sidebar
controller expects a runner-like API: `create-session`, `get-session`,
`list-sessions`, `run-turn`, `cancel-turn`, and related lifecycle helpers.

The workflow system already persists definitions, runs, run steps, and events.
`WorkflowRunner` supports runs entering `:waiting` and later resuming a waiting
step with explicit input. That maps naturally to a chat session waiting for the
next user message.

The missing pieces are:

- event helpers and projection logic that turn workflow events into the existing
  session shape expected by the sidebar;
- runtime support for passing agent-turn context into workflow step execution;
- an editable default agent-session workflow definition;
- a runner-compatible facade backed by workflow runs;
- an explicit migration tool for old session JSON;
- graph/key-loader polish so workflow runs and agent sessions feel like the same
  object through graph and sidebar views.

## Chosen Architecture

### Session Identity

Because there are no external references to existing session ids, migrated
sessions may be re-identified. The workflow run id becomes the durable runtime
identity for workflow-backed chats. The sidebar compatibility facade may expose
that run id as the session id.

Migration records the legacy id in run context for audit and idempotency, not as
the primary public identity.

### Ownership

- `WorkflowStore` owns workflow definitions, long-lived chat workflow runs, run
  steps, and workflow events.
- `CodeEntityStore` owns editable workflow step source.
- Agent/provider implementations own provider-specific behavior but no longer
  own durable chat orchestration state.
- The sidebar is a view/control surface over workflow-backed sessions.
- The graph is also a view/control surface over the same workflow definitions,
  runs, and events. Graph topology does not own agent session state.

### One Session = One Long-Lived Run

The default agent chat workflow has one initial agent-chat step in v1. That step
enters a human-input wait state when the chat is idle. Sending a sidebar message
resumes the waiting step with the user's input. Provider streaming, transcript
mutations, status changes, errors, and completion are appended as workflow
events. After the turn completes, the step returns to waiting for the next user
input instead of terminating the run.

The run should remain nonterminal while the chat session is active. Cancellation
of an active provider turn cancels the active turn handle and records compatible
status/error events, then returns the run to the waiting-for-input state unless a
full session cancellation/delete action is explicitly invoked.

### Transcript as Workflow Events

Workflow events are the durable transcript source of truth. A new projection
module folds events into the existing session shape:

```fennel
{:id workflow-run-id
 :workflow-run-id workflow-run-id
 :agent-id ...
 :status ...
 :items [...]
 :data {...}
 :created-at ...
 :updated-at ...}
```

Required event kinds include:

- `:agent-session-created`
- `:agent-status-changed`
- `:agent-item-appended`
- `:agent-item-upserted`
- `:agent-item-updated`

Projection must preserve current transcript item shapes and stable item ids for
`message`, `tool-call`, `tool-result`, `reasoning`, `event`, and `error` items.
Duplicate appends and updates to missing item ids should fail loudly in the
projection/event helper layer so corrupt transcript streams are caught in tests.

No dedicated transcript cache is introduced in v1. If performance becomes an
issue, a later general projection/cache system can be designed once broader
requirements are known.

### Workflow Runtime Extensions

The generic workflow runtime should stay small. It needs enough context
injection for agent workflow steps to operate, without turning the workflow
scheduler itself into an async provider runtime.

Required extensions:

- workflow step context includes run id, run record, store, and optional runtime
  data;
- `resume-step` accepts optional runtime data while preserving existing call
  compatibility;
- agent workflow code can access the runtime object that contains the selected
  agent, turn controller, app services, provider metadata, and callbacks.

Async streaming remains managed by the workflow-backed agent runner facade and
existing turn/controller abstractions. The workflow records streaming effects as
events.

### Editable Default Agent Workflow

The cutover creates or ensures a default editable workflow definition, for
example `wf-agent-session-v1`, whose step source lives in `CodeEntityStore`.
The source returns an agent-chat step implementation. Existing workflow graph
nodes can then expose and edit that definition and code entity using the normal
workflow user flow.

V1 may use a single `step-agent-chat` step. Multi-step agent behavior can be
authored later by editing the workflow graph and code entities.

### Sidebar Compatibility Facade

The runtime installs a workflow-backed runner as `app.agent-runner`. Its public
API remains compatible with the sidebar controller:

- `create-session(agent-id)` creates a workflow run and appends session-created
  events;
- `get-session(session-id)` loads the workflow run and projects it;
- `list-sessions()` lists workflow-backed chat runs and returns session
  summaries sorted as before;
- `run-turn(session-id, input, callbacks)` appends the user item, resumes the
  waiting workflow step, wires callback persistence to workflow events, and
  returns a turn handle immediately;
- `cancel-turn(session-id)` cancels the active provider turn and records
  compatible events;
- delete/drop/flush helpers preserve the existing sidebar contract.

The sidebar should not need behavior changes beyond any strictly necessary
dependency wiring. Existing agent panel tests should continue to pass against
the workflow-backed runner.

## Migration Design

Migration is an explicit command, not startup behavior. A tool such as
`tools.agent-session-migrate` accepts a base Space user-data directory and
converts old files under `agent-sessions/*.json` into workflow-backed runs.

For each old session, migration must:

1. validate and load the JSON session;
2. create or locate the default agent workflow definition;
3. create a workflow run with context identifying it as an agent session;
4. copy `agent-id`, status, timestamps, `data`, runtime context, provider ids,
   artifact/report paths, and legacy id metadata;
5. convert transcript items into workflow transcript events in order;
6. write an old-id to new-run-id mapping report;
7. move successfully migrated old files to an archive directory only after the
   workflow data is durable.

The migration must be idempotent. If a workflow run already records a matching
legacy id, rerunning the tool must not create a duplicate. Malformed JSON,
missing required fields, or failed archive moves should fail loudly with an
actionable error and must not silently drop data.

After cutover, app startup does not scan old `agent-sessions/*.json`. If a user
has not run migration, old sessions simply are not part of the new runtime until
the migration command is run.

## Graph Behavior

Existing workflow graph nodes already expose workflow definitions, steps, runs,
run steps, events, and linked code entities. Workflow-backed sessions should be
visible through those nodes because they are workflow runs.

Additional polish can add `agent-session:<workflow-run-id>` key loaders or
aliases if the sidebar needs a chat-specific graph entry point, but such nodes
must resolve through `WorkflowStore` and projection helpers. They should not
introduce a separate persistence owner.

## Testing Strategy

Implementation should be test-driven in these layers:

1. **Event projection tests**: prove transcript append/update/upsert/status
   events project to the existing session shape without a cache.
2. **Workflow runtime tests**: prove optional runtime context is available on
   `run`/`resume` without breaking existing workflow tests.
3. **Template tests**: prove the default agent workflow definition/code entity
   is created, stable, editable, and not overwritten if user-edited.
4. **Runner compatibility tests**: mirror current `AgentRunner` and agent panel
   expectations for create/list/get/run/cancel/status/streaming callbacks.
5. **Provider continuity tests**: prove OpenCode session ids, runtime context,
   artifact/report paths, and relevant metadata survive projection and migration.
6. **Migration tests**: use temp directories and fixture JSON to prove
   transcript preservation, idempotency, archive behavior, malformed input
   failure, and old-id/new-run-id mapping.
7. **Graph tests**: prove workflow-backed sessions are visible as workflow runs
   and that graph previews/events show the same run state the sidebar projects.
8. **Final validation**: Fennel compile check, constraints, focused agent and
   workflow tests, then broader `make test` because app bootstrap and runtime
   behavior change.

## Risks and Mitigations

- **Async streaming vs synchronous workflow executor**: keep provider streaming
  in the workflow-backed runner/turn controller and record effects as workflow
  events; do not overcomplicate the generic scheduler in v1.
- **Status mismatch**: characterize current status/cancel/error behavior first
  and make workflow projection match the sidebar-visible contract.
- **Provider continuity loss**: make provider metadata preservation an explicit
  migration and runner test requirement.
- **Transcript item instability**: preserve item ids and update/upsert semantics
  exactly; add focused tests for live stream de-duping behavior.
- **Migration data loss**: use temp-dir tests, idempotency checks, atomic writes,
  archive-after-success only, and a mapping report.
- **Performance from event projection**: accept simple projection in v1; design
  a general cache only when requirements are clearer.

## Acceptance Criteria

- New sidebar chats are backed by workflow runs, not old session JSON files.
- Existing chat side panel behavior remains user-seamless under the
  workflow-backed runner.
- A single chat session remains one long-lived workflow run across multiple user
  turns.
- Transcript/status/data projection comes from workflow events.
- The default agent workflow is editable through existing workflow graph/code
  nodes.
- Existing sessions can be migrated with an explicit command, preserving
  transcript and provider continuity and archiving old files after success.
- Migration is idempotent and thoroughly covered by tests.
- No runtime startup migration or permanent old-session dual read path is added.
