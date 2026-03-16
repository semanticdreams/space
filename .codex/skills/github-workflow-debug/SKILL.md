---
name: github-workflow-debug
description: Debug a GitHub Actions workflow end-to-end using a temporary branch, temporarily enable the workflow for that branch, commit/push/poll in 100-second intervals until green, review and simplify the resulting fix commits, then squash-merge the final result into main and delete the temporary branch locally and on remote.
---

# GitHub Workflow Debug Loop

Use this skill when the user wants a GitHub Actions workflow fixed autonomously in CI, not just locally.

Use the bundled helper first:
- Script: `scripts/gh-workflow-debug.sh`
- It provides deterministic branch naming, remote branch SHA checks, run lookup by workflow/branch/SHA, failed-job lookup, and 100-second polling.

This skill is for the full loop:
- create a throwaway branch automatically
- temporarily enable the target workflow on that branch
- push and poll every `100s`
- fix failures in a commit/push/poll loop until green
- review all workflow-fix commits for correctness, cleanliness, and simplification
- if worthwhile, improve and re-run the loop until green again
- land the final result on `main` as a single commit
- delete the throwaway branch locally and on remote

## Inputs to establish up front

- Workflow file or workflow name, for example `.github/workflows/test.yml`
- Base branch: default to `main`
- Temporary branch name:
  - `codex/workflow-debug/<workflow-stem>-<utc-timestamp>`

If the workflow target is ambiguous, ask once before doing any branch work.

## Safety rules

- Use non-interactive git commands only.
- Do not amend or force-push unless the user explicitly asks.
- Keep the throwaway branch isolated from `main` until the final squash.
- Do not leave the throwaway branch in workflow triggers on the final landed commit.
- Poll with `sleep 100` between checks.
- Prefer `gh run` for status/log inspection.
- Always identify workflow runs by throwaway branch and, when possible, by the pushed commit SHA. Do not assume the latest run in the repo is the right one.

## Trigger enablement

Before the first debug push, edit the target workflow so the throwaway branch will trigger it.

Preferred approach:
- If the workflow already has `on.push.branches`, add the throwaway branch to that list.
- If the workflow only has tag-based `push` triggers, add a temporary branch entry for the throwaway branch while preserving the existing tag trigger.
- If the workflow already has `workflow_dispatch`, keep it; do not rely on it for the main loop unless push triggering is impossible.

Common shapes in this repo:
- `push.branches` only:
  - add the throwaway branch under `on.push.branches`
- `workflow_dispatch` plus `push.tags`:
  - keep `workflow_dispatch`
  - preserve `push.tags`
  - add `push.branches` with the throwaway branch instead of replacing `tags`
- `push.branches: [main]`:
  - expand it to a multi-line list and add the throwaway branch alongside `main`

The throwaway-branch trigger change is temporary and must not survive the final squash onto `main`.

## Main loop

1. Create and switch to the throwaway branch from `main`.
   - Prefer: `scripts/gh-workflow-debug.sh branch-name <workflow>`
2. Add the temporary workflow trigger change.
3. Commit and push.
   - Verify the remote branch SHA if needed:
     - `scripts/gh-workflow-debug.sh remote-branch-sha <throwaway-branch>`
4. Poll the workflow with `gh run` every `100s` until it completes.
   - Prefer: `scripts/gh-workflow-debug.sh wait-run --workflow <workflow> --branch <throwaway-branch> --sha <pushed-sha>`
   - Prefer filtering by the throwaway branch.
   - Confirm the run corresponds to the pushed commit before acting on it.
   - If no run appears after a reasonable wait, treat that as a workflow-trigger failure:
     - verify the workflow trigger edit
     - verify the push reached the remote branch
     - fix the trigger/setup issue
     - commit, push, and restart polling
5. If it fails:
   - inspect the failing job log
   - prefer selecting the first failed job deterministically:
     - `scripts/gh-workflow-debug.sh first-failed-job-id --run-id <run-id>`
   - identify the first real blocker
   - implement the cleanest fix
   - commit
   - push
   - go back to step 4
6. If it passes:
   - review the full sequence of fix commits for correctness, design quality, unnecessary complexity, and cleanup opportunities
   - implement worthwhile simplifications or fixes
   - commit and push those changes
   - re-enter the same poll loop until green again

## Review standard before finalizing

After the first green run, review the throwaway branch as if preparing a final PR:

- remove brittle or overly specific workarounds if a cleaner general fix is available
- collapse repeated patterns into the right shared layer
- prefer environment/setup fixes over per-port/per-call hacks when the problem is systemic
- verify every retained commit contributed to the final design
- remove dead attempts and partial work from the final landed result

If improvements are worthwhile, make them on the throwaway branch and repeat the commit/push/poll loop until green.

## Polling commands

Typical commands:

```bash
scripts/gh-workflow-debug.sh branch-name .github/workflows/test.yml
scripts/gh-workflow-debug.sh remote-branch-sha <branch>
scripts/gh-workflow-debug.sh latest-run-id --workflow test.yml --branch <branch> --sha <sha>
scripts/gh-workflow-debug.sh first-failed-job-id --run-id <run-id>
scripts/gh-workflow-debug.sh wait-run --workflow test.yml --branch <branch> --sha <sha> --json
gh run list --workflow <workflow-file> --limit 5
gh run view <run-id> --json jobs
gh run view <run-id> --job <job-id> --log
sleep 100
```

Bias toward:
- checking the latest run for the throwaway branch
- matching the run to the pushed commit SHA when multiple runs are plausible
- focusing on the first failed job
- reading the narrowest useful log before changing code

## Commit discipline on the throwaway branch

- Make small, single-purpose commits during debugging.
- Use clear `ci` or `fix(ci)` style subjects.
- If commit wording matters, also use the local `git-commit` skill.
- During the review/simplification phase, keep committing normally on the throwaway branch; do not try to curate history there.

The throwaway branch is allowed to have many debugging commits. `main` is not.

## Final landing on main

Once the throwaway branch is green and the result is satisfactory:

1. Check out `main`.
2. Fast-forward `main` to the latest remote `main`.
3. Squash-merge the throwaway branch into `main`.
4. Before committing the squash:
   - remove the temporary throwaway-branch trigger from the workflow file
   - keep all real workflow/build/test fixes
   - verify the final staged diff is exactly what should land on `main`
5. Create one final commit on `main`.
6. Push `main`.
7. Poll the `main` workflow run in the same `100s` cadence until it is green.

Do not merge the throwaway branch directly. The final landed history must be a single commit.

## Cleanup

After `main` is pushed successfully:

- delete the throwaway branch locally
- delete the throwaway branch on remote

Typical commands:

```bash
git branch -D <throwaway-branch>
git push origin --delete <throwaway-branch>
```

## Final verification

After pushing `main`:

- confirm the throwaway branch no longer exists locally or remotely
- confirm the workflow file on `main` no longer includes the throwaway branch in its triggers
- confirm the final single commit on `main` contains all intended fixes
- confirm the `main` workflow run for the landed commit is green
