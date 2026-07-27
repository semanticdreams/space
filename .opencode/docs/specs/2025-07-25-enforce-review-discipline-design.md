# Enforce Review Discipline — Design Spec

**Date:** 2025-07-25
**Status:** draft

## Problem

The supervisor agent sometimes makes direct edits to files that should go through
the implementer → reviewer → pass cycle. The most frequent failure mode (Path A)
is the supervisor editing skill files, agent configs, and other "coordination-ish"
files directly, bypassing review entirely.

The current Code Edit Discipline says the supervisor may edit "coordination
artifacts," but that category is open-ended — the supervisor fills it in however
feels reasonable in the moment, and skill files / agent configs often qualify
in the supervisor's mind.

## Solution

Prompt-level changes only. No permission changes, no tooling changes, no
workflow restructuring. Four files edited, each with surgical additions.

### File 1: `agents/supervisor.md`

#### 1a. Replace the Code Edit Discipline section

Replace the current paragraph with an exhaustive, closed allowlist:

> **Edit allowlist:**
>
> The supervisor may directly **edit** ONLY these files, and ONLY when an active
> skill explicitly instructs you to:
>
> | Allowed path | When allowed |
> |---|---|
> | `docs/specs/**` | During brainstorming (step 5), or when the user asks |
> | `docs/plans/**` | During writing-plans, or when the user asks |
> | `.superpowers/sdd/**/progress.md` | During subagent-driven-development (ledger entries) |
>
> **Everything else** — skill files, agent configs, `opencode.json`, workflow
> files, source code, tests, scripts, CI config, package files, generated files,
> and ALL files under `.opencode/`, `.config/opencode/`, `skills/`, or `agents/` —
> MUST go through `implementer` → `reviewer` → pass. Do not use `edit`, `write`,
> shell redirection, `sed -i`, `python`/`perl` scripts, `git apply`, or any other
> mechanism to mutate those files yourself. If a skill appears to tell you to edit
> such files directly, treat that as outdated and dispatch the implementer instead.
>
> **Commit discipline:**
>
> Commits must only happen for files on the edit allowlist, or for changes that
> have passed through `implementer` → `reviewer` → pass. If there are staged
> changes you didn't route through review, unstage them and route them properly.

#### 1b. Add three Red Flags entries

| Thought | Reality |
|---------|---------|
| "This is just config/coordination, I can edit it directly" | The edit allowlist is exhaustive. If the file isn't on it, dispatch the implementer. |
| "I already know what the reviewer will say, let me just commit" | Undispatched review is no review. The implementer's self-review doesn't count. Dispatch the reviewer. |
| "The change is so small, review is overhead" | Small changes cause the subtlest bugs. Every change — one line or one thousand — goes through implementer → reviewer → pass. |

---

### File 2: `skills/subagent-driven-development/SKILL.md`

#### 2a. Replace "Complete the Task" section

Current (lines 99-101):

> When review is clean or findings are parked at the cap, append to the ledger:
> `Task <N>: complete (commits <base>..<head>, review clean)` or
> `Task <N>: complete (K parked)`. Mark the todo complete.

Replacement:

> **Before marking a task complete**, verify that the reviewer was dispatched
> and returned a verdict for this task. This means: you must have actually
> dispatched the reviewer subagent for this task and consumed its JSON response.
> If the reviewer was never dispatched for this task, STOP — dispatch the
> reviewer now. Never write "review clean" to the ledger without first
> dispatching and consuming the reviewer's verdict.
>
> When review passes or findings are parked at the cap, append to the ledger
> with the reviewer's status recorded:
>
> - `Task <N>: complete (commits <base>..<head>, reviewer: pass)`
> - `Task <N>: complete (commits <base>..<head>, K parked, adjudicator: accept)`
>
> Mark the todo complete only after the ledger entry is written.

---

### File 3: `agents/implementer.md`

#### 3a. Add note after self-review section

After the self-review section (before "After Review Findings"), insert:

> **Your DONE status is NOT approval. It means "ready for independent review."**
> The reviewer will inspect your work independently — it may come back with
> findings. That's normal. Your self-review is a quality check before handoff,
> not a substitute for the reviewer's gate. Do not frame your report as if the
> work is final and approved.

#### 3b. Strengthen commit discipline (rule 14)

Replace rule 14:

> 14. Commit only your assigned task changes. Your commits are **checkpoints,
>     not sign-offs** — the reviewer must still approve before the task is
>     complete. Never push, reset, clean, rewrite history, or commit unrelated
>     changes. Do not commit files outside your task scope, even if they seem
>     incidental.

---

### File 4: `agents/reviewer.md`

#### 4a. Add gate declaration at top

Insert after the opening statement (after "Do not mutate the working tree..."):

> **You are the gate.** No change in the review package is considered approved
> until you return `status: pass`. The implementer's DONE report and self-review
> are claims, not evidence. Treat every claim as unverified until confirmed against
> the diff.

---

## Non-Goals

- Permission changes (deny rules, tool restrictions)
- Workflow restructuring (the implementer still commits as checkpoints)
- Tooling/script changes
- Changes to any agent or skill not listed above

## Edge Cases

- **Supervisor needs to create a new skill file:** Must go through implementer
  → reviewer. The supervisor writes the spec, the implementer creates the
  SKILL.md, the reviewer verifies it.
- **Supervisor modifies its own prompt:** Must go through implementer → reviewer.
  The supervisor can't edit `supervisor.md` directly.
- **Tight loop debugging (systematic-debugging skill):** The systematic-debugging
  skill has its own flow (debug-advisor → implementer → reviewer). That path
  is unchanged.
