# Fennel Agent Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add project-native Fennel compile validation, structural query tools, MCP wrappers, and agent workflow guidance so agents stop using unsupported Fennel syntax checks.

**Architecture:** Build a reusable Fennel validation service that uses vendored `assets/lua/fennel.lua`, existing tree-sitter bindings, and existing constraints modules. Expose that service through a CLI/Make target first, then through read-only MCP tools, and finally update repo/OpenCode guidance around the compile → constraints → focused tests → broader suite ladder.

**Tech Stack:** Fennel/Lua under `assets/lua/`, vendored Fennel via `(require :fennel)`, `./build/space -m module:main`, existing `constraints.*` modules, existing `tree-sitter` binding, existing `mcp/tool-registry` and HTTP bridge patterns, Make, Markdown, project-local OpenCode agent/skill files.

## Global Constraints

- Build the full reliability stack in layers, with each layer useful on its own.
- The service must be testable without an MCP server and must never rely on system `fennel`, system `lua`, or unavailable `./build/space` flags.
- Add Space-native commands that agents can run reliably: `make fennel-check`, `./build/space -m tools.fennel-check:main -- --target repo`, and `./build/space -m tools.fennel-check:main -- --target files --file assets/lua/foo.fnl`.
- `make fennel-check` must use the same canonical runtime environment as constraints and tests.
- `make constraints` must run the compile check before structural constraints so `make test` remains transitively gated.
- The Makefile must avoid hand-copying Fennel runtime variables across targets.
- MCP tools must be loopback-only by default when served, must label filesystem-read risk accurately, and must avoid write/edit tools in this slice.
- MCP tools must wrap the project-native service, not duplicate parser/compiler logic.
- For `.fnl` changes, implementers must run: fast compile check for touched files or `make fennel-check`; relevant constraints, preferably explicit files when the task is narrow; focused Fennel tests; broader relevant suite, with `make test` for final validation.
- Do not replace the constraints system with generic Tree-sitter analysis.
- Do not make LSP the primary solution.
- Do not require system `fennel`, system `lua`, `fennel-ls`, or `fnlfmt`.
- Do not add automatic AST rewriting or production code editing through MCP.
- Do not introduce broad formatting churn unrelated to syntax reliability.

---

### Task 1: Fennel Validation Service Compile Gate

**Files:**
- Create: `assets/lua/llm/fennel-validation/service.fnl`
- Create: `assets/lua/tests/test-fennel-validation.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `(require :fennel)`, `constraints.targets.resolve(argv, env)`, `constraints.source.discover(target)`, existing `fs`/`tempfile` modules, and existing `tests/runner` test style.
- Produces: `FennelValidationService.FennelValidationService(opts) -> service`.
- Produces: `service:resolve-target(argv) -> target`.
- Produces: `service:check-target(target) -> result`.
- Produces: `service:check-repo(args) -> result`.
- Produces: `service:check-files({:files path-list}) -> result`.
- Result shape: `{:ok boolean :status :pass|:fail :checked absolute-path-list :diagnostics diagnostic-list :summary {:checked n :failed n}}`.
- Diagnostic shape: `{:kind :compile|:input :file absolute-path-or-empty :line integer-or-nil :column integer-or-nil :message string :hint string}`.

- [ ] **Step 1: Write failing service tests**

  Create `assets/lua/tests/test-fennel-validation.fnl` using the pattern in `assets/lua/tests/test-tree-sitter-fennel.fnl`: `(local tests [])`, named test functions, `table.insert`, a `main` that calls `tests/runner`, and final export `{:name "fennel-validation" :tests tests :main main}`.

  Include these four tests:
  - `valid-file-compile-succeeds`: write temp `valid.fnl` containing `(fn hello [name]\n  (print name))\n{:hello hello}\n`; call `(service:check-files {:files [path]})`; assert `result.ok`, `result.status` is `:pass`, one absolute checked path, `summary.checked` is `1`, `summary.failed` is `0`, and no diagnostics.
  - `malformed-delimiter-fails-with-diagnostic`: write temp `broken.fnl` containing `(fn broken [name]\n  (print name)\n`; assert `ok` false, `status` `:fail`, one failed file, first diagnostic kind `:compile`, absolute file path, non-empty message, and a hint containing `enclosing form` or `delimiter`.
  - `file-target-checks-only-requested-files`: write valid `good.fnl` and broken sibling `bad.fnl`; call `check-files` with only `good.fnl`; assert pass and one checked path.
  - `non-fennel-file-is-rejected`: write `README.md`; assert fail, `summary.checked` `0`, first diagnostic kind `:input`, and message mentions `.fnl`.

- [ ] **Step 2: Register the failing service test in the fast suite**

  Add `:tests.test-fennel-validation` in `assets/lua/tests/fast.fnl` near `:tests.test-tree-sitter-fennel` and the constraints tests.

- [ ] **Step 3: Run the focused test and verify RED**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-validation:main
  ```

  Expected: FAIL because `llm/fennel-validation/service` is not found.

- [ ] **Step 4: Implement the minimal compile service**

  Create `assets/lua/llm/fennel-validation/service.fnl` with:
  - `FennelValidationService(opts)` returning an object table with methods.
  - Internal `fnl-path?`, `diagnostic-hint`, `compile-file`, `input-diagnostic`, `compile-diagnostic`, and `finish-result` helpers.
  - `compile-file(path)` reads file text and calls `fennel.compile-string` inside `pcall`; it never shells out.
  - `compile-diagnostic(path, err)` parses line/column from compiler messages when present and leaves them nil when unavailable.
  - `check-files(args)` absolute-normalizes and sorts `args.files`, rejects non-`.fnl` paths before compile, then compiles requested files only.
  - `resolve-target(argv)` calls `Targets.resolve argv {}`.
  - `check-repo(args)` resolves `--target repo` and calls `check-target`.
  - `check-target(target)` uses `Source.discover(target)`, compiles every discovered `.fnl` file independently, and returns all diagnostics.
  - Export `{:FennelValidationService FennelValidationService}`.

- [ ] **Step 5: Run focused service tests and verify GREEN**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-validation:main
  ```

  Expected: PASS.

- [ ] **Step 6: Run the relevant fast suite slice**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  ```

  Expected: PASS.

- [ ] **Step 7: Commit**

  ```bash
  git add assets/lua/llm/fennel-validation/service.fnl assets/lua/tests/test-fennel-validation.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(lua): add fennel validation service"
  ```

---

### Task 2: Fennel Check CLI and Makefile Runtime Environment

**Files:**
- Create: `assets/lua/tools/fennel-check.fnl`
- Create: `assets/lua/tests/test-fennel-check-cli.fnl`
- Modify: `assets/lua/tests/fast.fnl`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `FennelValidationService.FennelValidationService(opts)`, `service:resolve-target(argv)`, and `service:check-target(target)` from Task 1.
- Produces: `FennelCheck.run(argv, opts) -> result`.
- Produces: `FennelCheck.main(opts-or-argv) -> nil`, where tests may pass `{:argv table :print fn :exit fn}`.
- Produces: Make target `fennel-check: build`.
- Produces: Make dependency `constraints: fennel-check`.

- [ ] **Step 1: Write failing CLI tests**

  Create `assets/lua/tests/test-fennel-check-cli.fnl` using temp files and a helper:

  ```fennel
  (fn run-main-capturing [argv]
    (var printed nil)
    (var exit-code nil)
    (FennelCheck.main {:argv argv
                       :print (fn [msg] (set printed msg))
                       :exit (fn [code] (set exit-code code))})
    {:printed printed :exit-code exit-code})
  ```

  Include tests for valid explicit file exit `0`, broken explicit file exit `1`, explicit valid file ignoring a broken sibling, and non-`.fnl` file exit `1`. Each test must parse the printed JSON and assert the status/summary/diagnostic fields from Task 1.

- [ ] **Step 2: Register the failing CLI test**

  Add `:tests.test-fennel-check-cli` in `assets/lua/tests/fast.fnl` next to `:tests.test-fennel-validation`.

- [ ] **Step 3: Run the focused CLI test and verify RED**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-check-cli:main
  ```

  Expected: FAIL because `tools/fennel-check` is not found.

- [ ] **Step 4: Implement `assets/lua/tools/fennel-check.fnl`**

  Implement `run(argv, opts)` by instantiating the validation service, resolving argv into a target, and returning `service:check-target(target)`. Implement `main(opts-or-argv)` so it supports injected `:argv`, `:print`, and `:exit` for tests; prints exactly one JSON result; exits `0` for `result.ok` and `1` otherwise; and converts resolver/service exceptions into the standard failure result shape.

- [ ] **Step 5: Refactor Makefile environment and add `fennel-check`**

  In `Makefile`:
  - Add `fennel-check` to `.PHONY`.
  - Add shared variables near the top:

    ```make
    SPACE_TEST_ENV = SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(CURDIR)/assets
    SPACE_FENNEL_ENV = FENNEL_PATH=$(CURDIR)/assets/lua/?.fnl\;$(CURDIR)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(CURDIR)/assets/lua/?.fnl\;$(CURDIR)/assets/lua/?/init.fnl
    SPACE_RUNTIME_ENV = $(SPACE_TEST_ENV) $(SPACE_FENNEL_ENV)
    ```

  - Add `fennel-check: build` running `@$(SPACE_RUNTIME_ENV) ./build/space -m tools.fennel-check:main -- --target repo`.
  - Change `constraints: build` to `constraints: fennel-check`.
  - Replace duplicated runtime env prefixes in `constraints`, `test`, `test-e2e`, `test-slow`, `test-integration`, `test-all-lua`, and `test-live-hot-reload` with `$(SPACE_RUNTIME_ENV)` while preserving `xvfb-run`, `SDL_VIDEODRIVER=x11`, and script invocations.

- [ ] **Step 6: Run focused CLI tests and verify GREEN**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-check-cli:main
  ```

  Expected: PASS.

- [ ] **Step 7: Validate Makefile wiring**

  ```bash
  make -n fennel-check constraints test
  ```

  Expected: dry-run output shows `tools.fennel-check:main` before `constraints.runner:main`, and `test` still runs `scripts/ctest-summary.py`.

- [ ] **Step 8: Run the new gates**

  ```bash
  make fennel-check
  make constraints
  ```

  Expected: both PASS.

- [ ] **Step 9: Commit**

  ```bash
  git add assets/lua/tools/fennel-check.fnl assets/lua/tests/test-fennel-check-cli.fnl assets/lua/tests/fast.fnl Makefile
  git commit -m "feat(lua): add fennel check cli"
  ```

---

### Task 3: Structural Queries and Constraints-by-File Service Methods

**Files:**
- Modify: `assets/lua/llm/fennel-validation/service.fnl`
- Modify: `assets/lua/tests/test-fennel-validation.fnl`

**Interfaces:**
- Consumes: Task 1 service object, existing `tree-sitter.parse(source, {:language :fennel})`, `constraints.runner.run-target(target, opts)`, `constraints.targets.resolve(argv, env)`, `constraints.source.discover(target)`, and `constraints.facts.extract(file-records)`.
- Produces: `service:parse-tree({:file path :max-chars n}) -> {:ok boolean :file path :root-type string :sexpr string :truncated? boolean :diagnostics table}`.
- Produces: `service:enclosing-form({:file path :line n :column n}) -> {:ok boolean :file path :form string :node-type string :start table :end table :diagnostics table}`.
- Produces: `service:structure-metrics({:file path}) -> {:ok boolean :file path :metrics {:module-lines n :max-nesting-depth n :functions table} :diagnostics table}`.
- Produces: `service:check-constraints-files({:files path-list}) -> constraints-runner-result`.

- [ ] **Step 1: Add failing structural tests**

  Extend `assets/lua/tests/test-fennel-validation.fnl` with tests named `parse-tree-returns-bounded-summary`, `parse-tree-degrades-on-invalid-fennel`, `enclosing-form-finds-smallest-delimited-form`, `structure-metrics-return-module-and-function-data`, and `constraints-files-wrapper-returns-runner-status`. Use temp `.fnl` files. Assert the output shapes listed in this task's Interfaces section, including `(print item)` for the enclosing form test.

- [ ] **Step 2: Run focused tests and verify RED**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-validation:main
  ```

  Expected: FAIL because structural methods are missing.

- [ ] **Step 3: Implement parse-tree query**

  In `service.fnl`, add `read-fnl-file`, recursive `node-has-error?`, and `parse-tree(args)`. Use `tree-sitter.parse source {:language :fennel}`, bound `root:sexpr()` to `args.max-chars` or `8000`, and return `ok=false` plus diagnostics when any node type is `"ERROR"`.

- [ ] **Step 4: Implement enclosing-form lookup**

  In `service.fnl`, add `byte-offset-at-line-column(source, line, column)` using 1-indexed line/column input. Walk the tree for the deepest node containing the byte offset, then return the smallest enclosing delimited source text beginning with `(`, `[`, or `{`. Return a structured diagnostic when the location is outside the file.

- [ ] **Step 5: Implement structure metrics and constraints wrapper**

  In `service.fnl`, implement `structure-metrics(args)` by resolving a files target, discovering source, extracting facts, and returning metrics from the first file record. Implement `check-constraints-files(args)` by resolving a files target and calling `Runner.run-target target {}` while preserving runner statuses exactly.

- [ ] **Step 6: Run focused tests and gates**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-validation:main
  make fennel-check
  make constraints
  ```

  Expected: all PASS.

- [ ] **Step 7: Commit**

  ```bash
  git add assets/lua/llm/fennel-validation/service.fnl assets/lua/tests/test-fennel-validation.fnl
  git commit -m "feat(lua): add fennel structure queries"
  ```

---

### Task 4: Read-Only Fennel Validation MCP Tools

**Files:**
- Create: `assets/lua/llm/fennel-validation/tools.fnl`
- Create: `assets/lua/llm/fennel-validation/bridge.fnl`
- Create: `assets/lua/tools/fennel-validation-mcp-server.fnl`
- Create: `assets/lua/tests/test-fennel-validation-mcp.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: Task 3 service methods, `mcp/tool-registry`, existing external-unit MCP service/tools/bridge patterns, `json`, `tempfile`, and `callbacks.run-loop`.
- Produces: `FennelValidationMcpTools.make-tool-registry(opts) -> registry`.
- Produces: `FennelValidationMcpTools.register-tools(registry, service) -> registry`.
- Produces: `FennelValidationMcpTools.get-tool-risks() -> table`.
- Produces read-only tools: `space_fennel_check_file`, `space_constraints_check_files`, `space_fennel_parse_tree`, `space_fennel_enclosing_form`, and `space_fennel_structure_metrics`.
- Produces: `FennelValidationMcpBridge.FennelValidationMcpBridge(opts) -> bridge`, with `start`, `stop`, `status`, and `opencode-env` methods.

- [ ] **Step 1: Write failing MCP wrapper tests**

  Create `assets/lua/tests/test-fennel-validation-mcp.fnl`. Assert that the registry lists all five tool names, `get-tool-risks` maps each to `"filesystem-read"`, `space_fennel_check_file` returns structured JSON diagnostics for malformed Fennel, parse/enclosing/metrics tools return JSON payloads for representative valid Fennel, and `space_constraints_check_files` returns `status`, `counts`, and `diagnostics`.

- [ ] **Step 2: Register the failing MCP test**

  Add `:tests.test-fennel-validation-mcp` in `assets/lua/tests/fast.fnl` near existing MCP tests.

- [ ] **Step 3: Run focused MCP tests and verify RED**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-validation-mcp:main
  ```

  Expected: FAIL because `llm/fennel-validation/tools` is not found.

- [ ] **Step 4: Implement `tools.fnl`**

  Follow `assets/lua/llm/external-unit-mcp/tools.fnl`: use `ToolRegistry {:namespace-prefix "space_"}`, register all five tool names, set every risk to `"filesystem-read"`, have each `:run` return `json.dumps(payload)`, catch service errors into structured JSON, and use input schemas for each tool's string/integer/array fields.

- [ ] **Step 5: Implement bridge and server entrypoint**

  Add `bridge.fnl` by following `assets/lua/llm/external-unit-mcp/bridge.fnl`, with default host `"127.0.0.1"`, generated MCP server key `space-fennel-validation`, generated config that denies edit/write/bash/task/webfetch/websearch/external-directory-style permissions and allows read/list/glob/grep, and no mutation of user or project global config.

  Add `assets/lua/tools/fennel-validation-mcp-server.fnl` that creates the service, registers tools, starts the bridge, prints `MCP_URL=<url>` and `OPENCODE_XDG_CONFIG_HOME=<config-root>`, flushes stdout, and enters `callbacks.run-loop {:poll-http true :sleep-ms 10}`.

- [ ] **Step 6: Run focused MCP tests and compile gate**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-validation-mcp:main
  make fennel-check
  ```

  Expected: both PASS.

- [ ] **Step 7: Commit**

  ```bash
  git add assets/lua/llm/fennel-validation/tools.fnl assets/lua/llm/fennel-validation/bridge.fnl assets/lua/tools/fennel-validation-mcp-server.fnl assets/lua/tests/test-fennel-validation-mcp.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(lua): expose fennel validation mcp tools"
  ```

---

### Task 5: Agent Workflow Documentation and OpenCode Guidance

**Files:**
- Create: `docs/dev/features/fennel-agent-reliability.md`
- Create: `.opencode/skills/space-fennel/SKILL.md`
- Modify: `AGENTS.md`
- Modify: `docs/dev/experimental-constraints.md`
- Modify: `.opencode/agents/supervisor.md`
- Modify: `.opencode/agents/planner.md`
- Modify: `.opencode/agents/implementer.md`
- Modify: `.opencode/agents/reviewer.md`
- Modify: `.opencode/skills/space-testing-runtime/SKILL.md`
- Modify: `.opencode/skills/subagent-driven-development/SKILL.md`

**Interfaces:**
- Consumes: CLI commands from Task 2 and MCP tool names from Task 4.
- Produces: canonical docs page `docs/dev/features/fennel-agent-reliability.md`.
- Produces: project skill `space-fennel`, used for all Space `.fnl` work; `space-fennel-ui` remains additional guidance for widget/layout/rendering work.
- Produces: repo-local agent guidance requiring compile-check evidence before Fennel handoff when relevant.

- [ ] **Step 1: Create the Fennel reliability docs page**

  Create `docs/dev/features/fennel-agent-reliability.md` with sections `Validation Ladder`, `Commands`, `MCP Tools`, `Repair Workflow`, and `Deferred Integrations`. It must document compile check first, constraints second, focused tests third, final `make test` fourth, the five read-only MCP tools, delimiter/enclosing-form repair workflow, and deferral of `fennel-ls`, `fnlfmt`, write-capable MCP tools, and automatic AST rewriting.

- [ ] **Step 2: Update repository docs**

  In `AGENTS.md`, add concise bullets that require the `.fnl` validation ladder and forbid system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, and `./build/space -e` as validation oracles. In `docs/dev/experimental-constraints.md`, add `## Relationship to Fennel Compile Check` explaining that `make fennel-check` is the first-stage syntax oracle and `make constraints` runs after it.

- [ ] **Step 3: Create the general Space Fennel skill**

  Create `.opencode/skills/space-fennel/SKILL.md` with frontmatter:

  ```markdown
  ---
  name: space-fennel
  description: Use when editing assets/lua/**/*.fnl, Fennel tests, Fennel constraints, or Space Fennel CLI/MCP tools; provides validation commands, syntax traps, macro path requirements, and parser-repair workflow.
  ---
  ```

  The body must instruct agents to use this for all Space `.fnl` work, use `space-fennel-ui` additionally for widget/layout/rendering work, follow the validation ladder, avoid unsupported validation oracles, use enclosing-form repair for delimiter errors, and report compile/constraints/test evidence.

- [ ] **Step 4: Update OpenCode agent and process guidance**

  Update these files while preserving existing roles and review discipline:
  - `.opencode/agents/supervisor.md`: route any request touching `.fnl`, Fennel tests, Fennel constraints, or Fennel tooling to `space-fennel`; keep `space-fennel-ui` for UI/widget/layout overlap.
  - `.opencode/agents/planner.md`: Fennel plans must name compile-check, constraints, focused test, and broader-suite commands.
  - `.opencode/agents/implementer.md`: Fennel reports must include compile-check evidence before constraints and tests when relevant.
  - `.opencode/agents/reviewer.md`: missing compile-check evidence is a validation gap for relevant Fennel diffs unless the reported command clearly included the gate.
  - `.opencode/skills/space-testing-runtime/SKILL.md`: list `make fennel-check` before `make constraints` for Fennel-facing work.
  - `.opencode/skills/subagent-driven-development/SKILL.md`: include compile-check expectations in Fennel task briefs and ledger triage.

- [ ] **Step 5: Validate docs and skill text**

  ```bash
  rg -n "fennel-check|tools.fennel-check|space_fennel_check_file|space_constraints_check_files|space-fennel|fennel-ls|fnlfmt|enclosing form" AGENTS.md docs/dev/experimental-constraints.md docs/dev/features/fennel-agent-reliability.md .opencode/skills/space-fennel/SKILL.md .opencode/agents/supervisor.md .opencode/agents/planner.md .opencode/agents/implementer.md .opencode/agents/reviewer.md .opencode/skills/space-testing-runtime/SKILL.md .opencode/skills/subagent-driven-development/SKILL.md
  ```

  Expected: each listed file contains relevant new guidance.

- [ ] **Step 6: Run runtime validation for documented commands**

  ```bash
  make fennel-check
  make constraints
  ```

  Expected: both PASS.

- [ ] **Step 7: Commit**

  ```bash
  git add AGENTS.md docs/dev/experimental-constraints.md docs/dev/features/fennel-agent-reliability.md .opencode/skills/space-fennel/SKILL.md .opencode/agents/supervisor.md .opencode/agents/planner.md .opencode/agents/implementer.md .opencode/agents/reviewer.md .opencode/skills/space-testing-runtime/SKILL.md .opencode/skills/subagent-driven-development/SKILL.md
  git commit -m "docs(opencode): document fennel validation workflow"
  ```

## Acceptance Criteria

- `make fennel-check` exists and uses `./build/space -m tools.fennel-check:main -- --target repo`.
- Explicit-file compile mode checks only requested `.fnl` files.
- Compile diagnostics include file path, compiler message, and repair hint; line/column are included when Fennel provides them.
- Non-`.fnl` file targets fail with a clear diagnostic.
- `make constraints` runs after the compile gate, and `make test` remains transitively gated.
- Service methods expose compile checks, explicit-file constraints, parse-tree summaries, enclosing-form lookup, and structure metrics without requiring MCP.
- MCP exposes exactly the five read-only project-native tools named in the spec.
- MCP tools return structured JSON error payloads for bad paths, invalid syntax, and invalid locations instead of crashing the registry.
- Documentation, agents, and project-local OpenCode skill describe the compile → constraints → focused tests → broader suite ladder.
- Documentation explicitly defers `fennel-ls`, `fnlfmt`, write-capable MCP tools, and AST rewriting.

## Validation Ladder

1. Focused implementation tests during each task:
   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-validation:main
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-check-cli:main
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-validation-mcp:main
   ```

2. Complete relevant suite:
   ```bash
   make fennel-check
   make constraints
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
   ```

3. Broader final check required because the Makefile changes alter shared runtime environment:
   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
   ```
