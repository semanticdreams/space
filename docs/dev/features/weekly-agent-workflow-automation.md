# Weekly Agent Workflow Automation

The weekly agent workflow automation runs through Orca/OpenCode to analyze recent Space agent sessions, identify high-confidence workflow improvements, route changes through implementation and review gates, and publish a sanitized weekly report.

## Orca Setup

Start the automation from Orca with this prompt:

```text
Run the weekly agent workflow automation
```

OpenCode loads project configuration, agents, and skills at startup. Restart OpenCode after changes to `.opencode/opencode.json`, `.opencode/agents/**`, or `.opencode/skills/**` before relying on the new automation behavior.

## Required Local Access

The analyzer reads only the whitelisted local sources needed to produce sanitized evidence JSON for agents:

- `~/.local/share/opencode/opencode.db*`
- `~/.local/share/opencode/tool-output/**`
- `~/.local/share/opencode/log/**`
- `~/space/**` for sibling Space worktree discovery

The automation is scoped to this project across Space worktrees. It excludes unrelated projects.

## Branch and Pull Request Policy

Weekly automation runs on a dedicated branch named with the format `automation/weekly-agent-workflow/YYYY-Www`.

The automation must never push directly to `main`. Any implemented changes go through the implementer, reviewer, and validation gates before a pull request is created against `main`. Auto-merge is allowed only after branch protection and required checks are verified.

## Evidence and Privacy

Agents consume the analyzer's sanitized evidence JSON, not raw OpenCode database rows, raw logs, or raw tool-output dumps.

The analyzer excludes `auth.json`, credential tables, account tables, token/secret/auth-related data, and unrelated projects. Reports may include short sanitized excerpts only when they materially justify a finding.

Raw OpenCode database rows, raw logs, raw tool-output dumps, credential files, auth files, tokens, and secret-bearing material remain out of bounds for weekly automation. If sanitized analyzer evidence is insufficient to justify a finding, defer the recommendation instead of browsing raw sources.

## Weekly permission-friction classes

The analyzer classifies `permission-friction` findings into four permission-friction classes so reports can distinguish safe capability gaps from requests that should remain blocked:

- `routine-project-scoped`: normal in-repository checks and inspection, such as `make test`, `pytest`, `ctest`, `git status`, or `git diff`.
- `privileged-bounded`: guarded Git and GitHub operations that should route through `git-integrator` or `github-operator`, such as fetching or merging `origin/main`, pushing a feature branch, creating/viewing/auto-merging a PR, or checking/watching GitHub runs.
- `role-mismatch`: requests that would break role boundaries, such as reviewer edit/bash, implementer push/external access, or web-researcher local read/bash.
- `destructive-ambiguous`: destructive, credentialed, cross-project, broad, or ambiguous requests, including force-push, rebase, reset/clean, `rm -rf`, sudo/package-manager operations, direct `origin/main` push, auth/token material, broad home/root access, and any general permission prompt with no specific safe match.

Weekly reports use sanitized analyzer evidence only. They may include bounded redacted excerpts and session refs from the analyzer output, but never raw session IDs or unsanitized OpenCode data.

## Weekly Reports

Weekly reports are published under [Agent Workflow Reports](/dev/reports/agent-workflow/). Each report records the analyzed date range, data sources and redaction status, summarized session signals, top findings with sanitized evidence, implemented changes, deferred recommendations, validation, risks, and signals to re-check next week.
