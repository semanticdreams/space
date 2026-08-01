# Agent Validation Continuation Design

## Context

Agents sometimes stop after final validation fails with a message that the
failure is unrelated to the current branch, flaky, environmental, or caused by a
known runtime suite issue. That behavior leaves the branch unfinished even though
the next useful action is usually still agent-owned: investigate the failing
suite, identify the root cause, fix the underlying issue when possible, update
the branch from `origin/main` when needed, rerun validation, and continue toward
the normal integration action.

The repository already has a validation-failure recovery policy for normal
development finishing, but workflow-specific instructions still leave loopholes:
automation workflows can treat validation failure as `BLOCKED`, the finalization
path does not explicitly require checking whether the branch is behind
`origin/main`, and “unrelated” or “environmental” can be read as a reason to stop
before attempting a clean recovery.

## Requirement

All Space agent workflows must treat required validation failures as active work
to investigate and resolve, not as a terminal state. This applies to normal
implementation branches, final finishing, docs/OpenCode branches, daily devlog
automation, weekly agent workflow automation, and any future scheduled or manual
automation that performs required validation before integration.

When required validation fails, the agent must:

1. Preserve integration safety: do not report completion, push, create a PR,
   merge, clean up, or claim ready-to-merge while validation is red.
2. Capture the failing command, failing tests, relevant output, current branch
   state, and `git status --porcelain`.
3. Invoke `systematic-debugging` and continue investigating even when the failure
   appears unrelated, flaky, timing-dependent, or environmental.
4. Establish root cause or gather enough evidence to justify why root cause
   cannot be established with available access.
5. Route any repository fix through `implementer` → `reviewer` → pass, commit
   reviewed fixes, rerun validation, and restart finalization from the top.
6. Stop for the human only when systematic debugging establishes that progress
   requires human input: credentials, inaccessible infrastructure, unsafe git
   history decisions, unreproducible behavior after reasonable evidence
   gathering, or a product/API/data/architecture choice.

Additionally, before final validation and PR creation, workflows must ensure the
branch is evaluated against current `origin/main`. If the branch is behind or
remote integration would be rejected, the agent should fetch `origin`, update the
feature branch by a safe merge from `origin/main` when permitted, resolve any
conflicts through the normal implementer/reviewer loop, and rerun validation. The
agent must not rebase or force-push unless the human explicitly requests it.

## Approaches Considered

### Approach A: Update only `finishing-a-development-branch`

This would improve the normal implementation path but leave scheduled automation
skills and other workflow entry points with different failure semantics. Agents
could still stop early in daily/weekly automation because those skills currently
name validation failure as a `BLOCKED` condition.

### Approach B: Patch every workflow independently

This covers more entry points, but each skill would own its own variant of the
recovery loop. Over time those variants can drift, especially around what counts
as environmental, how much evidence is enough, and whether `origin/main` must be
checked before final validation.

### Approach C: Centralize the invariant and update all entry points

This is the recommended approach. Keep the canonical policy in repository-wide
guidance and the finishing skill, then make daily/weekly automation and related
workflow docs defer to the same recovery contract. Add explicit current-base
handling so final validation happens on a branch that has accounted for current
`origin/main`.

## Design

### Architecture

The workflow change is instruction-only. It updates the layers agents consult at
different moments:

- `AGENTS.md`: repository-wide invariant for all workflows: validation failure
  means debug/fix/rerun, and all final validation is against current
  `origin/main` state.
- `.opencode/agents/supervisor.md`: completion discipline and core workflow
  rules, including the distinction between “appears unrelated” and “cannot
  proceed without human input.”
- `.opencode/skills/finishing-a-development-branch/SKILL.md`: concrete final
  validation loop, with a safe `origin/main` freshness check before required
  validation and before automatic PR creation.
- `.opencode/skills/daily-devlog-automation/SKILL.md`: remove validation failure
  as an automatic terminal blocker; failed validation enters the shared recovery
  loop.
- `.opencode/skills/weekly-agent-workflow-automation/SKILL.md`: same recovery
  loop and current-base expectation for weekly automation.
- `.opencode/skills/subagent-driven-development/SKILL.md`: reinforce that the
  finishing handoff stays in coordination mode until validation is green or a
  true human-input blocker is established.
- `docs/dev/features/opencode-agent-workflow.md`: document the all-workflows
  expectation for collaborators.

No production runtime code, product tests, OpenCode schema, or package
configuration changes are in scope.

### Data Flow

1. A workflow reaches finalization with reviewed, committed changes.
2. The agent verifies a clean tree and fetches current `origin/main`.
3. If the feature branch is behind or has not incorporated current base changes,
   the agent performs a safe merge from `origin/main` when allowed. Merge
   conflicts or resulting code/test changes go through `implementer` →
   `reviewer` → pass.
4. The agent runs required validation.
5. A red validation result creates a systematic-debugging task. Root cause may be
   in the branch, in upstream changes, in flaky timing, in the test harness, in
   environment setup, or in external services; all are investigated.
6. Repository fixes are implemented and reviewed, then committed.
7. The agent reruns from clean-tree/current-base validation until green.
8. Only after green validation does the workflow perform its default integration
   action, such as pushing and creating a PR.

### Error Handling

The instructions must avoid weakening safety gates:

- Do not bypass, skip, xfail, or reduce required validation to make a branch
  mergeable.
- Do not label a failure `BLOCKED` merely because it appears unrelated to the
  branch. “Unrelated” is diagnostic information; it does not end the workflow.
- Do not label flaky or timing-dependent failures `BLOCKED` until the agent has
  attempted to reproduce, isolate, and fix the flake or test harness problem.
- Do not perform rebases, force pushes, destructive resets, or broad cleanup as
  automatic recovery steps.
- Do not ask the human to choose whether to investigate required validation
  failures; investigation is the default. Ask only for credentials, permissions,
  unsafe git-history decisions, unavailable infrastructure, or true product/API/
  data/architecture choices.

### Testing

Because this is an instruction/workflow change, validation should focus on the
edited instruction surface:

- Review edited files for consistent wording that required validation failures
  enter `systematic-debugging`, even when apparently unrelated/flaky/
  environmental.
- Confirm daily and weekly automation no longer treat validation failure as an
  immediate `BLOCKED` condition.
- Confirm current-base handling uses `origin/main`, allows safe merge, forbids
  automatic rebase/force-push, and requires rerunning validation after base
  updates.
- Run `git diff --check`.
- Run focused text searches over edited files for `systematic-debugging`,
  `origin/main`, `BLOCKED`, `implementer`, and `reviewer`.
- A full product test suite is not required unless implementation edits runtime
  code, tests, build files, or executable scripts.

## Self-Review Notes

- No placeholders remain.
- The scope covers all current agent workflows, including daily and weekly
  automation.
- The design preserves reviewed-fix discipline and does not authorize supervisor
  edits to non-allowlisted files.
- The `origin/main` update rule avoids rebase and force-push by default.
