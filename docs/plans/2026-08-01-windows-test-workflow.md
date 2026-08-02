# Windows Test Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `test.yml` Windows fast-suite job pass by removing Windows path assumptions from Fennel source/unit tooling and runtime-layout-sensitive tests.

**Architecture:** Keep the Windows CI workflow shape intact and fix the path handling at the Fennel boundaries that consume filesystem paths. The source/unit logic should accept both `/` and `\\` separators, produce stable slash-delimited logical identifiers where the API promises logical source ids/modules, and tests should compare against absolute runtime paths where production APIs return absolutes.

**Tech Stack:** GitHub Actions `test.yml`; Space Fennel modules under `assets/lua`; native `fs` binding exposed by `src/lua_fs.cpp`; validation through `tools.fennel-check`, constraints, focused Fennel tests, and the Windows CI debug branch loop.

## Global Constraints

- Use `space-fennel` and `space-testing-runtime` rules for all `.fnl` changes.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- Run Fennel validation in order: compile check, constraints, focused Fennel tests, broader relevant suite / CI.
- Keep the debug branch trigger in `.github/workflows/test.yml` only while debugging; remove it from the final landed commit.
- No broad C++ `fs` API behavior change unless a task proves the Fennel-local fix cannot cover the failing Windows cases.
- Preserve logical source ids with `/` separators (for example `components/view.fnl`) even on Windows.

---

## File Structure

- `assets/lua/llm/external-unit-mcp/service.fnl`: owns external-unit source artifact ids and source path resolution. Make its basename, relative path, and containment checks separator-agnostic.
- `assets/lua/constraints/source.fnl`: owns source discovery records, module-name derivation, and relative-path derivation. Make root-prefix matching accept `/` and `\\`, and return slash-delimited module/relative paths.
- `assets/lua/tests/test-external-unit-mcp.fnl`: focused regression tests for Windows-style owned paths/source ids and runtime-neutral symlink behavior.
- `assets/lua/tests/test-constraints-source.fnl`: focused regression tests for absolute path comparisons and Windows separator handling.
- `assets/lua/tests/test-constraints-rules-test-isolation-wra.fnl`: real-file regression should locate bundled test sources via `runtime.assets-path` or `SPACE_ASSETS_PATH`, not CWD.
- `assets/lua/tests/test-constraints-rules-test-isolation-precision.fnl`: same runtime-asset-path fix for the activity-slots real-file regression.
- `.github/workflows/test.yml`: temporary debug-branch trigger only; final landing removes the debug branch entry.

### Task 1: External Unit MCP Source IDs Are Separator-Agnostic

**Files:**
- Modify: `assets/lua/llm/external-unit-mcp/service.fnl:20-60,164-205`
- Test: `assets/lua/tests/test-external-unit-mcp.fnl`

**Interfaces:**
- Consumes: existing `fs.absolute`, `fs.parent`, `fs.join-path`, `fs.stat`, `fs.exists`.
- Produces: source artifact `:source-id` values that are logical slash-delimited strings, and `resolve-source-path(unit, source-id, operation)` that accepts logical source ids and safely resolves them under native filesystem paths.

- [ ] **Step 1: Add focused regression coverage**

  Add tests near the existing external-unit source artifact/read-source tests. The tests should prove the behavior without requiring a Windows runner by constructing units whose `owned-paths` contain backslash-separated strings that mimic Windows native paths.

  Required test cases:

  ```fennel
  (fn test-path-basename-accepts-backslash-owned-path []
    ;; Register a flat unit with an owned path containing backslashes.
    ;; `service:inspect` must report source-handle.source-id = "bubble-overlay.fnl",
    ;; not the whole `C:\\...\\bubble-overlay.fnl` path.
    )

  (fn test-directory-unit-source-id-uses-logical-slashes-for-backslash-paths []
    ;; Register a directory unit with unit root and nested file paths represented
    ;; with backslashes. `service:inspect` must include `components/view.fnl` and
    ;; `init.fnl` source ids.
    )
  ```

  If direct `fs.exists` requirements make synthetic Windows paths impractical on Linux, add exported/internal test-only helper coverage only if already established in this module is not needed; otherwise rely on the existing CI failures and add assertions to the current directory-unit tests that all artifact ids do not contain `:` or `\\`.

- [ ] **Step 2: Run the focused test to observe current Linux baseline**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data SKIP_KEYRING_TESTS=1 \
  ./build/space -m tests.test-external-unit-mcp:main
  ```

  Expected before the fix: existing Linux tests may pass, but any new synthetic Windows-path regression should fail with a source id containing a backslash/full path or a containment rejection caused by `/`-only checks.

- [ ] **Step 3: Implement separator-agnostic helpers**

  In `service.fnl`, replace `/`-only path parsing with local helpers such as:

  ```fennel
  (fn path-separator? [c]
    (or (= c "/") (= c "\\")))

  (fn normalize-logical-path [path]
    (select 1 (string.gsub (or path "") "\\\\" "/")))

  (fn path-basename [path]
    (local normalized (normalize-logical-path path))
    (local name (string.match normalized "([^/]+)$"))
    name)
  ```

  For directory-unit source ids, compare normalized `path` and normalized `unit-root` with a separator boundary, then return the relative suffix with `/` separators. Keep native paths for actual `fs.*` calls.

  For containment in `resolve-source-path`, compare normalized absolute paths and accept either exact root equality or a `/` boundary after normalizing `\\` to `/`. Do not relax `..`, absolute source-id, or symlink checks.

- [ ] **Step 4: Run compile and focused tests**

  Run:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/external-unit-mcp/service.fnl --file assets/lua/tests/test-external-unit-mcp.fnl
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data SKIP_KEYRING_TESTS=1 \
  ./build/space -m tests.test-external-unit-mcp:main
  ```

  Expected: compile passes; focused external-unit MCP tests pass on Linux.

- [ ] **Step 5: Commit**

  Commit only the service/test files from this task:

  ```bash
  git add assets/lua/llm/external-unit-mcp/service.fnl assets/lua/tests/test-external-unit-mcp.fnl
  git commit -m "fix(lua): normalize external unit source paths"
  ```

### Task 2: Constraint Source Discovery Handles Windows Paths

**Files:**
- Modify: `assets/lua/constraints/source.fnl:30-71,91-135`
- Test: `assets/lua/tests/test-constraints-source.fnl`

**Interfaces:**
- Consumes: target records with `:roots`, `:files`, and `:module-roots` from `constraints.targets`.
- Produces: file records whose `:path` is absolute, `:module` is root-relative dotted module text when under a module root, and `:relative-path` is slash-delimited when under a module root.

- [ ] **Step 1: Add/adjust tests for absolute and separator-normalized records**

  Update expectations where `Source.discover` returns absolute paths:

  ```fennel
  (assert (. paths (fs.absolute (fs.join-path dir "alpha.fnl")))
          "alpha.fnl should be discovered")
  (assert (= r.path (fs.absolute file-path))
          "path should match the absolute original file")
  ```

  Add direct regression tests for Windows-style strings if they can be tested without touching the filesystem. If helper functions remain private, cover the behavior through existing module/relative-path tests and the Windows CI rerun.

- [ ] **Step 2: Run the focused constraint source test**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data SKIP_KEYRING_TESTS=1 \
  ./build/space -m tests.test-constraints-source:main
  ```

  Expected before the fix: Linux should identify any changed expectation mistakes; Windows CI currently fails on this module.

- [ ] **Step 3: Implement separator-aware module and relative-path computation**

  In `source.fnl`, add local helpers:

  ```fennel
  (fn normalize-path-separators [path]
    (select 1 (string.gsub (or path "") "\\\\" "/")))

  (fn path-under-root? [file-path root]
    (let [file (normalize-path-separators file-path)
          root-path (normalize-path-separators root)
          file-lower (file:lower)
          root-lower (root-path:lower)]
      (or (= file-lower root-lower)
          (= (string.sub file-lower 1 (+ (# root-lower) 1))
             (.. root-lower "/")))))
  ```

  Use normalized strings for matching, suffix extraction, slash-to-dot module conversion, and `:relative-path`. Preserve existing behavior when no root matches: return the original `file-path` string.

- [ ] **Step 4: Run compile, constraints, and focused tests**

  Run:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/constraints/source.fnl --file assets/lua/tests/test-constraints-source.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data SKIP_KEYRING_TESTS=1 \
  ./build/space -m tests.test-constraints-source:main
  ```

  Expected: all commands pass.

- [ ] **Step 5: Commit**

  ```bash
  git add assets/lua/constraints/source.fnl assets/lua/tests/test-constraints-source.fnl
  git commit -m "fix(lua): make constraint source paths portable"
  ```

### Task 3: Constraint Real-File Regression Tests Use Runtime Assets

**Files:**
- Modify: `assets/lua/tests/test-constraints-rules-test-isolation-wra.fnl:297-308`
- Modify: `assets/lua/tests/test-constraints-rules-test-isolation-precision.fnl` around the `test-scene-activity-slots.fnl` real-file regression

**Interfaces:**
- Consumes: `runtime.assets-path` and/or `SPACE_ASSETS_PATH`.
- Produces: tests that locate bundled `assets/lua/tests/*.fnl` in both checkout-based Linux runs and artifact-only Windows runs.

- [ ] **Step 1: Add a shared local helper in each touched test file**

  In each file near the real-file regression, resolve the asset Lua root with this behavior:

  ```fennel
  (fn asset-lua-root []
    (local runtime (require :runtime))
    (local assets-path (or runtime.assets-path (os.getenv "SPACE_ASSETS_PATH") "assets"))
    (fs.join-path assets-path "lua"))
  ```

  Use it to build the real-file paths:

  ```fennel
  (local lua-root (asset-lua-root))
  (local sandbox-path (fs.absolute (fs.join-path lua-root "tests" "test-sandbox-activity.fnl")))
  (local target {:kind :files
                 :files [sandbox-path]
                 :module-roots [(fs.absolute lua-root)]})
  ```

  Apply the same pattern for `test-scene-activity-slots.fnl`.

- [ ] **Step 2: Run compile and the two focused tests**

  Run:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-constraints-rules-test-isolation-wra.fnl --file assets/lua/tests/test-constraints-rules-test-isolation-precision.fnl
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data SKIP_KEYRING_TESTS=1 \
  ./build/space -m tests.test-constraints-rules-test-isolation-wra:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data SKIP_KEYRING_TESTS=1 \
  ./build/space -m tests.test-constraints-rules-test-isolation-precision:main
  ```

  Expected: compile and both focused tests pass.

- [ ] **Step 3: Commit**

  ```bash
  git add assets/lua/tests/test-constraints-rules-test-isolation-wra.fnl assets/lua/tests/test-constraints-rules-test-isolation-precision.fnl
  git commit -m "fix(lua): resolve constraint regression fixtures from assets"
  ```

### Task 4: Debug Branch CI Verification and Cleanup Prep

**Files:**
- Modify only if necessary: `.github/workflows/test.yml` temporary debug branch trigger while on `opencode/workflow-debug/test-20260801132707`

**Interfaces:**
- Consumes: committed fixes from Tasks 1-3.
- Produces: a green `test.yml` run on the debug branch, ready for CI debug review and final squash landing.

- [ ] **Step 1: Run local validation ladder**

  Run:

  ```bash
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: all pass. If any fail, capture the first real failure and route back through systematic debugging before more edits.

- [ ] **Step 2: Push the debug branch and wait for CI**

  ```bash
  git push origin opencode/workflow-debug/test-20260801132707
  .opencode/skills/github-workflow-debug/scripts/gh-workflow-debug.sh wait-run --workflow test.yml --branch opencode/workflow-debug/test-20260801132707 --sha $(git rev-parse HEAD) --timeout 7200 --json
  ```

  Expected: conclusion is `success`. If it fails, inspect the first failed job log and update the evidence before additional fixes.

- [ ] **Step 3: Do not remove the debug trigger here**

  The final landing flow removes `opencode/workflow-debug/test-20260801132707` from `.github/workflows/test.yml` after reviewer approval and before the final squash commit on `main`.

## Self-Review

- Spec coverage: Covers the three observed failure clusters: external unit source ids/path containment, constraint source module/relative-path path handling, and real-file regression asset resolution under the Windows artifact-only job.
- Placeholder scan: No task contains TBD/implement-later placeholders; each task names exact files and commands.
- Type consistency: Source ids remain strings, file records keep `:path`, `:module`, `:relative-path`, and target tables keep `:kind`, `:files`, `:module-roots`.
