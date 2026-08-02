# Workflow Debug PR Landing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the workflow-debug process so CI debug fixes land through a dedicated PR branch instead of a local `main` commit or direct `main` push.

**Architecture:** Pin the policy with Node validation in the existing OpenCode automation config test, then update the project `github-workflow-debug` skill and supervisor permissions to describe and permit the PR-branch landing path. The final landing branch is created from `origin/main`, receives a squash-merge from the temporary debug branch, removes the temporary trigger before commit, passes staged review, pushes, and creates a PR.

**Tech Stack:** Markdown OpenCode skills/agent config, Node `node:test` policy checks, git, GitHub CLI (`gh`).

## Global Constraints

- Work in the current worktree and do not use the separate main checkout for this change.
- `.opencode/**`, validation script, and other non-allowlisted edits must be made by `implementer` and pass `reviewer` before final commit.
- Preserve debug-branch CI green requirement before workflow-debug landing.
- Preserve reviewer verification before final landing.
- Preserve staged review after removing the temporary workflow trigger and before final commit.
- Preserve “no review artifacts staged/tracked” and “final workflow file has no temporary debug branch trigger.”
- Final landing instructions must create/push a PR branch and create a PR; they must not require local `main` checkout or direct `main` push.
- Direct `main` push must be called branch-protection incompatible for this repo.

---

## File Structure

- Modify: `docs/scripts/test-opencode-automation-config.mjs`
  - Adds policy checks for `github-workflow-debug` and supervisor permissions.
- Modify: `.opencode/skills/github-workflow-debug/SKILL.md`
  - Replaces local-main landing with PR-branch landing.
- Modify: `.opencode/agents/supervisor.md`
  - Allows workflow-debug final PR branch push and PR creation while keeping direct `git push origin main` ask-gated.

## Task 1: Add Failing Policy Tests

**Files:**
- Modify: `docs/scripts/test-opencode-automation-config.mjs`

**Interfaces:**
- Consumes: current repo files.
- Produces: policy tests that fail against the current workflow-debug skill and pass after Task 2.

- [ ] **Step 1: Extend test fixture loading**

Add a new cached variable near the existing `skillContent`, `supervisorContent`, and `notesContent` declarations:

```js
let workflowDebugContent = ''
```

Inside `loadFiles()`, after loading the daily devlog skill, read the workflow-debug skill:

```js
    workflowDebugContent = await readFile(join(repoRoot, '.opencode', 'skills', 'github-workflow-debug', 'SKILL.md'), 'utf8')
```

- [ ] **Step 2: Add policy tests**

Append these tests to `docs/scripts/test-opencode-automation-config.mjs`:

```js
test('github workflow debug lands through a PR branch instead of local main', async () => {
    await loadFiles()

    const oneLineSkill = workflowDebugContent.replace(/\s+/g, ' ')

    assert.match(oneLineSkill, /final PR branch/i,
        'workflow-debug skill should name a final PR branch')
    assert.match(oneLineSkill, /origin\/main/i,
        'workflow-debug final PR branch should be created from origin/main')
    assert.match(oneLineSkill, /squash-merge/i,
        'workflow-debug skill should keep squash-merge landing semantics')
    assert.match(oneLineSkill, /remove.{0,160}temporary.{0,80}trigger/i,
        'workflow-debug skill should remove the temporary workflow trigger before final commit')
    assert.match(oneLineSkill, /staged review/i,
        'workflow-debug skill should require staged review')
    assert.match(oneLineSkill, /gh pr create --base main --head <final-pr-branch> --fill/i,
        'workflow-debug skill should create a PR with gh pr create')
    assert.match(oneLineSkill, /PR URL/i,
        'workflow-debug skill should return the PR URL')
    assert.match(oneLineSkill, /branch-protection incompatible/i,
        'workflow-debug skill should say direct main push is branch-protection incompatible')

    assert.doesNotMatch(workflowDebugContent, /## Final landing on main/,
        'workflow-debug skill must not title the landing path as local main')
    assert.doesNotMatch(oneLineSkill, /Check out `main`|Fast-forward `main`|Final commit on main|Ready to push/i,
        'workflow-debug skill must not require local main checkout or ready-to-push-main output')
    assert.doesNotMatch(workflowDebugContent, /git push origin main/,
        'workflow-debug skill must not tell agents to push main directly')
})

test('supervisor permissions allow workflow-debug final PR branch integration only', async () => {
    await loadFiles()

    assert.ok(supervisorContent.includes('"git push origin HEAD:refs/heads/opencode/workflow-debug-pr/*": allow'),
        'supervisor should allow pushing workflow-debug final PR branches')
    assert.ok(supervisorContent.includes('"gh pr create --base main --head opencode/workflow-debug-pr/* --fill": allow'),
        'supervisor should allow creating workflow-debug final PRs')
    assert.ok(supervisorContent.includes('"git push origin main": ask'),
        'direct main push must remain ask-gated, not allowed')
    assert.ok(!supervisorContent.includes('"git push origin main": allow'),
        'direct main push must not be allowed')
})
```

- [ ] **Step 3: Run the targeted validation and confirm RED**

Run:

```bash
node --test docs/scripts/test-opencode-automation-config.mjs
```

Expected before Task 2: FAIL in the new workflow-debug policy test because the current skill still says “Final landing on main,” local `main` commit, and `git push origin main`. If the new test passes before Task 2, tighten it so it catches the current bad instructions.

## Task 2: Update Skill and Supervisor Policy

**Files:**
- Modify: `.opencode/skills/github-workflow-debug/SKILL.md`
- Modify: `.opencode/agents/supervisor.md`
- Modify if Task 1 needs small wording alignment only: `docs/scripts/test-opencode-automation-config.mjs`

**Interfaces:**
- Consumes: failing Task 1 tests.
- Produces: updated workflow-debug landing instructions and permissions that pass the policy test.

- [ ] **Step 1: Update workflow-debug description and overview**

In `.opencode/skills/github-workflow-debug/SKILL.md`, replace references to “land the final result on `main` as a single local commit (ready to push)” with PR-branch wording. The overview must say the final result lands on a dedicated PR branch created from `origin/main`, is pushed, and returns a PR URL.

- [ ] **Step 2: Update completion contract**

Change the done state from “final local squash commit exists on `main` ready to push” to “final PR branch has one reviewed squash commit, is pushed, and a GitHub PR URL has been returned.” Keep pending workflow polling mandatory until debug-branch CI is green.

- [ ] **Step 3: Replace final landing section**

Rename `## Final landing on main` to `## Final landing through a PR branch` and rewrite it to require this sequence:

1. Fetch `origin/main`.
2. Create or switch to `opencode/workflow-debug-pr/<workflow-stem>-<utc-timestamp>` from `origin/main`; do not require checking out local `main`.
3. Squash-merge the throwaway debug branch into the final PR branch.
4. Dispatch `implementer` to remove the temporary throwaway-branch workflow trigger while preserving real fixes and staging the result.
5. Generate `.superpowers/sdd/ci-staged.diff` from the staged diff and dispatch `reviewer` in CI STAGED REVIEW mode.
6. On staged-review pass, create exactly one final squash commit on the PR branch.
7. Verify no `.superpowers/sdd/ci-*` artifacts are staged/tracked and the final workflow file no longer includes the temporary debug branch trigger.
8. Push with `git push origin HEAD:refs/heads/<final-pr-branch>`.
9. Create the PR with `gh pr create --base main --head <final-pr-branch> --fill`.
10. Return the PR URL plus optional cleanup command for the remote debug branch.

Include an explicit sentence: direct pushes to `main` are branch-protection incompatible for this repo.

- [ ] **Step 4: Update cleanup/final verification wording**

Change cleanup and final verification from “after the final commit is created on `main`” / “workflow file on `main`” to “after the final PR branch commit and PR are created.” Preserve local debug branch deletion and artifact checks.

- [ ] **Step 5: Update supervisor permissions**

In `.opencode/agents/supervisor.md`, add allow rules after the existing workflow-debug push/PR-related rules:

```yaml
    "git push origin HEAD:refs/heads/opencode/workflow-debug-pr/*": allow
    "gh pr create --base main --head opencode/workflow-debug-pr/* --fill": allow
```

Do not change the existing `"git push origin main": ask` rule to `allow`.

- [ ] **Step 6: Run validation and confirm GREEN**

Run:

```bash
node --test docs/scripts/test-opencode-automation-config.mjs
```

Expected: PASS.

Also run this content check:

```bash
rg -n "Final landing on main|Ready to push|Final commit on main|git push origin main|Check out `main`|Fast-forward `main`" .opencode/skills/github-workflow-debug/SKILL.md
```

Expected: no matches.

## Reviewer Instructions

Review the final diff against `docs/specs/2026-08-02-workflow-debug-pr-landing-design.md`. Confirm the skill no longer requires checking out or committing on local `main`, direct main push is described as branch-protection incompatible, the PR-branch sequence is complete, debug-branch CI/reviewer/staged-review requirements remain intact, no review artifacts are staged or tracked, and validation passes.
