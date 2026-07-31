# Constraint-Aware Agent Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make project agents use the completed experimental Fennel constraints gate as early, efficient feedback during Fennel-facing work.

**Architecture:** Keep `AGENTS.md` as the canonical command source, expand the constraints docs with workflow philosophy, and update only the project-local OpenCode agent/skill instructions that control implementation, review, testing, and task handoff. Do not add CI or runner-output changes in this slice.

**Tech Stack:** Markdown repo docs, project-local OpenCode agents and skills, existing `make constraints` / `make test` runtime.

## Global Constraints

- Constraints are feedback accelerators: they exist to catch issues earlier and reduce review/fix cycles, not to enforce structure for its own sake.
- For Fennel-facing implementation work, agents should run `make constraints` before focused Fennel tests and report the result before claiming `DONE`.
- Reviewers should verify constraint validation evidence when Fennel-facing changes are reviewed.
- Feature and bugfix reports should include a lightweight constraint-impact note: helped, obstructed/noisy, changed, or not applicable.
- If an intentional architecture change conflicts with an existing constraint, update the code and constraint contract together through reviewed changes; do not blindly contort production code, skip the gate, or add broad baselines/allowlists.
- `make test` already depends on `make constraints`; do not duplicate full-suite work unnecessarily when `make test` is the validation command.
- Do not create `.github/workflows/**` in this slice.
- Do not change constraint runner output behavior in this slice.
- Edits to `.opencode/skills/**` must be treated as process-documentation TDD: use the RED pressure-scenario evidence below and verify the changed wording with GREEN pressure checks before declaring the plan complete.

## RED Pressure Evidence

The supervisor ran three read-only baseline pressure scenarios before any workflow edits:

1. **Implementer validation pressure:** a tiny Fennel UI fix with focused tests passing and final validation delegated later. The implementer chose focused test + `make test`, but did not explicitly report early `make constraints` or a constraint-impact note. Gap: early constraint feedback and reporting are not explicit.
2. **Reviewer omission pressure:** a small Fennel lifecycle fix where the implementer report omitted `make constraints`. The reviewer treated omission as irrelevant or at most non-blocking unless the plan required it. Gap: reviewer must have an explicit criterion.
3. **Architecture-change pressure:** a constraint fails because an intentional ownership contract changed. The agent chose to update the constraint contract with tests rather than contort code or bypass. This behavior is good and should be preserved in docs.

---

### Task 1: Add Constraint-Aware Agent Workflow Guidance

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/dev/experimental-constraints.md`
- Modify: `.opencode/agents/implementer.md`
- Modify: `.opencode/agents/reviewer.md`
- Modify: `.opencode/skills/space-testing-runtime/SKILL.md`
- Modify: `.opencode/skills/subagent-driven-development/SKILL.md`

**Interfaces:**
- Consumes: existing `make constraints`, `make test`, and `docs/dev/experimental-constraints.md` semantics.
- Produces: project workflow instructions that make constraint validation and constraint-impact reporting visible to implementers and reviewers.

- [ ] **Step 1: Read the current workflow files**

  Inspect the six files listed above. Confirm there is still no `.github/workflows/**` file in this worktree and do not create one.

- [ ] **Step 2: Update `AGENTS.md`**

  In Build/Run/Test guidance, preserve existing command spellings and add these behaviors:
  - For Fennel-facing work, run `make constraints` before narrowed Fennel test commands.
  - If running full `make test`, do not run a duplicate `make constraints` immediately before it unless early feedback is useful, because `make test` already depends on constraints.
  - Treat `violations`, `fail`, and `interrupted` as validation failures that require diagnosis and reviewed fixes, not bypasses.
  - Add a lightweight constraint-impact line to feature/bugfix handoffs when relevant.

- [ ] **Step 3: Expand `docs/dev/experimental-constraints.md`**

  Add an agent workflow section covering:
  - constraints as early feedback/review-cycle reduction;
  - pre-focused-test usage;
  - reviewer expectations;
  - constraint-impact notes;
  - architecture-transition behavior when constraints encode an old contract;
  - deferred CI and output-verbosity follow-ups.

- [ ] **Step 4: Update `.opencode/agents/implementer.md`**

  Add concise implementer instructions:
  - For Fennel-facing work, run `make constraints` before focused Fennel tests when feasible.
  - Before `DONE`, report constraint status for Fennel-facing changes.
  - Add a `Constraint Impact` bullet to the full report format with one of: `helped catch`, `obstructed/noisy`, `changed constraint`, or `not applicable`.
  - If constraints conflict with an intentional design change, return `NEEDS_CONTEXT` when the new contract is ambiguous; otherwise update code and constraints together within assigned scope.

- [ ] **Step 5: Update `.opencode/agents/reviewer.md`**

  Add review criteria:
  - For Fennel-facing diffs, verify the implementer reported constraint validation or explain why it is not applicable.
  - Treat unresolved constraint failures as validation findings.
  - Treat broad baselines/allowlists or production contortions to satisfy stale constraints as design-integrity findings.
  - Do not require duplicate `make constraints` evidence when the reported validation is `make test`, because `make test` already gates constraints.

- [ ] **Step 6: Update `.opencode/skills/space-testing-runtime/SKILL.md`**

  Add a short constraints subsection:
  - `make constraints` is the fast pre-test gate for Fennel-facing work.
  - `make test` already depends on constraints.
  - Use `docs/dev/experimental-constraints.md` for statuses, targets, and baseline policy.

- [ ] **Step 7: Update `.opencode/skills/subagent-driven-development/SKILL.md`**

  Add task-loop guidance:
  - Include relevant constraint validation expectations in implementer briefs for Fennel-facing tasks.
  - Include constraint-impact notes in implementer reports and ledger entries when relevant.
  - Final review should triage any repeated “constraint obstructed/noisy” notes as possible constraint-system follow-ups.

- [ ] **Step 8: Run GREEN pressure checks**

  Because running project-local OpenCode config may require a restart, use read-only fresh subagent prompts that quote or point to the updated relevant snippets. Verify three scenarios:
  - Implementer-style Fennel task now chooses early `make constraints` and reports constraint status/impact.
  - Reviewer-style missing-constraints report now becomes a review concern/finding for Fennel-facing work.
  - Architecture-change scenario still updates the constraint contract with tests rather than blindly obeying or bypassing the old constraint.

- [ ] **Step 9: Validate docs/config text**

  Run:

  ```bash
  rg -n "make constraints|Constraint Impact|constraint-impact|experimental constraints|violations|interrupted" AGENTS.md docs/dev/experimental-constraints.md .opencode/agents/implementer.md .opencode/agents/reviewer.md .opencode/skills/space-testing-runtime/SKILL.md .opencode/skills/subagent-driven-development/SKILL.md
  ```

  Then run:

  ```bash
  make constraints
  ```

  Expected: text search finds the workflow hooks and constraints pass.

- [ ] **Step 10: Commit**

  Commit only the six listed files:

  ```bash
  git add AGENTS.md docs/dev/experimental-constraints.md .opencode/agents/implementer.md .opencode/agents/reviewer.md .opencode/skills/space-testing-runtime/SKILL.md .opencode/skills/subagent-driven-development/SKILL.md
  git commit -m "docs(opencode): add constraint-aware agent workflow"
  ```

## Acceptance Criteria

- Fennel-facing agent workflow requires or explicitly justifies constraint validation before readiness.
- Reviewer instructions make missing or failed constraint validation reviewable.
- Reports include lightweight constraint-impact learning without creating a new persistent reporting system.
- Documentation explains that constraints are efficiency tools and may need contract updates during intentional architecture changes.
- No GitHub Actions workflow is added.
- No constraint runner output behavior changes.
- `make constraints` still passes.

## Validation Ladder

1. GREEN pressure checks for implementer, reviewer, and architecture-transition behavior.
2. Text search for workflow hooks:
   ```bash
   rg -n "make constraints|Constraint Impact|constraint-impact|experimental constraints|violations|interrupted" AGENTS.md docs/dev/experimental-constraints.md .opencode/agents/implementer.md .opencode/agents/reviewer.md .opencode/skills/space-testing-runtime/SKILL.md .opencode/skills/subagent-driven-development/SKILL.md
   ```
3. Runtime validation:
   ```bash
   make constraints
   ```

## Out of Scope

- Creating or debugging GitHub Actions workflows.
- Changing constraint runner output format or verbosity.
- Adding new constraint rules.
- Editing global OpenCode config outside the repo.
