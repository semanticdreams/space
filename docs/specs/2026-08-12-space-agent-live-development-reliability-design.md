# Space Agent Live Development Reliability Design

## Context

Internal Space agents use OpenCode plus Space MCP tools to inspect, edit, test,
and hot-reload live Space user units. Investigation of agent session
`agt-ses-e7853e76-05ce-4777-b6f7-bf48d5829eb1` showed that the agent's reasoning
was mostly useful, but the development loop was fragile: MCP endpoints became
stale across app restarts, review agents could not read bounded Space-owned
runtime/user-unit files, report artifacts under `/tmp` were not consistently
available, and `space_unit_reload` could drop the active activity renderer
without reactivating it.

The goal is to make internal Space agents reliable for live user-unit
development without over-engineering strict per-instance isolation. Multiple
Space instances may exist, but users are not expected to intentionally assign
two internal agents to the same unit at the same time.

## Goals

- Reconnect internal OpenCode sessions to the correct live Space MCP endpoint
  after ordinary Space restarts or MCP session churn.
- Give internal implementer/reviewer flows bounded access to Space-owned
  runtime artifacts and live user-unit source needed for evidence-based review.
- Replace ad-hoc `/tmp` report handoffs with session-scoped Space artifact
  directories.
- Make agent handoffs distinguish live validation from disk-only validation.
- Make `space_unit_reload` preserve or restore active activity/session state
  sufficiently for live development.
- Add lightweight instance sanity checks that reduce accidental wrong-instance
  work without blocking normal single-user multi-instance workflows.

## Non-goals

- Full hard isolation between every running Space instance.
- Locking user units globally or preventing two instances from opening the same
  unit.
- Fixing generated user-code bugs found during agent sessions unless a user
  explicitly asks for that generated code to be changed.
- Granting broad home-directory, credential, token, keyring, or secret access.

## Proposed approach

### 1. Session-scoped agent runtime context

Each Space agent session should persist a small runtime context alongside the
existing OpenCode session id:

- Space app instance id or launch id when available.
- MCP endpoint used when the session was created.
- OpenCode server/session id.
- Artifact directory path, e.g.
  `~/.local/share/space/agent-artifacts/<agent-session-id>/`.
- Last successful live MCP connection timestamp.

The context is advisory rather than a hard isolation boundary. When reconnecting,
the agent first tries the recorded endpoint. If that endpoint is unavailable, it
may discover and use the most recent live Space MCP endpoint, but it must perform
a lightweight sanity check before continuing.

### 2. Dynamic MCP endpoint discovery and reconnect

Space should expose enough information for internal OpenCode config generation
and reconnect logic to avoid stale hard-coded MCP URLs. A generated OpenCode MCP
config may still contain a concrete endpoint, but it should be refreshed before
new turns and after connection errors such as:

- `Session not found`
- `Unable to connect`
- socket closed / SSE disconnected

Reconnect behavior should be conservative:

1. Re-read the session runtime context.
2. Try the recorded endpoint.
3. If dead, find the latest live Space MCP endpoint from the running app/bridge
   registry or status source.
4. Run sanity checks such as expected unit exists, expected source path exists,
   and the Space MCP tool surface responds.
5. Retry the failed safe operation once when it was read-only or explicitly
   idempotent.
6. If sanity checks fail, report a live-connection blocker instead of silently
   continuing against an unrelated instance.

### 3. Bounded Space artifact and user-unit access

Internal Space agent OpenCode configs should permit bounded access to Space-owned
runtime development artifacts while continuing to deny sensitive files. The
allowed scope should cover:

- `~/.local/share/space/agent-sessions/**`
- `~/.local/share/space/agent-opencode/**`
- `~/.local/share/space/agent-approvals/**`
- `~/.local/share/space/agent-artifacts/**`
- `~/.local/share/space/code/**`
- `~/.cache/space/log/**`

The access policy must continue to avoid raw auth, token, secret, credential,
keyring, and similarly named files. Internal agents should prefer Space MCP unit
tools for live user-unit edits, but reviewers must be able to read the bounded
user-unit files needed to verify changes.

### 4. Session-scoped artifact handoffs

Implementers, reviewers, and supervisor code should use the session artifact
directory for report files instead of `/tmp/opencode` or unrelated `/tmp` paths.
Reports should include a consistent validation section:

- compile check evidence,
- constraints evidence or scoped non-applicability rationale,
- focused test evidence,
- live smoke evidence when live MCP was available,
- explicit `validation-mode: live` or `validation-mode: disk-only`.

If a report is disk-only, the supervisor should not describe the running app as
validated until a live reload/smoke step succeeds.

### 5. Live reload preserves active activity state

`space_unit_reload` should be upgraded from a pure unit snapshot/unload/load/
restore action into a live-development action. Before reload, it should capture
whether the reloaded unit owns or registered the active activity/session. After
reload, it should restore the unit state and, when appropriate, reactivate the
previous active activity, recreate the renderer/root, and wait or force one
update frame before reporting success.

The reload result should include structured evidence:

- active activity before and after,
- whether reactivation was attempted,
- whether the expected slot/root/renderer exists after reload,
- whether render batches or unit-specific smoke checks are present when
  available,
- any log errors seen during reload.

### 6. Lightweight instance sanity checks

Because multiple Space instances may exist, reconnect and live validation should
not simply use any random MCP endpoint. However, strict isolation is unnecessary.
The minimum sanity checks are:

- The expected Space MCP tool set is available.
- The expected user unit id or source path is visible when the task targets a
  user unit.
- The reconnect target is not obviously an unrelated workspace/session.

If checks pass, continue. If checks fail, report a clear blocker with the stale
endpoint, candidate endpoint, and failed check.

## Expected user experience

- After restarting Space, saying “continue” should let the internal agent
  reconnect without manual config repair.
- If a live edit is made through Space unit tools, the current app should reload
  the unit and keep/recreate the active activity instead of requiring an app
  restart.
- If the agent had to edit or validate disk-only, it should say so and avoid
  claiming live validation.
- Reviewers should be able to inspect the actual bounded user-unit files or the
  session artifact reports, not fail solely due missing external-directory
  access.

## Risks and mitigations

- **Wrong instance after reconnect:** mitigate with advisory session context and
  sanity checks rather than strict locks.
- **Over-broad filesystem access:** allow only Space-owned runtime/code/log
  scopes and keep secret-looking paths denied.
- **Reload side effects:** start with activity reactivation only when the unit
  was active before reload; return structured evidence so failures are visible.
- **Flaky live validation:** distinguish live and disk-only validation, and make
  reconnect retries explicit and bounded.

## Testing strategy

- Unit tests for generated internal OpenCode config and permission scopes.
- Unit tests for session artifact directory creation and report path selection.
- Unit tests for reconnect/status behavior where MCP endpoint changes.
- Unit tests for `UnitManager`/Space unit reload preserving unit snapshot while
  restoring active activity/session state.
- Focused tests for external unit MCP reload responses including before/after
  active activity evidence.
- Existing focused suites likely include:
  - `tests.test-agent-layer`
  - `tests.test-external-unit-mcp`
  - `tests.test-fennel-validation-mcp`
  - `tests.test-units`
  - `tests.test-activity-retention`

## Acceptance criteria

- Internal OpenCode config no longer leaves agents stuck on stale MCP endpoints
  after ordinary Space restarts when a live endpoint can be discovered.
- Internal agents and reviewers can read bounded Space runtime/user-unit files
  and session artifacts required for review, while sensitive-looking files remain
  denied.
- New report handoffs use `agent-artifacts/<agent-session-id>` and include live
  versus disk-only validation mode.
- `space_unit_reload` on an active user-unit activity reactivates/recreates the
  active renderer/session or reports structured evidence explaining why it could
  not.
- Focused Fennel compile, constraints, and relevant unit tests pass.
