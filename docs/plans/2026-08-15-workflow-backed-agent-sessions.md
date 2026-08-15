# Workflow-Backed Agent Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert sidebar agent chats into workflow-backed long-lived runs while preserving seamless chat panel behavior and enabling graph/workflow editing of agent behavior.

**Architecture:** One chat session is one long-lived workflow run. User turns are wait/resume cycles inside that run, transcript/status/data changes are workflow events, and the existing sidebar consumes a runner-compatible facade projected from those events. Migration is explicit and test-driven: old JSON session files are converted to workflow runs, provider continuity metadata is preserved, and old files are archived after successful migration.

**Tech Stack:** Space Fennel modules under `assets/lua`, `WorkflowStore`, `WorkflowRunner`, `WorkflowCodeExecutor`, `CodeEntityStore`, existing agent turn/provider modules, graph key loaders/nodes/previews, project-native Fennel tests and constraints.

## Global Constraints

- New sidebar chats are backed by workflow runs, not old `agent-sessions/*.json` files.
- One chat session is one long-lived workflow run across multiple user turns.
- User turns are human-input wait/resume cycles inside the run.
- Transcript, status, and session data are projected from workflow events in v1; do not add a dedicated transcript cache.
- The existing chat side panel must keep the same user-facing behavior.
- Preserve the sidebar runner API shape: `create-session`, `get-session`, `list-sessions`, `run-turn`, `cancel-turn`, `delete-session`, `flush`, and `drop`.
- Provider continuity must be preserved for migrated sessions: OpenCode/provider session ids, runtime context, artifact/report paths, timestamps, and relevant session metadata survive migration.
- Existing sessions may be re-identified; the workflow run id becomes the durable runtime identity, while legacy ids are migration metadata for audit/idempotency.
- Migration is an explicit CLI/tool action, not startup migration.
- Migration archives old JSON session files only after successful durable workflow conversion.
- Migration must be idempotent and fail loudly on malformed input or partial failure.
- `WorkflowStore` owns workflow definitions, long-lived chat workflow runs, run steps, and events.
- `CodeEntityStore` owns editable workflow step source.
- Graph nodes/key loaders are adapters over owning stores; graph topology does not own agent session state.
- The default agent workflow must be editable through existing workflow graph/code entity nodes.
- Async provider streaming remains in the workflow-backed agent runner/turn-controller layer; do not make the generic workflow scheduler a provider runtime in v1.
- Do not introduce startup dual-read behavior for old JSON sessions.
- No new provider stale-session semantics; preserve current provider validation/recovery behavior.
- Use `assets/lua/json-utils.fnl` for atomic JSON writes.
- For Fennel-facing changes, run compile checks first, constraints second, focused Fennel tests third.
- Run `make build` with timeout `14400000` first when `./build/space` is missing or stale.
- Direct Fennel test commands must set `SPACE_ASSETS_PATH=$(pwd)/assets`, `FENNEL_PATH`, and `FENNEL_MACRO_PATH` to `$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl`.
- Test hygiene: use `SPACE_DISABLE_AUDIO=1`, `SKIP_KEYRING_TESTS=1`, and `XDG_DATA_HOME=/tmp/space/tests/xdg-data` for direct test runs.
- If Fennel delimiter or parse errors occur, inspect the nearest enclosing form, simplify nested logic into helpers, and rerun compile check before constraints/tests.
- PR CI is the full integration gate.

---

## File Structure / Task Decomposition

- Create `assets/lua/llm/agent/workflow-events.fnl`: event append helpers and event-to-session projection.
- Create `assets/lua/tests/test-agent-workflow-events.fnl`: focused event projection tests.
- Modify `assets/lua/tests/fast.fnl`: register new focused test modules.
- Modify `assets/lua/workflows/outcomes.fnl`: add optional run/store/runtime fields to workflow step context helpers.
- Modify `assets/lua/workflows/code-executor.fnl`: pass optional runtime context into step `run`/`resume` calls.
- Modify `assets/lua/workflows/runner.fnl`: allow `resume-step` runtime options without breaking existing calls.
- Modify `assets/lua/tests/test-workflow-code-executor.fnl`: runtime context regression tests.
- Modify `assets/lua/tests/test-workflow-runner.fnl`: resume compatibility/runtime context tests.
- Create `assets/lua/llm/agent/workflow-step.fnl`: default agent-chat workflow step implementation.
- Create `assets/lua/llm/agent/workflow-template.fnl`: ensure editable default agent workflow definition/code entity.
- Create `assets/lua/tests/test-agent-workflow-template.fnl`: template creation/non-overwrite tests.
- Create `assets/lua/llm/agent/workflow-runner.fnl`: sidebar-compatible workflow-backed runner facade.
- Modify `assets/lua/main.fnl`: instantiate workflow-backed runner as `app.agent-runner`.
- Create `assets/lua/tests/test-agent-workflow-runner.fnl`: runner compatibility/provider continuity tests.
- Modify `assets/lua/tests/test-agent-panel.fnl`: ensure existing panel behavior passes against workflow-backed runner.
- Create `assets/lua/llm/agent/session-migration.fnl`: explicit migration library.
- Create `assets/lua/tools/agent-session-migrate.fnl`: CLI entry point for migration.
- Create `assets/lua/tests/test-agent-session-migration.fnl`: transcript/provider/idempotency/archive migration tests.
- Modify `assets/lua/graph/key-loaders.fnl`: expose workflow-backed agent session keys if needed by graph entry points.
- Create `assets/lua/graph/nodes/agent-session.fnl`: optional chat-specific graph adapter over workflow run projection.
- Create `assets/lua/graph/view/previews/agent-session.fnl`: optional session preview if graph key loader is added.
- Modify `assets/lua/tests/test-workflow-graph.fnl`: graph parity tests for workflow-backed sessions.
- Create `docs/dev/features/workflow-backed-agent-sessions.md`: canonical developer documentation.
- Modify `docs/dev/features/workflows.md`: update workflow docs for agent-session-backed runs.
- Modify `docs/dev/features/agent-runner-system.md`: point to workflow-backed sessions as current architecture.

## Observable Acceptance Criteria

- Creating a chat from the sidebar creates a workflow run and no old session JSON file.
- Listing/selecting chats in the sidebar works from workflow run projection.
- Sending multiple messages to the same chat resumes the same long-lived workflow run.
- Transcript item ids and shapes remain compatible with existing transcript UI rows.
- Streaming item append/update/upsert callbacks persist as workflow events and remain visible in the sidebar.
- Canceling an active turn keeps sidebar behavior compatible and leaves the long-lived run ready for the next input unless a full delete/cancel action is used.
- The default agent workflow definition and code entity are visible/editable through normal workflow graph nodes.
- Migrating old JSON sessions preserves transcript order, metadata, runtime context, OpenCode/provider continuity fields, artifact/report paths, and timestamps.
- Migration writes an old-id to new-run-id mapping and archives old files only after durable workflow conversion.
- Rerunning migration does not duplicate already migrated sessions.
- Focused agent/workflow/graph tests and broader `make test` pass after app bootstrap changes.

---

### Task 1: Workflow Event Transcript Projection

**Files:**
- Create: `assets/lua/llm/agent/workflow-events.fnl`
- Create: `assets/lua/tests/test-agent-workflow-events.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `WorkflowStore:append-event(run-id, event)`, workflow run records shaped as `{:id :definition-id :status :context :events :created-at :updated-at}`.
- Produces:
  - `WorkflowEvents.append-session-created(store, run-id, data) -> event`
  - `WorkflowEvents.append-status(store, run-id, status, data) -> event`
  - `WorkflowEvents.append-item(store, run-id, item) -> event`
  - `WorkflowEvents.append-upsert(store, run-id, item) -> event`
  - `WorkflowEvents.append-update(store, run-id, item-id, updates) -> event`
  - `WorkflowEvents.project-session(run) -> {:id string :workflow-run-id string :agent-id string :status string :items table :data table :created-at string :updated-at string}`
  - `WorkflowEvents.session-summary(session) -> {:id string :agent-id string :status string :item-count number :created-at string :updated-at string}`

- [ ] **Step 1: Write failing projection tests**

In `assets/lua/tests/test-agent-workflow-events.fnl`, create isolated temp `WorkflowStore` helpers and add tests named:

- `projects-session-created-event-to-sidebar-session-shape`
- `projects-appended-message-items-in-order`
- `projects-status-changes-with-latest-status`
- `upserts-existing-stream-item-with-stable-id`
- `updates-existing-item-fields`
- `rejects-duplicate-append-item-id`
- `rejects-update-for-missing-item-id`

Each test must construct a workflow run with only context/events and assert projection output, proving no transcript cache is required.

- [ ] **Step 2: Run focused test and verify it fails because module is missing**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-workflow-events:main
```

Expected: FAIL with `llm/agent/workflow-events` module-not-found or missing function error.

- [ ] **Step 3: Implement event helper module**

Implement event kinds exactly:

```fennel
(local KIND_SESSION_CREATED :agent-session-created)
(local KIND_STATUS_CHANGED :agent-status-changed)
(local KIND_ITEM_APPENDED :agent-item-appended)
(local KIND_ITEM_UPSERTED :agent-item-upserted)
(local KIND_ITEM_UPDATED :agent-item-updated)
```

Each append helper must assert required arguments and call `store:append-event run-id event` with a compact event payload. `append-item` and `append-upsert` store full item tables. `append-update` stores `:item-id` and `:updates`.

- [ ] **Step 4: Implement projection fold**

`project-session` must:

- initialize session id from `run.id`;
- initialize `workflow-run-id` from `run.id`;
- initialize `agent-id`, `data`, and legacy metadata from `run.context` when present;
- fold events in stored order;
- append items for `:agent-item-appended` only if id is not already present;
- upsert items by replacing the existing item with the same id or appending when absent;
- update only existing item ids;
- set status from latest `:agent-status-changed` event;
- derive `updated-at` from latest relevant event timestamp or `run.updated-at`.

- [ ] **Step 5: Register and validate**

Add the test module to `assets/lua/tests/fast.fnl`, then run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/agent/workflow-events.fnl --file assets/lua/tests/test-agent-workflow-events.fnl --file assets/lua/tests/fast.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-workflow-events:main
```

Expected: compile check PASS, constraints PASS, focused test PASS.

- [ ] **Step 6: Commit**

```bash
git add assets/lua/llm/agent/workflow-events.fnl assets/lua/tests/test-agent-workflow-events.fnl assets/lua/tests/fast.fnl
git commit -m "feat(agent): project sessions from workflow events"
```

---

### Task 2: Workflow Runtime Context for Agent Turns

**Files:**
- Modify: `assets/lua/workflows/outcomes.fnl`
- Modify: `assets/lua/workflows/code-executor.fnl`
- Modify: `assets/lua/workflows/runner.fnl`
- Modify: `assets/lua/tests/test-workflow-code-executor.fnl`
- Modify: `assets/lua/tests/test-workflow-runner.fnl`

**Interfaces:**
- Consumes: existing `WorkflowRunner:resume-step(run-id, step-id, wait-result)` and workflow code entity step methods `:run`, `:resume`, `:cancel`.
- Produces:
  - `WorkflowRunner:resume-step(run-id, step-id, wait-result, opts)` where `opts` is optional.
  - Step context fields `:run-id`, `:run`, `:store`, and `:runtime` when supplied.
  - Backward-compatible existing workflow code executor behavior.

- [ ] **Step 1: Add failing code-executor context tests**

In `assets/lua/tests/test-workflow-code-executor.fnl`, add a test `step-context-includes-run-and-runtime-metadata`. Use a code entity whose `:run` method returns `ctx:succeed {:run-id ctx.run-id :runtime-value ctx.runtime.value}`. Assert output includes the provided run id and runtime value.

- [ ] **Step 2: Add failing runner resume compatibility tests**

In `assets/lua/tests/test-workflow-runner.fnl`, add tests:

- `resume-step-still-accepts-three-arguments`
- `resume-step-passes-runtime-to-resumed-step`

Use a waiting step and assert old three-argument calls still pass while four-argument calls pass `{:runtime {:value "agent-runtime"}}` into resumed code.

- [ ] **Step 3: Run focused tests and verify failures**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-code-executor:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-runner:main
```

Expected: FAIL because runtime/run metadata is unavailable.

- [ ] **Step 4: Extend outcome context helpers**

Modify `assets/lua/workflows/outcomes.fnl` so the context object created for step code carries optional `run-id`, `run`, `store`, and `runtime` fields in addition to existing helper methods such as `succeed`, `fail`, and `wait`.

- [ ] **Step 5: Extend code executor call path**

Modify `assets/lua/workflows/code-executor.fnl` so `run-step` and `resume-step` accept optional execution metadata, pass it to context construction, and preserve existing call signatures when metadata is nil.

- [ ] **Step 6: Extend workflow runner resume path**

Modify `assets/lua/workflows/runner.fnl` so `resume-step` accepts optional `opts`, passes run/store/runtime metadata into the executor, and leaves waiting/running/terminal transitions unchanged for existing tests.

- [ ] **Step 7: Validate**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/workflows/outcomes.fnl --file assets/lua/workflows/code-executor.fnl --file assets/lua/workflows/runner.fnl --file assets/lua/tests/test-workflow-code-executor.fnl --file assets/lua/tests/test-workflow-runner.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-code-executor:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-runner:main
```

Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add assets/lua/workflows/outcomes.fnl assets/lua/workflows/code-executor.fnl assets/lua/workflows/runner.fnl assets/lua/tests/test-workflow-code-executor.fnl assets/lua/tests/test-workflow-runner.fnl
git commit -m "feat(workflows): pass runtime context to resumed steps"
```

---

### Task 3: Editable Agent Workflow Template

**Files:**
- Create: `assets/lua/llm/agent/workflow-step.fnl`
- Create: `assets/lua/llm/agent/workflow-template.fnl`
- Create: `assets/lua/tests/test-agent-workflow-template.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `CodeEntityStore:create-entity(opts)`, `CodeEntityStore:get-entity(id)`, `WorkflowStore:create-definition(opts)`, `WorkflowStore:get-definition(id)`, `WorkflowStore:add-step(definition-id, step)`, runtime context fields from Task 2.
- Produces:
  - `WorkflowStep.AgentChatStep(config) -> {:run fn :resume fn :cancel fn}`
  - `WorkflowTemplate.ensure-definition(opts) -> definition`
  - Stable definition id `wf-agent-session-v1`
  - Stable step id `step-agent-chat`
  - Stable code entity id `space-agent-session-step-v1`

- [ ] **Step 1: Add failing template creation tests**

Create `assets/lua/tests/test-agent-workflow-template.fnl` with tests:

- `ensure-definition-creates-editable-agent-workflow`
- `ensure-definition-reuses-existing-definition`
- `ensure-definition-does-not-overwrite-user-edited-code`
- `agent-chat-step-starts-waiting-for-user-input`

Assert the definition references the stable code entity id, the code entity language is `fnl`, and the generated source returns `WorkflowStep.AgentChatStep`.

- [ ] **Step 2: Run focused test and verify failure**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-workflow-template:main
```

Expected: FAIL because template modules do not exist.

- [ ] **Step 3: Implement default workflow step module**

`WorkflowStep.AgentChatStep(config)` must return an object with:

- `:run self ctx input state` returning `ctx:wait :agent-user-input {:agent-id config.agent-id}`;
- `:resume self ctx wait-result state` delegating to `ctx.runtime.run-agent-turn` or a similarly explicit runtime function and returning its workflow outcome;
- `:cancel self ctx state` calling `ctx.runtime.cancel-agent-turn` when present, then returning a cancellation-compatible outcome.

All required runtime functions must be asserted before use.

- [ ] **Step 4: Implement workflow template module**

`WorkflowTemplate.ensure-definition(opts)` must assert `workflow-store` and `code-store`, create the stable code entity only when missing, create the stable workflow definition only when missing, add the stable step only when absent, and never overwrite an existing code entity source or existing definition fields.

- [ ] **Step 5: Register and validate**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/agent/workflow-step.fnl --file assets/lua/llm/agent/workflow-template.fnl --file assets/lua/tests/test-agent-workflow-template.fnl --file assets/lua/tests/fast.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-workflow-template:main
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add assets/lua/llm/agent/workflow-step.fnl assets/lua/llm/agent/workflow-template.fnl assets/lua/tests/test-agent-workflow-template.fnl assets/lua/tests/fast.fnl
git commit -m "feat(agent): add editable workflow template for chats"
```

---

### Task 4: Workflow-Backed Runner API for Sidebar Compatibility

**Files:**
- Create: `assets/lua/llm/agent/workflow-runner.fnl`
- Create: `assets/lua/tests/test-agent-workflow-runner.fnl`
- Modify: `assets/lua/tests/test-agent-panel.fnl`
- Modify: `assets/lua/tests/fast.fnl`
- Modify: `assets/lua/main.fnl`

**Interfaces:**
- Consumes: `WorkflowEvents` from Task 1, runtime context injection from Task 2, `WorkflowTemplate.ensure-definition` from Task 3, existing `llm/agent/turn.fnl`, existing agent/provider registry APIs, existing approval/artifact dependencies from app bootstrap.
- Produces:
  - `WorkflowAgentRunner(opts) -> runner`
  - `runner:create-session(agent-id) -> projected-session`
  - `runner:get-session(session-id) -> projected-session|nil`
  - `runner:list-sessions() -> session-summary[]`
  - `runner:run-turn(session-id, input, callbacks) -> TurnHandle`
  - `runner:cancel-turn(session-id) -> true`
  - `runner:delete-session(session-id) -> nil`
  - `runner:flush() -> nil`
  - `runner:drop() -> nil`

- [ ] **Step 1: Add failing runner compatibility tests**

In `assets/lua/tests/test-agent-workflow-runner.fnl`, add tests named:

- `create-session-creates-workflow-run-and-projects-session`
- `list-sessions-sorts-projected-workflow-sessions-by-updated-at`
- `run-turn-appends-user-message-and-returns-turn-handle`
- `streaming-callbacks-persist-item-events`
- `completion-sets-session-idle-and-preserves-items`
- `error-adds-error-item-and-sets-session-idle`
- `cancel-turn-cancels-active-turn-and-allows-next-input`
- `new-turn-cancels-existing-active-turn-for-same-session`

Use stub agents/providers so tests do not require network access.

- [ ] **Step 2: Add provider continuity tests**

In the same test file, add `runtime-context-preserves-provider-continuity-fields`. Assert projected session data/runtime contains existing field names used today: `agent-session-id`, `artifact-dir`, `report-path`, `opencode-session-id`, `mcp-endpoint`, `opencode-server-url`, `last-live-connection-at`, and `validation-mode` when supplied.

- [ ] **Step 3: Add panel compatibility coverage**

Modify `assets/lua/tests/test-agent-panel.fnl` so the existing panel/controller tests can run against `WorkflowAgentRunner` with stubbed dependencies. Do not weaken existing assertions about visible item rows, active session state, approvals, or callback updates.

- [ ] **Step 4: Run tests and verify failures**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-workflow-runner:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-panel:main
```

Expected: new runner tests fail because `workflow-runner` does not exist; panel compatibility fails until wiring is added.

- [ ] **Step 5: Implement workflow-backed runner**

`WorkflowAgentRunner(opts)` must assert required dependencies: `workflow-store`, `workflow-runner`, `code-store`, agent registry/access function, artifact root, approvals, app/runtime services needed by current agents. It keeps only active turn handles in memory; durable state is workflow run/events.

- [ ] **Step 6: Implement session creation/listing/projection**

`create-session` must ensure the default workflow definition, start a run or create a waiting run, append `:agent-session-created` and status events, initialize runtime context/artifact paths, and return `WorkflowEvents.project-session`. `list-sessions` must filter runs whose context marks them as agent sessions and return summaries sorted by `updated-at` descending.

- [ ] **Step 7: Implement turn lifecycle**

`run-turn` must append a user message event, cancel any active turn for that session, create a `TurnPair`, resume the waiting workflow step with `{:kind :agent-user-input :input input}`, pass runtime callbacks that append/update/upsert workflow item events, and return the handle immediately.

- [ ] **Step 8: Implement cancellation/delete/drop**

`cancel-turn` must cancel the active turn handle and append compatible status/error events. `delete-session` must delete or mark the workflow run according to existing store capabilities and ensure `get-session` returns nil afterward. `flush` and `drop` must preserve current no-op/cleanup expectations.

- [ ] **Step 9: Switch app bootstrap**

Modify `assets/lua/main.fnl` so `app.agent-runner` uses `WorkflowAgentRunner`. Do not scan old `agent-sessions/*.json` at startup. Preserve existing dependencies for providers, approvals, artifacts, presets, tools, and OpenCode/MCP bridge.

- [ ] **Step 10: Register and validate**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/agent/workflow-runner.fnl --file assets/lua/tests/test-agent-workflow-runner.fnl --file assets/lua/tests/test-agent-panel.fnl --file assets/lua/tests/fast.fnl --file assets/lua/main.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-workflow-runner:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-panel:main
```

Expected: all PASS.

- [ ] **Step 11: Commit**

```bash
git add assets/lua/llm/agent/workflow-runner.fnl assets/lua/tests/test-agent-workflow-runner.fnl assets/lua/tests/test-agent-panel.fnl assets/lua/tests/fast.fnl assets/lua/main.fnl
git commit -m "feat(agent): back sidebar chats with workflow runs"
```

---

### Task 5: Explicit Legacy Session Migration Tool

**Files:**
- Create: `assets/lua/llm/agent/session-migration.fnl`
- Create: `assets/lua/tools/agent-session-migrate.fnl`
- Create: `assets/lua/tests/test-agent-session-migration.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: old files under `{base-dir}/agent-sessions/*.json`, `WorkflowTemplate.ensure-definition`, `WorkflowEvents` helpers, workflow-backed runner/session projection.
- Produces:
  - `SessionMigration.migrate(opts) -> {:migrated number :archived number :mapping table :archive-dir string}`
  - CLI module `tools.agent-session-migrate:main`
  - Command: `./build/space -m tools.agent-session-migrate:main -- --base-dir <space-user-data-dir>`

- [ ] **Step 1: Add failing transcript migration tests**

Create `assets/lua/tests/test-agent-session-migration.fnl` with temp old session files. Test `migrates-items-to-workflow-events` must assert old `items` project back to the same ordered transcript after migration.

- [ ] **Step 2: Add failing provider continuity tests**

Add `preserves-provider-continuity-fields` asserting migrated projected session preserves `session.data`, `session.data.runtime-context`, `opencode-session-id`, `artifact-dir`, `report-path`, timestamps, and agent id.

- [ ] **Step 3: Add failing archive/idempotency tests**

Add tests:

- `archives-old-files-after-successful-migration`
- `does-not-archive-when-workflow-write-fails`
- `rerun-does-not-create-duplicate-for-legacy-id`
- `malformed-json-fails-loudly`

- [ ] **Step 4: Run focused test and verify failure**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-session-migration:main
```

Expected: FAIL because migration module does not exist.

- [ ] **Step 5: Implement migration library**

`SessionMigration.migrate(opts)` must assert `base-dir`, `workflow-store`, `workflow-runner`, and `code-store`. It reads each `*.json` under `<base-dir>/agent-sessions`, validates required fields, ensures the default workflow definition, creates a workflow run with context `{:kind :agent-session :legacy-agent-session-id old-id :agent-id old-agent-id :data old-data}`, appends transcript events in order, and records mapping `old-id -> run-id`.

- [ ] **Step 6: Implement idempotency lookup**

Before creating a run, scan existing workflow runs for `context.legacy-agent-session-id == old-id`. If found, add mapping to the report and do not duplicate events or archive again unless the old file is still present and the existing run projection matches.

- [ ] **Step 7: Implement archive-after-success**

After each session is durably converted, move its JSON file to `<base-dir>/agent-sessions-archive/<timestamp>/`. If archive move fails, report failure and leave enough mapping evidence to retry safely.

- [ ] **Step 8: Implement CLI**

`tools.agent-session-migrate:main` must parse `--base-dir`, fail loudly if missing, construct the same workflow/code stores used by app data layout, call `SessionMigration.migrate`, print migrated count, archived count, archive dir, and old/new mapping.

- [ ] **Step 9: Register and validate**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/agent/session-migration.fnl --file assets/lua/tools/agent-session-migrate.fnl --file assets/lua/tests/test-agent-session-migration.fnl --file assets/lua/tests/fast.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-session-migration:main
```

Expected: all PASS.

- [ ] **Step 10: Commit**

```bash
git add assets/lua/llm/agent/session-migration.fnl assets/lua/tools/agent-session-migrate.fnl assets/lua/tests/test-agent-session-migration.fnl assets/lua/tests/fast.fnl
git commit -m "feat(agent): migrate legacy sessions to workflows"
```

---

### Task 6: Graph Parity for Workflow-Backed Agent Sessions

**Files:**
- Modify: `assets/lua/graph/key-loaders.fnl`
- Create: `assets/lua/graph/nodes/agent-session.fnl`
- Create: `assets/lua/graph/view/previews/agent-session.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`

**Interfaces:**
- Consumes: `WorkflowEvents.project-session(run)`, `WorkflowStore:get-run(id)`, existing `workflow-run:<id>` graph nodes.
- Produces:
  - Key loader for `agent-session:<workflow-run-id>` returning a graph node adapter projected from the workflow run.
  - `AgentSessionNode(opts) -> node` with actions that load the backing `workflow-run:<id>` and relevant run events.
  - Preview requiring direct build context and dropping owned child widgets.

- [ ] **Step 1: Add failing graph key-loader tests**

In `assets/lua/tests/test-workflow-graph.fnl`, add `agent-session-key-loads-workflow-backed-session`. It must create a workflow-backed session run, load `agent-session:<run-id>`, and assert the node title/status/item count matches projection.

- [ ] **Step 2: Add failing graph action/preview tests**

Add tests:

- `agent-session-node-loads-backing-workflow-run`
- `agent-session-preview-requires-direct-context`
- `agent-session-preview-shows-status-and-item-count`

- [ ] **Step 3: Run focused graph test and verify failure**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: FAIL because `agent-session` graph loader/node does not exist.

- [ ] **Step 4: Implement key loader and node adapter**

Add a loader for `agent-session:<workflow-run-id>` that returns nil for missing runs or non-agent-session runs. `AgentSessionNode` must hold only the projected session and store references needed for actions; it must not own or persist session data.

- [ ] **Step 5: Implement preview**

The preview builder must assert direct build context, instantiate child `Text`/layout widgets with that context, display session id/status/agent id/item count compactly, and drop direct child widgets.

- [ ] **Step 6: Implement graph actions**

Add actions to load the backing `workflow-run:<id>` and recent run events into the current graph map. Fail loudly if graph map/load dependencies are missing.

- [ ] **Step 7: Validate**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/key-loaders.fnl --file assets/lua/graph/nodes/agent-session.fnl --file assets/lua/graph/view/previews/agent-session.fnl --file assets/lua/tests/test-workflow-graph.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add assets/lua/graph/key-loaders.fnl assets/lua/graph/nodes/agent-session.fnl assets/lua/graph/view/previews/agent-session.fnl assets/lua/tests/test-workflow-graph.fnl
git commit -m "feat(agent): expose workflow-backed sessions in graph"
```

---

### Task 7: Documentation and Final Local Validation

**Files:**
- Create: `docs/dev/features/workflow-backed-agent-sessions.md`
- Modify: `docs/dev/features/workflows.md`
- Modify: `docs/dev/features/agent-runner-system.md`

**Interfaces:**
- Consumes: behavior from Tasks 1-6.
- Produces: developer-facing architecture and migration documentation.

- [ ] **Step 1: Document architecture**

Create `docs/dev/features/workflow-backed-agent-sessions.md` describing:

- one sidebar chat equals one long-lived workflow run;
- turns are wait/resume cycles;
- transcript source of truth is workflow events;
- sidebar runner API is compatibility facade;
- graph nodes expose the same workflow run/session state;
- migration is explicit and startup does not read old JSON sessions.

- [ ] **Step 2: Document event schema**

List `:agent-session-created`, `:agent-status-changed`, `:agent-item-appended`, `:agent-item-upserted`, and `:agent-item-updated`, including which fields are required for each.

- [ ] **Step 3: Document migration command**

Include:

```bash
./build/space -m tools.agent-session-migrate:main -- --base-dir <space-user-data-dir>
```

Document mapping output, archive directory behavior, idempotency, and failure semantics.

- [ ] **Step 4: Update existing docs**

Update workflow docs so they no longer say workflows do not replace `AgentRunner` in a way that contradicts the new workflow-backed architecture. Update agent runner docs so the current architecture points to workflow-backed sessions and event projection.

- [ ] **Step 5: Validate docs text**

Run:

```bash
rg "workflow-backed|agent-session-created|agent-session-migrate|wait/resume|long-lived workflow run" docs/dev/features assets/lua/llm/agent assets/lua/tools
git diff --check -- docs/dev/features/workflow-backed-agent-sessions.md docs/dev/features/workflows.md docs/dev/features/agent-runner-system.md
```

Expected: required terms present; no whitespace errors.

- [ ] **Step 6: Run final compile check first**

```bash
make fennel-check
```

Expected: PASS.

- [ ] **Step 7: Run constraints second**

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 8: Run focused Fennel tests third**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-workflow-events:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-code-executor:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-runner:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-workflow-template:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-workflow-runner:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-session-migration:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-panel:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
```

Expected: all PASS.

- [ ] **Step 9: Run broader suite because bootstrap/runtime behavior changed**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add docs/dev/features/workflow-backed-agent-sessions.md docs/dev/features/workflows.md docs/dev/features/agent-runner-system.md
git commit -m "docs(agent): document workflow-backed chat sessions"
```

---

## Final Review and Finishing Notes

After Task 7 passes, run a final whole-branch review through subagent-driven-development. Then use the finishing-a-development-branch skill. The branch must be clean, current with `origin/main`, validated with the required local checks, pushed, opened as a PR targeting `main`, and polled through merge queue until merged. Do not claim ready-to-merge until PR CI is green.
