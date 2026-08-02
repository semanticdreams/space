# Targeted Agent Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update Space/OpenCode prompt and workflow documentation so agents use targeted local validation by default, keep `make build` as the runtime freshness prerequisite, and treat PR CI as the full integration gate.

**Architecture:** This is a Markdown-only instruction change. `AGENTS.md` becomes the always-on validation policy source, repo-local OpenCode agent prompts consume that policy, workflow skills align handoff/finishing behavior, and `docs/dev/features/opencode-agent-workflow.md` documents the canonical developer workflow. No production code, tests, Makefile targets, or CI workflows change.

**Tech Stack:** Markdown repository docs, repo-local OpenCode agent definitions, repo-local OpenCode skills, focused `rg` validation, `git diff --check`.

## Global Constraints

- Do not change production runtime code, tests, Makefile targets, CI workflows, or repository workbench check implementations in this pass.
- Do not skip Fennel constraints; targeted validation may call constraints directly through `./build/space`, but constraints remain part of Fennel-facing validation.
- Do not pretend Fennel can run without a built Space runtime.
- Do not make local targeted validation a substitute for the full PR integration gate.
- Full product tests are not required for this prompt/docs-only change.
- No dependency, version, runtime, Makefile, CMake, CTest, GitHub Actions, or executable behavior changes.
- OpenCode users must restart OpenCode after `.opencode/**` changes.
- Docs/dev page to update: `docs/dev/features/opencode-agent-workflow.md`; do not create a new docs/dev page because this existing page is canonical for Space/OpenCode workflow expectations.
- Observable acceptance criteria: modified instructions explicitly say targeted local validation is the default, `make build` remains the runtime/freshness prerequisite when `./build/space` may be missing or stale, high-risk changes broaden local validation, and PR CI is the full integration gate.
- Validation ladder for this docs-only change: focused `rg` checks during implementation; complete relevant suite is the full set of focused `rg` checks plus `git diff --check`; broader final checks are reviewer verification and PR CI, not local `make test`.

---

### Task 1: Repo and Agent Validation Guidance

**Files:**
- Modify: `AGENTS.md`
- Modify: `.opencode/agents/implementer.md`
- Modify: `.opencode/agents/reviewer.md`
- Modify: `.opencode/agents/planner.md`
- Test: focused `rg` commands in this task; `git diff --check`

**Interfaces:**
- Consumes: committed spec `docs/specs/2026-08-02-targeted-agent-validation-design.md`.
- Produces: canonical validation-policy phrases for Task 2 to reuse: `targeted local validation by default`, `narrowest meaningful checks`, `make build` as runtime/freshness prerequisite, and `PR CI` as full integration gate.

- [ ] **Step 1: Inspect the current validation wording**

  Read these sections before editing:
  - `AGENTS.md` Build, Run & Test and Commit Conventions sections.
  - `.opencode/agents/implementer.md` Your Job, Fennel-facing validation, Implementation Rules, and Report Format sections.
  - `.opencode/agents/reviewer.md` Test Discipline section.
  - `.opencode/agents/planner.md` validation-ladder rules.

- [ ] **Step 2: Update `AGENTS.md` validation policy**

  Replace unconditional full-suite-before-commit wording with this policy:
  - Local default: agents run the narrowest meaningful checks for the changed behavioral surface.
  - Keep `make build` as the normal freshness/runtime prerequisite when `./build/space` may be missing or stale, or when C++, CMake, runtime initialization, bindings, or host scaffolding changed.
  - Fennel/UI/layout behavior: compile check, constraints, focused Fennel tests.
  - C++ behind Fennel bindings: build first, then focused Fennel tests through the binding surface.
  - Pure C++ utility behavior: build the relevant target and/or focused CTest.
  - Docs/prompt-only changes: focused text searches, diff review, and formatting checks.
  - Build, package, startup, runtime initialization, broad binding/API, or other high-risk changes: broaden local validation, including `make test` when that is the relevant local gate.
  - Preserve the standard full-suite command as the command to use when full local validation is justified, not as the default before every checkpoint commit.

- [ ] **Step 3: Update `AGENTS.md` Commit Conventions**

  Replace the current “Before committing, run the full test suite” requirement with:
  - Before checkpoint commits, run sufficient focused validation for the change and record a short coverage rationale.
  - Escalate to broader local validation when the changed surface is high risk or the plan/reviewer requires it.
  - Do not claim ready-to-merge until the applicable PR CI integration gate is green.

- [ ] **Step 4: Update `.opencode/agents/implementer.md`**

  Change implementer expectations so they:
  - Run the narrowest meaningful check first while iterating.
  - Before committing, run sufficient focused validation for the assigned task and explain coverage.
  - Run broader local validation only when the plan, changed risk surface, reviewer finding, or high-risk category requires it.
  - Preserve Fennel ordering: compile check first, constraints second, focused Fennel tests third, broader relevant suite last.
  - Report commands run, results, and why the selected checks cover the behavioral surface.
  - Do not claim `DONE` when required validation failed.

- [ ] **Step 5: Update `.opencode/agents/reviewer.md`**

  Adjust review criteria so reviewers:
  - Verify that reported validation is appropriate for the behavioral surface and risk.
  - Do not require full `make test` by default for every task.
  - Flag under-covered validation when the task touches high-risk surfaces.
  - Continue requiring Fennel compile-check and constraints evidence for Fennel-facing diffs.
  - Treat PR CI as the full integration gate, not as a substitute for missing focused local validation.

- [ ] **Step 6: Update `.opencode/agents/planner.md`**

  Update planning rules so implementation plans require:
  - Focused checks used during implementation.
  - The complete relevant local suite only when justified by behavior/risk.
  - Broader final checks justified by risk, with PR CI named as the full integration gate.
  - Explicit `make build` runtime/freshness prerequisite language when Fennel validation or runtime tests need `./build/space`.

- [ ] **Step 7: Run focused phrase checks for Task 1**

  ```bash
  rg -n "targeted local validation by default|narrowest meaningful checks|make build.*(runtime|freshness).*prerequisite|PR CI.*full integration gate" AGENTS.md .opencode/agents/implementer.md .opencode/agents/reviewer.md .opencode/agents/planner.md
  ```

  Expected: matches show the new policy appears in the repository guidance and relevant agent prompts.

- [ ] **Step 8: Verify removed unconditional full-suite-before-task language for Task 1**

  ```bash
  rg -n "Before committing, run the full test suite|run the full suite once before committing|Verify implementation works — run the narrowest relevant test first, then the complete relevant suite|Default test invocation is `make test`.*prefer this unless" AGENTS.md .opencode/agents/implementer.md .opencode/agents/planner.md
  ```

  Expected: no matches.

- [ ] **Step 9: Run whitespace validation**

  ```bash
  git diff --check
  ```

  Expected: no output and exit code 0.

- [ ] **Step 10: Commit Task 1**

  ```bash
  git add AGENTS.md .opencode/agents/implementer.md .opencode/agents/reviewer.md .opencode/agents/planner.md
  git commit -m "docs: target agent validation guidance"
  ```

---

### Task 2: Workflow, Finishing, and Dev Docs Alignment

**Files:**
- Modify: `.opencode/skills/subagent-driven-development/SKILL.md`
- Modify: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Modify: `docs/dev/features/opencode-agent-workflow.md`
- Test: focused `rg` commands in this task; `git diff --check`

**Interfaces:**
- Consumes: Task 1 policy phrases and validation contract in `AGENTS.md` and agent prompts.
- Produces: aligned workflow instructions that dispatch, finish, and document targeted local validation consistently.

- [ ] **Step 1: Update subagent-driven-development task handoff guidance**

  In `.opencode/skills/subagent-driven-development/SKILL.md`, update implementer dispatch/report expectations so every task brief includes:
  - The targeted local validation default.
  - The changed behavioral surface to validate.
  - `make build` as runtime/freshness prerequisite when `./build/space` may be missing or stale.
  - Fennel compile-check → constraints → focused Fennel tests ordering for Fennel-facing work.
  - A requirement for the implementer report to explain validation coverage, not merely list commands.
  - A reminder that checkpoint commits are not final integration sign-offs.

- [ ] **Step 2: Update subagent-driven-development finish handoff**

  In the Finish section, clarify that:
  - Final review passing does not mean ready-to-merge.
  - The finishing skill chooses required final validation from `AGENTS.md`.
  - PR CI remains the authoritative full integration gate before any ready-to-merge claim.
  - OpenCode must be restarted after `.opencode/**` changes for updated workflow instructions to take effect.

- [ ] **Step 3: Update finishing skill validation selection**

  In `.opencode/skills/finishing-a-development-branch/SKILL.md`, replace “Run the project’s full test suite” as the unconditional Step 1 validation with:
  - Run the required final validation from `AGENTS.md` for the changed surface.
  - For docs/prompt-only changes, focused text checks plus `git diff --check` are sufficient locally unless the reviewer or risk surface requires more.
  - For build, package, startup, runtime initialization, broad binding/API, or other high-risk changes, run broader local validation such as the standard `make test` command.
  - Do not push, PR, merge, clean up, or claim ready-to-merge while required local validation is red.
  - Do not claim ready-to-merge until the applicable PR CI gate is green.

- [ ] **Step 4: Update OpenCode workflow docs**

  In `docs/dev/features/opencode-agent-workflow.md`, replace the current “Full Space validation” default with a targeted-local-validation section that documents:
  - Agents use targeted local validation by default.
  - `make build` remains the runtime/freshness prerequisite when the built Space runtime may be missing or stale.
  - Behavioral-surface examples from the spec: Fennel/UI/layout, C++ behind Fennel bindings, pure C++ utility, docs/prompt-only, and high-risk broad changes.
  - The standard full-suite command remains documented for high-risk or explicitly required local validation.
  - PR CI is the full integration gate.
  - OpenCode users must restart after `.opencode/**` changes.

- [ ] **Step 5: Run focused phrase checks for Task 2**

  ```bash
  rg -n "targeted local validation by default|narrowest meaningful checks|make build.*(runtime|freshness).*prerequisite|PR CI.*full integration gate|docs/prompt-only changes|restart OpenCode" .opencode/skills/subagent-driven-development/SKILL.md .opencode/skills/finishing-a-development-branch/SKILL.md docs/dev/features/opencode-agent-workflow.md
  ```

  Expected: matches show the workflow skill, finishing skill, and dev docs all contain the aligned policy.

- [ ] **Step 6: Verify removed unconditional full-suite workflow language**

  ```bash
  rg -n "Run the project's full test suite|Full Space validation|Run full test suite" .opencode/skills/subagent-driven-development/SKILL.md .opencode/skills/finishing-a-development-branch/SKILL.md docs/dev/features/opencode-agent-workflow.md
  ```

  Expected: no matches.

- [ ] **Step 7: Run final focused repository-wide instruction checks**

  ```bash
  rg -n "Before committing, run the full test suite|run the full suite once before committing|Run the project's full test suite|Default test invocation is `make test`.*prefer this unless|Full Space validation" AGENTS.md .opencode/agents/implementer.md .opencode/agents/planner.md .opencode/skills/subagent-driven-development/SKILL.md .opencode/skills/finishing-a-development-branch/SKILL.md docs/dev/features/opencode-agent-workflow.md
  ```

  Expected: no matches.

- [ ] **Step 8: Verify changed-file scope**

  ```bash
  git diff --name-only HEAD~1..HEAD
  git diff --name-only
  ```

  Expected combined changed files are limited to instruction/docs files from this plan. No production code, tests, Makefile, CMake, or CI workflow files are changed.

- [ ] **Step 9: Run whitespace validation**

  ```bash
  git diff --check
  ```

  Expected: no output and exit code 0.

- [ ] **Step 10: Commit Task 2**

  ```bash
  git add .opencode/skills/subagent-driven-development/SKILL.md .opencode/skills/finishing-a-development-branch/SKILL.md docs/dev/features/opencode-agent-workflow.md
  git commit -m "docs: align agent validation workflows"
  ```

- [ ] **Step 11: Final note for handoff**

  Include this exact note in the implementation handoff: `OpenCode users must restart after .opencode/** changes for the updated agent and skill instructions to take effect.`
