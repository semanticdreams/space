# Validation Failure Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make failed required finishing validation trigger root-cause debugging and reviewed fixes instead of a terminal stop.

**Architecture:** Keep repository policy concise in `AGENTS.md`, put operational details in the finishing skill, and align supervisor and SDD handoff wording so there is no contradictory “report failure and stop” path. This is instruction/documentation-only; no runtime behavior, product code, tests, or OpenCode schema changes are in scope.

**Tech Stack:** Markdown repository instructions, OpenCode project agent prompts, OpenCode project skills, existing `systematic-debugging`, `implementer`, and `reviewer` workflows.

## Global Constraints

- Do not edit production code, runtime tests, build scripts, assets, or OpenCode JSON schema/config for this change.
- Because `AGENTS.md` and `.opencode/**` are outside the supervisor edit allowlist, all instruction changes must be made by `implementer` and verified by `reviewer`.
- OpenCode users must restart after `.opencode/**` changes.
- Failed required validation after implementation/review/commit must not be treated as done, ready-to-merge, or ready-to-PR.
- While required validation is red, agents must not push, create a PR, merge, or clean up the branch.
- Any fix for a validation failure must be based on `systematic-debugging`, address root cause rather than symptoms, avoid silent failures and test weakening, and pass through `implementer` → `reviewer` → pass.
- `BLOCKED` is allowed only when systematic debugging establishes an unresolved blocker: human decision required, external/environmental failure, unreproducible failure with available evidence, or unsafe scope/architecture uncertainty.

---

## File Structure

- Modify `AGENTS.md`: repository-level policy for failed required validation after implementation/review/commit.
- Modify `.opencode/agents/supervisor.md`: always-on routing rule so supervisors invoke debugging/fix coordination before reporting `BLOCKED` for red validation.
- Modify `.opencode/skills/finishing-a-development-branch/SKILL.md`: canonical finishing-time validation-failure loop.
- Modify `.opencode/skills/subagent-driven-development/SKILL.md`: final handoff reminder that finishing validation failures remain active coordination work.
- Modify `docs/dev/features/development-tooling.md`: maintainer-facing documentation of the OpenCode workflow.

## Baseline Evidence

- Observed real failure: an agent stopped at finishing checks after the full suite failed and reported `BLOCKED` instead of diagnosing root cause.
- Current finishing skill contains the direct stop instruction: `If tests fail, report the failures and stop — integration comes after a green suite.`
- A read-only pressure check against current instructions found ambiguity: the finishing skill says stop, while `systematic-debugging` says test failures should be investigated. The implementation must remove that ambiguity by making “stop integration” distinct from “stop working.”

---

### Task 1: Repository and Supervisor Policy

**Files:**
- Modify: `AGENTS.md`
- Modify: `.opencode/agents/supervisor.md`

**Interfaces:**
- Consumes: Existing branch convention, completion discipline, and subagent routing rules.
- Produces: Always-on policy that red validation enters systematic debugging and reviewed fixes before finishing.

- [ ] **Step 1: Inspect current wording**

Read `AGENTS.md` and `.opencode/agents/supervisor.md`. Confirm the current automatic PR policy requires tests passing and that supervisor completion discipline currently allows reporting `BLOCKED` when required checks fail.

- [ ] **Step 2: Add repository-level validation failure policy**

In `AGENTS.md`, under `## Branch Convention` and after the existing automatic PR policy paragraph, add this paragraph exactly, wrapping only for Markdown line length:

```markdown
If required validation fails after implementation, review, or commit, do not
finish, push, create a pull request, merge, or clean up the branch. Invoke the
`systematic-debugging` skill, identify the root cause, route any fix through
`implementer` → `reviewer` → pass, rerun validation, and only proceed with the
default integration action when the required suite is green.
```

- [ ] **Step 3: Replace supervisor completion failure behavior**

In `.opencode/agents/supervisor.md`, update the `Completion discipline` section so it keeps the clean-tree and required-checks gate, but replaces the unconditional “required checks fail → report BLOCKED” behavior with this contract:

```markdown
If required validation fails, do not report completion and do not stop at the
failure summary. Invoke `systematic-debugging`, identify the root cause, route
any fix through `implementer` → `reviewer` → pass, commit reviewed fixes, rerun
the failed validation, and restart finishing checks from the top. Report BLOCKED
only when systematic debugging establishes that the failure cannot be resolved
without human input, is external/environmental, is unreproducible with available
evidence, or requires a product/API/data/architecture decision.
```

- [ ] **Step 4: Align supervisor core workflow handoff**

In `.opencode/agents/supervisor.md`, replace Core Workflow step 4 with:

```markdown
4. Invoke **finishing-a-development-branch** — verify clean tree and required
   validation, use `systematic-debugging` plus `implementer` → `reviewer` for
   any validation failure, then consult project policy and execute the
   integration action only when green.
```

- [ ] **Step 5: Focused validation for Task 1**

Run:

```bash
rg -n "required validation fails|do not stop at the|systematic-debugging|implementer.*reviewer|only proceed.*green" AGENTS.md .opencode/agents/supervisor.md
git diff --check AGENTS.md .opencode/agents/supervisor.md
```

Expected: both files contain the validation-failure recovery policy; no whitespace errors.

---

### Task 2: Finishing and SDD Skill Contract

**Files:**
- Modify: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Modify: `.opencode/skills/subagent-driven-development/SKILL.md`

**Interfaces:**
- Consumes: Existing finishing steps and SDD final-review handoff.
- Produces: Concrete loop for failed finishing validation.

- [ ] **Step 1: Inspect current skill wording**

Read `.opencode/skills/finishing-a-development-branch/SKILL.md` and `.opencode/skills/subagent-driven-development/SKILL.md`. Confirm the finishing skill currently says tests failing should report and stop, and SDD currently only says to use the finishing skill after final review.

- [ ] **Step 2: Update finishing skill trigger description**

Change the frontmatter description in `.opencode/skills/finishing-a-development-branch/SKILL.md` to:

```yaml
description: Use when implementation is complete and reviewed, to run final validation, recover from validation failures, and integrate only when green
```

- [ ] **Step 3: Update finishing skill core principle**

Replace the existing core principle sentence with:

```markdown
**Core principle:** Verify clean tree → Verify required validation → If validation fails, debug root cause and route reviewed fixes → Rerun validation until green or blocked → Consult project policy → Detect environment → Execute action (or present options if no policy) → Clean up.
```

- [ ] **Step 4: Replace finishing skill Step 1 failure behavior**

Replace the current Step 1 failed-tests sentence with:

```markdown
**If tests fail**, integration is forbidden but the branch is not finished.
Do all of the following:

1. Capture the exact failing command, failing tests, relevant error output, and
   current `git status --porcelain`.
2. Invoke `systematic-debugging` before proposing any fix.
3. Identify and document the root cause. If root cause cannot be established,
   continue gathering evidence or report BLOCKED with the missing evidence.
4. Route any fix through `implementer` → `reviewer` → pass. The supervisor must
   not edit code, tests, `.opencode/**`, workflow files, or other non-allowlisted
   files directly.
5. After reviewed fixes are committed and the tree is clean, rerun this finishing
   skill from Step 0.
6. Only continue to Step 2 when the required validation suite passes.

If systematic debugging establishes that the failure is external, environmental,
unrelated to this branch, unreproducible with available evidence, or requires a
human product/API/data/architecture decision, report BLOCKED or
HUMAN_DECISION_REQUIRED with the evidence. Do not push, PR, merge, or clean up
while required validation is red.
```

- [ ] **Step 5: Add finishing skill rationalization guard**

Add this row to the `Common Rationalizations` table:

```markdown
| "The final suite failed, so I'll just report it and stop" | A red final suite is a debugging task. Invoke `systematic-debugging`, route reviewed fixes through `implementer` → `reviewer`, rerun validation, and finish only when green or explicitly blocked. |
```

- [ ] **Step 6: Update SDD finish handoff**

Replace `.opencode/skills/subagent-driven-development/SKILL.md` `## Finish` section with:

```markdown
## Finish

When final review is clean, use the finishing-a-development-branch skill.
If finishing validation fails, stay in coordination mode: follow the finishing
skill's validation-failure loop, invoke `systematic-debugging`, route fixes
through `implementer` → `reviewer` → pass, rerun validation, and only finish or
PR when the required suite is green.
```

- [ ] **Step 7: Focused validation for Task 2**

Run:

```bash
rg -n "validation fails|systematic-debugging|implementer.*reviewer|only.*green|HUMAN_DECISION_REQUIRED|branch is not finished" .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/subagent-driven-development/SKILL.md
git diff --check .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/subagent-driven-development/SKILL.md
```

Expected: finishing and SDD both contain the red-validation loop; no whitespace errors.

---

### Task 3: Developer Documentation

**Files:**
- Modify: `docs/dev/features/development-tooling.md`

**Interfaces:**
- Consumes: The policy and skill wording from Tasks 1 and 2.
- Produces: Maintainer documentation explaining the OpenCode validation-failure workflow.

- [ ] **Step 1: Inspect the OpenCode guidance section**

Read `docs/dev/features/development-tooling.md` and find the existing OpenCode guidance mentioning `AGENTS.md` and `.opencode/skills/space-*`.

- [ ] **Step 2: Extend the OpenCode guidance**

Update that guidance so it includes this sentence:

```markdown
After implementation/review/commit, failed required validation is handled as a debugging task: supervisors invoke `systematic-debugging`, route fixes through `implementer` → `reviewer`, rerun validation, and finish or PR only when green.
```

- [ ] **Step 3: Focused validation for Task 3**

Run:

```bash
rg -n "failed required validation|systematic-debugging|finish or PR only when green" docs/dev/features/development-tooling.md
git diff --check docs/dev/features/development-tooling.md
```

Expected: the docs page contains the workflow summary; no whitespace errors.

---

### Task 4: Final Instruction Consistency Review

**Files:**
- Test: `AGENTS.md`
- Test: `.opencode/agents/supervisor.md`
- Test: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Test: `.opencode/skills/subagent-driven-development/SKILL.md`
- Test: `docs/dev/features/development-tooling.md`

**Interfaces:**
- Consumes: Completed instruction edits from Tasks 1 through 3.
- Produces: Verified instruction contract ready for commit and restart notice.

- [ ] **Step 1: Run cross-file consistency search**

Run:

```bash
rg -n "do not.*push|do not.*pull request|do not.*PR|only.*green|systematic-debugging|implementer.*reviewer|branch is not finished" AGENTS.md .opencode/agents/supervisor.md .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/subagent-driven-development/SKILL.md docs/dev/features/development-tooling.md
```

Expected: each changed file has at least one relevant match, and the finishing skill has the most detailed loop.

- [ ] **Step 2: Run whitespace validation**

Run:

```bash
git diff --check
```

Expected: no whitespace or formatting errors.

- [ ] **Step 3: Inspect final diff and status**

Run:

```bash
git status --short
git diff -- AGENTS.md .opencode/agents/supervisor.md .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/subagent-driven-development/SKILL.md docs/dev/features/development-tooling.md
```

Expected: only the five intended files are modified for implementation. Plan/spec commits may already exist separately.

- [ ] **Step 4: Include restart notice in implementation report**

The implementer report must include this exact note:

```markdown
OpenCode must be restarted for `.opencode/**` agent and skill prompt changes to take effect.
```

## Acceptance Criteria

- Future supervisors encountering failed required validation after implementation/review/commit invoke `systematic-debugging` instead of stopping at the failure summary.
- No instruction permits finishing, pushing, PR creation, merging, or cleanup while required validation is red.
- Any validation-failure fix is routed through `implementer` → `reviewer` → pass.
- Finishing checks are rerun from Step 0 after reviewed fixes.
- `AGENTS.md`, supervisor prompt, finishing skill, SDD handoff, and docs/dev tooling page agree without contradictory stop conditions.
- The implementation report includes the OpenCode restart notice.

## Out of Scope

- Changing OpenCode schema/config files.
- Changing production code, runtime tests, build scripts, or runtime assets.
- Adding a new skill or agent.
- Automating validation failure parsing.
- Allowing PRs with known red required validation.
- Weakening, skipping, or deleting failing tests as a default response.
