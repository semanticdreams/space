# Stable Fennel Constraints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the obsolete `experimental` qualifier from the active Space Fennel constraints feature without changing constraints behavior.

**Architecture:** Treat this as a stable naming migration across active docs, build/test identifiers, CI labels, Fennel constraint comments/data strings, and project-local agent guidance. Keep the existing `make constraints` command, `constraints.runner:main` module, constraint rules, runner statuses, output formats, and baseline semantics unchanged. Do not add old-name aliases because the feature should no longer advertise the experimental label anywhere active.

**Tech Stack:** Markdown docs, VitePress docs paths, CMake/CTest, GitHub Actions YAML, Fennel tests and constraint modules, project-local OpenCode skill Markdown.

## Global Constraints

- Stable docs page: `docs/dev/constraints.md` with title `# Fennel Constraints`.
- Stable CTest test: `${PROJECT_NAME}_constraints`.
- Stable CTest fixture: `space_constraints`.
- Stable CI step name: `Run constraints`.
- Keep `make constraints`, `constraints.runner:main`, `assets/lua/constraints/**` module paths, runner statuses, output formats, and baseline semantics unchanged.
- Remove `experimental` from active constraints feature references, including active source comments and baseline reason strings.
- Leave historical `docs/plans/**` and `docs/specs/**` unchanged, including historical references to experimental constraints.
- Do not touch unrelated uses of `experimental`, such as Codex flags, OpenCode experimental APIs, or vendored external protocols.
- For Fennel-facing edits, validate in this order when feasible: compile check first, constraints second, focused Fennel tests third, broader suite last.
- Project-local OpenCode skill edits require the final handoff to remind the user to restart OpenCode for changed skill text to take effect in future sessions.

---

### Task 1: Rename Active Constraints Terminology

**Files:**
- Rename: `docs/dev/experimental-constraints.md` -> `docs/dev/constraints.md`
- Modify: `AGENTS.md`
- Modify: `docs/dev/index.md`
- Modify: `.github/workflows/test.yml`
- Modify: `CMakeLists.txt`
- Modify: `assets/lua/tests/test-constraints-integration-config.fnl`
- Modify: `assets/lua/constraints/runner.fnl`
- Modify: `assets/lua/constraints/facts.fnl`
- Modify: `assets/lua/constraints/baseline.fnl`
- Modify: `assets/lua/constraints/targets.fnl`
- Modify: `assets/lua/constraints/source.fnl`
- Modify: `assets/lua/constraints/diagnostics.fnl`
- Modify: `assets/lua/constraints/scenarios.fnl`
- Modify: `assets/lua/constraints/baseline-data.fnl`
- Modify: `assets/lua/constraints/rules/lifecycle.fnl`
- Modify: `assets/lua/constraints/rules/init.fnl`
- Modify: `assets/lua/constraints/rules/scene-sandbox.fnl`
- Modify: `assets/lua/constraints/rules/test-isolation.fnl`
- Modify: `assets/lua/constraints/rules/layout.fnl`
- Modify: `assets/lua/constraints/rules/structure.fnl`
- Modify: `.opencode/skills/space-testing-runtime/SKILL.md`
- Modify: `.opencode/skills/subagent-driven-development/SKILL.md`

**Interfaces:**
- Consumes: existing `make constraints`, `make fennel-check`, `space -m constraints.runner:main`, CTest Fennel test fixture wiring, docs index link conventions.
- Produces: active repo references using stable constraints terminology only; CTest fixture `space_constraints`; CTest test `${PROJECT_NAME}_constraints`; canonical docs page `docs/dev/constraints.md`.

- [ ] **Step 1: Record the current failing terminology check**

  Run this search before editing to prove the repo currently fails the stable-naming requirement:

  ```bash
  rg -n "experimental-constraints|Experimental Fennel Constraints|Experimental Constraints|experimental constraints|experimental structure debt|space_experimental_constraints|experimental_constraints" AGENTS.md docs/dev .github/workflows/test.yml CMakeLists.txt assets/lua/constraints assets/lua/tests/test-constraints-integration-config.fnl .opencode/skills
  ```

  Expected: FAIL for the desired stable-naming state by printing matches in active constraints files such as `AGENTS.md`, `docs/dev/experimental-constraints.md`, `CMakeLists.txt`, `assets/lua/tests/test-constraints-integration-config.fnl`, `assets/lua/constraints/**`, and `.opencode/skills/**`.

- [ ] **Step 2: Update the CMake integration test expectation first**

  In `assets/lua/tests/test-constraints-integration-config.fnl`, make these exact test-side naming changes before editing `CMakeLists.txt`:

  ```fennel
  ;; Integration configuration checks for the constraints gate.
  ```

  Change `ctest-block-has-fixture?` to search for the stable fixture:

  ```fennel
  (local (fixture-pos) (string.find cmake "FIXTURES_REQUIRED space_constraints" start true))
  ```

  Rename the CMake test function and expected strings/messages to stable terminology:

  ```fennel
  (fn test-cmake-wires-constraints-fixture []
    (local cmake (read-repo-file "CMakeLists.txt"))
    (assert-contains cmake "add_test(NAME ${PROJECT_NAME}_constraints"
                     "CMake should declare the constraints test")
    (assert-contains cmake "COMMAND space -m constraints.runner:main -- --output summary --target repo"
                     "constraints CTest should run the repo constraints command in concise summary mode")
    (assert-contains cmake "FIXTURES_SETUP space_constraints"
                     "constraints CTest should set up its fixture")
    (assert (ctest-block-has-fixture? cmake "${PROJECT_NAME}_fnl_tests")
            "space_fnl_tests should require the constraints fixture")
    (assert (ctest-block-has-fixture? cmake "${PROJECT_NAME}_fnl_tests_integration")
            "space_fnl_tests_integration should require the constraints fixture"))
  ```

  Update the table entry to call the renamed function:

  ```fennel
  (table.insert tests {:name "CMake wires constraints fixture"
                       :fn test-cmake-wires-constraints-fixture})
  ```

- [ ] **Step 3: Run the focused test and verify RED**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl ./build/space -m tests.test-constraints-integration-config:main
  ```

  Expected: FAIL because `CMakeLists.txt` still declares `${PROJECT_NAME}_experimental_constraints` and `space_experimental_constraints`.

- [ ] **Step 4: Rename the canonical docs page**

  Move `docs/dev/experimental-constraints.md` to `docs/dev/constraints.md`.

  In the moved file, use this stable opening:

  ```markdown
  # Fennel Constraints

  The constraints gate checks repository Fennel code before normal Fennel tests run. It combines source facts from the Fennel parser with executable scenario checks so structural, lifecycle, layout, rendering, Scene, and Sandbox mistakes are caught early.

  The gate is blocking. If a constraint is noisy or wrong, fix or remove that constraint through normal reviewed code. Do not bypass the gate.
  ```

  Also make these prose updates in the moved file:

  - `full test runs execute the experimental constraints gate first` -> `full test runs execute the constraints gate first`.
  - ``Run experimental constraints`` -> ``Run constraints``.
  - ``space_experimental_constraints`` -> ``space_constraints``.
  - `Treat experimental constraints as early feedback` -> `Treat constraints as early feedback`.
  - `The current experimental constraints are grouped into four families` -> `The current constraints are grouped into four families`.

- [ ] **Step 5: Update active workflow docs and docs index**

  In `AGENTS.md`, replace the constraints bullets with stable wording:

  ```markdown
  - For Fennel-facing work, `make constraints` runs after `make fennel-check` so constraint violations surface before slower debugging loops. The constraints gate is blocking; every result other than `pass` (`violations`, `fail`, or `interrupted`) exits nonzero and should be diagnosed and fixed through reviewed code or reviewed baseline data, not bypassed. See [Fennel Constraints](docs/dev/constraints.md).
  ```

  And:

  ```markdown
  - `make test` already depends on `make constraints`, so full-suite runs execute the constraints gate before normal Fennel tests; do not duplicate `make constraints` immediately before `make test` unless the early, faster feedback is useful.
  ```

  In `docs/dev/index.md`, update the Core Docs entry to:

  ```markdown
  - [Fennel Constraints](/dev/constraints) — constraints workflow
  ```

- [ ] **Step 6: Rename CI and CTest labels**

  In `.github/workflows/test.yml`, change the Linux job step name to:

  ```yaml
      - name: Run constraints
        run: make constraints
  ```

  In `CMakeLists.txt`, change the CTest fixture and test identifiers exactly:

  ```cmake
  FIXTURES_REQUIRED space_constraints
  ```

  for both `${PROJECT_NAME}_fnl_tests` and `${PROJECT_NAME}_fnl_tests_integration`, and:

  ```cmake
  add_test(NAME ${PROJECT_NAME}_constraints
      COMMAND space -m constraints.runner:main -- --output summary --target repo
  )
  set_tests_properties(${PROJECT_NAME}_constraints PROPERTIES
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
      FIXTURES_SETUP space_constraints
      ENVIRONMENT "SKIP_KEYRING_TESTS=1;XDG_DATA_HOME=/tmp/space/tests/xdg-data;SPACE_DISABLE_AUDIO=1;SPACE_LOG_DIR=/tmp/space/tests/log;SPACE_ASSETS_PATH=${CMAKE_SOURCE_DIR}/assets;FENNEL_PATH=${CMAKE_SOURCE_DIR}/assets/lua/?.fnl\;${CMAKE_SOURCE_DIR}/assets/lua/?/init.fnl;FENNEL_MACRO_PATH=${CMAKE_SOURCE_DIR}/assets/lua/?.fnl\;${CMAKE_SOURCE_DIR}/assets/lua/?/init.fnl"
  )
  ```

- [ ] **Step 7: Update constraint module comments and baseline reasons**

  In all `assets/lua/constraints/**/*.fnl` headers, replace `for experimental Fennel constraints.` with `for Fennel constraints.` Examples:

  ```fennel
  ;; Runner module for Fennel constraints.
  ;; Rule registry for Fennel constraints.
  ;; Layout/Rendering constraint rules for Fennel constraints.
  ```

  In `assets/lua/constraints/baseline-data.fnl`, replace baseline reason text `existing experimental structure debt` with `existing structure debt`. Do not change constraint IDs, file names, fingerprints, measures, or rule behavior.

- [ ] **Step 8: Update project-local OpenCode skill references**

  In `.opencode/skills/space-testing-runtime/SKILL.md`, change the section heading and docs path references:

  ```markdown
  ## Constraints
  ```

  and:

  ```markdown
  - Use `docs/dev/constraints.md` for runner statuses, targets, and baseline policy.
  ```

  and in Canonical References:

  ```markdown
  - `docs/dev/constraints.md`
  ```

  In `.opencode/skills/subagent-driven-development/SKILL.md`, update the implementer-dispatch context line to reference `docs/dev/constraints.md` instead of `docs/dev/experimental-constraints.md`.

- [ ] **Step 9: Verify stable terminology search passes**

  Run:

  ```bash
  if rg -n "experimental-constraints|Experimental Fennel Constraints|Experimental Constraints|experimental constraints|experimental structure debt|space_experimental_constraints|experimental_constraints" AGENTS.md docs/dev .github/workflows/test.yml CMakeLists.txt assets/lua/constraints assets/lua/tests/test-constraints-integration-config.fnl .opencode/skills; then exit 1; fi
  ```

  Expected: PASS for the stable-naming requirement by returning no matches.

- [ ] **Step 10: Run compile check**

  Run:

  ```bash
  make fennel-check
  ```

  Expected: PASS.

- [ ] **Step 11: Reconfigure CMake for renamed CTest identifiers**

  Run:

  ```bash
  make cmake
  ```

  Expected: PASS. Use timeout `600000` when invoking through automation.

- [ ] **Step 12: Verify focused integration test passes**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl ./build/space -m tests.test-constraints-integration-config:main
  ```

  Expected: PASS.

- [ ] **Step 13: Verify constraints gate behavior remains green**

  Run:

  ```bash
  make constraints
  ```

  Expected: PASS with status `pass`.

- [ ] **Step 14: Verify renamed CTest wiring**

  Run:

  ```bash
  ctest --test-dir build -R '^space_constraints$|^space_fnl_tests$|^space_fnl_tests_integration$' --output-on-failure -V
  ```

  Expected: PASS, and CTest output shows the constraints fixture under `space_constraints` before Fennel tests.

- [ ] **Step 15: Verify docs build after path rename**

  Run:

  ```bash
  npm --prefix docs run docs:build
  ```

  Expected: PASS.

## Acceptance Criteria

- Active repo references no longer call the Space Fennel constraints feature `experimental`.
- `docs/dev/constraints.md` is the canonical docs/dev page and `docs/dev/experimental-constraints.md` is removed.
- CTest uses `space_constraints` fixture and `${PROJECT_NAME}_constraints` test name.
- `make constraints` behavior and runner invocation are unchanged.
- Historical `docs/plans/**` and `docs/specs/**` are not rewritten.
- The final user-facing handoff notes that OpenCode should be restarted because project-local skill files changed.

## Post-Review Commit

After the task implementation has passed reviewer verification, commit the reviewed changes together:

```bash
git add AGENTS.md docs/dev/constraints.md docs/dev/index.md .github/workflows/test.yml CMakeLists.txt assets/lua/tests/test-constraints-integration-config.fnl assets/lua/constraints .opencode/skills/space-testing-runtime/SKILL.md .opencode/skills/subagent-driven-development/SKILL.md
git add -u docs/dev/experimental-constraints.md
git commit -m "chore(lua): promote fennel constraints naming"
```

## Final Validation

Run these after the task commit and final review pass:

```bash
if rg -n "experimental-constraints|Experimental Fennel Constraints|Experimental Constraints|experimental constraints|experimental structure debt|space_experimental_constraints|experimental_constraints" AGENTS.md docs/dev .github/workflows/test.yml CMakeLists.txt assets/lua/constraints assets/lua/tests/test-constraints-integration-config.fnl .opencode/skills; then exit 1; fi
make fennel-check
make cmake
make constraints
ctest --test-dir build -R '^space_constraints$|^space_fnl_tests$|^space_fnl_tests_integration$' --output-on-failure -V
npm --prefix docs run docs:build
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Use timeout `600000` for `make cmake` and timeout `14400000` for build-like full validation commands when invoking through automation.
