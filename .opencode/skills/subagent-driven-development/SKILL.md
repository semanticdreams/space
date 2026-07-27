---
name: subagent-driven-development
description: Use when executing implementation plans with independent tasks using specialized subagents
---

# Subagent-Driven Development

Execute plan by dispatching the **implementer** subagent per task, a task review (spec compliance + code quality) by the **reviewer** subagent after each, a fix loop if needed, and a broad whole-branch review at the end. The **adjudicator** resolves findings at the fix-loop cap.

**Why subagents:** Each role has a specialized prompt and the right model for its job. The controller constructs exactly what each subagent needs — no inherited session context.

## Model Selection

The subagent config defines the model per role. On fix-loop escalation (rounds 4-5 when the implementer can't converge), dispatch the implementer with the same model — the issue at that point is usually structural, not model-capability.

## Setup

1. **Isolated workspace:** use `.opencode/skills/subagent-driven-development/scripts/sdd-workspace PLAN_FILE` to resolve/create the plan's scratch directory. If a ledger (`progress.md`) exists and names this plan, resume from the last uncompleted task. Redirect to a fresh workspace if the ledger names a different plan.

2. **Read the plan once** and create a todo per task.

3. **Pre-flight scan:** check for tasks that contradict each other or the plan's Global Constraints. Present findings as a batched question before execution.

## The Task Loop

### 1. Dispatch the Implementer

Record BASE (`git rev-parse HEAD`) before dispatching.

**Task brief:** run `.opencode/skills/subagent-driven-development/scripts/task-brief PLAN_FILE N` — it extracts the task's full text to a file. The controller's dispatch should include:
1. One line on where this task fits in the project
2. The brief path ("read this first — it is your requirements")
3. Interfaces and decisions from earlier tasks the brief cannot know
4. The report-file path (`task-N-report.md` in the workspace)
5. Context: whether this is a fresh dispatch or a fix-round resume

**Report file:** `task-N-report.md` in the plan's workspace. The implementer writes its full report there and returns only status summary.

**Never make a subagent read the whole plan file.** The brief is the single source of requirements. Exact values (numbers, magic strings, signatures, test cases) appear only in the brief.

Never dispatch multiple implementation subagents in parallel (conflicts).

### 2. Handle the Report

Implementer subagents report one of four statuses:

- **DONE:** Generate the review package (`.opencode/skills/subagent-driven-development/scripts/review-package PLAN_FILE BASE HEAD`), then dispatch the **reviewer** subagent in FULL REVIEW MODE with: the brief path, the report file path, the review package path, and the plan's Global Constraints. See below for review dispatch format.

- **DONE_WITH_CONCERNS:** Read the concerns. If about correctness or scope, address them before review. If observations (e.g., "this file is getting large"), note them and proceed to review.

**Atomic handoff (review dispatch):** When DONE or DONE_WITH_CONCERNS proceeds to review, the review-package generation and reviewer dispatch form a single atomic handoff. Do not emit any user-facing status update (including "review queued," "in progress," "waiting," or ledger/todo changes) before the reviewer `task` tool call has actually been issued. If the reviewer dispatch cannot proceed, report BLOCKED explicitly rather than implying a handoff that hasn't happened.

- **NEEDS_CONTEXT:** Provide the missing context and re-dispatch the implementer.

- **BLOCKED:** Assess the blocker — provide more context, or if the task is too large, break it into smaller pieces. If the plan is wrong, escalate to the human.

### 3. Review the Task

Dispatch the **reviewer** subagent in FULL REVIEW MODE. The reviewer's prompt body should specify:

```
You are reviewing Task N using FULL REVIEW MODE.

Task brief: [BRIEF_FILE]
Implementer report: [REPORT_FILE]
Review package (diff): [DIFF_FILE]

Global constraints:
[Copy verbatim from the plan's Global Constraints section]
```

The reviewer returns JSON with verification results. The key fields: `status` (pass/candidates_found/requires_human), `candidate_findings`, `cannot_verify_from_diff`, and `non_blocking_notes`.

**Large review packages:** If the review package contains a `## Manifest` section with a file checklist, the reviewer MUST enumerate every file in the manifest and report in `non_blocking_notes` that all manifest entries were inspected. Any file the reviewer could not inspect must be reported as a `cannot_verify_from_diff` item with the file name and reason.

- Minor findings: record in the ledger (`Task <N>: minor (deferred): <one-liner>`) — they don't enter the fix loop.
- Plan-mandated contradictions: present to the human.
- Critical and Important findings enter the fix loop.

### 4. The Fix Loop

Triggered when review status is `candidates_found` with Critical or Important findings.

**Atomic handoff:** When Critical or Important findings are returned and no `requires_human` or BLOCKED condition applies, immediately dispatch/resume the implementer with the open findings in the same turn. Do not pause for user acknowledgement or say "I'll send these next." User-facing status may be emitted only after the implementer has been dispatched/resumed, or when human input is actually required.

**Rounds 1-3:** Dispatch the implementer with the open findings. It is being *resumed* — it knows the code and the task. The dispatch should include: brief path, report-file path, and the findings verbatim.

**Rounds 4-5:** The implementer should try fresh — this is a hard stall. Same model but frame it as a fresh dispatch: "A prior implementer attempted this task and could not converge. You own it now. Read the report file for what was tried."

**Every round:** Record `FIX_BASE=$(git rev-parse HEAD)` before dispatching the fix. The implementer fixes, re-runs covering tests, and appends a fix report to the report file. After the implementer returns, generate a fix-diff package: run `.opencode/skills/subagent-driven-development/scripts/review-package PLAN_FILE FIX_BASE HEAD` and pass that output to the reviewer in TARGETED VERIFICATION MODE for a scoped re-review:

```
You are verifying fixes for Task N using TARGETED VERIFICATION MODE.

Task brief: [BRIEF_FILE]
Implementer report (fix reports appended): [REPORT_FILE]
Findings under verification: [list findings verbatim]
Review package (fix diff): [FIX_DIFF_FILE]
```

**The breaker (round 5 cap):** When round 5's re-review still leaves findings open, dispatch the **adjudicator** subagent with the open findings and the plan. The adjudicator returns accept/park/escalate decisions. Parked findings go to the ledger for the final review.

### 5. Complete the Task

**Before marking a task complete**, verify that the reviewer was dispatched
and returned a verdict for this task. This means: you must have actually
dispatched the reviewer subagent for this task and consumed its JSON response.
If the reviewer was never dispatched for this task, STOP — dispatch the
reviewer now. Never write "review clean" to the ledger without first
dispatching and consuming the reviewer's verdict.

When review passes or findings are parked at the cap, append to the ledger
with the reviewer's status recorded:

- `Task <N>: complete (commits <base>..<head>, reviewer: pass)`
- `Task <N>: complete (commits <base>..<head>, K parked, adjudicator: accept)`

Mark the todo complete only after the ledger entry is written.

## Final Whole-Branch Review

After all tasks, dispatch the **reviewer** in FULL REVIEW MODE with the complete branch diff (`.opencode/skills/subagent-driven-development/scripts/review-package PLAN_FILE MERGE_BASE HEAD`) and the ledger's deferred-minor and parked findings for triage.

## Finish

When final review is clean, use the finishing-a-development-branch skill.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Close enough on spec compliance" | Reviewer found spec gaps = not done. Fix or hit the cap and adjudicate. |
| "I'll fix it myself, dispatching is overhead" | Controller fixes pollute your context and skip review. Resume the implementer. |
| "One more round will converge" | Past the cap, rounds don't converge — the failure is structural. Adjudicate and route. |
| "The fix was small, skip the re-review" | Unreviewed fixes are how regressions land. Every round ends with a scoped re-review. |
| "Ledger bookkeeping is overhead" | The ledger is what survives compaction. Controllers without one have re-dispatched entire completed task sequences. |
