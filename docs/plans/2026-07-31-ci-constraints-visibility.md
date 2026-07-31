# CI Constraints Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make GitHub Actions surface the experimental Fennel constraints gate as an explicit early Linux test step.

**Architecture:** Preserve the existing CTest fixture as the authoritative blocking gate, and add a named `make constraints` step after the Linux build in `.github/workflows/test.yml` so failures are easy to find. Update the constraints documentation to describe both the explicit CI step and the CTest fixture gate.

**Tech Stack:** GitHub Actions YAML, Make, CTest, Markdown docs.

## Global Constraints

- `.github/workflows/test.yml` contains an explicit Linux CI step that runs `make constraints` after build and before the broader CTest step.
- The broader CTest step remains unchanged enough to continue exercising the `space_experimental_constraints` fixture.
- Documentation states both the explicit CI step and fixture-based gate.
- No other workflow files are modified.
- Local validation confirms `make constraints` still passes.
- Do not create new workflows.
- Do not change build, release, docs Pages, or devlog workflows.
- Do not change constraint runner output or Makefile behavior.
- Do not alter Windows test behavior in this slice.

---

### Task 1: Add Explicit Constraints Step to Test Workflow

**Files:**
- Modify: `.github/workflows/test.yml`
- Modify: `docs/dev/experimental-constraints.md`

**Interfaces:**
- Consumes: existing Make target `make constraints`; existing CTest fixture `space_experimental_constraints`; existing GitHub Actions Linux `test` job.
- Produces: a named GitHub Actions step that runs constraints before the broader CTest suite, plus documentation of CI behavior.

- [ ] **Step 1: Inspect current CI ordering**

  Confirm `.github/workflows/test.yml` has the Linux job sequence:

  ```yaml
      - name: Build
        env:
          CMAKE_C_COMPILER_LAUNCHER: ccache
          CMAKE_CXX_COMPILER_LAUNCHER: ccache
        run: make build

      - name: Run test suite
        env:
          SPACE_ASSETS_PATH: ${{ github.workspace }}/assets
        run: xvfb-run -a ctest --test-dir build --output-on-failure -V
  ```

- [ ] **Step 2: Add explicit Linux constraints step**

  Insert this step after `Build` and before cache stats / test suite steps if that preserves existing stats behavior; otherwise place it immediately before `Run test suite`:

  ```yaml
      - name: Run experimental constraints
        run: make constraints
  ```

  Keep the existing `Run test suite` step using CTest, so the fixture gate still runs as defense in depth. Do not alter Windows jobs.

- [ ] **Step 3: Document CI behavior**

  In `docs/dev/experimental-constraints.md`, add a short CI note explaining:
  - GitHub Actions `test.yml` runs `make constraints` explicitly after the Linux build.
  - The broader CTest suite still has the `space_experimental_constraints` fixture dependency.
  - The explicit step is for fast, named failure output; the fixture remains the structural gate.

- [ ] **Step 4: Validate changed files**

  Run:

  ```bash
  rg -n "Run experimental constraints|make constraints|space_experimental_constraints|GitHub Actions|CTest" .github/workflows/test.yml docs/dev/experimental-constraints.md CMakeLists.txt
  ```

  Then run:

  ```bash
  make constraints
  ```

  Expected: text search shows the explicit workflow step and CTest fixture references; constraints pass.

- [ ] **Step 5: Commit**

  Commit only the workflow and docs files:

  ```bash
  git add .github/workflows/test.yml docs/dev/experimental-constraints.md
  git commit -m "ci: run experimental constraints explicitly"
  ```

## Acceptance Criteria

- Linux GitHub `test` job has a clearly named `Run experimental constraints` step running `make constraints` after build and before the broader test suite.
- Existing CTest command remains present.
- Documentation explains why both explicit step and CTest fixture exist.
- No other workflow file changes.
- `make constraints` passes locally.

## Validation Ladder

1. Text search:
   ```bash
   rg -n "Run experimental constraints|make constraints|space_experimental_constraints|GitHub Actions|CTest" .github/workflows/test.yml docs/dev/experimental-constraints.md CMakeLists.txt
   ```
2. Runtime validation:
   ```bash
   make constraints
   ```

## Out of Scope

- Running or debugging GitHub Actions remotely.
- Changing constraint runner verbosity.
- Modifying Windows CI behavior.
- Modifying release, docs Pages, or devlog workflows.
