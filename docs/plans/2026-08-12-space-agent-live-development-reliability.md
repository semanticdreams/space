# Space Agent Live Development Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make internal Space OpenCode agents more reliable for live user-unit development by adding bounded runtime artifact access, session-scoped context/artifacts, explicit live-vs-disk validation guidance, lightweight reconnect/status evidence, and active-activity-preserving reload results.

**Architecture:** Keep the first pass practical and localized: extend the existing internal OpenCode MCP bridge and SpaceAgent session lifecycle rather than introducing strict per-instance isolation. Store advisory runtime context in existing agent session JSON, generate bounded OpenCode config from Space-owned roots, and enrich existing MCP/unit reload paths with active activity reactivation evidence. Reconnect is bounded to refreshing the current internal bridge/provider and retrying safe session lookup once; wrong-instance prevention is advisory sanity evidence, not global locking.

**Tech Stack:** Space Fennel modules under `assets/lua`, Space MCP tool registry, OpenCode config JSON via `json-utils.fnl`, existing `AgentRunner`/`SpaceAgent` session persistence, existing `ExternalUnitService`/`UnitManager` reload path, project-native Fennel validation through `./build/space`.

## Global Constraints

- This pass implements practical setup improvements, not strict instance isolation.
- Multiple Space instances may exist, but users are not expected to intentionally assign two internal agents to the same unit at the same time.
- Do not grant broad home-directory, credential, token, keyring, or secret access.
- Internal agents should prefer Space MCP unit tools for live user-unit edits.
- Reviewers must be able to read bounded user-unit files needed to verify changes.
- Reports must include explicit `validation-mode: live` or `validation-mode: disk-only`.
- If a report is disk-only, the supervisor must not describe the running app as validated until a live reload/smoke step succeeds.
- Reconnect retries must be explicit and bounded.
- Fennel validation order is compile-check → constraints → focused tests.
- `make build` is a runtime/freshness prerequisite before commands that use `./build/space` when the binary may be missing or stale.
- On Fennel delimiter or parse errors, inspect the nearest enclosing form around the reported location, then simplify by extracting helper functions instead of guessing delimiters.

---

### Task 1: Internal OpenCode Bridge Runtime Config and Status

**Files:**
- Modify: `assets/lua/llm/agent/opencode-mcp-bridge.fnl`
- Modify: `assets/lua/main.fnl`
- Test: `assets/lua/tests/test-agent-layer.fnl`
- Docs: `docs/dev/notes/opencode-runtime-artifact-access.md`

**Interfaces:**
- Consumes: `AgentOpencodeMcpBridge.AgentOpencodeMcpBridge(opts)` with existing required `:tools` and `:data-dir`.
- Produces:
  - `AgentOpencodeMcpBridge(opts)` accepts optional `:space-data-dir string`, `:space-cache-dir string`, `:code-dir string`, and `:artifact-root string`.
  - Bridge status returns `{:started? boolean :host string :port number|nil :url string|nil :config-root string|nil :config-path string|nil :artifact-root string|nil :allowed-roots table}`.
  - Bridge object exposes `refresh-config! self -> table` and `config-path self -> string|nil`.
  - Generated `opencode.json` keeps Space MCP server enabled and allows only bounded Space-owned read/list/glob/grep/external-directory roots while denying secret-looking paths after allows.

- [ ] **Step 1: Add failing tests for bounded generated config.**

  In `assets/lua/tests/test-agent-layer.fnl`, extend `test-opencode-mcp-bridge-starts-and-writes-config` so it constructs the bridge with Space root options and verifies the generated config includes the allowed roots and secret denies.

  Expected test assertions:
  - `config.mcp.space.url == status.url`.
  - Native write/edit/bash/task/web/search/lsp/skill/question stay `"deny"`.
  - Read/list/glob/grep are not broadly denied; they contain bounded allow entries for the Space-owned roots passed to the bridge.
  - `external_directory` denies `"*"` and then allows only:
    - `<space-data-dir>/agent-sessions/**`
    - `<space-data-dir>/agent-opencode/**`
    - `<space-data-dir>/agent-approvals/**`
    - `<space-data-dir>/agent-artifacts/**`
    - `<space-data-dir>/code/**`
    - `<space-cache-dir>/log/**`
  - Secret-looking paths under those roots are denied after allow rules for `*auth*`, `*token*`, `*secret*`, `*credential*`, and `*keyring*`.

- [ ] **Step 2: Run the focused test and verify it fails.**

  Prerequisite if `./build/space` is missing or stale: `make build` with timeout 14400000.

  Run:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/agent/opencode-mcp-bridge.fnl --file assets/lua/main.fnl --file assets/lua/tests/test-agent-layer.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-layer:main
  ```

  Expected focused test failure before implementation: bridge config assertions fail because current generated config denies all native tools and has no bounded root allow entries.

- [ ] **Step 3: Write bounded config helpers in `opencode-mcp-bridge.fnl`.**

  Add focused helper functions before `AgentOpencodeMcpBridge`:
  - `normalize-root [path] -> string|nil`: returns `nil` for nil/empty values; strips one trailing `/` except root `/`.
  - `join-pattern [root suffix] -> string`: joins normalized root and suffix without double slashes.
  - `space-owned-roots [opts data-dir] -> table`: derives roots from `opts.space-data-dir`, `opts.space-cache-dir`, `opts.code-dir`, and `opts.artifact-root`; default `artifact-root` is `<space-data-dir>/agent-artifacts` when `space-data-dir` exists.
  - `secret-deny-patterns [allowed-patterns] -> table`: appends deny patterns for `*auth*`, `*token*`, `*secret*`, `*credential*`, and `*keyring*` under every allowed pattern root.
  - `native-tool-permissions [allowed-patterns] -> table`: returns a table where read/list/glob/grep and external_directory are pattern maps with `"*": "deny"`, each bounded pattern as `"allow"`, and secret-looking patterns as `"deny"` after the allows; write/edit/bash/task/todowrite/webfetch/websearch/lsp/skill/question/invalid remain `"deny"`.

  Keep this localized and production-ready because the bridge already owns isolated OpenCode config generation; no new cross-bridge abstraction is needed in this pass.

- [ ] **Step 4: Wire `write-opencode-config!` and bridge status to bounded roots.**

  Change `write-opencode-config!` to accept `allowed-patterns` and write the new permission table. Keep `JsonUtils.write-json!` for atomic writes. In `start`, compute roots once, ensure `artifact-root` exists, and pass allowed patterns into config generation. Add `refresh-config!` to rewrite the current config with the current URL and existing allowed patterns; error if called before `start`.

- [ ] **Step 5: Pass Space roots from `main.fnl` bootstrap.**

  In the `AgentOpencodeMcpBridge.AgentOpencodeMcpBridge` call in `assets/lua/main.fnl`, pass:
  - `:space-data-dir app.user-data-dir`
  - `:space-cache-dir (appdirs.user-cache-dir "space")`
  - `:code-dir app.code-dir`
  - `:artifact-root (fs.join-path app.user-data-dir "agent-artifacts")`

- [ ] **Step 6: Update runtime artifact access docs.**

  In `docs/dev/notes/opencode-runtime-artifact-access.md`, add `agent-artifacts` to the internal runtime artifact list and document that generated internal OpenCode configs allow bounded read/list/glob/grep/external-directory access only to the six Space-owned runtime/code/log scopes while denying secret-looking paths.

- [ ] **Step 7: Validate Task 1.**

  Run in order:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/agent/opencode-mcp-bridge.fnl --file assets/lua/main.fnl --file assets/lua/tests/test-agent-layer.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-layer:main
  ```

  Acceptance criteria:
  - Generated internal config has bounded allow entries for Space runtime/user-unit/artifact/log roots.
  - Secret-looking paths are denied after bounded allows.
  - Existing MCP server URL and isolated config behavior remain intact.
  - No broad home-directory or credential access is introduced.

- [ ] **Step 8: Commit Task 1.**

  ```bash
  git add assets/lua/llm/agent/opencode-mcp-bridge.fnl assets/lua/main.fnl assets/lua/tests/test-agent-layer.fnl docs/dev/notes/opencode-runtime-artifact-access.md
  git commit -m "feat(agent): bound internal opencode runtime access"
  ```

---

### Task 2: Session-Scoped Artifact Context and Validation Guidance

**Files:**
- Modify: `assets/lua/llm/agent/runner.fnl`
- Modify: `assets/lua/llm/agent/builtins/space-agent.fnl`
- Modify: `assets/lua/main.fnl`
- Test: `assets/lua/tests/test-agent-layer.fnl`
- Docs: `docs/dev/features/opencode-agent-workflow.md`

**Interfaces:**
- Consumes:
  - `AgentRunner {:data-dir string :registry table :deps table}`.
  - Bridge `status -> table` from Task 1.
- Produces:
  - `ctx.artifacts` table in agent run context: `{:root string :session-dir string :report-path string}`.
  - `session.data.runtime-context` persisted table: `{:agent-session-id string :artifact-dir string :report-path string :mcp-endpoint string|nil :opencode-server-url string|nil :opencode-session-id string|nil :last-live-connection-at number|nil :validation-mode string}`.
  - `SpaceAgent` system prompt includes artifact path and validation mode guidance.

- [ ] **Step 1: Add failing tests for artifact context creation.**

  In `assets/lua/tests/test-agent-layer.fnl`, add a runner-focused test that creates an `AgentRunner` with `deps.artifact-root`, a stub registry/agent that captures `ctx.artifacts`, runs a turn, and asserts:
  - `ctx.artifacts.session-dir == <artifact-root>/<session-id>`.
  - `ctx.artifacts.report-path == <artifact-root>/<session-id>/report.md`.
  - The directory exists on disk.
  - The persisted session has `session.data.runtime-context.artifact-dir`, `report-path`, `agent-session-id`, and `validation-mode == "disk-only"` before live evidence is recorded.

- [ ] **Step 2: Add failing tests for SpaceAgent prompt guidance.**

  In the existing SpaceAgent mock-provider tests in `assets/lua/tests/test-agent-layer.fnl`, assert the prompt system text includes:
  - the exact artifact report path from `ctx.artifacts.report-path`,
  - `validation-mode: live`,
  - `validation-mode: disk-only`,
  - `compile check`, `constraints`, and `focused test`,
  - a warning not to claim live validation after disk-only validation.

- [ ] **Step 3: Run the focused test and verify it fails.**

  Prerequisite if `./build/space` is missing or stale: `make build` with timeout 14400000.

  Run:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/agent/runner.fnl --file assets/lua/llm/agent/builtins/space-agent.fnl --file assets/lua/main.fnl --file assets/lua/tests/test-agent-layer.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-layer:main
  ```

- [ ] **Step 4: Implement artifact context in `AgentRunner`.**

  In `AgentRunner`:
  - Accept optional `deps.artifact-root`.
  - Add `ensure-artifact-context! [session] -> table` that creates `<artifact-root>/<session.id>` when `deps.artifact-root` exists, stores `runtime-context` in `session.data`, and returns `{:root artifact-root :session-dir session-artifact-dir :report-path report-path}`.
  - If `deps.artifact-root` is nil, derive a default sibling root from `data-dir`: parent of `agent-sessions` plus `agent-artifacts` when possible; otherwise `<data-dir>/agent-artifacts`.
  - Preserve any existing `runtime-context.last-live-connection-at` and `runtime-context.opencode-session-id` when updating artifact paths.

- [ ] **Step 5: Include runtime context in `build-context`.**

  In `AgentRunner.build-context`, add:
  - `:artifacts (ensure-artifact-context! session)`
  - `:runtime-context session.data.runtime-context`

  Save the session after creating/updating runtime context before the agent runs.

- [ ] **Step 6: Pass artifact root from `main.fnl`.**

  In `AgentRunner.AgentRunner` construction in `assets/lua/main.fnl`, add `:artifact-root (fs.join-path app.user-data-dir "agent-artifacts")` inside `:deps`.

- [ ] **Step 7: Add SpaceAgent prompt guidance block.**

  In `assets/lua/llm/agent/builtins/space-agent.fnl`, add a small `format-runtime-guidance [ctx] -> string` helper and include it in the system prompt blocks. It must tell agents:
  - write implementer/reviewer/supervisor reports under `ctx.artifacts.session-dir`,
  - prefer `ctx.artifacts.report-path` for report handoff,
  - include a validation section with compile check, constraints or scoped non-applicability, focused tests, and live smoke evidence when available,
  - state `validation-mode: live` only after live MCP reload/smoke succeeds,
  - state `validation-mode: disk-only` when validation did not use the running app,
  - do not claim the running app was validated from disk-only evidence.

- [ ] **Step 8: Update docs for artifact handoffs.**

  In `docs/dev/features/opencode-agent-workflow.md`, add a focused section describing internal Space agent artifact handoffs:
  - reports live under `~/.local/share/space/agent-artifacts/<agent-session-id>/`,
  - report validation sections must include `validation-mode: live` or `validation-mode: disk-only`,
  - disk-only reports are not live app validation.

- [ ] **Step 9: Validate Task 2.**

  Run in order:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/agent/runner.fnl --file assets/lua/llm/agent/builtins/space-agent.fnl --file assets/lua/main.fnl --file assets/lua/tests/test-agent-layer.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-layer:main
  ```

  Acceptance criteria:
  - Every internal agent session has a session-scoped artifact directory and `report.md` path in persisted `runtime-context`.
  - SpaceAgent prompts tell implementers/reviewers how to report live-vs-disk validation.
  - Existing session CRUD and SpaceAgent behavior still pass.

- [ ] **Step 10: Commit Task 2.**

  ```bash
  git add assets/lua/llm/agent/runner.fnl assets/lua/llm/agent/builtins/space-agent.fnl assets/lua/main.fnl assets/lua/tests/test-agent-layer.fnl docs/dev/features/opencode-agent-workflow.md
  git commit -m "feat(agent): add session artifact validation context"
  ```

---

### Task 3: Lightweight Reconnect and MCP Sanity Evidence

**Files:**
- Modify: `assets/lua/llm/agent/builtins/space-agent.fnl`
- Modify: `assets/lua/llm/agent/opencode-mcp-bridge.fnl`
- Modify: `assets/lua/main.fnl`
- Test: `assets/lua/tests/test-agent-layer.fnl`
- Docs: `docs/dev/features/opencode-agent-workflow.md`

**Interfaces:**
- Consumes:
  - `ctx.runtime-context` from Task 2.
  - `ctx.providers.opencode-factory` existing provider factory.
  - Optional `ctx.providers.refresh-opencode` function introduced in this task.
  - Bridge `refresh-config! self -> table` from Task 1.
- Produces:
  - `ctx.providers.refresh-opencode -> provider`: closes old provider if possible, refreshes bridge config, creates and stores a new provider.
  - `SpaceAgent` retries only `opencode.session.get` once on stale-session/connect-style failures, then clears stale OpenCode session id and creates a new one.
  - `session.data.runtime-context` updates `mcp-endpoint`, `opencode-server-url`, `opencode-session-id`, `last-live-connection-at`, and `validation-mode`.

- [ ] **Step 1: Add failing SpaceAgent reconnect test.**

  In `assets/lua/tests/test-agent-layer.fnl`, add a mock provider/factory test where:
  - `session.data.opencode-session-id` is `"stale-oc-session"`.
  - First provider `session.get` returns `{ok false :error "Session not found"}`.
  - `ctx.providers.refresh-opencode` returns a second provider.
  - Second provider `session.create` succeeds with id `"fresh-oc-session"`.
  - Prompt succeeds and messages return an assistant response.
  - Assertions confirm `refresh-opencode` was called exactly once, `session.data.opencode-session-id == "fresh-oc-session"`, and `session.data.runtime-context.validation-mode == "live"`.

- [ ] **Step 2: Add failing bridge/provider refresh test.**

  In `assets/lua/tests/test-agent-layer.fnl`, add a bridge-adjacent test for a provider table shaped like `app.agent-providers`:
  - old provider has `close` that records it was closed,
  - bridge mock has `refresh-config!` and `opencode-env`,
  - factory replacement stores a new provider,
  - assertions confirm old provider is closed, config refresh is called, and returned provider replaces `providers.opencode`.

- [ ] **Step 3: Run the focused test and verify it fails.**

  Prerequisite if `./build/space` is missing or stale: `make build` with timeout 14400000.

  Run:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/agent/builtins/space-agent.fnl --file assets/lua/llm/agent/opencode-mcp-bridge.fnl --file assets/lua/main.fnl --file assets/lua/tests/test-agent-layer.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-layer:main
  ```

- [ ] **Step 4: Implement stale connection classification in SpaceAgent.**

  In `space-agent.fnl`, add:
  - `stale-opencode-error? [message] -> boolean` matching `"Session not found"`, `"Unable to connect"`, `"socket closed"`, `"SSE disconnected"`, and `"connection refused"` case-insensitively.
  - `refresh-opencode-provider [ctx] -> provider|nil` that calls `ctx.providers.refresh-opencode` when available; otherwise returns nil.
  - `record-live-context! [session ctx opencode-session-id] -> nil` that writes `runtime-context.opencode-session-id`, `mcp-endpoint`, `opencode-server-url`, `last-live-connection-at`, and `validation-mode "live"` using provider/bridge status when available.

- [ ] **Step 5: Retry only safe session lookup once.**

  Update `resolve-session` in `space-agent.fnl`:
  - When existing `opencode-session-id` lookup fails with a stale connection error, clear `session.data.opencode-session-id`, call `refresh-opencode-provider`, and then `create-session`.
  - Do not retry `session.prompt`; if prompt fails, fail explicitly with the OpenCode error.
  - If refresh is unavailable, create a new session through the current provider and keep the failure visible in `runtime-context.last-reconnect-error`.

- [ ] **Step 6: Record live runtime context on successful session create/get.**

  Call `record-live-context!` before `send-prompt` when `session.get` or `session.create` returns a valid session id. Preserve session-scoped artifact paths from Task 2.

- [ ] **Step 7: Expose provider refresh from `main.fnl` bootstrap.**

  In `assets/lua/main.fnl`, add `app.agent-providers.refresh-opencode` alongside `:opencode-factory`. It must:
  - close and clear existing `app.agent-providers.opencode` if present,
  - call `app.agent-opencode-mcp-bridge:refresh-config!`,
  - create a new `OpencodeSdk.Opencode` using the bridge env,
  - store and return it.

- [ ] **Step 8: Document reconnect behavior.**

  In `docs/dev/features/opencode-agent-workflow.md`, document that internal SpaceAgent reconnect is advisory and bounded: it refreshes bridge config/provider on stale session/connect errors, retries safe session lookup/session creation only once, and reports blockers instead of claiming live validation if a live session cannot be established.

- [ ] **Step 9: Validate Task 3.**

  Run in order:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/agent/builtins/space-agent.fnl --file assets/lua/llm/agent/opencode-mcp-bridge.fnl --file assets/lua/main.fnl --file assets/lua/tests/test-agent-layer.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-layer:main
  ```

  Acceptance criteria:
  - Stale OpenCode session lookup triggers one provider/config refresh and creates a fresh OpenCode session.
  - Prompt failures are not blindly retried.
  - Runtime context records live connection evidence after a successful OpenCode session connection.
  - Reconnect remains advisory and bounded.

- [ ] **Step 10: Commit Task 3.**

  ```bash
  git add assets/lua/llm/agent/builtins/space-agent.fnl assets/lua/llm/agent/opencode-mcp-bridge.fnl assets/lua/main.fnl assets/lua/tests/test-agent-layer.fnl docs/dev/features/opencode-agent-workflow.md
  git commit -m "feat(agent): refresh stale opencode live sessions"
  ```

---

### Task 4: Active Activity Reload Reactivation Evidence

**Files:**
- Modify: `assets/lua/activities.fnl`
- Modify: `assets/lua/unit-manager.fnl`
- Modify: `assets/lua/llm/external-unit-mcp/service.fnl`
- Modify: `assets/lua/llm/external-unit-mcp/tools.fnl`
- Test: `assets/lua/tests/test-external-unit-mcp.fnl`
- Test: `assets/lua/tests/test-activity-retention.fnl`
- Docs: `docs/dev/reloadable-units.md`
- Docs: `docs/dev/notes/external-unit-mcp.md`

**Interfaces:**
- Consumes:
  - `Activities.active-activity-id -> string|nil`.
  - `Activities.activate-activity activity-id -> session|nil`.
  - `UnitManager.reload-unit self id ctx -> existing reload behavior`.
- Produces:
  - `Activities.activity-status [] -> {:active-activity-id string|nil :registered? boolean :has-active-session? boolean}`.
  - `Activities.reactivate-active-activity [activity-id] -> {:attempted boolean :active-activity-before string|nil :active-activity-after string|nil :registered-after? boolean :has-active-session-after? boolean :reactivated boolean :error string|nil}`.
  - `UnitManager.reload-unit self id ctx -> reload-result`, where `reload-result` includes `:unit-id`, `:reloaded true`, and optional `:activity` evidence.
  - `ExternalUnitService:reload args -> structured reload evidence` including activity before/after and reactivation attempt.

- [ ] **Step 1: Add failing activity reactivation tests.**

  In `assets/lua/tests/test-activity-retention.fnl`, add a focused test that:
  - snapshots app fields and resets `app.activity-registry`.
  - registers an activity `"live-dev"` with an activation counter and a session table.
  - activates `"live-dev"`.
  - unregisters and re-registers `"live-dev"` to simulate unit reload replacing the activity spec.
  - calls `Activities.reactivate-active-activity "live-dev"`.
  - asserts evidence shows `attempted true`, `reactivated true`, `active-activity-before "live-dev"`, `active-activity-after "live-dev"`, `registered-after? true`, and the activation counter increased.

- [ ] **Step 2: Add failing external unit reload evidence tests.**

  In `assets/lua/tests/test-external-unit-mcp.fnl`, add a test using a filesystem `ModuleUnit` whose `init` registers an activity with the same id as the unit or a declared activity id in app state. The test should:
  - load/activate the activity,
  - call `service:reload {:unit_id "user-live-dev"}`,
  - assert returned JSON/table includes `unit-id`, `reloaded true`, `activity.active-activity-before`, `activity.active-activity-after`, `activity.reactivation-attempted`, `activity.registered-after?`, and `activity.has-active-session-after?`.

- [ ] **Step 3: Run focused tests and verify they fail.**

  Prerequisite if `./build/space` is missing or stale: `make build` with timeout 14400000.

  Run:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/activities.fnl --file assets/lua/unit-manager.fnl --file assets/lua/llm/external-unit-mcp/service.fnl --file assets/lua/llm/external-unit-mcp/tools.fnl --file assets/lua/tests/test-external-unit-mcp.fnl --file assets/lua/tests/test-activity-retention.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-retention:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-external-unit-mcp:main
  ```

- [ ] **Step 4: Add activity status/reactivation helpers.**

  In `activities.fnl`, implement:
  - `activity-status []` using `ensure-registry`, returning active id, whether that id is registered, and whether an active session exists.
  - `reactivate-active-activity [activity-id]` that only attempts reactivation when `activity-id` is non-nil, registered after reload, and matches the active id before reload. It should call `activate-activity activity-id` and return structured evidence. It must catch activation errors and include `:error` instead of silently succeeding.

- [ ] **Step 5: Update `UnitManager.reload-unit` to capture activity evidence.**

  In `unit-manager.fnl`, require `activities` lazily inside `reload-unit` only when needed. Before reload, capture `active-before` via `Activities.active-activity-id`. After `unit:reload`, if there was an active activity before reload, call `Activities.reactivate-active-activity active-before`. Return:
  ```fennel
  {:unit-id id
   :reloaded true
   :activity <reactivation-evidence-or-status>}
  ```
  Preserve existing behavior that reload errors throw; do not convert failed unit reload into success.

- [ ] **Step 6: Thread reload evidence through external unit service write paths.**

  In `ExternalUnitService`:
  - In `reload`, return the `mgr:reload-unit` result merged with `:unit-id unit.id` and `:reloaded true`.
  - In `apply-patch` and `create-source`, preserve existing rollback behavior but include `:reload-result reload-result` and `:activity reload-result.activity` on successful reload responses.
  - Keep source hashes and `created` fields unchanged.

- [ ] **Step 7: Update MCP tool description.**

  In `external-unit-mcp/tools.fnl`, change `space_unit_reload` description to state it returns active activity before/after and reactivation evidence.

- [ ] **Step 8: Update reload docs.**

  In `docs/dev/reloadable-units.md`, document that `UnitManager.reload-unit` now returns structured reload evidence and attempts active activity reactivation only when an activity was active before reload.

  In `docs/dev/notes/external-unit-mcp.md`, document the `space_unit_reload` response fields:
  - `unit-id`
  - `reloaded`
  - `activity.active-activity-before`
  - `activity.active-activity-after`
  - `activity.reactivation-attempted`
  - `activity.registered-after?`
  - `activity.has-active-session-after?`
  - `activity.error` when reactivation fails.

- [ ] **Step 9: Validate Task 4.**

  Run in order:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/activities.fnl --file assets/lua/unit-manager.fnl --file assets/lua/llm/external-unit-mcp/service.fnl --file assets/lua/llm/external-unit-mcp/tools.fnl --file assets/lua/tests/test-external-unit-mcp.fnl --file assets/lua/tests/test-activity-retention.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-retention:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-external-unit-mcp:main
  ```

  Acceptance criteria:
  - Reload on an active activity attempts reactivation after unit reload.
  - Reload results include active activity before/after and whether a session exists after reload.
  - Failed unit reload still fails loudly and does not report success.
  - External MCP reload responses expose structured evidence for reviewers.

- [ ] **Step 10: Commit Task 4.**

  ```bash
  git add assets/lua/activities.fnl assets/lua/unit-manager.fnl assets/lua/llm/external-unit-mcp/service.fnl assets/lua/llm/external-unit-mcp/tools.fnl assets/lua/tests/test-external-unit-mcp.fnl assets/lua/tests/test-activity-retention.fnl docs/dev/reloadable-units.md docs/dev/notes/external-unit-mcp.md
  git commit -m "feat(units): report active activity reload evidence"
  ```

---

### Task 5: Final Focused Integration Validation

**Files:**
- Validate: `assets/lua/llm/agent/opencode-mcp-bridge.fnl`
- Validate: `assets/lua/llm/agent/runner.fnl`
- Validate: `assets/lua/llm/agent/builtins/space-agent.fnl`
- Validate: `assets/lua/llm/external-unit-mcp/service.fnl`
- Validate: `assets/lua/llm/external-unit-mcp/tools.fnl`
- Validate: `assets/lua/unit-manager.fnl`
- Validate: `assets/lua/activities.fnl`
- Validate: `assets/lua/main.fnl`
- Validate: `assets/lua/tests/test-agent-layer.fnl`
- Validate: `assets/lua/tests/test-external-unit-mcp.fnl`
- Validate: `assets/lua/tests/test-fennel-validation-mcp.fnl`
- Validate: `assets/lua/tests/test-units.fnl`
- Validate: `assets/lua/tests/test-activity-retention.fnl`
- Validate: docs changed under `docs/dev/**`

**Interfaces:**
- Consumes: all previous task outputs.
- Produces: validation evidence that the first implementation pass satisfies the spec acceptance criteria.

- [ ] **Step 1: Ensure runtime is fresh.**

  Because validation invokes `./build/space`, run this if the binary is missing or may be stale:
  ```bash
  make build
  ```
  Use timeout 14400000.

- [ ] **Step 2: Run touched-file Fennel compile check first.**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/agent/opencode-mcp-bridge.fnl --file assets/lua/llm/agent/runner.fnl --file assets/lua/llm/agent/builtins/space-agent.fnl --file assets/lua/llm/external-unit-mcp/service.fnl --file assets/lua/llm/external-unit-mcp/tools.fnl --file assets/lua/unit-manager.fnl --file assets/lua/activities.fnl --file assets/lua/main.fnl --file assets/lua/tests/test-agent-layer.fnl --file assets/lua/tests/test-external-unit-mcp.fnl --file assets/lua/tests/test-activity-retention.fnl
  ```

- [ ] **Step 3: Run constraints second.**

  ```bash
  make constraints
  ```

- [ ] **Step 4: Run focused Fennel tests third.**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-layer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-external-unit-mcp:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-validation-mcp:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-units:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-activity-retention:main
  ```

- [ ] **Step 5: Run broader local suite only if focused tests expose cross-subsystem risk or reviewer requires it.**

  The touched surface spans Fennel agent session/bootstrap/reload behavior, but focused suites directly cover the behavior. If a reviewer requires broader local coverage, run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 6: Review docs and acceptance criteria.**

  Check the diff for:
  - `docs/dev/notes/opencode-runtime-artifact-access.md` documents bounded internal runtime/artifact/log/code access and secret denies.
  - `docs/dev/features/opencode-agent-workflow.md` documents artifact reports, validation modes, and reconnect limits.
  - `docs/dev/reloadable-units.md` documents reload evidence.
  - `docs/dev/notes/external-unit-mcp.md` documents `space_unit_reload` activity evidence.

- [ ] **Step 7: Commit final validation/doc fixups if any were needed.**

  If final validation required small follow-up fixes, commit only the exact files
  changed by those fixes. For this plan, the expected file set is:
  `assets/lua/llm/agent/opencode-mcp-bridge.fnl`,
  `assets/lua/llm/agent/runner.fnl`,
  `assets/lua/llm/agent/builtins/space-agent.fnl`,
  `assets/lua/llm/external-unit-mcp/service.fnl`,
  `assets/lua/llm/external-unit-mcp/tools.fnl`,
  `assets/lua/unit-manager.fnl`, `assets/lua/activities.fnl`,
  `assets/lua/main.fnl`, the focused test files, and the docs named in Step 6.
  Stage only the files actually changed:
  ```bash
  git add assets/lua/llm/agent/opencode-mcp-bridge.fnl assets/lua/llm/agent/runner.fnl assets/lua/llm/agent/builtins/space-agent.fnl assets/lua/llm/external-unit-mcp/service.fnl assets/lua/llm/external-unit-mcp/tools.fnl assets/lua/unit-manager.fnl assets/lua/activities.fnl assets/lua/main.fnl assets/lua/tests/test-agent-layer.fnl assets/lua/tests/test-external-unit-mcp.fnl assets/lua/tests/test-activity-retention.fnl docs/dev/notes/opencode-runtime-artifact-access.md docs/dev/features/opencode-agent-workflow.md docs/dev/reloadable-units.md docs/dev/notes/external-unit-mcp.md
  git commit -m "fix(agent): stabilize live development reliability"
  ```

- [ ] **Step 8: Record integration gate.**

  PR CI is the full integration gate. Do not claim ready-to-merge until PR CI is green.

  Final acceptance criteria:
  - Internal OpenCode config includes bounded access to Space-owned runtime/user-unit/artifact/log roots while sensitive-looking paths remain denied.
  - New internal sessions persist runtime context and use `agent-artifacts/<agent-session-id>/report.md`.
  - Agent prompts and docs require explicit live-vs-disk validation reporting.
  - Stale OpenCode session lookup refreshes provider/config once and recovers when a live endpoint is available.
  - `space_unit_reload` returns structured activity reactivation evidence and preserves/reactivates active activity enough for live development.
  - Focused Fennel compile, constraints, and relevant unit tests pass.

## Out of Scope

- Full hard isolation between every running Space instance.
- Global user-unit locks or prevention of two instances opening/editing the same unit.
- Broad home-directory, credential, token, keyring, or secret access.
- Automatic repair of arbitrary generated user-code bugs found during agent sessions.
- Retrying non-idempotent OpenCode prompt/tool operations after connection errors.
- New cross-bridge abstraction shared by internal, external-unit, and Fennel-validation MCP bridges.
- End-to-end live GUI automation beyond the focused reload/session tests and PR CI integration gate.
