# Daily Devlog Automation Design

## Purpose

The project should have a daily Orca/OpenCode automation that turns meaningful recent development work into a short narrative devlog entry. The entry is not a commit history: it should explain the work in the context of recent progress, project goals, and milestones, then publish through the existing docs/devlog pipeline after it lands in `main`.

## Direction

Use a repo-owned OpenCode skill invoked by the existing `supervisor` default agent, with Orca UI owning only the schedule and a small trigger prompt. This keeps the durable workflow, style rules, and safety checks in version control while still matching the Orca UI model, where the automation appears to select the OpenCode software rather than a project-specific primary agent.

Do not change `.opencode/opencode.json` away from `default_agent: supervisor`. A specialized primary agent would be hard to route from the Orca UI and would disrupt normal sessions. A UI-only prompt would be easy to lose and difficult to review. A repo skill gives the current supervisor an explicit, triggerable workflow without making the scheduled prompt carry all project policy.

## Components

- `.opencode/skills/daily-devlog-automation/SKILL.md` defines the scheduled workflow and writing contract.
- `.opencode/agents/supervisor.md` gains narrow routing guidance for daily devlog automation prompts and, if needed, narrow permissions for publishing automation branches and using GitHub PR commands.
- `docs/dev/notes/daily-devlog-automation.md` documents how to configure the Orca automation, including the exact prompt to paste into the UI if the Orca config is lost.
- A deterministic journal-index helper should keep `docs/dev/journal/index.md` synchronized from `docs/dev/journal/*.md`, so the automation does not have to hand-edit the index structure.
- The existing `docs/scripts/generate-devlog-index.mjs` remains the source for the aggregate `docs/dev/devlog.md` page.

## Daily Workflow

The Orca UI should run OpenCode daily with a short prompt equivalent to:

> Run the repo's daily devlog automation. Inspect recent meaningful development changes, write today's brief narrative devlog entry if warranted, validate it, commit it, push an automation branch, and open/auto-merge a pull request when repository policy allows.

The supervisor should invoke the `daily-devlog-automation` skill. The skill should require a clean dedicated checkout, fetch `origin/main`, work from a dated automation branch, inspect changes since the latest journal entry or recent day boundary, and gather enough surrounding context from recent journal entries, docs notes, plans, and commits to explain why the work matters.

If there are no meaningful user-facing, architectural, workflow, tooling, or milestone-relevant changes, the automation should stop without creating a journal entry or commit. Routine churn, pure fix-loop commits, formatting-only changes, or changes already covered by a prior entry should be skipped unless they complete or clarify a broader story.

When there is a meaningful entry, an implementer should create or update `docs/dev/journal/YYYY-MM-DD.md`, regenerate the journal index and aggregate devlog, run focused docs validation, and commit the result. A reviewer must verify the entry and touched files before the supervisor pushes. The supervisor then pushes an `automation/daily-devlog/YYYY-MM-DD` branch, opens a PR with `gh` when available, and enables auto-merge if branch protection and credentials allow. Direct pushes to `origin/main` should remain blocked or require explicit permission; branch protection is the intended final guard.

## Writing Contract

Automated journal entries use the existing journal/devlog frontmatter and a single dated heading:

```md
---
type: journal
tags: [journal, devlog]
created: YYYY-MM-DD
---

# YYYY-MM-DD

One short narrative paragraph.
```

The body must be one short paragraph. It should describe the day's meaningful work as a small step in the ongoing project, connecting concrete changes to current goals, milestones, or recent momentum. It must not include `## Today`, `## Decisions`, `## Tomorrow`, commit hashes, author lists, raw file lists, or bullet-point commit summaries. The automation should include a final compression/style pass before writing or committing so the paragraph is brief, contextual, and readable as a devlog.

## Safety and Permissions

The default supervisor remains a coordination agent and does not directly edit `docs/dev/**`; content edits still go through implementer and reviewer. Any permission changes should be narrow:

- allow pushing only dated `automation/daily-devlog/*` branches;
- allow only the GitHub CLI operations needed to create and enable auto-merge for that PR;
- keep direct `git push origin main`, force-push, branch deletion, resets, and cleanup destructive commands denied or ask-gated.

The workflow should fail closed when credentials, `gh` authentication, branch protection, checks, or a clean checkout are unavailable. A failed automation should leave a clear summary rather than attempting unsafe recovery.

## Validation

Validation should be lightweight enough for a daily docs-only automation but still catch broken docs output:

- regenerate `docs/dev/journal/index.md` deterministically;
- regenerate `docs/dev/devlog.md` with the existing devlog script;
- run focused script tests for journal index generation if a new script is added;
- run `cd docs && npm run docs:build` before pushing or auto-merging;
- inspect the final diff to ensure only the expected devlog, journal, and docs automation files changed during the daily run.

## Acceptance Criteria

- The Orca automation can be configured with a small prompt documented in repo docs.
- The project keeps `supervisor` as the default OpenCode agent.
- A repo-owned skill defines the daily devlog workflow and style contract.
- Automated entries are skipped when no meaningful changes exist.
- Generated entries contain only frontmatter, `# YYYY-MM-DD`, and one short narrative paragraph.
- The automation commits, pushes an automation branch, opens a PR, and attempts auto-merge when credentials and branch protection allow.
- Direct pushes to `origin/main` are not enabled as the default path.
- Existing devlog publishing remains separate and continues to publish entries only after they land and deploy through the docs pipeline.
