# Autonomous Flow Approval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove manual user approval gates after design spec and implementation plan creation while preserving autonomous quality gates.

**Architecture:** Update the two process skills that encode these gates. Brainstorming will auto-transition after spec self-review and commit; writing-plans will auto-invoke SDD after plan self-review and commit.

**Tech Stack:** Markdown process documentation in `skills/*/SKILL.md`; git for commit checkpoints; subagent-driven-development for implementation and review.

## Global Constraints

- Supervisor must not directly edit skill files; all skill changes go through implementer → reviewer.
- Preserve self-review and commit checkpoints.
- Preserve implementer → reviewer → adjudicator gates and final clean-tree completion discipline.
- Stop for the user only on unresolved ambiguity, explicit user-requested checkpoints, permission prompts, or blockers.

---

### Task 1: Make brainstorming automatically proceed after spec

**Files:**
- Modify: `skills/brainstorming/SKILL.md`

**Interfaces:**
- Consumes: Existing brainstorming skill flow.
- Produces: Updated brainstorming flow that invokes writing-plans automatically after committed spec self-review.

- [ ] **Step 1: Establish baseline failing behavior**

Run a targeted text check showing the current skill still contains manual approval gates:

```bash
rg -n "get user approval|User reviews written spec|User Review Gate|human for approval|user approves|approved" skills/brainstorming/SKILL.md
```

Expected: matches on the design approval gate, written spec user review gate, and terminal plan approval wording.

- [ ] **Step 2: Update brainstorming flow wording**

Edit `skills/brainstorming/SKILL.md` so that:

```markdown
Do NOT invoke implementation execution until the design has been captured in a committed, self-reviewed spec and the implementation plan has been captured in a committed, self-reviewed plan.
```

Replace approval-oriented checklist items with automatic progression semantics:

```markdown
4. **Present design direction** — summarize the chosen direction and proceed unless a blocking ambiguity remains
5. **Write design doc** — save to `docs/specs/YYYY-MM-DD-<topic>-design.md`
6. **Commit the spec** — ...
7. **Spec self-review** — ...
8. **Automatic transition** — invoke the writing-plans skill from the committed spec; do not wait for user review unless the user explicitly requested a checkpoint or the spec has unresolved ambiguity.
```

Replace the user review section with an automatic progression section that says to ask the user only for unresolved ambiguity, explicit review checkpoints, permission prompts, or blockers.

- [ ] **Step 3: Verify brainstorming no longer has stale approval gates**

Run:

```bash
rg -n "get user approval|User reviews written spec|User Review Gate|human for approval|user approves|If approved" skills/brainstorming/SKILL.md
```

Expected: no matches for stale manual approval gates. Acceptable matches may remain only if they describe explicit user-requested checkpoints or permission/blocker exceptions.

- [ ] **Step 4: Commit brainstorming skill update**

Run:

```bash
git add skills/brainstorming/SKILL.md
git commit -m "docs(skills): automate brainstorming handoff"
```

Expected: commit succeeds and includes only `skills/brainstorming/SKILL.md`.

### Task 2: Make writing-plans automatically invoke SDD after plan

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

**Interfaces:**
- Consumes: Committed plan file produced by writing-plans.
- Produces: Deterministic automatic handoff to subagent-driven-development after plan commit.

- [ ] **Step 1: Establish baseline failing behavior**

Run a targeted text check showing the current plan skill still waits for approval:

```bash
rg -n "offer execution choice|If approved|Ready to execute|approval" skills/writing-plans/SKILL.md
```

Expected: matches in the Execution Handoff section.

- [ ] **Step 2: Update execution handoff**

Edit `skills/writing-plans/SKILL.md` so the Execution Handoff section says:

```markdown
After committing the plan, invoke subagent-driven-development automatically. Tell the user execution is starting and summarize the committed plan path. Do not ask for approval unless the user explicitly requested a checkpoint, the plan has unresolved ambiguity, a permission prompt requires it, or the process is blocked.
```

Include the exact message shape:

```markdown
"Plan complete and saved to `docs/plans/<filename>.md`. Proceeding with subagent-driven-development now — it will dispatch `implementer` for each task, `reviewer` for spec/quality gates, and `adjudicator` if findings stall at the cap."
```

- [ ] **Step 3: Verify writing-plans no longer has stale execution approval gates**

Run:

```bash
rg -n "offer execution choice|If approved|ask for approval|approval" skills/writing-plans/SKILL.md
```

Expected: no stale approval-gate wording. Acceptable matches may remain only if they describe explicit user-requested checkpoints or permission/blocker exceptions.

- [ ] **Step 4: Commit writing-plans skill update**

Run:

```bash
git add skills/writing-plans/SKILL.md
git commit -m "docs(skills): automate plan execution handoff"
```

Expected: commit succeeds and includes only `skills/writing-plans/SKILL.md`.

### Task 3: Cross-skill consistency review

**Files:**
- Modify: `skills/brainstorming/SKILL.md`
- Modify: `skills/writing-plans/SKILL.md`

**Interfaces:**
- Consumes: Task 1 and Task 2 edits.
- Produces: Verified skill documentation updates ready for supervisor review.

- [ ] **Step 1: Cross-check automatic progression language**

Run:

```bash
rg -n "automatic|automatically|subagent-driven-development|writing-plans|commit" skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md
```

Expected: both skills explicitly preserve commit/self-review checkpoints and automatic progression.

- [ ] **Step 2: Review the diff**

Run:

```bash
git diff -- skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md
```

Expected: diff only changes manual approval gates into automatic progression wording; no unrelated rewrites.

- [ ] **Step 3: Verify all skill updates are already committed**

Run:

```bash
git status --short
git log --oneline -5
```

Expected: no uncommitted skill changes remain; recent commits include Task 1 and Task 2 skill updates.

## Self-Review

- Spec coverage: Tasks cover both manual approval points named by the user: design spec review and implementation plan execution approval.
- Placeholder scan: No placeholder tasks remain; each task names files, commands, and expected outcomes.
- Type consistency: Not applicable; this plan changes Markdown process documentation.
