# OpenCode Explore → Plan → Implement → Review Workflow

This scaffold implements an opinionated workflow on top of OpenCode. The normal
interface is the conversational supervisor:

```bash
scripts/agent
```

The supervisor gathers the task, recommends exploration when useful, coordinates
the specialist agents, pauses for plan approval, resumes interrupted workflows,
and then hands off to the autonomous implementation/review loop.

```text
optional exploration
        ↓
human selects/clarifies direction
        ↓
proposed plan
        ↓
human approves plan; supervisor checkpoints workflow artifacts
        ↓
initial implementation
        ↓
full independent review
        ↓
finding adjudication
        ↓
accepted findings only
        ↓
fix attempt
        ↓
targeted verification
        ↺ up to the configured fix-attempt budget
        ↓
fresh full review of the entire accumulated diff
        ↺ up to the configured review-round budget
        ↓
final deterministic validation
        ↓
human verifies final diff and behavior
```

The scripts launch each role as a fresh primary OpenCode session. They never use
`--continue` or `--session`. This preserves context separation between
implementation, review, and adjudication.

The Python supervisor owns persisted state transitions and safety gates. When
`models.supervisor` is configured, it also invokes a read-only conversational
supervisor agent to summarize artifacts, surface decisions, recommend next
actions, and prepare the final human-test checklist. That agent still does not
implement, review, or adjudicate code.

## Roles

| Role | Suggested model | Temperature | Writes code |
|---|---|---:|---|
| Supervisor | DeepSeek V4 Pro | 0.2 | No |
| Explorer | GPT-5.5-class model | 0.7 | No |
| Planner | GPT-5.5-class model | 0.1 | No |
| Implementer | DeepSeek V4 Pro | 0.4 | Yes |
| Fixer | DeepSeek V4 Pro | 0.25 | Yes |
| Reviewer | GPT-5.5-class model | 0.1 | No |
| Adjudicator | GPT-5.5-class model | 0.1 | No |

The reviewer has two prompt modes:

- **Full review:** reassesses the complete accumulated change.
- **Targeted verification:** checks only whether accepted findings were fixed.

The adjudicator does not perform another review. It accepts, rejects, or
escalates each candidate finding. This is intended to filter false positives,
premature abstractions, stylistic preferences, and unrelated cleanup.

## Quality bar

Every workflow stage should optimize for the smallest clean production-ready
design, not the smallest patch. Final changes should be functional, tested,
native to the existing codebase, and not overengineered. Agents should reuse and
extend existing abstractions when they fit, but should refactor or redesign
previous abstractions when that is the cleanest way to avoid brittle patchwork or
support expected follow-on work.

Material features, subsystems, recurring problems, workflows, architectural
decisions, and operational assumptions should be documented under `docs/dev/`.
Documentation should describe the final implementation and current invariants,
not just the initial plan. Missing or stale docs are review-blocking when future
work would reasonably depend on that context.

## Requirements

- OpenCode
- Git
- Python 3.11 or newer
- Bash
- A Git repository
- Configured OpenCode provider credentials

This scaffold is designed for Linux, macOS, or WSL. The shell validation runner
uses `/bin/bash`.

## 1. Copy the scaffold into a repository

Copy these paths into the root of the target repository:

```text
.opencode/agents/
.agent-workflow/
scripts/
agent.toml
```

Merge `.gitignore` entries rather than replacing an existing `.gitignore`.

## 2. Configure providers and model identifiers

Authenticate providers through OpenCode, then list exact identifiers:

```bash
opencode auth login
opencode models --refresh
```

Edit `[models]` in `agent.toml`. For example:

```toml
[models]
explorer = "your-chatgpt-provider/your-gpt-model"
supervisor = "your-opencode-go-provider/deepseek-v4-pro"
planner = "your-chatgpt-provider/your-gpt-model"
implementer = "your-opencode-go-provider/deepseek-v4-pro"
fixer = "your-opencode-go-provider/deepseek-v4-pro"
reviewer = "your-chatgpt-provider/your-gpt-model"
adjudicator = "your-chatgpt-provider/your-gpt-model"
```

Do not copy those illustrative provider names literally. Use the exact
`provider/model` values printed by your OpenCode installation.

Model selection is kept in `agent.toml`, while behavior and temperature are
kept in the agent Markdown files. The orchestrator passes `--model` for each
run, allowing model changes without editing agent definitions. Initial
implementation and review-fix attempts use separate model keys (`implementer`
and `fixer`) so bounded fixes can use a cheaper build-capable model.

OpenAI-backed roles are invoked through OpenCode, not the OpenAI API directly.
The orchestrator cannot rely on provider rate-limit headers. When an OpenCode
stage fails, stdout and stderr are saved beside that stage's raw output. If the
text looks model-limit related, the supervisor model classifies the failure from
the captured output. It may auto-wait only when the failure text explicitly
contains a retry/reset time; otherwise it records a resumable
`blocked_model_limit` state and stops.

Verify that OpenCode sees the agents:

```bash
opencode agent list
```

## 3. Configure deterministic validation

The implementer agent is instructed to:

1. use the narrowest focused test during development;
2. run the complete relevant suite after the focused test passes;
3. run the checks listed in the approved plan.

The orchestrator can additionally enforce repository-specific commands. Edit
`[validation]` in `agent.toml`:

```toml
[validation]
after_implementation = [
  "make build"
]
after_fix = [
  "make build"
]
final = [
  "make test"
]
```

These are the Space defaults. The planner should still choose focused tests for
the feature area, such as a single Fennel test module, a targeted CTest binary,
or an E2E snapshot suite when visual behavior changes. Keep expensive or
environment-sensitive checks like `make test-e2e` in `final` unless the task
specifically requires snapshot validation.

The external commands are deterministic gates. A failed command stops the
workflow immediately and records output in the run's `validation.log`.

## 4. Commit the scaffold

The automation requires a clean worktree before implementation so it can define
an unambiguous base commit.

```bash
chmod +x scripts/agent scripts/agent.py scripts/extract_json.py
git add .opencode .agent-workflow scripts agent.toml .gitignore
git commit -m "Add OpenCode agent workflow"
```

## 5. Describe the task

Run the supervisor and describe the task conversationally:

```bash
scripts/agent
```

It writes the durable task artifact at `.agent-workflow/TASK.md` before running
exploration or planning. Advanced users can still pass a task directly to a
stage command:

```bash
scripts/agent start "Implement appointment department filtering"
```

For multiline tasks, pipe Markdown into the command:

```bash
cat task.md | scripts/agent plan
```

When no task argument is supplied and stdin is interactive, `explore`, `plan`,
and `start` prompt with `Describe the task:` and read until EOF. `plan` can also
reuse an existing `.agent-workflow/TASK.md` after confirmation.

The supervisor uses `.agent-workflow/STATE.json` to resume. If you stop after
exploration, after plan generation, after approval, or at the commit boundary,
running `scripts/agent` again continues from that explicit state.

If the supervisor model is configured, exploration and planning produce
additional summaries such as `.agent-workflow/SUPERVISOR.exploration.md` and
`.agent-workflow/SUPERVISOR.plan.md`. These summaries are advisory; the approved
`.agent-workflow/PLAN.md` remains the implementation contract. If an advisory
summary fails, the supervisor prints a warning and continues.

Include enough detail for:

- requested behavior;
- known constraints;
- acceptance criteria;
- human-selected direction after exploration;
- forbidden compatibility or architecture changes.

## 6. Optional exploration

The supervisor recommends exploration when the task looks architectural,
ambiguous, migration-heavy, or cross-cutting. Advanced users can run exploration
directly:

Use exploration for ambiguous, architectural, cross-cutting, migration, or
unfamiliar work:

```bash
scripts/agent explore "Investigate appointment filtering architecture"
```

The report is written to:

```text
.agent-workflow/EXPLORATION.md
```

Read it and include the chosen direction or resolved questions when you run
`scripts/agent plan "..."`. Do not pass exploration directly to implementation.
The planner receives it; the approved plan becomes the sole implementation
contract.

Skip exploration for localized bugs, mechanical changes, or work that already
has an approved design.

## 7. Generate and approve the plan

The supervisor normally generates the plan and asks whether to approve, revise,
edit externally, or cancel. Advanced users can run planning directly:

Generate a proposal:

```bash
scripts/agent plan "Implement appointment department filtering"
```

If `.agent-workflow/TASK.md` already contains the desired task, run
`scripts/agent plan` and accept the reuse prompt.

Review and edit:

```text
.agent-workflow/PLAN.proposed.md
```

The planner is expected to define:

- one chosen approach;
- implementation steps;
- invariants;
- acceptance criteria;
- focused tests;
- the relevant suite;
- broader final checks;
- explicit non-goals;
- rollback and risk considerations.
- docs/dev pages to create or update.

The approval command refuses plans containing `HUMAN_DECISION_REQUIRED`:

```bash
scripts/agent approve-plan
```

This copies the proposal to:

```text
.agent-workflow/PLAN.md
```

Review it once more. In supervisor mode, approval can create a narrow checkpoint
commit containing only workflow artifacts (`TASK.md`, exploration, and proposed
and approved plans) before starting implementation. If unrelated
files are dirty, the supervisor refuses the checkpoint and asks you to resolve
the worktree first.

In conversational supervisor mode, unresolved `HUMAN_DECISION_REQUIRED` items are
shown before approval. Enter the decisions once; the supervisor appends them to
`TASK.md`, re-runs planning, and asks for approval of the revised plan. The
approval command still refuses unresolved decisions as a final safety gate.

For manual operation, commit the task and approved plan:

```bash
git add -u -- .agent-workflow
git add .agent-workflow/TASK.md .agent-workflow/PLAN.proposed.md \
        .agent-workflow/PLAN.md
test ! -f .agent-workflow/EXPLORATION.md || git add .agent-workflow/EXPLORATION.md
git commit -m "Approve implementation plan"
```

The `git add -u` line stages tracked deletions, such as a stale
`.agent-workflow/EXPLORATION.md` from a previous task when exploration is skipped
for the current task.

## 8. Run the automated portion

```bash
scripts/agent run
```

The command requires a clean worktree. It records the current `HEAD` as the
base commit and then performs:

1. initial implementation;
2. deterministic post-implementation validation;
3. full review;
4. adjudication;
5. fixes for accepted findings only, using the separate fixer role;
6. deterministic post-fix validation;
7. targeted verification;
8. another fresh full review;
9. final deterministic validation.

Each implementation, review, adjudication, fix, and verification call is a new
OpenCode session.

For the ergonomic complete flow, use:

```bash
scripts/agent
```

This captures the task, optionally runs exploration, creates the proposed plan,
pauses for approval, creates a workflow checkpoint commit when needed, then uses
the same approval and run logic as `approve-plan` and `run`. If unrelated dirty
files prevent checkpointing, resolve them and run `scripts/agent` again.

## Review convergence rules

A full review passes directly when it reports no candidate findings.

When candidates exist, adjudication assigns:

- `accept`: real blocking defect; send to fixer;
- `reject`: unsupported, non-blocking, premature, or unrelated; ignore;
- `escalate`: stop for human judgment.

Accepted findings receive a configured fix-attempt budget. Each attempt is
followed by targeted verification. Once all accepted findings are verified, the
system performs a new full review of the entire accumulated diff. This is
necessary because a correct fix may expose masked issues or introduce other
defects.

The workflow stops for a human when:

- review or adjudication finds a plan-level ambiguity;
- the configured fix-attempt budget is exhausted;
- the configured review-round budget is exhausted;
- a deterministic validation command fails;
- material docs/dev documentation is missing or stale;
- OpenCode returns malformed structured output.

Budgets are configured in `agent.toml`:

```toml
[workflow]
review_round_budget = 10
fix_attempt_budget = 5
max_model_limit_wait_seconds = 21600
```

Budgets are safety windows, not quality targets. If either budget is exhausted,
the workflow saves `blocked_review_budget`, not success. Running `scripts/agent`
again asks whether to continue another budget window from the saved review or
fix step. Final success still requires a fresh full review pass and final
validation pass.

If a deterministic validation command fails, the workflow saves
`blocked_validation` with the failed command, remaining command list, validation
log, and next run checkpoint. Running `scripts/agent` or `scripts/agent run`
reruns the remaining validation commands and then continues from that checkpoint.

`max_model_limit_wait_seconds` caps automatic waiting for an explicit short
model-limit reset. The default Space value is six hours. Longer, weekly, or
unclear limits stop and can be resumed later with `scripts/agent`.

## Human notifications

The workflow can play a sound and send a desktop notification when it reaches a
human-required pause. The default Space config is:

```toml
[notifications]
enabled = true
sound = ["paplay", "/usr/share/sounds/freedesktop/stereo/message.oga"]
desktop = ["notify-send"]
```

Notifications are best-effort and non-blocking. Missing commands, unavailable
audio, SSH sessions, or a missing desktop notification bus do not fail the
workflow. The desktop command receives the notification title and message as
additional arguments after the configured prefix.

Notification points include plan approval, unresolved planner decisions,
checkpoint confirmation, model-limit blocks, review/adjudication/verification
human-judgment stops, and final human testing.

## Model-limit recovery

When a provider/model limit blocks a stage, the supervisor records:

- blocked role and model;
- blocked stage;
- stdout/stderr artifacts;
- classifier summary and quoted evidence;
- retry time when one was explicit;
- resume command and run-stage checkpoint when available.

Run `scripts/agent` to continue. If the explicit retry time is still in the
future, the supervisor asks whether to wait; `Ctrl-C` stops safely and preserves
state. If the retry time has passed, it retries the saved stage. If no reliable
retry time was available, it asks before retrying interactively.

For `explorer` and `planner`, resume re-runs the blocked read-only stage. For
run-time `reviewer` and `adjudicator` failures, resume continues from the saved
full-review, adjudication, or targeted-verification checkpoint without rerunning
the implementation stage. Automatic resume is intentionally limited to read-only
stages. If implementation or fixing stops on a long/unclear provider limit,
inspect the diff and run artifacts before deciding how to continue.

## 9. Inspect results

Run:

```bash
scripts/agent status
git diff --stat
git diff
```

Run artifacts are under:

```text
.agent-workflow/runs/<timestamp>/
```

They include:

- base commit;
- raw agent outputs;
- parsed full reviews;
- adjudications;
- accepted finding subsets;
- pre-fix patches;
- targeted verification reports;
- validation logs;
- a `SUCCESS` marker when the automation converges.

When automation converges, the supervisor enters `ready_for_human_test` and asks
you to perform the final human behavior review. The final human check should
verify:

- actual behavior, not only code shape;
- acceptance criteria;
- the entire accumulated diff;
- migrations and rollback where applicable;
- tests that matter but were omitted from configured gates;
- absence of unrelated changes.

After this check passes, the supervisor can mark the workflow `human_accepted`
and hand off to your normal git-commit workflow. It writes
`human-test-handoff.md` in the run directory with the task, approved-plan path,
automation result, current worktree summary, diff stat, validation log, latest
review/adjudication artifacts, and manual checks. If the supervisor model is
configured, it also writes a concise `human-test-supervisor.md` checklist.

The final commit remains explicit. After `human_accepted`, inspect `git status`,
`git diff --stat`, and `git diff`, then use the repository's normal git-commit
workflow so the final commit includes only intended implementation and workflow
artifacts.

## Agent safety model

The Python supervisor owns state transitions. The optional supervisor agent owns
conversation and summaries only. Neither writes implementation code, performs
review, or adjudicates findings.

The supervisor, explorer, planner, reviewer, and adjudicator deny editing and
shell access. The orchestrator supplies review-stage Git status and diff
artifacts as file attachments, including capped untracked-file contents, so
those roles do not need to run Git commands themselves.

The implementer can edit and run repository commands, but denies common
history-changing and destructive Git operations such as push, commit, reset,
checkout, restore, and clean. It also denies external-directory access and
subagent delegation.

OpenCode's shell permission patterns are useful safeguards, not a complete
sandbox. The implementer intentionally keeps enough shell access to build, test,
run focused `./build/space` modules, and profile. Risky Make targets such as
clean, install, release, packaging, and AppImage builds are denied. For
sensitive repositories, run the workflow in a disposable Git worktree or
container.

## Optional isolated worktree

After committing the approved plan:

```bash
branch="agent/$(date +%Y%m%d-%H%M%S)"
worktree="../$(basename "$PWD")-agent"

git worktree add -b "$branch" "$worktree" HEAD
cd "$worktree"
scripts/agent run
```

Review and commit in that branch, then merge it through the normal repository
process.

## Customization guidance

### Expensive tests

Keep focused and subsystem tests in the plan. Put slow repository-wide checks in
`validation.final`.

### High-risk work

For authentication, authorization, security boundaries, concurrency, billing,
schema migration, or irreversible data operations, add a final adversarial
review with a different model family before human approval. It should challenge
both plan assumptions and implementation rather than merely check compliance.

### Finding granularity

The default implementation fixes all accepted findings from a full-review
round as one batch. For risky or unrelated findings, modify `agent.py` to
write one accepted-finding file per subsystem or finding and invoke separate
fix sessions. Targeted verification is easier when each batch shares a root
cause.

### Existing uncommitted work

Do not weaken the clean-tree requirement casually. Use a dedicated worktree,
commit a checkpoint, or stash unrelated work before automation.

## Important limitation

This is orchestration built on OpenCode's agent, model, permission, and
non-interactive CLI primitives. It is not a built-in OpenCode workflow engine.
The scripts intentionally own the stage transitions and stopping rules.
