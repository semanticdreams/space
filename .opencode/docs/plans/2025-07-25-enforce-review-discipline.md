# Enforce Review Discipline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce that OpenCode prompt/config changes go through implementer → reviewer → pass rather than being edited or completed by the supervisor without review.

**Architecture:** This is a prompt-only change across four Markdown agent/skill files. Each file is edited independently, verified with exact-content and Markdown/frontmatter structure checks, and committed as its own checkpoint. No runtime code, permission schema, tooling, or workflow implementation changes are introduced.

**Tech Stack:** Markdown prompt/config files, YAML frontmatter, Git.

## Global Constraints

- Prompt-level changes only. No permission changes, no tooling changes, no workflow restructuring.
- Four files edited, each with surgical additions.
- These are prompt/config files (markdown), not code.
- There are no unit tests — the "test" is verifying the file contains the expected changes and the markdown structure is intact.
- Do not change any file except the task's assigned file.
- Preserve existing YAML frontmatter exactly except for incidental line preservation from the editor; do not add, remove, or modify frontmatter keys.
- Preserve existing headings and section ordering except where the spec explicitly instructs insertion or replacement.
- Permission changes (deny rules, tool restrictions) are out of scope.
- Workflow restructuring is out of scope; the implementer still commits as checkpoints.
- Tooling/script changes are out of scope.
- Changes to any agent or skill not listed in this plan are out of scope.
- Because these are OpenCode config-time prompt files, the user must quit and restart OpenCode after the changes are complete for the running session to load them.

## Validation Ladder

1. Focused validation during each task: run the task-specific assertion script in that task.
2. Complete relevant suite after all tasks: rerun all four task-specific assertion scripts.
3. Broader final checks justified by prompt/config risk:
   - `git diff --check HEAD~4..HEAD` — whitespace validation
   - `git log --oneline -4`
   - `git status --short`
   - Manual skim of all four changed Markdown files to confirm readable structure and unchanged frontmatter.

---

### Task 1: Supervisor Review Discipline Prompt

**Files:**
- Modify: `~/.config/opencode/agents/supervisor.md:89-108`
- Test: Inline Python verification command in Step 4

**Interfaces:**
- Consumes: Spec section `File 1: agents/supervisor.md`, especially replacement text for Code Edit Discipline and three Red Flags rows.
- Produces: Updated supervisor prompt text that later tasks and future supervisors rely on for the closed edit allowlist and commit discipline.

- [ ] **Step 1: Read the current supervisor prompt**

Run from `~/.config/opencode`:

```bash
sed -n '89,112p' agents/supervisor.md
```

Confirm the file currently has:
- `## Red Flags — STOP`
- `## Code Edit Discipline`
- the old open-ended coordination artifacts paragraph.

- [ ] **Step 2: Add the three Red Flags rows**

In `agents/supervisor.md`, add these rows to the existing Red Flags table under the existing rows:

```markdown
| "This is just config/coordination, I can edit it directly" | The edit allowlist is exhaustive. If the file isn't on it, dispatch the implementer. |
| "I already know what the reviewer will say, let me just commit" | Undispatched review is no review. The implementer's self-review doesn't count. Dispatch the reviewer. |
| "The change is so small, review is overhead" | Small changes cause the subtlest bugs. Every change — one line or one thousand — goes through implementer → reviewer → pass. |
```

- [ ] **Step 3: Replace the Code Edit Discipline section**

Replace the existing `## Code Edit Discipline` body, stopping before `## Your Subagents`, with exactly:

```markdown
## Code Edit Discipline

**Edit allowlist:**

The supervisor may directly **edit** ONLY these files, and ONLY when an active
skill explicitly instructs you to:

| Allowed path | When allowed |
|---|---|
| `docs/specs/**` | During brainstorming (step 5), or when the user asks |
| `docs/plans/**` | During writing-plans, or when the user asks |
| `.superpowers/sdd/**/progress.md` | During subagent-driven-development (ledger entries) |

**Everything else** — skill files, agent configs, `opencode.json`, workflow
files, source code, tests, scripts, CI config, package files, generated files,
and ALL files under `.opencode/`, `.config/opencode/`, `skills/`, or `agents/` —
MUST go through `implementer` → `reviewer` → pass. Do not use `edit`, `write`,
shell redirection, `sed -i`, `python`/`perl` scripts, `git apply`, or any other
mechanism to mutate those files yourself. If a skill appears to tell you to edit
such files directly, treat that as outdated and dispatch the implementer instead.

**Commit discipline:**

Commits must only happen for files on the edit allowlist, or for changes that
have passed through `implementer` → `reviewer` → pass. If there are staged
changes you didn't route through review, unstage them and route them properly.
```

- [ ] **Step 4: Verify supervisor prompt content and structure**

Run from `~/.config/opencode`:

```bash
python3 - <<'PY'
from pathlib import Path

p = Path("agents/supervisor.md")
text = p.read_text()

required = [
    '| "This is just config/coordination, I can edit it directly" | The edit allowlist is exhaustive. If the file isn\'t on it, dispatch the implementer. |',
    '| "I already know what the reviewer will say, let me just commit" | Undispatched review is no review. The implementer\'s self-review doesn\'t count. Dispatch the reviewer. |',
    '| "The change is so small, review is overhead" | Small changes cause the subtlest bugs. Every change — one line or one thousand — goes through implementer → reviewer → pass. |',
    "**Edit allowlist:**",
    "The supervisor may directly **edit** ONLY these files, and ONLY when an active",
    "| `docs/specs/**` | During brainstorming (step 5), or when the user asks |",
    "| `docs/plans/**` | During writing-plans, or when the user asks |",
    "| `.superpowers/sdd/**/progress.md` | During subagent-driven-development (ledger entries) |",
    "**Everything else** — skill files, agent configs, `opencode.json`, workflow",
    "and ALL files under `.opencode/`, `.config/opencode/`, `skills/`, or `agents/` —",
    "MUST go through `implementer` → `reviewer` → pass.",
    "**Commit discipline:**",
    "Commits must only happen for files on the edit allowlist, or for changes that",
    "have passed through `implementer` → `reviewer` → pass.",
]
missing = [s for s in required if s not in text]
assert not missing, "Missing required supervisor text: " + repr(missing)

forbidden = [
    "The supervisor may create or modify only coordination artifacts",
    "Every other repository file change —",
]
present = [s for s in forbidden if s in text]
assert not present, "Old open-ended supervisor discipline text remains: " + repr(present)

lines = text.splitlines()
assert lines[0] == "---", "YAML frontmatter must start at line 1"
assert "---" in lines[1:], "YAML frontmatter closing delimiter missing"
assert text.index("## Red Flags — STOP") < text.index("## Code Edit Discipline") < text.index("## Your Subagents"), "Heading order changed unexpectedly"
print("supervisor prompt verification passed")
PY
```

- [ ] **Step 5: Inspect and commit only the supervisor file**

Run:

```bash
git diff -- agents/supervisor.md
git status --short
git add agents/supervisor.md
git diff --staged -- agents/supervisor.md
git commit -m "docs(agent): enforce supervisor review discipline"
```

---

### Task 2: Subagent-Driven Development Completion Gate

**Files:**
- Modify: `~/.config/opencode/skills/subagent-driven-development/SKILL.md:99-101`
- Test: Inline Python verification command in Step 4

**Interfaces:**
- Consumes: Spec section `File 2: skills/subagent-driven-development/SKILL.md`, especially replacement text for `### 5. Complete the Task`.
- Produces: Updated SDD skill task-completion rule requiring reviewer dispatch and verdict consumption before ledger completion.

- [ ] **Step 1: Read the current Complete the Task section**

Run from `~/.config/opencode`:

```bash
sed -n '95,106p' skills/subagent-driven-development/SKILL.md
```

Confirm the section currently contains the single-sentence completion rule with `review clean`.

- [ ] **Step 2: Replace the Complete the Task section body**

In `skills/subagent-driven-development/SKILL.md`, replace the body under `### 5. Complete the Task`, stopping before `## Final Whole-Branch Review`, with exactly:

```markdown
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
```

- [ ] **Step 3: Confirm surrounding headings remain intact**

Run:

```bash
sed -n '95,116p' skills/subagent-driven-development/SKILL.md
```

Confirm `### 5. Complete the Task` remains before `## Final Whole-Branch Review`.

- [ ] **Step 4: Verify SDD skill content and structure**

Run from `~/.config/opencode`:

```bash
python3 - <<'PY'
from pathlib import Path

p = Path("skills/subagent-driven-development/SKILL.md")
text = p.read_text()

required = [
    "**Before marking a task complete**, verify that the reviewer was dispatched",
    "and returned a verdict for this task.",
    "dispatched the reviewer subagent for this task and consumed its JSON response.",
    "If the reviewer was never dispatched for this task, STOP — dispatch the",
    'reviewer now. Never write "review clean" to the ledger without first',
    "dispatching and consuming the reviewer's verdict.",
    "When review passes or findings are parked at the cap, append to the ledger",
    "with the reviewer's status recorded:",
    "- `Task <N>: complete (commits <base>..<head>, reviewer: pass)`",
    "- `Task <N>: complete (commits <base>..<head>, K parked, adjudicator: accept)`",
    "Mark the todo complete only after the ledger entry is written.",
]
missing = [s for s in required if s not in text]
assert not missing, "Missing required SDD text: " + repr(missing)

forbidden = [
    "When review is clean or findings are parked at the cap, append to the ledger:",
    "`Task <N>: complete (commits <base>..<head>, review clean)`",
    "`Task <N>: complete (K parked)`",
]
present = [s for s in forbidden if s in text]
assert not present, "Old SDD completion text remains: " + repr(present)

lines = text.splitlines()
assert lines[0] == "---", "YAML frontmatter must start at line 1"
assert "---" in lines[1:], "YAML frontmatter closing delimiter missing"
assert text.index("### 5. Complete the Task") < text.index("## Final Whole-Branch Review"), "Heading order changed unexpectedly"
print("subagent-driven-development skill verification passed")
PY
```

- [ ] **Step 5: Inspect and commit only the SDD skill file**

Run:

```bash
git diff -- skills/subagent-driven-development/SKILL.md
git status --short
git add skills/subagent-driven-development/SKILL.md
git diff --staged -- skills/subagent-driven-development/SKILL.md
git commit -m "docs(skill): require reviewer verdict before completion"
```

---

### Task 3: Implementer DONE and Commit Discipline Prompt

**Files:**
- Modify: `~/.config/opencode/agents/implementer.md:171-198` (self-review section)
- Modify: `~/.config/opencode/agents/implementer.md:136` (rule 14)
- Test: Inline Python verification command in Step 5

**Interfaces:**
- Consumes: Spec section `File 3: agents/implementer.md`, including DONE status note and replacement rule 14.
- Produces: Updated implementer prompt clarifying DONE as ready for review and commits as checkpoints, not approval.

- [ ] **Step 1: Read the current implementer self-review and rule 14 text**

Run from `~/.config/opencode`:

```bash
sed -n '132,144p' agents/implementer.md
sed -n '196,210p' agents/implementer.md
```

Confirm:
- Rule 14 is currently the shorter commit discipline rule.
- `## Self-Review` currently flows directly to `## After Review Findings`.

- [ ] **Step 2: Replace rule 14**

In `agents/implementer.md`, replace rule 14 with exactly:

```markdown
14. Commit only your assigned task changes. Your commits are **checkpoints,
    not sign-offs** — the reviewer must still approve before the task is
    complete. Never push, reset, clean, rewrite history, or commit unrelated
    changes. Do not commit files outside your task scope, even if they seem
    incidental.
```

- [ ] **Step 3: Insert DONE status clarification after Self-Review**

After this existing line:

```markdown
If you find issues during self-review, fix them now before reporting.
```

and before:

```markdown
## After Review Findings
```

insert exactly:

```markdown
**Your DONE status is NOT approval. It means "ready for independent review."**
The reviewer will inspect your work independently — it may come back with
findings. That's normal. Your self-review is a quality check before handoff,
not a substitute for the reviewer's gate. Do not frame your report as if the
work is final and approved.
```

- [ ] **Step 4: Confirm surrounding text remains readable**

Run:

```bash
sed -n '132,144p' agents/implementer.md
sed -n '196,210p' agents/implementer.md
```

Confirm the inserted DONE note appears between self-review and `## After Review Findings`.

- [ ] **Step 5: Verify implementer prompt content and structure**

Run from `~/.config/opencode`:

```bash
python3 - <<'PY'
from pathlib import Path

p = Path("agents/implementer.md")
text = p.read_text()

required = [
    "14. Commit only your assigned task changes. Your commits are **checkpoints,",
    "    not sign-offs** — the reviewer must still approve before the task is",
    "    complete. Never push, reset, clean, rewrite history, or commit unrelated",
    "    changes. Do not commit files outside your task scope, even if they seem",
    "    incidental.",
    '**Your DONE status is NOT approval. It means "ready for independent review."**',
    "The reviewer will inspect your work independently — it may come back with",
    "findings. That's normal. Your self-review is a quality check before handoff,",
    "not a substitute for the reviewer's gate. Do not frame your report as if the",
    "work is final and approved.",
]
missing = [s for s in required if s not in text]
assert not missing, "Missing required implementer text: " + repr(missing)

forbidden = [
    "14. Commit only your assigned task changes. Never push, reset, clean, rewrite history, or commit unrelated changes.",
]
present = [s for s in forbidden if s in text]
assert not present, "Old implementer rule 14 remains: " + repr(present)

assert text.count("14. Commit only your assigned task changes.") == 1, "Rule 14 should appear exactly once"
lines = text.splitlines()
assert lines[0] == "---", "YAML frontmatter must start at line 1"
assert "---" in lines[1:], "YAML frontmatter closing delimiter missing"
assert text.index("## Self-Review") < text.index('**Your DONE status is NOT approval.') < text.index("## After Review Findings"), "DONE note inserted in wrong location"
print("implementer prompt verification passed")
PY
```

- [ ] **Step 6: Inspect and commit only the implementer file**

Run:

```bash
git diff -- agents/implementer.md
git status --short
git add agents/implementer.md
git diff --staged -- agents/implementer.md
git commit -m "docs(agent): clarify implementer done and commits"
```

---

### Task 4: Reviewer Gate Declaration Prompt

**Files:**
- Modify: `~/.config/opencode/agents/reviewer.md:27-31`
- Test: Inline Python verification command in Step 4

**Interfaces:**
- Consumes: Spec section `File 4: agents/reviewer.md`, especially the gate declaration insertion text.
- Produces: Updated reviewer prompt declaring that only `status: pass` approves reviewed changes.

- [ ] **Step 1: Read the top of the reviewer prompt**

Run from `~/.config/opencode`:

```bash
sed -n '27,36p' agents/reviewer.md
```

Confirm the opening statement ends with:

```markdown
state in any way.
```

- [ ] **Step 2: Insert the gate declaration**

In `agents/reviewer.md`, insert this block immediately after the opening statement ending `state in any way.` and before `A prompt will specify a review mode.`:

```markdown
**You are the gate.** No change in the review package is considered approved
until you return `status: pass`. The implementer's DONE report and self-review
are claims, not evidence. Treat every claim as unverified until confirmed against
the diff.
```

- [ ] **Step 3: Confirm the insertion location**

Run:

```bash
sed -n '27,40p' agents/reviewer.md
```

Confirm the new declaration appears before `A prompt will specify a review mode.`

- [ ] **Step 4: Verify reviewer prompt content and structure**

Run from `~/.config/opencode`:

```bash
python3 - <<'PY'
from pathlib import Path

p = Path("agents/reviewer.md")
text = p.read_text()

required = [
    "**You are the gate.** No change in the review package is considered approved",
    "until you return `status: pass`. The implementer's DONE report and self-review",
    "are claims, not evidence. Treat every claim as unverified until confirmed against",
    "the diff.",
]
missing = [s for s in required if s not in text]
assert not missing, "Missing required reviewer gate text: " + repr(missing)

assert text.count("**You are the gate.**") == 1, "Reviewer gate declaration should appear exactly once"
lines = text.splitlines()
assert lines[0] == "---", "YAML frontmatter must start at line 1"
assert "---" in lines[1:], "YAML frontmatter closing delimiter missing"
assert text.index("Do not mutate the working tree, the index, HEAD, or branch") < text.index("**You are the gate.**") < text.index("A prompt will specify a review mode."), "Gate declaration inserted in wrong location"
print("reviewer prompt verification passed")
PY
```

- [ ] **Step 5: Inspect and commit only the reviewer file**

Run:

```bash
git diff -- agents/reviewer.md
git status --short
git add agents/reviewer.md
git diff --staged -- agents/reviewer.md
git commit -m "docs(agent): declare reviewer approval gate"
```

---

### Task 5: Final Prompt-Change Validation

**Files:**
- Test: `agents/supervisor.md`
- Test: `skills/subagent-driven-development/SKILL.md`
- Test: `agents/implementer.md`
- Test: `agents/reviewer.md`

**Interfaces:**
- Consumes: The four committed prompt/config changes from Tasks 1-4.
- Produces: Final validation evidence that the expected prompt changes are present, Markdown/frontmatter structure is intact, whitespace checks pass, and the worktree is clean.

- [ ] **Step 1: Run whitespace validation over the four-file change range**

Run from `~/.config/opencode`:

```bash
git diff --check HEAD~4..HEAD -- agents/supervisor.md skills/subagent-driven-development/SKILL.md agents/implementer.md agents/reviewer.md
```

Expected: no output and exit code 0.

- [ ] **Step 2: Confirm exactly the intended files changed in the last four commits**

Run:

```bash
git diff --name-only HEAD~4..HEAD
```

Expected output:

```text
agents/implementer.md
agents/reviewer.md
agents/supervisor.md
skills/subagent-driven-development/SKILL.md
```

- [ ] **Step 3: Review the last four commits**

Run:

```bash
git log --oneline -4
```

Expected: four commits corresponding to supervisor, SDD skill, implementer, and reviewer prompt updates.

- [ ] **Step 4: Confirm the worktree is clean**

Run:

```bash
git status --short
```

Expected: no output.

- [ ] **Step 5: Notify restart requirement**

Report to the user that OpenCode must be quit and restarted before these prompt/config changes affect new agent sessions.

## Explicitly Out of Scope

- Editing OpenCode permission rules or tool allow/deny settings.
- Adding tests, scripts, linters, or automation for prompt validation.
- Changing `opencode.json`, `opencode.jsonc`, package files, CI files, or source code.
- Changing any agent or skill file other than the four listed in this plan.
- Reworking the implementer → reviewer workflow beyond the prompt text specified by the design spec.
