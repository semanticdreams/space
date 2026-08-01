# Origin Main Constraint Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a validated safety integration branch that merges `origin/main` into the local Fennel constraint-system work and is ready for a PR targeting `main`.

**Architecture:** Create `integration/origin-main-constraints-2026-07-31` from the current local `main`, merge `origin/main`, and reconcile conflicts and validation failures through implementer/reviewer gates. Treat the newer mainline runtime/path architecture as the default contract while preserving still-current Fennel widget, lifecycle, layout, Scene, Sandbox, and structure invariants.

**Tech Stack:** Git, GitHub CLI, Fennel/Lua under `assets/lua`, C++17, Make/CMake, CTest, Markdown docs.

## Global Constraints

- The worktree starts clean on local `main`.
- Local `main` and `origin/main` are diverged; this is not a fast-forward.
- Use a safety branch named `integration/origin-main-constraints-2026-07-31`.
- Do not rebase or cherry-pick the local commit stack as the default integration path.
- Merge `origin/main` into the safety branch.
- Treat the newer `origin/main` architecture as the default contract unless a local constraint encodes an explicitly still-current invariant.
- If production code violates a still-current constraint, fix production code.
- If a constraint encodes an old contract contradicted by accepted `origin/main` architecture, update the constraint rule, focused tests, and docs together.
- If the intended contract is ambiguous, stop and report `HUMAN_DECISION_REQUIRED` rather than weakening the rule or contorting production code.
- Do not add broad baselines or allowlists just to make the merge green.
- Baseline-data changes are acceptable only for reviewed, precise known exceptions.
- `assets/lua/constraints/**` and `assets/lua/tests/test-constraints-*.fnl` remain the authoritative constraint contract and regression suite.
- Preserve `origin/main` runtime asset discovery and native log path behavior unless a reviewed conflict resolution intentionally changes it.
- Update `docs/dev/experimental-constraints.md` if constraint behavior changes.
- Update runtime-path documentation only if developer-visible runtime asset or log path behavior changes.
- Merge conflicts are resolved through implementation review, not by supervisor production-code edits.
- Constraint statuses other than `pass` block readiness and require diagnosis.
- Test or build failures after the merge are handled through systematic debugging before any fix is dispatched.
- Validation ladder: `make fennel-check`, `make constraints`, focused tests for changed areas, then `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`.

---

### Task 1: Create the Safety Branch and Merge `origin/main`

**Files:**
- Modify: Git branch state for `integration/origin-main-constraints-2026-07-31`
- Modify: Git merge metadata if the merge starts or completes
- Test: none

**Interfaces:**
- Consumes: clean local `main`, committed spec `docs/specs/2026-07-31-origin-main-constraint-integration-design.md`, remote ref `origin/main`.
- Produces: safety integration branch containing the merge attempt; either a completed merge commit or a merge-in-progress state with conflict inventory.

- [ ] **Step 1: Verify starting state**

  Run:

  ```bash
  git status --short --branch
  git branch --show-current
  git merge-base --is-ancestor ca276ef2 HEAD
  ```

  Expected: current branch is `main`, no file entries are listed by `git status --short`, and spec commit `ca276ef2` is reachable from `HEAD`.

- [ ] **Step 2: Fetch current mainline**

  Run:

  ```bash
  git fetch origin main
  git rev-parse HEAD
  git rev-parse origin/main
  git rev-list --left-right --count HEAD...origin/main
  git log --oneline --left-right --cherry-pick --max-count=120 HEAD...origin/main
  ```

  Expected: local and remote tips plus divergence counts are recorded in the implementer report.

- [ ] **Step 3: Create the safety branch**

  Run:

  ```bash
  git switch -c integration/origin-main-constraints-2026-07-31
  git status --short --branch
  ```

  Expected: current branch is `integration/origin-main-constraints-2026-07-31` and the worktree is clean.

- [ ] **Step 4: Merge without rebasing**

  Run:

  ```bash
  git merge --no-ff origin/main
  ```

  Expected: Git either creates a merge commit or stops with explicit conflicts. Do not use broad `--ours`, `--theirs`, rebase, or cherry-pick to avoid the merge.

- [ ] **Step 5: Capture merge outcome**

  Run:

  ```bash
  git status --short --branch
  git diff --name-only --diff-filter=U
  git diff --check
  ```

  Expected: if conflicts exist, the report lists each conflicted path; if no conflicts exist, the branch has a merge commit and remains otherwise clean.

- [ ] **Step 6: Commit**

  If Git completed the merge automatically, keep the merge commit. If the merge stopped for conflicts, do not create a commit in this task.

- [ ] **Step 7: Review gate**

  Reviewer verifies the safety branch exists, local `main` is untouched, `origin/main` was merged rather than rebased, and any unclean state is only Git's merge-in-progress conflict state.

---

### Task 2: Resolve Textual Merge Conflicts

**Files:**
- Modify: only files reported by `git diff --name-only --diff-filter=U`
- Likely conflict areas: `assets/lua/**`, `assets/lua/constraints/**`, `assets/lua/tests/test-constraints-*.fnl`, `apps/space/main.cpp`, `src/**`, `Makefile`, `CMakeLists.txt`, `.github/workflows/**`, `docs/**`
- Test: `git diff --check`, conflict-marker search

**Interfaces:**
- Consumes: merge-in-progress state from Task 1.
- Produces: no unresolved unmerged index entries, no conflict markers, and a merge commit.

- [ ] **Step 1: Inspect conflicted files**

  Run:

  ```bash
  git diff --name-only --diff-filter=U
  git diff --cc
  ```

  For each conflicted file, inspect the combined diff and compare the local side against the `origin/main` side before editing.

- [ ] **Step 2: Apply conflict-resolution rules**

  Resolve each conflict using this decision table:

  | Situation | Resolution |
  | --- | --- |
  | Runtime asset discovery or native log path conflict | Preserve `origin/main` behavior unless a reviewed invariant requires a change. |
  | Fennel widget/layout/lifecycle conflict | Preserve widget constructor closures, explicit `Layout` ownership, child teardown, direct layout transform writes during layout, shallow dirtying, and required context assertions. |
  | Production code violates a still-current constraint | Change production code and keep the constraint. |
  | Constraint encodes an old contract superseded by `origin/main` | Update the constraint, focused test, and docs in Tasks 3 and 5. |
  | Contract ownership is unclear | Stop and report `HUMAN_DECISION_REQUIRED` with the file, hunk, and exact architecture question. |

- [ ] **Step 3: Reject conflict shortcuts**

  Run:

  ```bash
  rg -n "<<<<<<<|=======|>>>>>>>" .
  git diff --check
  ```

  Expected: no conflict markers and no whitespace errors.

- [ ] **Step 4: Stage resolved conflicts**

  Run:

  ```bash
  git status --short --branch
  git add $(git diff --name-only --diff-filter=U)
  git status --short --branch
  ```

  Expected: no `UU`, `AA`, `DD`, `AU`, `UA`, `DU`, or `UD` entries remain.

- [ ] **Step 5: Complete the merge commit**

  Run:

  ```bash
  git commit -m "Merge remote-tracking branch 'origin/main' into integration/origin-main-constraints-2026-07-31"
  ```

  Expected: the merge commit is created.

- [ ] **Step 6: Review gate**

  Reviewer verifies all conflict resolutions, confirms no wholesale `ours` or `theirs` shortcut hid architecture changes, and flags any queued constraint/test/docs updates for Tasks 3 and 5.

---

### Task 3: Reconcile Fennel Compile and Constraint Contracts

**Files:**
- Modify: `assets/lua/constraints/**` only when a stale constraint contract is identified
- Modify: `assets/lua/tests/test-constraints-*.fnl` for every changed constraint rule
- Modify: `assets/lua/**` when production Fennel violates a still-current constraint
- Modify: `docs/dev/experimental-constraints.md` when constraint behavior changes
- Test: Fennel compile gate, constraints gate, focused constraint tests

**Interfaces:**
- Consumes: merged branch from Tasks 1 and 2.
- Produces: `make fennel-check` passes, `make constraints` returns `pass`, and changed constraints have focused tests.

- [ ] **Step 1: Run compile validation**

  Run:

  ```bash
  make fennel-check
  ```

  Expected: pass. If it fails, invoke systematic debugging before dispatching a fix.

- [ ] **Step 2: Run constraints validation**

  Run:

  ```bash
  make constraints
  ```

  Expected: pass with status `pass`. Any other status blocks readiness.

- [ ] **Step 3: Classify each constraint failure**

  If Step 2 fails, classify every diagnostic in the implementer report as one of:

  - `production-code-fix`: production code violates a still-current rule.
  - `constraint-contract-update`: a rule encodes an old contract superseded by accepted `origin/main` architecture.
  - `precise-baseline-update`: a reviewed, narrow known exception is required.
  - `HUMAN_DECISION_REQUIRED`: intended architecture or API contract is ambiguous.

- [ ] **Step 4: Implement the classified fix**

  For `production-code-fix`, edit the violating production file and keep the constraint unchanged.

  For `constraint-contract-update`, edit the rule under `assets/lua/constraints/rules/`, update the matching `assets/lua/tests/test-constraints-rules-*.fnl`, and update `docs/dev/experimental-constraints.md`.

  For `precise-baseline-update`, edit only `assets/lua/constraints/baseline-data.fnl` and include the exact accepted reason in the baseline entry.

  For `HUMAN_DECISION_REQUIRED`, stop without staging the disputed fix.

- [ ] **Step 5: Run focused constraint tests**

  Always run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-runner:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-default-run:main
  ```

  If a specific rule file changed, also run the matching family module: `tests.test-constraints-rules-layout:main`, `tests.test-constraints-rules-lifecycle:main`, `tests.test-constraints-rules-scene-sandbox:main`, `tests.test-constraints-rules-structure:main`, or the matching `tests.test-constraints-rules-test-isolation` module.

- [ ] **Step 6: Re-run compile and constraints**

  Run:

  ```bash
  make fennel-check
  make constraints
  ```

  Expected: both pass.

- [ ] **Step 7: Commit changed files**

  If Task 3 changed files, run:

  ```bash
  git status --short
  git diff --check
  git add assets/lua/constraints assets/lua/tests docs/dev/experimental-constraints.md assets/lua
  git commit -m "fix(lua): reconcile constraints with origin main"
  ```

  If Task 3 made no changes, report that compile and constraint validation required no constraint reconciliation commit.

- [ ] **Step 8: Review gate**

  Reviewer verifies every changed constraint has a focused test, changed constraint behavior is documented, baseline edits are precise, and no convenience bypass was introduced.

---

### Task 4: Preserve Runtime Asset and Native Log Path Behavior

**Files:**
- Modify: `apps/space/main.cpp` only if runtime bootstrap conflicts or validation failures require it
- Modify: `src/**` only if runtime asset/log bindings or path helpers require reconciliation
- Modify: `Makefile` or `CMakeLists.txt` only if test/runtime environment behavior requires reconciliation
- Modify: runtime/path focused tests under `assets/lua/tests/` only when behavior changes
- Test: build plus focused runtime/path tests

**Interfaces:**
- Consumes: merged `origin/main` runtime-path behavior and Space test environment variables.
- Produces: preserved or intentionally documented runtime asset discovery and native log path behavior.

- [ ] **Step 1: Inventory runtime/path differences**

  Run:

  ```bash
  git diff --name-only origin/main...HEAD -- apps src Makefile CMakeLists.txt assets/lua/tests
  rg -n "SPACE_ASSETS_PATH|SPACE_LOG_DIR|get-asset-path|asset path|log path|XDG_DATA_HOME" apps src Makefile CMakeLists.txt assets/lua/tests
  ```

  Expected: the report identifies whether runtime path behavior was touched by the integration.

- [ ] **Step 2: Compare against `origin/main`**

  Run:

  ```bash
  git diff origin/main...HEAD -- apps src Makefile CMakeLists.txt
  ```

  Expected: mainline runtime asset discovery and native log path behavior remain intact unless a reviewed reconciliation requires a change.

- [ ] **Step 3: Fix validated compatibility breaks only**

  If focused tests or build output show runtime/path breakage, fix the smallest implicated file while preserving these invariants:

  - `SPACE_ASSETS_PATH=$(pwd)/assets` resolves repository assets for tests.
  - `XDG_DATA_HOME=/tmp/space/tests/xdg-data` keeps test data outside the repo.
  - Native log configuration from `origin/main` remains developer-visible unless intentionally documented.

- [ ] **Step 4: Run focused runtime/path validation**

  Run:

  ```bash
  make build
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-check-cli:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-constraints-integration-config:main
  ```

  Expected: build and focused tests pass.

- [ ] **Step 5: Commit runtime/path reconciliation changes**

  If Task 4 changed files, run:

  ```bash
  git status --short
  git diff --check
  git add apps src Makefile CMakeLists.txt assets/lua/tests
  git commit -m "fix(engine): preserve runtime paths after merge"
  ```

  If Task 4 made no changes, report that runtime/path behavior was preserved without a commit.

- [ ] **Step 6: Review gate**

  Reviewer verifies the branch did not regress runtime asset discovery, native log path behavior, or test isolation.

---

### Task 5: Update Documentation for Actual Contract Changes

**Files:**
- Modify: `docs/dev/experimental-constraints.md` if constraint behavior changes
- Modify: `AGENTS.md` only if validation workflow instructions become inaccurate after the merge
- Create: `docs/dev/features/runtime-paths.md` only if this integration intentionally changes developer-visible runtime asset or log path behavior
- Test: documentation search checks

**Interfaces:**
- Consumes: reconciliation decisions from Tasks 2 through 4.
- Produces: docs that match actual merged behavior.

- [ ] **Step 1: Decide whether docs are required**

  Run:

  ```bash
  git diff --name-only origin/main...HEAD -- assets/lua/constraints assets/lua/tests docs/dev AGENTS.md apps src Makefile CMakeLists.txt
  ```

  Documentation is required only when a constraint contract, baseline policy, validation workflow, or developer-visible runtime path behavior actually changed.

- [ ] **Step 2: Update constraints documentation when needed**

  If any constraint rule behavior changed, update `docs/dev/experimental-constraints.md` with the affected family, the merged contract, the focused test module, and the rule that broad baselines/allowlists remain disallowed.

- [ ] **Step 3: Update runtime-path documentation when needed**

  If runtime asset or log path behavior intentionally changed, create `docs/dev/features/runtime-paths.md` documenting asset discovery, `SPACE_ASSETS_PATH`, native log directory behavior, and the compatibility reason for the integration change.

- [ ] **Step 4: Validate docs references**

  Run:

  ```bash
  rg -n "constraints|constraint|SPACE_ASSETS_PATH|SPACE_LOG_DIR|runtime path|log path" docs/dev AGENTS.md
  ```

  Expected: docs agree with commands and behavior validated in earlier tasks.

- [ ] **Step 5: Commit docs changes**

  If Task 5 changed files, run:

  ```bash
  git status --short
  git add docs/dev AGENTS.md
  git commit -m "docs: document constraint integration behavior"
  ```

  If Task 5 made no changes, report that no docs update was needed because behavior was preserved.

- [ ] **Step 6: Review gate**

  Reviewer verifies docs are factual, scoped to actual changes, and do not describe hypothetical conflicts.

---

### Task 6: Run Full Validation and Fix Failures Through Review

**Files:**
- Modify: only files implicated by failing validation commands
- Test: compile gate, constraints gate, focused tests, full suite, hygiene checks

**Interfaces:**
- Consumes: merged and reconciled branch from Tasks 1 through 5.
- Produces: passing validation evidence and a clean worktree.

- [ ] **Step 1: Run compile check**

  Run:

  ```bash
  make fennel-check
  ```

  Expected: pass.

- [ ] **Step 2: Run constraints**

  Run:

  ```bash
  make constraints
  ```

  Expected: pass with status `pass`.

- [ ] **Step 3: Run focused tests for changed areas**

  Run the focused tests from Tasks 3 and 4 that match changed files. For every additional changed Fennel test module under `assets/lua/tests/test-*.fnl`, run that module through `./build/space -m` with the module name derived from the file basename. For example, a changed `assets/lua/tests/test-sized.fnl` runs as `tests.test-sized:main` with the standard `SKIP_KEYRING_TESTS`, `XDG_DATA_HOME`, `SPACE_DISABLE_AUDIO`, `SPACE_ASSETS_PATH`, `FENNEL_PATH`, and `FENNEL_MACRO_PATH` environment from Task 3.

  Expected: all focused tests pass.

- [ ] **Step 4: Run the full suite**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: pass.

- [ ] **Step 5: Handle failures through systematic debugging**

  If any command fails, stop at the first failure, invoke systematic debugging, classify the root cause, dispatch an implementer for the exact fix, send the patch to reviewer, commit the reviewed fix, and restart this task from Step 1.

- [ ] **Step 6: Run final hygiene checks**

  Run:

  ```bash
  rg -n "<<<<<<<|=======|>>>>>>>" .
  git diff --check
  git merge-base --is-ancestor origin/main HEAD
  git status --short --branch
  ```

  Expected: no conflict markers, no whitespace errors, `origin/main` is an ancestor of `HEAD`, and the worktree is clean on `integration/origin-main-constraints-2026-07-31`.

- [ ] **Step 7: Review gate**

  Reviewer verifies validation evidence, constraint impact reporting for Fennel-facing changes, and clean tree state.

---

### Task 7: Push Safety Branch and Open PR to `main`

**Files:**
- Modify: Git remote branch metadata
- Create: PR body via GitHub CLI
- Test: branch ancestry and clean status checks

**Interfaces:**
- Consumes: validated integration branch from Task 6.
- Produces: pushed branch and PR targeting `main`.

- [ ] **Step 1: Verify PR readiness**

  Run:

  ```bash
  git status --short --branch
  git merge-base --is-ancestor origin/main HEAD
  git log --oneline --graph --decorate --max-count=40
  ```

  Expected: worktree is clean, `origin/main` is an ancestor of `HEAD`, and recent history shows the merge and reviewed reconciliation commits.

- [ ] **Step 2: Prepare PR summary**

  Create `/tmp/space-origin-main-constraint-integration-pr.md` after Task 6 has produced reviewed evidence. The body must include these exact sections:

  - `## Summary`: state that `origin/main` was merged into `integration/origin-main-constraints-2026-07-31`, constraints were reconciled with the merged architecture, and runtime asset/native log path behavior was preserved or intentionally documented.
  - `## Constraint contract triage`: list production-code fixes, constraint contract updates, baseline updates, and human decisions. Use `none` for categories with no reviewed changes.
  - `## Validation`: list the exact Task 6 result for `make fennel-check`, `make constraints`, each focused test command, and `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`.

- [ ] **Step 3: Push the safety branch**

  Run:

  ```bash
  git push -u origin integration/origin-main-constraints-2026-07-31
  ```

  Expected: remote branch is created or updated.

- [ ] **Step 4: Create PR targeting `main`**

  Run:

  ```bash
  gh pr create --base main --head integration/origin-main-constraints-2026-07-31 --title "Integrate origin/main with Fennel constraints" --body-file /tmp/space-origin-main-constraint-integration-pr.md
  ```

  Expected: GitHub returns a PR URL.

- [ ] **Step 5: Report final handoff**

  Report the PR URL, final branch name, merge status, validation evidence, constraint-impact summary, and any follow-up risks.

## Acceptance Criteria

- The integration branch includes `origin/main` and the local constraint-system work.
- There are no unresolved merge conflicts.
- Constraint rules accurately reflect the merged architecture and are not weakened for convenience.
- Any changed constraint behavior is covered by focused tests and documented.
- Runtime asset/log path behavior from `origin/main` is preserved or intentionally documented.
- `make fennel-check` passes.
- `make constraints` passes with status `pass`.
- Focused tests for changed constraint/runtime areas pass.
- `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test` passes.
- The final worktree is clean.
- The safety branch is pushed and a PR targeting `main` is open.

## Out of Scope

- Rebasing local `main` onto `origin/main`.
- Cherry-picking hundreds of local commits onto `origin/main`.
- Directly merging into local `main`.
- Directly pushing to `origin/main`.
- Adding broad constraint baselines or allowlists.
- Weakening constraints to make validation green.
- Rewriting unrelated Fennel UI, runtime, graph, or CI architecture.
- Debugging remote GitHub Actions beyond creating the PR-ready branch.
