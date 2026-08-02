# Windows Artifact Fast Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `test.yml`'s Windows artifact fast-suite pass after the first Windows path portability fixes.

**Architecture:** Keep the Windows `test-windows` job as an artifact-only validation of `build/dist/windows`; do not add a checkout that masks packaging/runtime-layout problems. Fix remaining tests and helpers so artifact-compatible tests use `SPACE_ASSETS_PATH`, Windows path normalization actually handles native separators, POSIX symlink assertions are skipped on Windows, and repo-root integration tests skip when no checkout/build root exists.

**Tech Stack:** Space Fennel tests and constraints modules under `assets/lua`; GitHub Actions `test.yml`; native `fs`, `runtime`, and `process` bindings; validation via `tools.fennel-check`, `constraints.runner`, focused Fennel tests, and debug-branch Windows CI.

## Global Constraints

- Use `space-fennel` and `space-testing-runtime` rules for all `.fnl` changes.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- Run Fennel validation in order: compile check, constraints, focused Fennel tests, broader relevant suite / CI.
- Keep the Windows job artifact-only unless the human explicitly chooses checkout-based testing.
- Preserve logical path outputs with `/` separators for modules, relative paths, and external-unit source ids.
- Do not hide failures with broad baseline entries or generic skips; any Windows skip must name the unavailable capability (for example POSIX symlinks or repo checkout).

---

## File Structure

- `assets/lua/constraints/source.fnl`: correct backslash normalization for actual Windows paths.
- `assets/lua/tests/test-constraints-source.fnl`: make path expectations absolute/native-aware and keep focused Windows-string regressions.
- `assets/lua/tests/test-external-unit-mcp.fnl`: skip the symlink-ancestor test when POSIX symlink creation cannot be verified on Windows.
- `assets/lua/tests/test-constraints-rules-layout-interactive-precision.fnl`: resolve production fixture files from `SPACE_ASSETS_PATH`/runtime assets.
- `assets/lua/tests/test-constraints-default-run.fnl`: resolve fixture files and repo target roots from runtime assets in artifact mode.
- `assets/lua/tests/test-constraints-integration-config.fnl`: skip repo-root Makefile/CMake assertions when no repository checkout/build root is present.
- `assets/lua/constraints/baseline-data.fnl`: update only exact stale baseline entries caused by line shifts from these fixes, with substantive reasons.

### Task 1: Fix Actual Windows Separator Normalization

**Files:**
- Modify: `assets/lua/constraints/source.fnl:30-45`
- Test: `assets/lua/tests/test-constraints-source.fnl:84-154,238-349,420-437`

**Interfaces:**
- Consumes: `Source.discover(target)` returning absolute record paths and helper exports `_normalize-path-separators`, `_path-under-root?`.
- Produces: module names such as `foo.bar` and relative paths such as `nested/deep.fnl` from native Windows paths such as `D:\tmp\space\unit\foo\bar.fnl`.

- [ ] **Step 1: Add or correct direct helper assertions for one-backslash strings**

  Ensure `test-constraints-source.fnl` includes assertions equivalent to:

  ```fennel
  (local Source (require :constraints.source))
  (local normalize Source._normalize-path-separators)
  (assert (= (normalize "D:\\tmp\\space\\unit\\foo\\bar.fnl")
             "D:/tmp/space/unit/foo/bar.fnl"))
  (assert (Source._path-under-root? "D:\\tmp\\space\\unit\\foo\\bar.fnl"
                                    "D:\\tmp\\space\\unit"))
  ```

  If those assertions already exist, make them fail before the implementation change by verifying they currently exercise the exact helper used by `compute-module` and `compute-relative-path`.

- [ ] **Step 2: Fix the normalization pattern**

  In `constraints/source.fnl`, make `normalize-path-separators` match the same single-backslash behavior that fixed `llm/external-unit-mcp/service.fnl`. The intended implementation is:

  ```fennel
  (fn normalize-path-separators [path]
    (local s (if path path ""))
    (select 1 (string.gsub s "\\" "/")))
  ```

  Keep `path-under-root?` case-insensitive and boundary-checked.

- [ ] **Step 3: Make constraint source tests compare absolute paths**

  Update remaining assertions that compare `Source.discover` paths to non-absolute temp paths. Required replacements:

  ```fennel
  (assert (= (. result.files 1) (fs.absolute "/tmp/space/constraints-one.fnl"))
          "files list should contain the absolute specified file")
  (assert (= (fs.parent (. records 1 :path)) (fs.absolute dir)))
  (assert (= r.path (fs.absolute fnl-path)) "only .fnl file should be discovered")
  ```

- [ ] **Step 4: Validate and commit**

  Run:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/constraints/source.fnl --file assets/lua/tests/test-constraints-source.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m constraints.runner:main -- --output summary --target repo
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" XDG_DATA_HOME=/tmp/space/tests/xdg-data SKIP_KEYRING_TESTS=1 ./build/space -m tests.test-constraints-source:main
  git add assets/lua/constraints/source.fnl assets/lua/tests/test-constraints-source.fnl assets/lua/constraints/baseline-data.fnl
  git commit -m "fix(lua): normalize constraint source Windows paths"
  ```

### Task 2: Guard POSIX Symlink Test on Windows

**Files:**
- Modify: `assets/lua/tests/test-external-unit-mcp.fnl:760-789`

**Interfaces:**
- Consumes: `Process.run` and `fs.stat`.
- Produces: the symlink-ancestor rejection test runs only when a symlink was actually created and recognized by `fs.stat(...).is-symlink`; otherwise it prints a Windows/capability skip message and returns successfully.

- [ ] **Step 1: Replace the hard symlink assertion with a capability guard**

  In `test-create-source-rejects-symlinked-ancestor`, keep the `ln -s` attempt. Replace the unconditional assertions with:

  ```fennel
  (if (not= symlink-result.exit-code 0)
      (do
        (print (.. "Skipping symlink ancestor test: ln -s unavailable: "
                   (or symlink-result.stderr symlink-result.stdout "")))
        (lua "return true"))
      (let [symlink-stat (fs.stat symlink-path)]
        (when (not symlink-stat.is-symlink)
          (print "Skipping symlink ancestor test: symlink not reported by fs.stat")
          (lua "return true"))))
  ```

  Do not skip after the symlink is verified; the security assertion must still run on POSIX platforms.

- [ ] **Step 2: Validate and commit**

  Run:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-external-unit-mcp.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m constraints.runner:main -- --output summary --target repo
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" XDG_DATA_HOME=/tmp/space/tests/xdg-data SKIP_KEYRING_TESTS=1 ./build/space -m tests.test-external-unit-mcp:main
  git add assets/lua/tests/test-external-unit-mcp.fnl assets/lua/constraints/baseline-data.fnl
  git commit -m "fix(test): skip symlink ancestor check without symlink support"
  ```

### Task 3: Make Constraint Fixture Tests Artifact-Aware

**Files:**
- Modify: `assets/lua/tests/test-constraints-rules-layout-interactive-precision.fnl` around the production `button-widget.fnl` fixture test.
- Modify: `assets/lua/tests/test-constraints-default-run.fnl:163-221,285-391`

**Interfaces:**
- Consumes: `SPACE_ASSETS_PATH` and `runtime.assets-path`.
- Produces: fixture paths under the bundled `assets/lua` tree when running from `build/dist/windows` without checkout.

- [ ] **Step 1: Add a compact asset Lua root helper in each file**

  Use an explicit, no-silent-fallback helper that stays below module-length limits:

  ```fennel
  (fn asset-lua-root []
    (local runtime (require :runtime))
    (local env-assets (os.getenv "SPACE_ASSETS_PATH"))
    (local assets-path (if env-assets env-assets
                         runtime.assets-path runtime.assets-path
                         "assets"))
    (fs.join-path assets-path "lua"))
  ```

- [ ] **Step 2: Update real-file fixture paths**

  Replace CWD-relative paths with `asset-lua-root` joins. Required patterns:

  ```fennel
  (local lua-root (asset-lua-root))
  (local file-path (fs.absolute (fs.join-path lua-root "next-app" "button-widget.fnl")))
  (local fixture-path (fs.absolute (fs.join-path lua-root "tests" "data" "constraint-fixture.fnl")))
  (local target {:kind :files :files [fixture-path] :module-roots [(fs.absolute lua-root)]})
  ```

- [ ] **Step 3: For repo-target default-run tests, use runtime assets when no checkout root exists**

  In `test-constraints-default-run.fnl`, where a repo target or default argv currently resolves `assets/lua` under CWD, pass an explicit root or environment that points to `(asset-lua-root)` so the runner tests exercise the bundled asset tree.

- [ ] **Step 4: Validate and commit**

  Run:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-constraints-rules-layout-interactive-precision.fnl --file assets/lua/tests/test-constraints-default-run.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m constraints.runner:main -- --output summary --target repo
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" XDG_DATA_HOME=/tmp/space/tests/xdg-data SKIP_KEYRING_TESTS=1 ./build/space -m tests.test-constraints-rules-layout-interactive-precision:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" XDG_DATA_HOME=/tmp/space/tests/xdg-data SKIP_KEYRING_TESTS=1 ./build/space -m tests.test-constraints-default-run:main
  git add assets/lua/tests/test-constraints-rules-layout-interactive-precision.fnl assets/lua/tests/test-constraints-default-run.fnl assets/lua/constraints/baseline-data.fnl
  git commit -m "fix(test): resolve constraint fixtures from runtime assets"
  ```

### Task 4: Skip Repo-Root Integration Config Tests Without Checkout

**Files:**
- Modify: `assets/lua/tests/test-constraints-integration-config.fnl:1-110`

**Interfaces:**
- Consumes: current working directory, `fs.exists`, `fs.parent`.
- Produces: Makefile/CMake wiring assertions still run from a repository checkout/build tree, but skip with an explicit message from artifact-only Windows runtime.

- [ ] **Step 1: Convert repo-root assertion to detection plus skip**

  Change the helper that currently asserts repository root/build directory so it returns `nil` when neither `Makefile` nor `CMakeLists.txt` can be found in CWD or its parent. Each repo-root integration test should begin:

  ```fennel
  (local root (repo-root-or-nil))
  (when (not root)
    (print "Skipping constraints integration config test: repository checkout not available")
    (lua "return true"))
  ```

  Keep the assertions unchanged when `root` exists.

- [ ] **Step 2: Validate and commit**

  Run:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-constraints-integration-config.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m constraints.runner:main -- --output summary --target repo
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" XDG_DATA_HOME=/tmp/space/tests/xdg-data SKIP_KEYRING_TESTS=1 ./build/space -m tests.test-constraints-integration-config:main
  git add assets/lua/tests/test-constraints-integration-config.fnl assets/lua/constraints/baseline-data.fnl
  git commit -m "fix(test): skip repo config checks without checkout"
  ```

### Task 5: Windows CI Rerun

**Files:**
- No source edits expected.

**Interfaces:**
- Consumes: commits from Tasks 1-4.
- Produces: green `test.yml` run on `opencode/workflow-debug/test-20260801132707`.

- [ ] **Step 1: Run local validation**

  ```bash
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 2: Supervisor pushes and polls CI**

  ```bash
  git push origin opencode/workflow-debug/test-20260801132707
  .opencode/skills/github-workflow-debug/scripts/gh-workflow-debug.sh wait-run --workflow test.yml --branch opencode/workflow-debug/test-20260801132707 --sha $(git rev-parse HEAD) --timeout 7200 --json
  ```

  Expected: `conclusion` is `success`.

## Self-Review

- Spec coverage: Covers all remaining failed clusters from run `30714164393`: symlink capability, constraints-source Windows separator/absolute tests, runtime asset fixtures, and repo-root integration config checks.
- Placeholder scan: No TBD/implement-later placeholders; each task has exact files, behavior, commands, and commit messages.
- Type consistency: Path helpers return strings; skip guards return from tests with `true`; logical outputs remain slash-delimited.
