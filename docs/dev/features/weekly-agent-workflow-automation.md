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

## Weekly Reports

Weekly reports are published under [Agent Workflow Reports](/dev/reports/agent-workflow/). Each report records the analyzed date range, data sources and redaction status, summarized session signals, top findings with sanitized evidence, implemented changes, deferred recommendations, validation, risks, and signals to re-check next week.
