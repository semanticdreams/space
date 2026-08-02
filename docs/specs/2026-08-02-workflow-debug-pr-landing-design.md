# Workflow Debug PR Landing Design

## Context

The `github-workflow-debug` OpenCode skill currently completes CI workflow debugging by checking out local `main`, squash-merging the temporary debug branch there, creating a local `main` commit, and telling the user to push `main`. That conflicts with this repository's branch convention: `origin/main` is the source of truth, local `main` may be stale or unrelated, and branch protection blocks direct pushes to `main`.

## Baseline validation scenario

Pressure scenario: after a debug branch CI run is green and reviewer verification passes, an agent follows the current `github-workflow-debug` final landing section under time pressure.

Current failing behavior is explicit in the skill text: it says to check out `main`, fast-forward local `main`, squash-merge into `main`, create a final local commit on `main`, report “Ready to push,” and run `git push origin main`. The skill therefore teaches the exact branch-protection-incompatible action this repository forbids.

## Desired behavior

Workflow-debug landing must produce a pull request branch, not a local `main` commit. After the temporary debug branch is green and branch-level reviewer verification passes, the skill should instruct agents to:

1. Fetch `origin/main` and create or switch to a dedicated final PR branch from `origin/main` without requiring local `main` checkout.
2. Squash-merge the temporary debug branch into that PR branch.
3. Remove the temporary debug workflow trigger before committing, preserving real workflow/build/test fixes.
4. Generate and review the staged diff; no review artifacts may be staged or tracked.
5. Create exactly one final squash commit on the PR branch only after staged reviewer verification passes.
6. Push the PR branch and create a GitHub PR with `gh pr create --base main --head <final-pr-branch> --fill`.
7. Return the PR URL and any optional debug-branch cleanup command.

The skill must explicitly say direct `main` push is branch-protection incompatible for this repo.

## Scope

Update the project OpenCode workflow-debug skill and any closely related project OpenCode validation/permission checks needed for this new landing path. Do not change application code, workflows, or unrelated automation skills.

## Safety and validation requirements

- Preserve the requirement that debug branch CI is green before landing.
- Preserve branch reviewer verification before final landing.
- Preserve staged review after removing the temporary trigger and before final commit.
- Preserve the requirement that final workflow files do not contain the temporary debug branch trigger.
- Preserve the requirement that `.superpowers/sdd/ci-*` review artifacts are not staged or tracked.
- Add or update policy validation so future regressions that reintroduce `checkout main`, local `main` commit, “ready to push main,” or `git push origin main` in the workflow-debug final landing path fail fast.
- Route `.opencode/**` and validation script changes through implementer → reviewer.

## Chosen approach

Use a documentation-policy update with a small Node policy test. This is the smallest reliable change: it fixes the operational instructions agents actually follow and pins the branch-protection contract in the existing OpenCode automation validation script.

Alternative approaches considered:

- Update only prose: faster, but no guard against future regressions.
- Add a new helper script for final PR branch creation: unnecessary because existing git/gh commands are sufficient and the issue is process guidance, not missing tooling.
