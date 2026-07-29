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

## Workflow

1. Fetch `origin/main`.
2. Create or switch to `automation/daily-devlog/YYYY-MM-DD` from `origin/main`.
3. Inspect recent journal entries, docs notes, plans/specs, and commits since the latest journal entry or recent day boundary.
4. Apply the meaningful-change filter.
5. If no entry is warranted, stop without edits, commits, pushes, or PRs.
6. If an entry is warranted, dispatch `implementer` to write/update the journal entry and regenerate indexes.
7. Dispatch `reviewer` before commit and before push.
8. Run validation.
9. Commit only reviewed devlog automation files.
10. Push only the dated automation branch.
11. Open a PR and attempt auto-merge when allowed.

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

Commit after review. Push only `automation/daily-devlog/YYYY-MM-DD`. Use `gh pr create --base main --head automation/daily-devlog/YYYY-MM-DD` when authenticated. Use `gh pr merge --auto --squash automation/daily-devlog/YYYY-MM-DD` only when available. Never push directly to `origin/main`.

## Fail-Closed Cases

Stop with a clear BLOCKED summary when the checkout is dirty, credentials are missing, `gh` is unavailable, validation fails, branch protection or checks prevent auto-merge, or the diff includes unexpected files.

## Red Flags

- "I'll just push main because this is docs-only."
- "The entry can be a commit summary this time."
- "A quiet day still needs an entry."
- "The reviewer is unnecessary for one paragraph."
- "The UI prompt already says enough."
