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
4. Verify branch protection rules and required status checks are active on the target repository before attempting auto-merge; do not assume they are available just because `gh auth status` succeeds. Protection may come from classic branch protection (HTTP 200 on `gh api repos/<owner>/<repo>/branches/main/protection`) or GitHub rulesets (classic endpoint returns HTTP 404). When the classic endpoint returns 404, verify effective branch rules via `gh api repos/<owner>/<repo>/rules/branches/main`. Required status checks (for this repo: `test`) and pull-request protection must be present in the effective rules before auto-merge. If neither classic protection nor active effective branch rules can be confirmed, fail closed.

## Workflow

1. Fetch `origin/main`.
2. Create or switch to `automation/daily-devlog/YYYY-MM-DD` from `origin/main`.
3. Inspect the latest relevant journal entry or recent day boundary, docs notes, plans/specs, and `origin/main` mainline/first-parent history to identify work that landed since that boundary.
4. Apply the meaningful-change filter.
5. If no entry is warranted, stop without edits, commits, pushes, or PRs.
6. If an entry is warranted, dispatch `implementer` to write/update the journal entry and regenerate indexes.
7. Dispatch `reviewer` before commit and before push.
8. Run validation.
9. Commit only reviewed devlog automation files.
10. Push only the dated automation branch.
11. Open a PR and attempt auto-merge when allowed.

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

The paragraph connects concrete work to current project goals, milestones, or recent momentum. Before writing or committing, perform a compression/style pass. Forbid section headings, bullet lists, commit hashes, author lists, raw file lists, and commit-summary prose.

## Validation

Run `cd docs && npm run devlog:indices && npm run docs:build`. Inspect the final diff and require only expected journal/devlog/docs automation files.

## Commit, Push, and PR

Commit after review. Push using `git push origin HEAD:refs/heads/automation/daily-devlog/YYYY-MM-DD`. Use `gh pr create --base main --head automation/daily-devlog/YYYY-MM-DD --fill` when authenticated. Verify branch protection, required status checks, and pull-request protection are active before attempting auto-merge (classic protection or rulesets). Inspect the effective branch rules for allowed merge methods, then use the corresponding flag: `gh pr merge --auto --merge automation/daily-devlog/YYYY-MM-DD` when rules allow merge commits (current for this repo), `gh pr merge --auto --squash ...` when rules require squash, or `gh pr merge --auto --rebase ...` when rules require rebase. Do not enable auto-merge merely because `gh` is authenticated. Never push directly to `origin/main`.

## Fail-Closed Cases

Stop with a clear BLOCKED summary when the checkout is dirty, credentials are missing, `gh` is unavailable, validation fails, `origin/main` cannot be fetched or inspected, mainline/merge evidence is ambiguous, branch protection or required status checks are unavailable or cannot be verified (via classic protection or rulesets/effective branch rules), auto-merge cannot proceed, or the diff includes unexpected files.

## Red Flags

- "I'll just push main because this is docs-only."
- "The entry can be a commit summary this time."
- "A quiet day still needs an entry."
- "The reviewer is unnecessary for one paragraph."
- "The UI prompt already says enough."
