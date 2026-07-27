---
name: finishing-a-development-branch
description: Use when implementation is complete, all tests pass, and you need to decide how to integrate the work
---

# Finishing a Development Branch

## Overview

**Core principle:** Verify clean tree → Verify tests → Detect environment → Present options → Execute choice → Clean up.

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

Never auto-stage or auto-discard. Only allowlisted coordination-artifact files may be committed or discarded here; code changes always go through implementer → reviewer.

## Step 1: Verify Tests

Run the project's full test suite. Consult AGENTS.md for the correct test command.

**If tests fail**, report the failures and stop — the menu comes after a green suite.

**If tests pass:** continue to Step 2.

## Step 2: Detect Environment

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
WORKTREE_PATH=$(git rev-parse --show-toplevel)
```

This determines which menu to show and how cleanup works:

| State | Menu | Cleanup |
|-------|------|---------|
| `GIT_DIR == GIT_COMMON` (normal repo) | Standard 3 options | No worktree to clean up |
| `GIT_DIR != GIT_COMMON`, named branch | Standard 3 options | Provenance-based (see Step 6) |
| `GIT_DIR != GIT_COMMON`, detached HEAD | Reduced 2 options (no merge) | Externally managed — leave in place |

## Step 3: Determine Base Branch

The base branch is whatever this work forked from — usually named in the plan, the conversation, or the branch's upstream. If it is not already known, ask. Confirm before merging: merging into the wrong base is expensive to undo.

## Step 4: Present Options

**Normal repo and named-branch worktree — present exactly these 3 options:**

```
Implementation complete. What would you like to do?

1. Merge back to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is (I'll handle it later)

Which option?
```

Present the menu exactly as written. The integration decision is the human's.

## Step 5: Execute Choice

### Option 1: Merge Locally

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
git checkout <base-branch>
git pull
git merge <feature-branch>
```

If tests fail on the merged result: stop, leave everything in place, and investigate — nothing has been pushed, so the merge is local and recoverable.

Once green: clean up the worktree (Step 6), then delete the branch:

```bash
git branch -d <feature-branch>
```

### Option 2: Push and Create PR

Push the branch and create the pull request using the forge's tooling. Keep the worktree — the human iterates on PR feedback there.

### Option 3: Keep As-Is

Report: "Keeping branch <name>. Worktree preserved at <path>."

## Step 6: Cleanup Workspace

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
| "They obviously want it merged" | Integration is your human partner's decision. Present the menu and wait. |
| "The base branch is obviously main" | Confirm the fork point or ask. Merging into the wrong base is expensive to undo. |
| "The push was rejected — force-push will fix it" | A rejected push means the remote moved. Investigate; force-push only on your human partner's explicit request. |
