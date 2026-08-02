---
name: finishing-a-development-branch
description: Use when implementation is complete and reviewed, to run final validation, recover from validation failures, and integrate only when green
---

# Finishing a Development Branch

## Overview

**Core principle:** Verify clean tree → Verify current `origin/main` base → Verify required validation → If validation fails, debug root cause and route reviewed fixes → Rerun validation from a clean/current-base tree until green or a true human-input blocker is established → Recheck `origin/main` before integration → Consult project policy → Detect environment → Execute action (or present options if no policy) → Clean up.

**Announce at start:** "I'm using the finishing-a-development-branch skill to complete this work."

## Step 0: Verify Clean Working Tree

```bash
git status --porcelain
```

**If output is empty:** Continue to Step 1.

**If output is non-empty:** The working tree is not clean. Report the files and **stop here**. Do not proceed to testing, the menu, or any integration action. Tell the user:

> The working tree is not clean. Found uncommitted changes:
>
> [list files from git status output]
>
> These must be resolved before finishing the branch. Would you like me to help commit them, or would you prefer to handle them yourself?

If they want help committing:
- Committable directly: `docs/specs/**`, `docs/plans/**`, and `.superpowers/sdd/**/progress.md`. Commit these and re-run the porcelain check from the top.
- Any other dirty file: stop and tell the user these must go through `implementer` → `reviewer` → pass first. The branch cannot be finished with uncommitted code changes that haven't been reviewed.

If they want to handle it themselves: stop and exit the skill. The branch is not finished.

Never auto-stage or auto-discard. Only allowlisted coordination-artifact files may be committed or discarded here; code changes always go through `implementer` → `reviewer` → pass.

## Step 1: Verify Current Base and Tests

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

Run the project's full test suite. Consult AGENTS.md for the correct test command.

**If tests fail**, integration is forbidden but the branch is not finished.
Do all of the following:

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

Report `BLOCKED` or `HUMAN_DECISION_REQUIRED` only when systematic debugging
establishes that progress requires human input: credentials, inaccessible
infrastructure, unsafe git history decisions, unreproducible behavior after
reasonable evidence gathering, or a product/API/data/architecture choice.
Do not push, PR, merge, or clean up while required validation is red.

**If tests pass:** continue to Step 2.

## Step 2: Consult Project Policy

Check `AGENTS.md` (or the project's equivalent integration-policy file) for default
integration instructions. This step determines whether the integration action is
automatic or requires presenting a menu.

**If the project policy specifies a default integration action** (e.g., "push the
current branch and create a pull request targeting `main`"):

  1. Confirm the user has not explicitly requested a different integration action.
  2. Confirm the branch is safe for automatic integration (clean tree, tests
     passing — already confirmed in Steps 0–1).

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

  3. If both checks pass: execute the default action automatically:
     - Push the current branch.
     - Create a pull request targeting the base branch.
     - Enable auto-merge (or queue the PR) when branch protection allows it.
     - Stop after successful merge-queue handoff. Keep the worktree for PR
       feedback and iteration — do not clean up. Skip the integration menu
       and end the skill.

     Do not continue polling the base branch or updating the PR branch
     solely because `origin/main` advanced after PR creation. Merge queue
     handles post-PR freshness. Resume only for actionable queue blockers:
     merge queue conflicts, required-check failures (including merge-group
     `test` failures), missing merge queue protection, or permission
     blockers. Each fix follows: invoke `systematic-debugging`, route any
     repository fix through `implementer` → `reviewer` → pass, commit
     reviewed fixes, current-base validation, and requeue. Do not rebase or
     force-push unless the human explicitly requests it.
  4. If the user explicitly requested a different integration action: execute
     that action instead.
  5. If the branch cannot be integrated safely (e.g., unresolved merge conflicts
     with the base branch): report the unsafe condition and fall through to the
     integration menu so the user can decide.

**If no project integration policy is found:** Continue to Step 3. The standard
integration menu will be presented.

## Step 3: Detect Environment

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
WORKTREE_PATH=$(git rev-parse --show-toplevel)
```

This determines which menu to show and how cleanup works:

| State | Menu | Cleanup |
|-------|------|---------|
| `GIT_DIR == GIT_COMMON` (normal repo) | Standard 3 options | No worktree to clean up |
| `GIT_DIR != GIT_COMMON`, named branch | Standard 3 options | Provenance-based (see Step 7) |
| `GIT_DIR != GIT_COMMON`, detached HEAD | Reduced 2 options (no merge) | Externally managed — leave in place |

## Step 4: Determine Base Branch

The base branch is whatever this work forked from — usually named in the plan, the conversation, or the branch's upstream. If it is not already known, ask. Confirm before merging: merging into the wrong base is expensive to undo.

## Step 5: Present Options

**Only reached when no project integration policy applies** (see Step 2).

**Normal repo and named-branch worktree — present exactly these 3 options:**

```
Implementation complete. What would you like to do?

1. Merge back to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is (I'll handle it later)

Which option?
```

Present the menu exactly as written. The integration decision is the human's when
no project policy specifies an automatic action.

## Step 6: Execute Choice

### Option 1: Merge Locally

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
git checkout <base-branch>
git pull
git merge <feature-branch>
```

If tests fail on the merged result: follow the Step 1 validation-failure loop — invoke `systematic-debugging`, route any fix through `implementer` → `reviewer` → pass, do not push/PR/merge/clean up while red, and rerun from Step 0 after reviewed fixes. Nothing has been pushed, so the merge is local and recoverable.

Once green: clean up the worktree (Step 7), then delete the branch:

```bash
git branch -d <feature-branch>
```

### Option 2: Push and Create PR

Before pushing or creating a PR, re-fetch and recheck the base:

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

Push the branch and create the pull request using the forge's tooling. Keep the worktree — the human iterates on PR feedback there.

### Option 3: Keep As-Is

Report: "Keeping branch <name>. Worktree preserved at <path>."

## Step 7: Cleanup Workspace

**If `GIT_DIR == GIT_COMMON`:** Normal repo, no worktree to clean up. Done.

**If `WORKTREE_PATH` is under `.worktrees/` or `worktrees/`:**

```bash
git worktree remove "$WORKTREE_PATH"
git worktree prune
```

**Otherwise:** The host environment owns this workspace — leave it in place.

## Quick Reference

| Option | Merge | Push | Keep Worktree | Cleanup Branch |
|--------|-------|------|---------------|----------------|
| 1. Merge locally | yes | — | — | yes |
| 2. Create PR | — | yes | yes | — |
| 3. Keep as-is | — | — | yes | — |

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Tests passed earlier this session" | Run the suite on the tree you are about to integrate. A green run only proves the tree it ran on. |
| "They obviously want it merged" | Follow the project's integration policy, not assumptions. If AGENTS.md specifies an automatic action (push + create PR), execute it. Only present the menu when no policy exists or branch-unsafe conditions block the automatic action. |
| "The base branch is obviously main" | Confirm the fork point or ask. Merging into the wrong base is expensive to undo. |
| "The final suite failed, so I'll just report it and stop" | A red final suite is a debugging task. Invoke `systematic-debugging`, route reviewed fixes through `implementer` → `reviewer` → pass, rerun validation, and finish only when green or explicitly blocked. |
| "The failure is unrelated/flaky/environmental — nothing to do" | "Unrelated," "flaky," and "environmental" are diagnostic labels, not terminal states. Investigate, gather evidence, and route fixes through `implementer` → `reviewer` → pass. Stop only when systematic debugging establishes a true human-input blocker. |
| "The branch is behind origin/main — I'll just push anyway" | Do not push, PR, merge, or claim ready-to-merge against a stale base. Safe-merge `origin/main` when permitted, route conflicts through `implementer` → `reviewer` → pass, commit reviewed fixes, and rerun validation from Step 0. |
| "The push was rejected — force-push will fix it" | A rejected push means the remote moved. Do not force-push. Fetch, update by safe merge from `origin/main` when permitted, resolve conflicts through `implementer` → `reviewer` → pass, and restart from Step 0. Do not rebase or force-push unless the human explicitly requests it. |
