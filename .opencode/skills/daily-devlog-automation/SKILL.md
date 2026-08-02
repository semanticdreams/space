---
name: daily-devlog-automation
description: Use when a scheduled Orca/OpenCode run or user prompt asks to run daily devlog automation, create a daily devlog entry, inspect recent repo changes for a devlog, or publish a devlog automation branch
---

# Daily Devlog Automation

## Overview

This skill turns a scheduled Orca/OpenCode run into a reviewed, brief devlog PR. The durable workflow lives in the repo; the Orca UI prompt is only a trigger.

## Preconditions

1. Verify a clean dedicated checkout with `git status --porcelain`; stop if dirty.
2. Verify the checkout is on a branch that can safely create `automation/daily-devlog/YYYY-MM-DD` from `origin/main`.
3. Verify `gh auth status` before relying on PR creation or auto-merge.
4. Verify branch protection rules and required status checks are active on the target repository before attempting auto-merge; do not assume they are available just because `gh auth status` succeeds. Protection may come from classic branch protection (HTTP 200 on `gh api repos/<owner>/<repo>/branches/main/protection`) or GitHub rulesets (classic endpoint returns HTTP 404). When the classic endpoint returns 404, verify effective branch rules via `gh api repos/<owner>/<repo>/rules/branches/main`. Required status checks (for this repo: `test`), pull-request protection, and merge queue requirement must be present in the effective rules before auto-merge. If merge queue is not enabled or cannot be verified, report `HUMAN_DECISION_REQUIRED` — the automation relies on merge queue for post-PR freshness. If neither classic protection nor active effective branch rules can be confirmed, fail closed.

## Workflow

1. Fetch `origin/main`.
2. Create or switch to `automation/daily-devlog/YYYY-MM-DD` from `origin/main`.
3. Inspect the latest relevant journal entry or recent day boundary, docs notes, plans/specs, and `origin/main` mainline/first-parent history to identify work that landed since that boundary.
4. Apply the meaningful-change filter.
5. If no entry is warranted, stop without edits, commits, pushes, or PRs.
6. If an entry is warranted, dispatch `implementer` to write/update the journal entry and regenerate indexes.
7. Dispatch `reviewer` before commit and before push.
8. Fetch `origin` and confirm the automation branch has accounted for current `origin/main`. If the branch is behind, safe-merge `origin/main` when permitted, route conflicts or regenerated docs changes through `implementer` → `reviewer` → pass, and rerun validation from a clean tree. Do not rebase or force-push unless the human explicitly requests it.
9. Run validation.
10. Commit only reviewed devlog automation files.
11. Re-fetch `origin` and recheck current `origin/main` before push or PR creation. If the branch is behind, safe-merge `origin/main` when permitted, route conflicts and fixes through `implementer` → `reviewer` → pass, and restart validation from a clean tree. Do not rebase or force-push unless the human explicitly requests it.
12. Push only the dated automation branch.
13. Open a PR, enable auto-merge (or queue the PR) when branch protection
    allows it. After the PR enters merge queue, poll with
    `gh pr view --json state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url`
    until `mergedAt` is present (PR merged). Inspect merge_group runs with
    `gh run list --workflow test.yml --event merge_group --limit 10 --json databaseId,headBranch,headSha,status,conclusion,event,url,displayTitle,createdAt`
    and `gh run watch <run-id> --exit-status --interval 100` when queue checks
    are failing. Do not update
    the PR branch solely because origin/main advanced after PR creation —
    merge queue handles post-PR freshness. Resume only for actionable
    queue blockers: merge queue conflicts, merge-group `test` failures,
    missing merge queue protection, or permission blockers. For queue
    failures, invoke `systematic-debugging`, route any repository fix
    through `implementer` → `reviewer` → pass, commit reviewed fixes,
    revalidate, and requeue. Do not rebase or force-push unless the human
    explicitly requests it.

## Landing-Date Attribution

Treat `origin/main` as the source of truth for recent work. Attribute work to the daily entry for the date it lands or merges into `origin/main`, regardless of the original author date or feature-branch commit date. Older feature-branch commits merged today are eligible for today's entry; author or original commit dates must not cause landed work to be skipped or backdated into an already-published journal entry.

Use mainline/first-parent history, merge commits, PR merges, or equivalent landed ranges on `origin/main` to decide what changed since the latest relevant journal entry or recent day boundary. Do not guess from local branch history when the `origin/main` landing evidence is unavailable.

## Meaningful Change Filter

Create an entry only for meaningful user-facing, architectural, workflow, tooling, or milestone-relevant progress. Skip routine churn, pure fix-loop commits, formatting-only changes, dependency noise, and changes already covered by a prior entry unless they complete or clarify a broader story.

## Journal Entry Contract

Use exactly this entry shape:

```md
---
type: journal
tags: [journal, devlog]
created: YYYY-MM-DD
---

# YYYY-MM-DD

One short narrative paragraph.
```

The paragraph connects concrete work to current project goals, milestones, or recent momentum. Inline Markdown links are allowed when they point to relevant docs, notes, plans, specs, or feature pages and improve reader context. Before writing or committing, perform a compression/style pass that makes the final paragraph denser than the full report while preserving the main landed changes, why they matter, and useful inline references. Forbid section headings, bullet lists, separate link lists, commit hashes, author lists, raw file lists, and commit-summary prose.

## Validation

Before running the docs build, ensure locked docs dependencies are installed:

```bash
cd docs
if [ ! -d node_modules ] || [ ! -x node_modules/.bin/vitepress ]; then npm ci; fi
```

Then run the full validation:

```bash
cd docs && npm run devlog:indices && npm run docs:build
```

Inspect the final diff and require only expected journal/devlog/docs automation files.

## Validation Failure Recovery

If required validation fails, do not commit, push, create a PR, enable
auto-merge, or report the automation branch as ready. Capture the failing
command, failing tests or docs build phase, relevant output, current branch
state, and `git status --porcelain`. Invoke `systematic-debugging` and continue
investigating even when the failure appears unrelated, flaky,
timing-dependent, or environmental.

Any repository fix, generated-doc repair, or conflict resolution must go
through `implementer` → `reviewer` → pass before commit. After reviewed fixes
are committed and the tree is clean, re-fetch `origin`, recheck current
`origin/main`, rerun validation, and continue only when validation is green.
Report BLOCKED or HUMAN_DECISION_REQUIRED only when systematic debugging
establishes that progress requires credentials, inaccessible infrastructure,
unsafe git history decisions, unreproducible behavior after reasonable evidence
gathering, or a product/API/data/architecture choice.

## Commit, Push, and PR

Commit after review. Push using `git push origin HEAD:refs/heads/automation/daily-devlog/YYYY-MM-DD`. Use `gh pr create --base main --head automation/daily-devlog/YYYY-MM-DD --fill` when authenticated. Verify branch protection, required status checks, pull-request protection, and merge queue requirement are active before attempting auto-merge (classic protection or rulesets). Inspect the effective branch rules for allowed merge methods, then use the corresponding flag: `gh pr merge --auto --merge automation/daily-devlog/YYYY-MM-DD` when rules allow merge commits (current for this repo) or `gh pr merge --auto --squash ...` when rules require squash. If repository rules require a rebase-only merge method, do not enable auto-merge automatically. Report HUMAN_DECISION_REQUIRED because the agent must not rebase unless the human explicitly requests it. Do not enable auto-merge merely because `gh` is authenticated. Never push directly to `origin/main`. After auto-merge is enabled, poll with `gh pr view --json state,mergedAt,...` until `mergedAt` is present — later `origin/main` movement is handled by merge queue. Resume only for actionable queue blockers: merge queue conflicts, merge-group `test` failures, missing merge queue protection, or permission blockers. Invoke `systematic-debugging` for any queue failure and route repository fixes through `implementer` → `reviewer` → pass before requeuing.

## Fail-Closed Cases

Stop with a clear BLOCKED or HUMAN_DECISION_REQUIRED summary when the checkout
is dirty, credentials are missing, `gh` is unavailable,
`origin/main` cannot be fetched or inspected, mainline/merge evidence is
ambiguous, branch protection, required status checks, or merge queue
requirement are unavailable or cannot be verified (via classic protection
or rulesets/effective branch rules), auto-merge cannot proceed safely,
merge queue handoff fails with an unresolved blocker, the diff includes
unexpected files, or validation remains red after systematic debugging
establishes a true human-input blocker.

## Red Flags

- "I'll just push main because this is docs-only."
- "The entry can be a commit summary this time."
- "A quiet day still needs an entry."
- "The reviewer is unnecessary for one paragraph."
- "The UI prompt already says enough."
