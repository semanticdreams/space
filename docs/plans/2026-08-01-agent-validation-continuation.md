# Agent Validation Continuation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Space/OpenCode workflow continue from required validation failures through systematic debugging, current-base recovery, reviewed fixes, and green validation before integration.

**Architecture:** This is an instruction/workflow-only change. Keep the canonical invariant in `AGENTS.md`, supervisor completion discipline, and the finishing skill; then align daily automation, weekly automation, SDD handoff guidance, and the developer workflow page so no entry point treats red validation as immediate `BLOCKED`.

**Tech Stack:** Markdown, OpenCode agent files, OpenCode skill files, Git/GitHub workflow instructions, focused `rg` and `git diff --check` validation.

## Global Constraints

- Committed spec: `docs/specs/2026-08-01-agent-validation-continuation-design.md`.
- All Space agent workflows must treat required validation failures as active work to investigate and resolve, not as a terminal state.
- This applies to normal implementation branches, final finishing, docs/OpenCode branches, daily devlog automation, weekly agent workflow automation, and any future scheduled or manual automation that performs required validation before integration.
- Preserve integration safety: do not report completion, push, create a PR, merge, clean up, or claim ready-to-merge while validation is red.
- Capture the failing command, failing tests, relevant output, current branch state, and `git status --porcelain`.
- Invoke `systematic-debugging` and continue investigating even when the failure appears unrelated, flaky, timing-dependent, or environmental.
- Route any repository fix through `implementer` → `reviewer` → pass, commit reviewed fixes, rerun validation, and restart finalization from the top.
- Stop for the human only when systematic debugging establishes that progress requires human input: credentials, inaccessible infrastructure, unsafe git history decisions, unreproducible behavior after reasonable evidence gathering, or a product/API/data/architecture choice.
- Before final validation and PR creation, workflows must ensure the branch is evaluated against current `origin/main`.
- If the branch is behind or remote integration would be rejected, fetch `origin`, update the feature branch by a safe merge from `origin/main` when permitted, resolve any conflicts through the normal implementer/reviewer loop, and rerun validation.
- The agent must not rebase or force-push unless the human explicitly requests it.
- No production runtime code, product tests, OpenCode schema, package configuration, model settings, or permission frontmatter changes are in scope.
- OpenCode users must restart after `.opencode/**` changes.
- Acceptance criterion: every edited workflow surface uses consistent wording for `systematic-debugging`, `implementer` → `reviewer` → pass, `origin/main` freshness, safe merge, no automatic rebase/force-push, and no immediate `BLOCKED` on validation failure.
- Validation is focused instruction validation: per-task `rg` checks, `git diff --check`, and changed-file scope inspection. Full product tests are not required unless implementation edits production, test, runtime, build, executable script, package, or schema/config files.
- HUMAN_DECISION_REQUIRED: none for this plan.

---

### Task 1: Repository and Supervisor Validation Invariants

**Files:**
- Modify: `AGENTS.md`
- Modify: `.opencode/agents/supervisor.md`
- Test: focused `rg` checks and `git diff --check` for both files

**Interfaces:**
- Consumes: committed spec `docs/specs/2026-08-01-agent-validation-continuation-design.md`
- Produces: repository-wide and supervisor-level invariant for current `origin/main` evaluation and validation-failure recovery

- [ ] **Step 1: Inspect current wording**

Read `AGENTS.md` and `.opencode/agents/supervisor.md`. Confirm the existing target sections are:
- `AGENTS.md` → `## Branch Convention`
- `.opencode/agents/supervisor.md` → `Completion discipline`, `## Core Workflow`, and `## Discipline`

- [ ] **Step 2: Add current-base validation rule to `AGENTS.md`**

Under `## Branch Convention`, immediately after the existing paragraph that names `origin/main` as the base for final validation and PR diff/base checks, add:

```markdown
Before final validation, PR creation, or any ready-to-merge claim, fetch
`origin` and evaluate the branch against current `origin/main`. If the branch
is behind `origin/main` or remote integration would be rejected, update the
feature branch by a safe merge from `origin/main` when permitted, resolve any
conflicts through `implementer` → `reviewer` → pass, commit reviewed fixes, and
rerun validation from a clean tree. Do not rebase or force-push unless the human
explicitly requests it.
```

- [ ] **Step 3: Strengthen required-validation failure policy in `AGENTS.md`**

Replace the existing paragraph that starts `If required validation fails after implementation` with:

```markdown
If required validation fails after implementation, review, or commit, do not
finish, push, create a pull request, merge, clean up the branch, or claim
ready-to-merge. Capture the failing command, failing tests, relevant output,
current branch state, and `git status --porcelain`. Invoke the
`systematic-debugging` skill and continue investigating even when the failure
appears unrelated, flaky, timing-dependent, or environmental. Establish root
cause or gather enough evidence to explain why root cause cannot be established
with available access. Route any repository fix through `implementer` →
`reviewer` → pass, commit reviewed fixes, rerun validation from a clean/current
`origin/main` base, and only proceed with the default integration action when
the required suite is green.
```

- [ ] **Step 4: Update supervisor completion discipline**

In `.opencode/agents/supervisor.md`, update the `Completion discipline` section so it preserves the existing clean-tree and committed-changes requirements and includes this contract:

```markdown
Before reporting completion, ready-to-merge, or ready-to-PR, fetch `origin` and
verify that the branch has been evaluated against current `origin/main`. If the
branch is behind `origin/main` or a remote integration action would be rejected,
do not report completion. Update by a safe merge from `origin/main` when
permitted, route conflicts or resulting repository fixes through `implementer`
→ `reviewer` → pass, commit reviewed fixes, rerun required validation, and
restart finishing checks from the top. Do not rebase or force-push unless the
human explicitly requests it.

If required validation fails, do not report completion and do not stop at the
failure summary. Capture the failing command, failing tests, relevant output,
current branch state, and `git status --porcelain`. Invoke
`systematic-debugging`, continue investigating even when the failure appears
unrelated, flaky, timing-dependent, or environmental, identify root cause or the
limits of available evidence, route any fix through `implementer` → `reviewer`
→ pass, commit reviewed fixes, rerun validation, and restart finishing checks
from the top. Report BLOCKED or HUMAN_DECISION_REQUIRED only when systematic
debugging establishes that progress requires human input: credentials,
inaccessible infrastructure, unsafe git history decisions, unreproducible
behavior after reasonable evidence gathering, or a product/API/data/architecture
choice.
```

Do not change supervisor frontmatter permissions, model, mode, temperature, or tool rules.

- [ ] **Step 5: Align supervisor summaries**

Update the supervisor `## Core Workflow` finishing step and `## Discipline` completion bullet so both reference:
- current `origin/main` evaluation before completion/integration;
- `systematic-debugging` for required validation failures;
- `implementer` → `reviewer` → pass for fixes;
- no `BLOCKED` unless systematic debugging establishes a true human-input blocker.

- [ ] **Step 6: Run focused validation for Task 1**

```bash
rg -n "origin/main|safe merge|rebase|force-push|force push|systematic-debugging|implementer.*reviewer|BLOCKED|HUMAN_DECISION_REQUIRED" AGENTS.md .opencode/agents/supervisor.md
git diff --check AGENTS.md .opencode/agents/supervisor.md
```

Expected: both files mention current `origin/main` handling, require `systematic-debugging` for red validation, preserve `implementer` → `reviewer` → pass, avoid saying validation failure alone is immediate `BLOCKED`, and have no whitespace errors.

- [ ] **Step 7: Commit Task 1 after reviewer pass**

```bash
git add AGENTS.md .opencode/agents/supervisor.md
git commit -m "docs(workflow): strengthen validation continuation policy"
```

---

### Task 2: Finishing Skill Current-Base and Red-Validation Loop

**Files:**
- Modify: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Test: focused `rg` checks and `git diff --check` for the finishing skill

**Interfaces:**
- Consumes: Task 1 repository/supervisor invariant
- Produces: canonical finishing procedure: clean tree → current `origin/main` check → required validation → systematic debugging/reviewed fixes on red → current-base recheck before integration

- [ ] **Step 1: Inspect current finishing flow**

Read `.opencode/skills/finishing-a-development-branch/SKILL.md`. Confirm the existing flow has `Step 0: Verify Clean Working Tree`, `Step 1: Verify Tests`, `Step 2: Consult Project Policy`, and the common rationalizations table.

- [ ] **Step 2: Update the core principle**

Replace the current core principle sentence with:

```markdown
**Core principle:** Verify clean tree → Verify current `origin/main` base → Verify required validation → If validation fails, debug root cause and route reviewed fixes → Rerun validation from a clean/current-base tree until green or a true human-input blocker is established → Recheck `origin/main` before integration → Consult project policy → Detect environment → Execute action (or present options if no policy) → Clean up.
```

- [ ] **Step 3: Rename and expand Step 1**

Rename `## Step 1: Verify Tests` to:

```markdown
## Step 1: Verify Current Base and Tests
```

At the start of Step 1, before running the full suite, add:

````markdown
Fetch the current base and confirm this branch has accounted for it:

```bash
git fetch origin main
git merge-base --is-ancestor origin/main HEAD
```

**If the merge-base check exits 0:** Continue to required validation.

**If the merge-base check exits nonzero:** The branch has not incorporated
current `origin/main`. Do not run final validation yet, and do not rebase or
force-push. If a safe merge is permitted, run:

```bash
git merge --no-edit origin/main
```

If the merge has conflicts, generated-file changes, or code/test/doc changes
that need repair, route that work through `implementer` → `reviewer` → pass.
After reviewed fixes are committed and `git status --porcelain` is clean,
restart this finishing skill from Step 0. If the merge requires a human
permission or unsafe git-history decision, report HUMAN_DECISION_REQUIRED with
the exact command and branch state.
````

- [ ] **Step 4: Strengthen Step 1 validation-failure recovery**

In the failed-tests branch of Step 1, ensure the recovery list includes:

```markdown
1. Capture the exact failing command, failing tests, relevant error output,
   current branch name, `HEAD`, `origin/main`, merge-base state, and
   `git status --porcelain`.
2. Invoke `systematic-debugging` before proposing any fix.
3. Continue investigating even when the failure appears unrelated, flaky,
   timing-dependent, or environmental. Those labels are diagnostic information,
   not a terminal workflow state.
4. Establish root cause or gather enough evidence to justify why root cause
   cannot be established with available access.
5. Route any repository fix through `implementer` → `reviewer` → pass. The
   supervisor must not edit code, tests, `.opencode/**`, workflow files, or
   other non-allowlisted files directly.
6. After reviewed fixes are committed and the tree is clean, rerun this
   finishing skill from Step 0.
7. Only continue to Step 2 when the required validation suite passes on a
   clean tree that has accounted for current `origin/main`.
```

Ensure the blocker paragraph says `BLOCKED` or `HUMAN_DECISION_REQUIRED` is allowed only when systematic debugging establishes credentials, inaccessible infrastructure, unsafe git history decisions, unreproducible behavior after reasonable evidence gathering, or product/API/data/architecture choice.

- [ ] **Step 5: Add current-base recheck before automatic integration**

In `Step 2: Consult Project Policy`, before executing default push/PR action, add:

````markdown
Before any automatic push or PR creation, re-fetch and recheck the base:

```bash
git fetch origin main
git merge-base --is-ancestor origin/main HEAD
```

If the branch is no longer current with `origin/main`, do not push or create a
PR. Safe-merge `origin/main` when permitted, route conflicts or resulting fixes
through `implementer` → `reviewer` → pass, commit reviewed fixes, and restart
from Step 0 so validation runs on the updated branch. If push is rejected
because the remote/base moved, do not force-push; fetch, update by safe merge
when permitted, and restart from Step 0.
````

- [ ] **Step 6: Update common rationalizations**

Ensure the common rationalizations table includes rows covering:
- final suite failure is a debugging task, not a stop point;
- “unrelated/environmental/flaky” does not mean no investigation;
- rejected push does not authorize force-push;
- branch behind `origin/main` requires safe merge and rerun, not stale validation.

- [ ] **Step 7: Run focused validation for Task 2**

```bash
rg -n "Verify Current Base|git fetch origin main|merge-base --is-ancestor origin/main HEAD|git merge --no-edit origin/main|systematic-debugging|unrelated|flaky|environmental|implementer.*reviewer|rebase|force-push|HUMAN_DECISION_REQUIRED|BLOCKED" .opencode/skills/finishing-a-development-branch/SKILL.md
git diff --check .opencode/skills/finishing-a-development-branch/SKILL.md
```

Expected: finishing checks current `origin/main` before validation and push/PR, safe merge is the only automatic update path, automatic rebase/force-push are forbidden, validation failures enter `systematic-debugging`, and no whitespace errors exist.

- [ ] **Step 8: Commit Task 2 after reviewer pass**

```bash
git add .opencode/skills/finishing-a-development-branch/SKILL.md
git commit -m "docs(workflow): require current-base finishing validation"
```

---

### Task 3: Daily and Weekly Automation Recovery Alignment

**Files:**
- Modify: `.opencode/skills/daily-devlog-automation/SKILL.md`
- Modify: `.opencode/skills/weekly-agent-workflow-automation/SKILL.md`
- Test: focused `rg` checks and `git diff --check` for both automation skills

**Interfaces:**
- Consumes: Task 1 invariant and Task 2 finishing recovery contract
- Produces: automation instructions that do not treat validation failure as immediate `BLOCKED`, verify current `origin/main`, and avoid automatic rebase/force-push

- [ ] **Step 1: Inspect current automation failure wording**

Read both automation skills. Confirm daily has `## Validation`, `## Commit, Push, and PR`, and `## Fail-Closed Cases`; weekly has `## Workflow`, `## Validation`, `## Commit, Push, and PR`, and `## Fail-Closed Cases`.

- [ ] **Step 2: Add daily current-base check before validation and PR**

In `.opencode/skills/daily-devlog-automation/SKILL.md`, update the workflow so before validation and before push/PR it requires:

```markdown
Fetch `origin` and confirm the automation branch has accounted for current
`origin/main`. If the branch is behind, safe-merge `origin/main` when
permitted, route conflicts or regenerated docs changes through `implementer` →
`reviewer` → pass, and rerun validation from a clean tree. Do not rebase or
force-push unless the human explicitly requests it.
```

- [ ] **Step 3: Add daily validation-failure recovery section**

Add this section after `## Validation`:

```markdown
## Validation Failure Recovery

If required validation fails, do not commit, push, create a PR, enable
auto-merge, or report the automation branch as ready. Capture the failing
command, failing tests or docs build phase, relevant output, current branch
state, and `git status --porcelain`. Invoke `systematic-debugging` and continue
investigating even when the failure appears unrelated, flaky,
timing-dependent, or environmental.

Any repository fix, generated-doc repair, or conflict resolution must go
through `implementer` → `reviewer` → pass before commit. After reviewed fixes
are committed and the tree is clean, re-fetch `origin`, recheck current
`origin/main`, rerun validation, and continue only when validation is green.
Report BLOCKED or HUMAN_DECISION_REQUIRED only when systematic debugging
establishes that progress requires credentials, inaccessible infrastructure,
unsafe git history decisions, unreproducible behavior after reasonable evidence
gathering, or a product/API/data/architecture choice.
```

- [ ] **Step 4: Remove daily immediate validation-failure fail-closed wording**

In daily `## Fail-Closed Cases`, remove validation failure as an immediate stop condition. Replace fail-closed wording with:

```markdown
Stop with a clear BLOCKED or HUMAN_DECISION_REQUIRED summary when the checkout
is dirty, credentials are missing, `gh` is unavailable, branch protection or
required status checks are unavailable or cannot be verified, auto-merge cannot
proceed safely, the diff includes unexpected files, or validation remains red
after systematic debugging establishes a true human-input blocker.
```

- [ ] **Step 5: Remove daily automatic rebase auto-merge option**

In daily `## Commit, Push, and PR`, remove any instruction to use `gh pr merge --auto --rebase` automatically. Replace it with:

```markdown
If repository rules require a rebase-only merge method, do not enable
auto-merge automatically. Report HUMAN_DECISION_REQUIRED because the agent must
not rebase unless the human explicitly requests it.
```

- [ ] **Step 6: Strengthen weekly current-base and validation recovery wording**

In `.opencode/skills/weekly-agent-workflow-automation/SKILL.md`, update workflow and validation sections so they require fetch/recheck current `origin/main` before validation and push/PR, safe merge from `origin/main` when permitted, conflict/fix routing through `implementer` → `reviewer` → pass, and no automatic rebase or force-push. Use this paragraph where weekly discusses validation failures:

```markdown
Use `systematic-debugging` for validation failures. A validation failure is not
an immediate `BLOCKED` condition, even when it appears unrelated, flaky,
timing-dependent, or environmental. Capture the failing command, failing tests,
relevant output, current branch state, and `git status --porcelain`; establish
root cause or the limits of available evidence; route any repository fix
through `implementer` → `reviewer` → pass; commit reviewed fixes; re-fetch
`origin`; recheck current `origin/main`; and rerun validation until green or a
true human-input blocker is established.
```

- [ ] **Step 7: Update weekly fail-closed cases**

In weekly `## Fail-Closed Cases`, replace immediate validation-failure blocking with:

```markdown
Stop with BLOCKED or HUMAN_DECISION_REQUIRED when the checkout is dirty,
analyzer execution or redaction fails, sanitized evidence is insufficient, raw
sensitive data would be needed, branch protection or required checks cannot be
verified, GitHub authentication is missing for PR work, reviewer does not pass
the diff, unexpected files appear, or validation remains red after systematic
debugging establishes a true human-input blocker.
```

- [ ] **Step 8: Run focused validation for Task 3**

```bash
rg -n "systematic-debugging|origin/main|safe-merge|safe merge|implementer.*reviewer|BLOCKED|HUMAN_DECISION_REQUIRED|rebase|force-push|force push|validation remains red|immediate `BLOCKED`" .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md
git diff --check .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md
```

Expected: daily and weekly both contain validation recovery loops, fail-closed cases no longer list validation failure alone as terminal, daily no longer authorizes automatic `gh pr merge --auto --rebase`, both skills forbid automatic rebase/force-push, and no whitespace errors exist.

- [ ] **Step 9: Commit Task 3 after reviewer pass**

```bash
git add .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md
git commit -m "docs(workflow): align automation validation recovery"
```

---

### Task 4: SDD Handoff and Developer Workflow Documentation

**Files:**
- Modify: `.opencode/skills/subagent-driven-development/SKILL.md`
- Modify: `docs/dev/features/opencode-agent-workflow.md`
- Test: focused `rg` checks and `git diff --check` for both files

**Interfaces:**
- Consumes: Tasks 1–3 validation continuation contract
- Produces: SDD finishing handoff remains in coordination mode, and collaborator docs describe the all-workflows rule

- [ ] **Step 1: Update SDD finish handoff**

In `.opencode/skills/subagent-driven-development/SKILL.md`, replace the `## Finish` section with:

```markdown
## Finish

When final review is clean, use the finishing-a-development-branch skill. Do
not report implementation complete merely because final review passed.

If finishing validation fails, or if the branch is behind current `origin/main`,
stay in coordination mode. Follow the finishing skill's current-base and
validation-failure loops: fetch `origin`, safe-merge `origin/main` when
permitted, invoke `systematic-debugging` for required validation failures,
continue investigating even when failures appear unrelated, flaky,
timing-dependent, or environmental, route conflicts and repository fixes
through `implementer` → `reviewer` → pass, commit reviewed fixes, rerun
validation, and only finish or create a PR when the required suite is green.

Report BLOCKED or HUMAN_DECISION_REQUIRED only when systematic debugging
establishes that progress requires credentials, inaccessible infrastructure,
unsafe git history decisions, unreproducible behavior after reasonable evidence
gathering, or a product/API/data/architecture choice. Do not rebase or
force-push unless the human explicitly requests it.
```

- [ ] **Step 2: Add developer docs section for validation continuation**

In `docs/dev/features/opencode-agent-workflow.md`, add this section before `## Branch and pull request policy`:

```markdown
## Validation continuation and current base

Required validation failures are active debugging work, not a terminal workflow
state. When a required suite fails, agents capture the failing command, failing
tests, relevant output, current branch state, and `git status --porcelain`;
invoke `systematic-debugging`; and continue investigating even when the failure
appears unrelated, flaky, timing-dependent, or environmental.

Repository fixes, generated-file repairs, and conflict resolutions go through
`implementer` → `reviewer` → pass before commit. Agents rerun validation from a
clean tree and proceed only when the required suite is green, or when systematic
debugging establishes a true human-input blocker such as missing credentials,
inaccessible infrastructure, an unsafe git-history decision, unreproducible
behavior after reasonable evidence gathering, or a product/API/data/architecture
choice.

Before final validation, PR creation, or a ready-to-merge claim, agents fetch
`origin` and evaluate the branch against current `origin/main`. If the branch is
behind, they use a safe merge from `origin/main` when permitted, route resulting
fixes through review, and rerun validation. Agents do not rebase or force-push
unless the human explicitly requests it.
```

- [ ] **Step 3: Update existing docs bullets to avoid drift**

In `docs/dev/features/opencode-agent-workflow.md`:
- update the existing `Required validation failures` bullet so it points to the new section instead of restating a weaker rule;
- update `## Branch and pull request policy` so it says final validation and PR creation require current `origin/main`;
- ensure the page says OpenCode must be restarted after `.opencode/**` changes for workflow instruction changes to take effect.

- [ ] **Step 4: Run focused validation for Task 4**

```bash
rg -n "Validation continuation|systematic-debugging|origin/main|safe merge|implementer.*reviewer|BLOCKED|HUMAN_DECISION_REQUIRED|rebase|force-push|restart" .opencode/skills/subagent-driven-development/SKILL.md docs/dev/features/opencode-agent-workflow.md
git diff --check .opencode/skills/subagent-driven-development/SKILL.md docs/dev/features/opencode-agent-workflow.md
```

Expected: SDD finish handoff explicitly stays in coordination mode, docs page documents all-workflows validation continuation and current-base behavior, docs page mentions OpenCode restart after `.opencode/**` changes, and no whitespace errors exist.

- [ ] **Step 5: Commit Task 4 after reviewer pass**

```bash
git add .opencode/skills/subagent-driven-development/SKILL.md docs/dev/features/opencode-agent-workflow.md
git commit -m "docs(workflow): document validation continuation handoff"
```

---

### Task 5: Focused Final Validation and Review Gate

**Files:**
- Test: all files modified by Tasks 1–4 plus the committed spec and plan files

**Interfaces:**
- Consumes: committed changes from Tasks 1–4
- Produces: final validation evidence that instruction surfaces are consistent and no out-of-scope files changed

- [ ] **Step 1: Confirm changed-file scope**

```bash
git diff --name-only origin/main...HEAD
```

Expected changed files are limited to:

```text
AGENTS.md
.opencode/agents/supervisor.md
.opencode/skills/finishing-a-development-branch/SKILL.md
.opencode/skills/daily-devlog-automation/SKILL.md
.opencode/skills/weekly-agent-workflow-automation/SKILL.md
.opencode/skills/subagent-driven-development/SKILL.md
docs/dev/features/opencode-agent-workflow.md
docs/specs/2026-08-01-agent-validation-continuation-design.md
docs/plans/2026-08-01-agent-validation-continuation.md
```

If production, runtime test, build, executable script, package, OpenCode schema/config, or unexpected generated files appear, stop and expand validation before finishing.

- [ ] **Step 2: Run complete focused whitespace validation**

```bash
git diff --check origin/main...HEAD
```

Expected: no whitespace errors.

- [ ] **Step 3: Run complete focused wording validation**

```bash
FILES="AGENTS.md .opencode/agents/supervisor.md .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md .opencode/skills/subagent-driven-development/SKILL.md docs/dev/features/opencode-agent-workflow.md"

rg -n "systematic-debugging" $FILES
rg -n "implementer.*reviewer|implementer` → `reviewer" $FILES
rg -n "origin/main" $FILES
rg -n "safe merge|safe-merge|merge from `origin/main`|git merge --no-edit origin/main" $FILES
rg -n "rebase|force-push|force push" $FILES
rg -n "BLOCKED|HUMAN_DECISION_REQUIRED" $FILES
rg -n "unrelated|flaky|timing-dependent|environmental" $FILES
```

Expected: every edited workflow surface has `systematic-debugging` where validation failure is discussed; every fix path uses `implementer` → `reviewer` → pass; current-base behavior consistently names `origin/main`; safe merge is allowed when permitted; automatic rebase and force-push are forbidden; `BLOCKED`/`HUMAN_DECISION_REQUIRED` are reserved for true human-input blockers; unrelated/flaky/timing-dependent/environmental failures are not terminal by themselves.

- [ ] **Step 4: Inspect automation fail-closed wording**

```bash
rg -n -C 4 "Fail-Closed|validation fails|validation failure|validation remains red|immediate `BLOCKED`|HUMAN_DECISION_REQUIRED" .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md
```

Expected: daily and weekly fail-closed cases do not say validation failure alone is immediate `BLOCKED`; both skills say validation remains red only after systematic debugging establishes a true blocker.

- [ ] **Step 5: Run final whole-branch review**

Dispatch `reviewer` in FULL REVIEW MODE with the complete branch diff. Review expectations:
- confirm spec coverage for all target surfaces;
- confirm consistent wording around `systematic-debugging`;
- confirm every repository fix path uses `implementer` → `reviewer` → pass;
- confirm `origin/main` freshness is required before final validation and PR creation;
- confirm safe merge is the only default base-update mechanism;
- confirm no automatic rebase or force-push is authorized;
- confirm no workflow reports immediate `BLOCKED` on validation failure alone;
- confirm no out-of-scope files changed.

- [ ] **Step 6: Commit validation fixes only if reviewer required changes**

If the final reviewer requires wording fixes, route them through `implementer` → `reviewer` → pass, rerun Steps 1–4, then commit with:

```bash
git add AGENTS.md .opencode/agents/supervisor.md .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md .opencode/skills/subagent-driven-development/SKILL.md docs/dev/features/opencode-agent-workflow.md
git commit -m "docs(workflow): align validation continuation wording"
```

If no fixes are required, create no additional commit.

- [ ] **Step 7: Finish with focused validation only**

Do not run full product tests for this instruction/workflow-only change. Full product tests become required only if implementation changed production code, tests, runtime assets, build files, executable scripts, package files, OpenCode schema/config, or executable workflow files.
