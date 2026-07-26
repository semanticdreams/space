# External Unit Development MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a separate Space-owned MCP surface that lets external OpenCode sessions resolve, inspect, edit, test, reload, and review user units through loader-aware Space tools instead of direct filesystem edits.

**Architecture:** Add a new external-unit MCP subsystem under `assets/lua/llm/external-unit-mcp/` with a loader-neutral service facade over today’s filesystem-backed `UnitManager` units. Register the external tools into their own `ToolRegistry` and expose them through a separate loopback MCP bridge and standalone tool entrypoint; do not replace or reuse the internal Space agent MCP bridge. Current filesystem-backed units are adapted into loader-neutral handle/source shapes, leaving database/remote loaders as future extensions.

**Tech Stack:** Fennel/Lua modules, existing `mcp/tool-registry`, `mcp/server-http`, `http_server`, `UnitManager`, `Units.ModuleUnit`, `repo/sha256`, `llm/tools/apply-patch`, `process`, `json`, `logging`, `callbacks.run-loop`.

## Global Constraints

- Do not add Space-specific behavior to global `~/.config/opencode`.
- OpenCode should never infer a user-unit path from the platform's Space user-data code directory.
- The external surface exposes high-level unit operations, not raw paths.
- User units commonly live under Space's local user code directory, but that is an implementation detail, not the contract.
- Future units may be backed by a local filesystem directory, database records, remote hosts, generated stores, or other loaders.
- External unit development should not grant broad native filesystem access.
- Unit reads and writes go through Space MCP tools.
- Native OpenCode filesystem access is fallback-only and requires explicit human approval plus a Space-reported local filesystem source handle.
- The MCP server binds to loopback by default.
- Risk labels remain explicit for filesystem writes, shell/test execution, destructive operations, and remote actions.
- Tool responses must fail loudly when a loader lacks a requested capability.
- Patches should include stale-content protection where the loader can provide hashes or versions.
- Out of scope: Changing global `~/.config/opencode` to include Space-specific unit guidance.
- Out of scope: Replacing the existing internal agent MCP bridge.
- Out of scope: Implementing every future loader type.
- Out of scope: Building a general repository workbench for user units.
- Out of scope: Allowing non-loopback MCP binds by default.

---

### Task 1: Loader-Neutral Unit Discovery, Handles, Inspect, and Resolve

**Files:**
- Create: `assets/lua/llm/external-unit-mcp/service.fnl`
- Create: `assets/lua/tests/test-external-unit-mcp.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: existing `UnitManager`, `Units.Unit`, `Units.ModuleUnit`, `fs`, `json`, `repo/sha256`
- Produces:
  - `ExternalUnitService.ExternalUnitService(opts: {:app table}) -> service`
  - `service:list(args: table) -> table`
  - `service:inspect(args: {:unit_id string}) -> table`
  - `service:resolve(args: {:description string, :limit number?}) -> table`
  - `service:unit-handle(unit: table) -> table`
  - Handle shape:
    - `:unit-id string`
    - `:loader string`
    - `:source-handle table`
    - `:edit-capabilities table`
    - `:test-capabilities table`
    - `:commit-capability string`
  - Source artifact shape:
    - `:source-id string`
    - `:kind string`
    - `:primary boolean`
    - `:size number`
    - `:hash string`

- [ ] **Step 1: Add focused failing tests for list, inspect, and vague resolve**

Add `assets/lua/tests/test-external-unit-mcp.fnl` with helpers that create a temporary `app.unit-manager`, register filesystem-backed units, and assert loader-neutral output. Include tests named:

- `external-unit-mcp: list returns loader-neutral handles`
- `external-unit-mcp: inspect reports source artifacts and lifecycle exports`
- `external-unit-mcp: resolve ranks vague description candidates`

Expected assertions:
- User filesystem units report `loader == "filesystem"`.
- Built-in/non-filesystem units report `loader == "unknown"` and no edit capabilities.
- Handles include `unit-id`, `source-handle`, `edit-capabilities`, `test-capabilities`, and `commit-capability`.
- Inspect includes lifecycle exports `init`, `drop`, `snapshot`, `restore` defaults.
- Resolve accepts a description such as `"bubble overlay unit"` and returns the matching unit candidate without requiring an exact unit id.

- [ ] **Step 2: Register the new test module in `assets/lua/tests/fast.fnl`**

Add `:tests.test-external-unit-mcp` near the other MCP/agent/unit tests so `make test` includes it.

- [ ] **Step 3: Run the focused test and confirm it fails because the service module does not exist**

Run:

```bash
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-external-unit-mcp:main
```

Expected: FAIL with a missing module or missing `ExternalUnitService` error.

- [ ] **Step 4: Implement `assets/lua/llm/external-unit-mcp/service.fnl` discovery/inspect/resolve**

Implement only read-only discovery in this task:
- Require `:unit-manager` through `opts.app.unit-manager`; assert loudly if absent.
- Classify current units as:
  - `"filesystem"` when `unit.source == :user` and at least one owned path exists.
  - `"unknown"` otherwise.
- For filesystem units, derive source artifacts from existing owned paths without making `app.code-dir` part of the external contract.
- Compute `sha256:<hex>` with `repo/sha256.hash-file` for file artifacts.
- Return deterministic ordering from `list` and `resolve`.
- `resolve` should score simple lowercase token matches against unit id, module name, artifact ids, and owned path basenames; return candidates with `:confidence` and `:evidence`.

- [ ] **Step 5: Re-run the focused test until Task 1 tests pass**

Run the same focused command from Step 3.

Expected: PASS.

---

### Task 2: Loader-Neutral Source Read, Patch, Create, and Reload Operations

**Files:**
- Modify: `assets/lua/llm/external-unit-mcp/service.fnl`
- Modify: `assets/lua/tests/test-external-unit-mcp.fnl`

**Interfaces:**
- Consumes:
  - Task 1 `ExternalUnitService`
  - existing `llm/tools/apply-patch.call(args, ctx)`
  - existing `repo/sha256.hash-file(path)`
  - existing `app.unit-manager:reload-unit(unit-id, ctx)`
- Produces:
  - `service:read-source(args: {:unit_id string, :source_id string}) -> table`
  - `service:apply-patch(args: {:unit_id string, :source_id string, :patch string?, :old string?, :new string?, :expected_hash string?}) -> table`
  - `service:create-source(args: {:unit_id string, :source_id string, :source string, :expected_absent boolean?}) -> table`
  - `service:reload(args: {:unit_id string}) -> table`

- [ ] **Step 1: Add failing tests for source read and exact patch with stale hash protection**

Extend `test-external-unit-mcp.fnl` with tests named:

- `external-unit-mcp: read-source returns content and hash`
- `external-unit-mcp: apply-patch exact replacement reloads unit`
- `external-unit-mcp: apply-patch rejects stale expected hash`

Expected assertions:
- `read-source` returns `unit-id`, `source-id`, `content`, and `hash`.
- `apply-patch` with `old`/`new` modifies only one exact match, reloads the unit, and returns `reloaded == true`.
- `apply-patch` with an incorrect `expected_hash` fails before writing and leaves source unchanged.

- [ ] **Step 2: Add failing tests for unified patch and source creation capability**

Add tests named:

- `external-unit-mcp: apply-patch unified diff reloads unit`
- `external-unit-mcp: create-source creates directory-unit artifact and reloads`
- `external-unit-mcp: create-source fails loudly for flat unit without create capability`

Expected assertions:
- Unified patches are applied through `llm/tools/apply-patch` with the filesystem unit root as `cwd`.
- Directory units can create a new loader-relative source artifact.
- Flat single-file units fail loudly for `create-source` because the current filesystem loader cannot create sibling artifacts safely for that shape.

- [ ] **Step 3: Run focused tests and confirm new tests fail**

Run:

```bash
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-external-unit-mcp:main
```

Expected: FAIL with missing method errors.

- [ ] **Step 4: Implement loader-relative source resolution and mutation**

In `service.fnl`:
- Require `unit_id` and `source_id`; do not accept absolute paths.
- Reject `..`, absolute paths, drive-letter paths, and NUL bytes in `source_id`.
- For filesystem directory units, resolve `source_id` under the unit directory.
- For filesystem flat units, allow only the primary source artifact for read/patch and reject create.
- Reject built-in or unknown-loader units for write operations.
- Verify `expected_hash` before writing when provided.
- Validate `.fnl` source with `fennel.compile-string` before reload.
- On write/reload failure, restore the old source and surface the reload error.

- [ ] **Step 5: Re-run focused tests until Task 2 tests pass**

Run the focused test command from Step 3.

Expected: PASS.

---

### Task 3: External Unit Test, Log, and Snapshot Operations

**Files:**
- Modify: `assets/lua/llm/external-unit-mcp/service.fnl`
- Modify: `assets/lua/tests/test-external-unit-mcp.fnl`

**Interfaces:**
- Consumes:
  - Task 1 and Task 2 service
  - existing `process.Process.run`
  - existing `logging.get-output-path`
  - existing `unit:snapshot(ctx)`
- Produces:
  - `service:run-tests(args: {:unit_id string, :test_name string?}) -> table`
  - `service:read-log(args: {:lines number?, :offset number?, :limit number?, :grep string?}) -> table`
  - `service:snapshot(args: {:unit_id string}) -> table`

- [ ] **Step 1: Add failing tests for snapshot and log reading**

Extend `test-external-unit-mcp.fnl` with tests named:

- `external-unit-mcp: snapshot returns unit state with capability metadata`
- `external-unit-mcp: read-log returns filtered recent lines`

Expected assertions:
- `snapshot` returns `unit-id`, `supported == true`, and `state`.
- `read-log` returns `lines`, `total-lines`, and `log-path`, and honors `grep`.

- [ ] **Step 2: Add a focused test for `run-tests`**

Add test `external-unit-mcp: run-tests executes unit test module`.

Use a temporary directory unit with `test-init.fnl` exporting `{:main main :tests tests}` and assert:
- result has `passed == true`
- `exit-code == 0`
- stdout contains `PASS` or the runner success output

- [ ] **Step 3: Run focused tests and confirm new tests fail**

Run:

```bash
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-external-unit-mcp:main
```

Expected: FAIL with missing methods.

- [ ] **Step 4: Implement `run-tests`, `read-log`, and `snapshot`**

In `service.fnl`:
- `run-tests` should mirror the existing unit test subprocess behavior from `assets/lua/llm/presets/builtins/units.fnl`, but return a structured table instead of plain text.
- `read-log` should fail loudly if no log file exists or it is empty.
- `snapshot` should call `unit:snapshot({})`; if the loader/unit cannot snapshot, return `supported == false` only for an explicit missing capability, not for unexpected errors.

- [ ] **Step 5: Re-run focused tests until Task 3 tests pass**

Run the focused test command from Step 3.

Expected: PASS.

---

### Task 4: External Unit MCP Tool Registry

**Files:**
- Create: `assets/lua/llm/external-unit-mcp/tools.fnl`
- Modify: `assets/lua/tests/test-external-unit-mcp.fnl`

**Interfaces:**
- Consumes:
  - Task 1–3 `ExternalUnitService`
  - existing `mcp/tool-registry`
- Produces:
  - `ExternalUnitMcpTools.make-tool-registry(opts: {:app table, :service table?}) -> ToolRegistry`
  - `ExternalUnitMcpTools.register-tools(registry: table, service: table) -> table`
  - MCP tools:
    - `space_unit_resolve`
    - `space_unit_list`
    - `space_unit_inspect`
    - `space_unit_read_source`
    - `space_unit_apply_patch`
    - `space_unit_create_source`
    - `space_unit_run_tests`
    - `space_unit_reload`
    - `space_unit_read_log`
    - `space_unit_snapshot`

- [ ] **Step 1: Add failing tests for tool registration and JSON responses**

Extend `test-external-unit-mcp.fnl` with tests named:

- `external-unit-mcp: tool registry exposes minimal external tool set`
- `external-unit-mcp: tool calls return JSON service responses`
- `external-unit-mcp: write tool errors propagate as MCP tool errors`

Expected assertions:
- Registry namespace prefix is `space_`.
- The registry lists exactly the ten external unit tool names above.
- Calling `space_unit_list` returns JSON parseable output.
- Calling a write tool for an unsupported loader returns `isError == true`.

- [ ] **Step 2: Run focused tests and confirm tool module is missing**

Run:

```bash
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-external-unit-mcp:main
```

Expected: FAIL with missing `llm/external-unit-mcp/tools`.

- [ ] **Step 3: Implement `tools.fnl`**

Implement:
- `make-tool-registry` creates `ToolRegistry {:namespace-prefix "space_"}`.
- `register-tools` registers the ten tools with non-empty descriptions and object `inputSchema`.
- Each tool calls the matching service method and returns `json.dumps` of the structured table.
- Tool input uses canonical keys only: `unit_id`, `source_id`, `description`, `limit`, `patch`, `old`, `new`, `expected_hash`, `source`, `test_name`, `lines`, `offset`, `grep`.

- [ ] **Step 4: Re-run focused tests until Task 4 tests pass**

Run the focused test command from Step 2.

Expected: PASS.

---

### Task 5: Separate External Unit MCP Bridge and Standalone Server Entrypoint

**Files:**
- Create: `assets/lua/llm/external-unit-mcp/bridge.fnl`
- Create: `assets/lua/tools/external-unit-mcp-server.fnl`
- Modify: `assets/lua/tests/test-external-unit-mcp.fnl`

**Interfaces:**
- Consumes:
  - Task 4 `ExternalUnitMcpTools.make-tool-registry`
  - existing `mcp/server-http`
  - existing `http_server`
  - existing `json-utils.JsonUtils.write-json!`
  - existing `callbacks.run-loop`
- Produces:
  - `ExternalUnitMcpBridge.ExternalUnitMcpBridge(opts: {:tools table, :data-dir string, :host string?, :http-server-factory function?, :mcp-server-factory function?}) -> bridge`
  - `bridge:start() -> bridge`
  - `bridge:stop() -> bridge`
  - `bridge:opencode-env() -> {:XDG_CONFIG_HOME string}`
  - `bridge:status() -> table`
  - Standalone entrypoint: `./build/space -m tools.external-unit-mcp-server:main`

- [ ] **Step 1: Add failing bridge tests**

Extend `test-external-unit-mcp.fnl` with test `external-unit-mcp: bridge starts loopback server and writes isolated opencode config`.

Expected assertions:
- `status.started? == true`
- `status.host == "127.0.0.1"`
- `status.port > 0`
- `bridge:opencode-env().XDG_CONFIG_HOME == status.config-root`
- `status.config-path` is under the provided temp `data-dir`, not under global `~/.config/opencode`
- written config has `mcp.space-unit-dev.type == "remote"`, `enabled == true`, and `url == status.url`
- native OpenCode tools `read`, `write`, `edit`, `grep`, `glob`, `list`, and `bash` are denied

- [ ] **Step 2: Run focused tests and confirm bridge module is missing**

Run:

```bash
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-external-unit-mcp:main
```

Expected: FAIL with missing `llm/external-unit-mcp/bridge`.

- [ ] **Step 3: Implement `bridge.fnl` as a separate bridge from `llm/agent/opencode-mcp-bridge.fnl`**

Implement the same production lifecycle expectations as the internal bridge, but with external-unit names:
- Config root: `<data-dir>/external-unit-opencode-config`
- Config path: `<config-root>/opencode/opencode.json`
- MCP config key: `space-unit-dev`
- Remote URL: `http://127.0.0.1:<port>/mcp`
- Server: `MCPHTTPServer {:http-server ..., :tools tools, :force-sse true}`
- Deny native OpenCode filesystem/shell tools by default.
- On startup failure, stop the server and clear partial state.
- Do not import or mutate the internal `AgentOpencodeMcpBridge`.

- [ ] **Step 4: Implement `tools/external-unit-mcp-server.fnl`**

The entrypoint should:
- Create or reuse global `app`.
- Ensure `app.engine` exists with `EngineModule.Engine {:headless true}` if absent.
- Require `:main` only to access `Main.ensure-user-code-units!`; do not call `app.init`.
- Initialize `app.user-data-dir` and `app.code-dir` using `appdirs.user-data-dir "space"` and `fs.join-path`.
- Ensure `app.unit-manager` exists.
- Call `Main.ensure-user-code-units!`.
- Create the external unit MCP tool registry with `ExternalUnitMcpTools.make-tool-registry {:app app}`.
- Create `ExternalUnitMcpBridge` with a temp data dir.
- Start it, print `MCP_URL=<url>` and `OPENCODE_XDG_CONFIG_HOME=<config-root>`, flush stdout, then run `callbacks.run-loop {:poll-http true :sleep-ms 10}`.

- [ ] **Step 5: Re-run focused tests until Task 5 tests pass**

Run the focused test command from Step 2.

Expected: PASS.

- [ ] **Step 6: Manually smoke-test the standalone module starts and prints connection info**

Run with a timeout so the long-running server is stopped by the shell:

```bash
timeout 2s env \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tools.external-unit-mcp-server:main
```

Expected: process prints `MCP_URL=http://127.0.0.1:<port>/mcp` and `OPENCODE_XDG_CONFIG_HOME=<temp path>` before timeout exits.

---

### Task 6: Documentation Updates

**Files:**
- Create: `docs/dev/notes/external-unit-mcp.md`
- Modify: `docs/dev/notes/remote-mcp.md`
- Modify: `docs/dev/notes/agent-presets.md`
- Modify: `docs/dev/reloadable-units.md`

**Interfaces:**
- Consumes:
  - Task 1–5 implemented behavior and exact tool names
- Produces:
  - Developer documentation for external unit MCP workflow, safety model, and separation from the internal Space agent bridge

- [ ] **Step 1: Create `docs/dev/notes/external-unit-mcp.md`**

Document:
- Purpose: external OpenCode user-unit development through Space MCP tools.
- Command to start the server:
  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
  ./build/space -m tools.external-unit-mcp-server:main
  ```
- How to use printed `OPENCODE_XDG_CONFIG_HOME` with OpenCode without modifying global config.
- Required resolution workflow:
  1. `space_unit_resolve`
  2. `space_unit_inspect`
  3. `space_unit_read_source`
  4. edit through `space_unit_apply_patch` or `space_unit_create_source`
  5. `space_unit_run_tests`
  6. `space_unit_reload`
  7. `space_unit_read_log`
- State that `app.code-dir` / Space user-data code directory is common local storage, not the external contract.
- State that direct filesystem edits are an escape hatch only.

- [ ] **Step 2: Update `docs/dev/notes/remote-mcp.md`**

Add a section distinguishing:
- `assets/lua/tools/mcp-remote-server.fnl`: existing app bootstrap-owned/internal agent-facing MCP registry.
- `assets/lua/tools/external-unit-mcp-server.fnl`: external unit-development MCP registry.
- Both bind loopback by default.
- External unit MCP has loader-neutral tools and does not mutate global OpenCode config.

- [ ] **Step 3: Update `docs/dev/notes/agent-presets.md`**

Add a short note near the unit preset/tool section:
- Existing `llm/presets/builtins/units.fnl` tools are internal Space agent tools.
- External user-unit development uses `llm/external-unit-mcp/*` instead.
- Do not add Space-specific user-unit behavior to global `~/.config/opencode`.

- [ ] **Step 4: Update `docs/dev/reloadable-units.md`**

Add a section explaining:
- Units are loader-backed runtime objects.
- Current user units are filesystem-backed, but callers should use unit handles/source ids instead of constructing paths.
- External editing should go through `space_unit_*` external MCP tools.

- [ ] **Step 5: Run docs-adjacent focused tests**

Run:

```bash
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-external-unit-mcp:main
```

Expected: PASS.

---

### Task 7: Final Integration Validation

**Files:**
- Modify: no production files unless validation exposes a defect

**Interfaces:**
- Consumes:
  - All previous tasks
- Produces:
  - Observable acceptance evidence for the implementation

- [ ] **Step 1: Run the external unit MCP focused suite**

```bash
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-external-unit-mcp:main
```

Expected: PASS.

- [ ] **Step 2: Run existing MCP HTTP transport coverage because the new bridge uses the same transport**

```bash
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-mcp-http:main
```

Expected: PASS.

- [ ] **Step 3: Run existing internal agent/unit coverage to verify separation and compatibility**

```bash
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-agent-units:main
```

Expected: PASS.

- [ ] **Step 4: Run the standard full suite from AGENTS.md**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
make test
```

Expected: PASS.

## Invariants and Compatibility Requirements

- Existing internal Space agent MCP bridge in `assets/lua/llm/agent/opencode-mcp-bridge.fnl` remains unchanged in purpose and is not replaced.
- Existing internal agent unit tools in `assets/lua/llm/presets/builtins/units.fnl` remain available for the in-app agent.
- External MCP tools return loader-neutral handles and source ids; callers must not construct paths from `app.code-dir`.
- Current implementation may adapt filesystem-backed units only, but response shapes must not prevent database, remote, generated, or unknown loaders later.
- Unsupported loader operations fail loudly with MCP tool errors.
- Loopback remains the default bind behavior.
- No code writes to global `~/.config/opencode`.

## Observable Acceptance Criteria

- `space_unit_resolve` accepts vague descriptions and returns zero, one, or multiple candidates with confidence and evidence.
- `space_unit_list` and `space_unit_inspect` expose loader metadata, handles, source summaries, lifecycle exports, and capabilities.
- `space_unit_read_source`, `space_unit_apply_patch`, and `space_unit_create_source` operate through Space’s unit service and enforce stale hash checks when supplied.
- `space_unit_run_tests`, `space_unit_reload`, `space_unit_read_log`, and `space_unit_snapshot` are available through the external MCP registry.
- External MCP bridge writes isolated OpenCode config outside global `~/.config/opencode`.
- Documentation clearly separates repository development, internal Space agent MCP, and external user-unit MCP.

## Explicitly Out of Scope

- Database, remote, generated, or remote-host loader implementations.
- Persistent unit registry redesign.
- Broad repository workbench tools for arbitrary repo files.
- Non-loopback external MCP binds by default.
- Global OpenCode configuration changes.
- Replacing or removing the existing internal Space agent bridge.
