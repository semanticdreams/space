---
name: weekly-agent-workflow-automation
description: Use when a scheduled Orca/OpenCode run or user prompt asks to run weekly agent workflow automation, audit recent OpenCode sessions, improve agent workflows, or publish a weekly agent workflow report
---

# Weekly Agent Workflow Automation

## Overview

This skill turns a scheduled Orca/OpenCode trigger into a guarded weekly audit of Space agent workflows. Agents must consume sanitized analyzer artifacts, implement only high-confidence improvements, and route every change through implementer → reviewer → pass before publishing a PR.

## Preconditions

1. Work only in the Space repository and a dedicated checkout. Stop if `git status --porcelain` is not clean.
2. Use the sanitized analyzer; do not browse raw OpenCode database rows, raw logs, raw tool-output dumps, `auth.json`, or credential/account/auth/token/secret tables.
3. Verify GitHub access with `gh auth status` before PR work.
4. Treat `.opencode/**` changes as startup-loaded; note that OpenCode must restart after merge before the new automation is relied on.
5. Verify merge queue protection is required for the target branch before relying on post-PR freshness; report `HUMAN_DECISION_REQUIRED` if merge queue is not enabled.

## Workflow

1. `git fetch origin main`.
2. Create the run branch from `origin/main` (`automation/weekly-agent-workflow/YYYY-Www`) only when it does not already exist. If the branch already exists, switch to it, fetch `origin`, safe-merge `origin/main` when permitted, route conflicts or regenerated docs changes through `implementer` → `reviewer` → pass, and do not reset unless the human explicitly requests it.
3. Run the analyzer and save sanitized evidence to a local scratch path that is not under `docs/`, for example:

   ```bash
   python3 scripts/weekly_agent_workflow_analyzer.py \
     --repo-root . \
     --opencode-data-dir ~/.local/share/opencode \
     --worktree-parent ~/space \
     --since-days 7 \
     --output .superpowers/sdd/weekly-agent-workflow/YYYY-Www-evidence.json
   ```

   Do not commit analyzer evidence JSON. It contains local source paths for scoping and diagnostics; published docs reports must include only intentionally selected sanitized excerpts.

4. Fail closed if the analyzer fails, reports redaction failures, includes unrelated projects, or requires raw OpenCode browsing to justify findings.
5. Read prior reports in `docs/dev/reports/agent-workflow/` and the feature contract in `docs/dev/features/weekly-agent-workflow-automation.md`.
6. Choose only high-confidence improvements with sanitized evidence and clear maintenance value.
7. Dispatch `implementer` for selected changes. For skill edits, the implementer must use `writing-skills` where practical.
8. Dispatch `reviewer`; accepted findings go back through implementer and reviewer until the result is pass.
9. Fetch `origin` and confirm the automation branch has accounted for current `origin/main`. If the branch is behind, safe-merge `origin/main` when permitted, route conflicts or regenerated docs changes through `implementer` → `reviewer` → pass, and rerun validation from a clean tree. Do not rebase or force-push unless the human explicitly requests it.
10. Run validation. Use `systematic-debugging` for validation failures. A validation failure is not an immediate `BLOCKED` condition, even when it appears unrelated, flaky, timing-dependent, or environmental. Capture the failing command, failing tests, relevant output, current branch state, and `git status --porcelain`; establish root cause or the limits of available evidence; route any repository fix through `implementer` → `reviewer` → pass; commit reviewed fixes; re-fetch `origin`; recheck current `origin/main`; and rerun validation until green or a true human-input blocker is established. Do not weaken valid tests or ignore noise.
11. Inspect the final diff and confirm it contains only reviewed, expected files.
12. Re-fetch `origin` and recheck current `origin/main` before push or PR creation. If the branch is behind, safe-merge `origin/main` when permitted, route conflicts and fixes through `implementer` → `reviewer` → pass, and restart validation from a clean tree.
13. Commit reviewed changes, push the automation branch, create the PR, verify branch protection, required checks, and merge queue protection, then enable auto-merge (or queue the PR) only when safe. After the PR enters merge queue, poll with `gh pr view --json state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url` until `mergedAt` is present (PR merged). Inspect merge_group runs with `gh run list --workflow test.yml --event merge_group --limit 10 --json databaseId,headBranch,headSha,status,conclusion,event,url,displayTitle,createdAt` and `gh run watch <run-id> --exit-status --interval 100` when queue checks are failing. Do not update the PR branch solely because origin/main advanced after PR creation — merge queue handles post-PR freshness. Resume only for actionable queue blockers: merge queue conflicts, merge-group `test` failures, missing merge queue protection, or permission blockers. For queue failures, invoke `systematic-debugging`, route any repository fix through `implementer` → `reviewer` → pass, commit reviewed fixes, revalidate, and requeue. Do not rebase or force-push unless the human explicitly requests it.

## Improvement Selection

Prefer small, reversible changes that remove repeated agent friction, close workflow safety gaps, improve validation clarity, or strengthen existing skills/agents. Defer speculative redesigns, style-only edits, weakly evidenced findings, changes outside the Space project, and anything requiring raw sensitive OpenCode data.

## Report Contract

Publish a dated weekly report under `docs/dev/reports/agent-workflow/` using this shape:

```md
# Weekly Agent Workflow Report: YYYY-Www

## Range Analyzed

## Data Sources and Redaction

## Session Summary

## Top Findings

## Implemented Changes

## Deferred Recommendations

## Validation

## Risks and Noise

## Signals To Re-check Next Week
```

Reports may include short sanitized excerpts only when they materially justify a finding. Link or name the analyzer artifact and state whether redaction passed.

## Validation

Run focused checks for edited files first, then the relevant full suite. Default full suite:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

For Fennel-facing changes, follow `AGENTS.md`: `make fennel-check`, constraints, focused tests, then broader suite.

If validation fails, follow the validation failure recovery steps in the Workflow section: invoke `systematic-debugging`, route repository fixes through `implementer` → `reviewer` → pass, commit reviewed fixes, re-fetch `origin`, recheck current `origin/main`, and rerun validation until green or a true human-input blocker is established.

## Commit, Push, and PR

Commit only after implementer → reviewer → pass and validation. Push with `git push origin HEAD:refs/heads/automation/weekly-agent-workflow/YYYY-Www`. Use `gh pr create --base main --head automation/weekly-agent-workflow/YYYY-Www --fill` when authenticated.

Before auto-merge, run `gh auth status`, verify protection with `gh api repos/<owner>/<repo>/branches/main/protection` (or rulesets when classic returns 404), and verify required checks and merge queue requirement are present and passing. Use `gh pr merge --auto --squash automation/weekly-agent-workflow/YYYY-Www` only after those checks. Never push directly to `origin/main`. After auto-merge is enabled, poll with `gh pr view --json state,mergedAt,...` until `mergedAt` is present — later `origin/main` movement is handled by merge queue. Resume only for actionable queue blockers (conflicts, merge-group `test` failures, missing merge queue protection, permission blockers). Invoke `systematic-debugging` for any queue failure and route repository fixes through `implementer` → `reviewer` → pass before requeuing.

## Fail-Closed Cases

Stop with BLOCKED or HUMAN_DECISION_REQUIRED when the checkout is dirty,
analyzer execution or redaction fails, sanitized evidence is insufficient, raw
sensitive data would be needed, branch protection, required checks, or merge
queue requirement cannot be verified, GitHub authentication is missing for PR
work, merge queue handoff fails with an unresolved blocker, reviewer does not
pass the diff, unexpected files appear, or validation remains red after
systematic debugging establishes a true human-input blocker.

## Red Flags

- "I'll inspect the OpenCode DB directly to get better evidence."
- "This is automation, so reviewer gates can be skipped."
- "Auto-merge is safe because `gh auth status` passed."
- "A broad redesign is fine because the weekly report mentioned friction."
- "It's okay to push main because this is only workflow/docs."
