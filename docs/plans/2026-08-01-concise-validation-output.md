# Concise Validation Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Space validation/build workflow output concise by default for `make fennel-check`, `make constraints`, and the CTest constraints fixture, while preserving JSON output for debugging and direct CLI consumers.

**Architecture:** Add output-mode parsing and formatting at the validation CLI boundary. Keep direct `./build/space -m ...` entrypoints JSON-compatible by default; Make/CMake commands pass summary mode explicitly and `VERBOSE=1` restores JSON in Make targets.

**Tech Stack:** GNU Make, CMake/CTest, Space runtime Fennel modules, existing Fennel test runner, existing JSON module.

## Global Constraints

- Preserve direct CLI JSON defaults for `./build/space -m tools.fennel-check:main -- --target repo` and `./build/space -m constraints.runner:main -- --target repo`.
- Preserve result schemas from `tools.fennel-check.run`, `constraints.runner.run`, and `constraints.runner.run-target`.
- Preserve exit-code semantics: constraints exits `0` only for `pass`; fennel-check exits `0` only for `ok`.
- Do not add dependencies.
- Preserve validation order: `make constraints` depends on `make fennel-check`; `make test` depends on `make constraints`.
- Concise failure output must include status, count, diagnostic location/message, hint when present, and rerun guidance for JSON output.
- Do not change constraint rules, baselines, diagnostic schemas, `ctest-summary.py`, C/C++ compilation output, or broad GitHub Actions workflow structure.

---

## File Structure

- `assets/lua/tools/validation-output.fnl` — new shared helper for CLI output-mode parsing and summary formatting primitives.
- `assets/lua/tools/fennel-check.fnl` — consume output-mode helper in `main`, keep `run` unchanged, print JSON or concise summary.
- `assets/lua/constraints/runner.fnl` — consume output-mode helper in `main`, keep `run` and `run-target` unchanged, print JSON or concise summary.
- `assets/lua/tests/test-fennel-check-cli.fnl` — focused CLI tests for JSON default, summary output, invalid output modes, and target argument preservation.
- `assets/lua/tests/test-constraints-runner.fnl` — focused runner CLI tests for JSON default, summary output, invalid output modes, and injected old-style opts behavior.
- `Makefile` — add `VALIDATION_OUTPUT = $(if $(VERBOSE),json,summary)` and pass `--output $(VALIDATION_OUTPUT)` from validation targets.
- `CMakeLists.txt` — pass `--output summary` from the `space_experimental_constraints` CTest fixture command.
- `docs/dev/experimental-constraints.md` — document concise defaults and JSON rerun path for constraints.
- `docs/dev/features/fennel-agent-reliability.md` — document concise Make output and direct CLI JSON compatibility.

### Task 1: Shared Output-Mode Parser

**Files:**
- Create: `assets/lua/tools/validation-output.fnl`
- Modify: `assets/lua/tests/test-fennel-check-cli.fnl`

**Interfaces:**
- Consumes: `split-output-argv argv default-output`, where `argv` is a sequential table of CLI args and `default-output` is `:json` or `:summary`.
- Produces: `{:argv filtered-argv :output output-mode}` on success, where `output-mode` is `:json` or `:summary`.
- Produces: `{:argv filtered-argv :output default-output :error message}` on invalid or incomplete output-mode arguments.

- [ ] **Step 1: Add parser unit coverage through `test-fennel-check-cli`**

Add these functions near the existing helper tests in `assets/lua/tests/test-fennel-check-cli.fnl`:

```fennel
(fn validation-output-strips-output-flag []
  (local Output (require :tools/validation-output))
  (local parsed (Output.split-output-argv ["--output" "summary" "--target" "repo"] :json))
  (assert (not parsed.error) (.. "unexpected parse error: " (tostring parsed.error)))
  (assert (= parsed.output :summary))
  (assert (= (# parsed.argv) 2))
  (assert (= (. parsed.argv 1) "--target"))
  (assert (= (. parsed.argv 2) "repo")))

(fn validation-output-defaults-when-flag-absent []
  (local Output (require :tools/validation-output))
  (local parsed (Output.split-output-argv ["--target" "repo"] :json))
  (assert (not parsed.error) (.. "unexpected parse error: " (tostring parsed.error)))
  (assert (= parsed.output :json))
  (assert (= (# parsed.argv) 2))
  (assert (= (. parsed.argv 1) "--target"))
  (assert (= (. parsed.argv 2) "repo")))

(fn validation-output-rejects-invalid-mode []
  (local Output (require :tools/validation-output))
  (local parsed (Output.split-output-argv ["--output" "xml" "--target" "repo"] :json))
  (assert parsed.error "invalid mode should produce an error")
  (assert (string.find parsed.error "--output must be json or summary" 1 true)
          (.. "unexpected error: " parsed.error)))

(fn validation-output-rejects-missing-mode []
  (local Output (require :tools/validation-output))
  (local parsed (Output.split-output-argv ["--target" "repo" "--output"] :json))
  (assert parsed.error "missing mode should produce an error")
  (assert (string.find parsed.error "--output requires" 1 true)
          (.. "unexpected error: " parsed.error)))
```

Register each new function with `table.insert tests` using descriptive names.

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-fennel-check-cli:main
```

Expected: FAIL because `tools.validation-output` does not exist.

- [ ] **Step 3: Create the parser helper**

Create `assets/lua/tools/validation-output.fnl` with this public shape:

```fennel
(local M {})

(fn valid-output-mode? [mode]
  (or (= mode :json)
      (= mode :summary)))

(fn normalize-output-mode [mode]
  (if (= mode "json")
      :json
      (= mode :json)
      :json
      (= mode "summary")
      :summary
      (= mode :summary)
      :summary
      nil))

(fn M.split-output-argv [argv default-output]
  (local source (if argv argv []))
  (local default-mode (or (normalize-output-mode default-output) :json))
  (local filtered [])
  (var output default-mode)
  (var error nil)
  (var index 1)
  (while (<= index (# source))
    (local item (. source index))
    (if (= item "--output")
        (let [raw-mode (. source (+ index 1))
              mode (normalize-output-mode raw-mode)]
          (if (not raw-mode)
              (set error "--output requires json or summary")
              (not mode)
              (set error "--output must be json or summary")
              true
              (set output mode))
          (set index (+ index 2)))
        (do
          (table.insert filtered item)
          (set index (+ index 1)))))
  {:argv filtered
   :output output
   :error error})

{:split-output-argv M.split-output-argv}
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-fennel-check-cli:main
```

Expected: PASS.

### Task 2: Concise Summary Formatting in Validation Entrypoints

**Files:**
- Modify: `assets/lua/tools/validation-output.fnl`
- Modify: `assets/lua/tools/fennel-check.fnl`
- Modify: `assets/lua/constraints/runner.fnl`
- Modify: `assets/lua/tests/test-fennel-check-cli.fnl`
- Modify: `assets/lua/tests/test-constraints-runner.fnl`

**Interfaces:**
- Consumes: `Output.split-output-argv` from Task 1.
- Produces: `Output.fennel-check-summary result` returning a string.
- Produces: `Output.constraints-summary result` returning a string.
- `tools.fennel-check.main` accepts `--output summary|json` in `options.argv`; no flag defaults to JSON.
- `constraints.runner.main` accepts `--output summary|json` in argv mode; old opts-based calls remain JSON by default unless `:output :summary` is supplied.

- [ ] **Step 1: Add fennel-check summary tests**

Append these tests to `assets/lua/tests/test-fennel-check-cli.fnl` and register them:

```fennel
(fn summary-output-valid-file-is-concise []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "valid.fnl" "{:ok true}\n"))
      (local captured (run-main-capturing ["--output" "summary" "--target" "files" "--file" path]))
      (assert (= captured.exit-code 0))
      (assert (= captured.printed "fennel-check: pass (checked 1 file)")))))

(fn json-output-remains-default []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "valid.fnl" "{:ok true}\n"))
      (local captured (run-main-capturing ["--target" "files" "--file" path]))
      (local result (parse-result captured))
      (assert (= captured.exit-code 0))
      (assert result.ok)
      (assert (= result.status "pass")))))

(fn summary-output-broken-file-includes-diagnostic-and-rerun []
  (with-temp-dir
    (fn [dir]
      (local path (write-temp-file dir "broken.fnl" "(fn broken [x]\n"))
      (local captured (run-main-capturing ["--output" "summary" "--target" "files" "--file" path]))
      (assert (= captured.exit-code 1))
      (assert (string.find captured.printed "fennel-check: fail (checked 1 file, 1 failed)" 1 true))
      (assert (string.find captured.printed (fs.absolute path) 1 true))
      (assert (string.find captured.printed "rerun with --output json" 1 true)))))

(fn invalid-output-mode-exits-one []
  (local captured (run-main-capturing ["--output" "xml" "--target" "repo"]))
  (assert (= captured.exit-code 1))
  (assert (string.find captured.printed "fennel-check: fail" 1 true))
  (assert (string.find captured.printed "--output must be json or summary" 1 true)))
```

- [ ] **Step 2: Add constraints summary tests**

Add local capture helpers and tests in `assets/lua/tests/test-constraints-runner.fnl` near the existing `runner-main-prints-json...` tests:

```fennel
(fn run-runner-main-capturing [opts]
  (local Runner (require :constraints.runner))
  (var printed nil)
  (var exit-code nil)
  (local merged opts)
  (tset merged :print (fn [msg] (set printed msg)))
  (tset merged :exit (fn [code] (set exit-code code)))
  (Runner.main merged)
  {:printed printed :exit-code exit-code})

(fn runner-main-summary-pass-is-concise []
  (local captured
    (run-runner-main-capturing {:rules [(fn [_target] nil)]
                                :target {:kind :files :name "test"}
                                :output :summary
                                :baseline-data false}))
  (assert (= captured.exit-code 0))
  (assert (= captured.printed "constraints: pass (0 diagnostics)")))

(fn runner-main-summary-violations-include-diagnostic-and-rerun []
  (local Diagnostics (require :constraints.diagnostics))
  (local captured
    (run-runner-main-capturing {:rules [(fn [_target]
                                          (Diagnostics.violation
                                            {:constraint-id "test"
                                             :family "style"
                                             :file "assets/lua/example.fnl"
                                             :line 3
                                             :column 4
                                             :message "bad"
                                             :hint "fix"}))]
                                :target {:kind :files :name "test"}
                                :output :summary
                                :baseline-data false}))
  (assert (not= captured.exit-code 0))
  (assert (string.find captured.printed "constraints: violations (1 diagnostic)" 1 true))
  (assert (string.find captured.printed "assets/lua/example.fnl:3:4" 1 true))
  (assert (string.find captured.printed "bad" 1 true))
  (assert (string.find captured.printed "hint: fix" 1 true))
  (assert (string.find captured.printed "rerun with --output json" 1 true)))
```

Keep the old opts-based JSON tests unchanged; they prove compatibility for existing injected `:rules`, `:target`, `:print`, and `:exit` callers. Task 1's `validation-output-strips-output-flag` test proves `--output` is removed before target resolution.

- [ ] **Step 3: Run focused tests to verify failure before implementation**

Run:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-fennel-check-cli:main
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-constraints-runner:main
```

Expected: FAIL because summary formatting functions and entrypoint output-mode handling are not implemented.

- [ ] **Step 4: Extend the helper with summary primitives**

Add functions to `assets/lua/tools/validation-output.fnl`:

```fennel
(fn plural [count singular plural-word]
  (if (= count 1) singular plural-word))

(fn location [diagnostic]
  (let [file (or diagnostic.file "")
        line diagnostic.line
        column diagnostic.column]
    (if (and (> (# file) 0) line column)
        (.. file ":" line ":" column)
        (and (> (# file) 0) line)
        (.. file ":" line)
        (> (# file) 0)
        file
        "<unknown>")))

(fn diagnostic-lines [diagnostics limit]
  (local lines [])
  (local max-count (or limit 5))
  (var index 1)
  (while (and (<= index (# diagnostics)) (<= index max-count))
    (local diagnostic (. diagnostics index))
    (table.insert lines (.. "- " (location diagnostic) " " (tostring (or diagnostic.message "diagnostic"))))
    (when diagnostic.hint
      (table.insert lines (.. "  hint: " (tostring diagnostic.hint))))
    (set index (+ index 1)))
  (when (> (# diagnostics) max-count)
    (table.insert lines (.. "- ... " (- (# diagnostics) max-count) " more diagnostics")))
  lines)
```

Then add exported `fennel-check-summary` and `constraints-summary` functions that use these primitives and include `rerun with --output json` for non-pass/non-ok statuses.

- [ ] **Step 5: Update `tools.fennel-check.main`**

Modify only the CLI boundary:

```fennel
(local Output (require :tools/validation-output))
```

In `main`, split output args before `run`:

```fennel
(local parsed (Output.split-output-argv options.argv :json))
(local result (if parsed.error
                  (failure-result parsed.error)
                  (run parsed.argv options.opts)))
(print-fn (if (= parsed.output :summary)
              (Output.fennel-check-summary result)
              (json.dumps result)))
```

Keep the existing exit-code branch based on `result.ok`.

- [ ] **Step 6: Update `constraints.runner.main`**

Modify only `M.main` formatting and argv parsing. For old opts-style calls, read `(or o.output :json)` and keep JSON as the default. For argv-style calls, call `Output.split-output-argv argv :json`, resolve targets from `parsed.argv`, and print summary only when `parsed.output` is `:summary`. Invalid output mode should print a `:fail` shaped constraints result with one diagnostic and exit nonzero.

Use this failure result shape for invalid output mode:

```fennel
{:status :fail
 :counts {:total 1 :by-family {:input 1} :by-severity {:error 1}}
 :diagnostics [{:constraint-id "constraints.runner/output"
                :family "input"
                :severity :error
                :message parsed.error
                :hint "Use --output json or --output summary."}]}
```

- [ ] **Step 7: Run focused tests to verify pass**

Run:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-fennel-check-cli:main
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-constraints-runner:main
```

Expected: PASS.

### Task 3: Make/CMake Wiring and Documentation

**Files:**
- Modify: `Makefile`
- Modify: `CMakeLists.txt`
- Modify: `docs/dev/experimental-constraints.md`
- Modify: `docs/dev/features/fennel-agent-reliability.md`

**Interfaces:**
- `make fennel-check` and `make constraints` produce summary output.
- `make fennel-check VERBOSE=1` and `make constraints VERBOSE=1` pass `--output json`.
- `space_experimental_constraints` CTest fixture passes `--output summary`.

- [ ] **Step 1: Update Makefile validation output variable**

Add near the existing environment variable definitions:

```make
VALIDATION_OUTPUT = $(if $(VERBOSE),json,summary)
```

Change the validation targets to:

```make
fennel-check: build
	@$(SPACE_RUNTIME_ENV) ./build/space -m tools.fennel-check:main -- --output $(VALIDATION_OUTPUT) --target repo

constraints: fennel-check
	@$(SPACE_RUNTIME_ENV) ./build/space -m constraints.runner:main -- --output $(VALIDATION_OUTPUT) --target repo
```

- [ ] **Step 2: Update CTest constraints fixture**

Change the CMake command at `CMakeLists.txt` around the `space_experimental_constraints` test to:

```cmake
add_test(NAME ${PROJECT_NAME}_experimental_constraints
    COMMAND space -m constraints.runner:main -- --output summary --target repo
)
```

- [ ] **Step 3: Update constraints docs**

In `docs/dev/experimental-constraints.md`, replace the deferred verbosity sentence with concrete behavior:

```markdown
`make constraints` prints concise summaries by default to keep local and agent logs readable. Use `make constraints VERBOSE=1` for the full JSON payload from both `fennel-check` and the constraints runner, or call `./build/space -m constraints.runner:main -- --output json --target repo` directly when debugging parser/constraint details.
```

- [ ] **Step 4: Update Fennel reliability docs**

In `docs/dev/features/fennel-agent-reliability.md`, add command notes under `## Commands`:

```markdown
- `make fennel-check` and `make constraints` use concise summary output by default. Add `VERBOSE=1` to either Make command when debugging needs the raw JSON result.
- Direct `./build/space -m tools.fennel-check:main -- ...` and `./build/space -m constraints.runner:main -- ...` commands remain JSON by default for tooling compatibility; pass `--output summary` for concise direct CLI output.
```

- [ ] **Step 5: Validate command wiring without running the full build**

Run:

```bash
make -n fennel-check constraints test
```

Expected: dry-run output includes `--output summary` for `fennel-check` and `constraints`.

Run:

```bash
make -n fennel-check constraints VERBOSE=1
```

Expected: dry-run output includes `--output json` for `fennel-check` and `constraints`.

- [ ] **Step 6: Run required validation**

Run:

```bash
make fennel-check
make constraints
ctest --test-dir build -R space_experimental_constraints --output-on-failure -V
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: all commands pass. `make fennel-check` and `make constraints` print concise summaries; the full `make test` command remains the standard final validation gate.

---

## Acceptance Criteria

- `make constraints` no longer prints raw JSON on success.
- `make constraints VERBOSE=1` prints existing JSON payloads for both `fennel-check` and constraints.
- Direct `./build/space -m constraints.runner:main -- --target repo` remains JSON by default.
- Direct `./build/space -m tools.fennel-check:main -- --target repo` remains JSON by default.
- Direct CLI `--output summary` works for both validation entrypoints.
- Failure output remains actionable without verbose mode: status, count, diagnostic location/message, hint, and rerun instruction are visible.
- Exit codes and JSON result schemas are unchanged.

## Self-Review

- Spec coverage: the plan covers concise Make/CMake validation output, JSON verbose/debug escape hatches, direct CLI compatibility, actionable failure output, docs, and validation commands.
- Red-flag scan: no incomplete sections or deferred implementation notes remain.
- Type consistency: output modes use `:json` and `:summary` internally, string CLI values `json` and `summary`, and exported helper names are consistent across tasks.
