---
type: note
tags:
  - automation
  - devlog
  - opencode
created: 2026-07-29
---

# Daily Devlog Automation

## Purpose

The daily devlog automation generates brief narrative journal entries capturing meaningful development work. It is triggered through a scheduled Orca UI prompt that invokes the repo-owned `daily-devlog-automation` OpenCode skill. The automation inspects recent changes, decides whether a new entry is warranted, validates it, and publishes it through a pull request workflow.

## Orca UI setup

1. Select OpenCode in Orca UI.
2. Use this repository checkout as the working directory.
3. Schedule the automation daily.

After any changes to `.opencode/**` (skills, agents, or configuration), restart OpenCode/Orca so the updated skill definitions are loaded.

## Prompt

```text
Run the repo's daily devlog automation. Inspect recent meaningful development changes, write today's brief narrative devlog entry if warranted, validate it, commit it, push an automation branch, and open/auto-merge a pull request when repository policy allows.
```

The UI prompt is intentionally short because `.opencode/skills/daily-devlog-automation/SKILL.md` owns the durable workflow.

## Repo-owned workflow

- `.opencode/opencode.json` keeps `default_agent: supervisor`.
- The skill name is `daily-devlog-automation`.
- Daily runs push `automation/daily-devlog/YYYY-MM-DD`, open a PR, and attempt auto-merge when available.
- Direct pushes to `origin/main` are not the default path.
- Daily runs skip entry creation when no meaningful changes exist.

## Safety model

The automation fails closed when credentials, `gh` authentication, branch protection (classic protection or GitHub rulesets/effective branch rules), required status checks, pull-request protection, or a clean checkout are unavailable. The auto-merge method is selected from the effective branch rules (`--merge`, `--squash`, or `--rebase`) rather than hard-coded. Daily entries contain only frontmatter, a date heading, and one short narrative paragraph connecting concrete work to current project goals or milestones — no commit hashes, author lists, raw file lists, or bullet-point summaries.

## Validation and recovery

Regenerate docs indexes and validate the build:

```bash
cd docs
npm run devlog:indices
npm run docs:build
```

Generated indexes are kept up to date by the automation workflow. If a run produces a stale or malformed entry, discard the branch and re-run from a clean state.
