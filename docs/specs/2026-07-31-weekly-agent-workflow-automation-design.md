# Weekly Agent Workflow Automation Design

## Goal

Create an Orca/OpenCode weekly automation that reviews this project's recent OpenCode sessions across all Space worktrees, compares them with prior automation reports, identifies ways to improve agent efficiency, reliability, and cost, automatically implements high-confidence improvements through the normal reviewed workflow, and publishes a full report in the repo docs.

The Orca setup must stay simple: the user chooses OpenCode as the agent software and pastes a short prompt. Because OpenCode starts the repo default `supervisor`, the durable workflow must live in repository-local OpenCode skills, agent routing, scripts, docs, and permissions.

Recommended Orca prompt:

```text
Run the weekly agent workflow automation
```

## Context and Existing Patterns

- `.opencode/opencode.json` sets `supervisor` as the default agent, so scheduled Orca runs enter the normal supervisor process.
- `.opencode/skills/daily-devlog-automation/SKILL.md` is the reference pattern for scheduled automation: prompt-triggered skill, clean checkout preconditions, dated automation branch, implementer/reviewer gates, validation, push, PR, and guarded auto-merge.
- OpenCode session data lives outside the repo under the user data directory, normally `~/.local/share/opencode/`. The useful durable source is `opencode.db` with `session`, `message`, and `part` tables; long command output may live under `tool-output/`; runtime errors may live under `log/`.
- Sensitive data is colocated with the session data, including `auth.json` and credential/account tables. The automation must not expose those to model context or docs reports.
- This repo may have many sibling worktrees under the same project worktree parent, and each may contain OpenCode sessions for the same project. The automation should include sessions for this project across worktrees, not unrelated projects.

## Requirements

### Functional

1. Add a scheduled skill triggered by prompts such as `Run the weekly agent workflow automation`.
2. Create or switch to a dated branch, e.g. `automation/weekly-agent-workflow/YYYY-Www`, based on `origin/main`.
3. Analyze recent OpenCode sessions for this project across all detected Space worktrees.
4. Analyze prior weekly reports so repeated recommendations are handled intentionally rather than rediscovered every run.
5. Identify improvement opportunities in:
   - agent workflow and subagent routing;
   - subagent definitions, model choices, permissions, or prompts;
   - repo instructions such as `AGENTS.md`;
   - OpenCode skills;
   - Fennel constraints and validation guidance;
   - source/tests/tooling/runtime support when evidence shows a code-level improvement is the right fix.
6. Automatically implement high-confidence improvements, regardless of file category, only through implementer → reviewer → validation gates.
7. Defer risky or ambiguous improvements into the report rather than guessing.
8. Generate a full docs report with sanitized evidence, decisions, implemented changes, deferred recommendations, validation, and follow-up signals for the next run.
9. Provide a docs page explaining how to configure the Orca weekly automation and exactly what prompt to paste.
10. Push the automation branch, create a PR targeting `main`, and auto-merge only when branch protection and required checks are verified.

### Safety and Privacy

1. The supervisor and subagents should reason over sanitized analysis artifacts, not raw OpenCode database rows or raw tool output dumps.
2. The automation must avoid reading `auth.json` and must not query credential/account tables.
3. Reports may include short sanitized excerpts from prompts, tool outputs, or reviewer findings when they materially justify a recommendation.
4. Sanitization must redact secrets, credentials, tokens, API keys, auth headers, private keys, and high-risk environment values.
5. External reads should be narrow and explicit:
   - `~/.local/share/opencode/opencode.db*`
   - `~/.local/share/opencode/tool-output/**`
   - `~/.local/share/opencode/log/**`
   - the configured Space worktree parent for identifying sibling worktrees of this repo
6. Implementer and reviewer should not need raw external-directory access; the deterministic analyzer produces the evidence package they consume.

### Autonomy Boundaries

The automation may implement any high-confidence improvement, including source/test/tooling changes, when the evidence supports it and the change can be reviewed and validated. It must not bypass existing development discipline:

- new behavior still goes through design/plan or a bounded automation plan when needed;
- `.opencode/**`, source, tests, docs, and constraints all go through implementer → reviewer → pass unless they are supervisor-allowlisted coordination artifacts;
- failures in validation trigger systematic debugging and reviewed fixes;
- no direct pushes to `main`;
- no auto-merge without verified branch protection and required checks.

Ambiguous changes, broad architecture changes, uncertain model/provider policy changes, or changes requiring human product judgment are reported as deferred recommendations.

## Approaches Considered

### Approach A: Skill-only raw session analysis

The weekly skill would directly inspect OpenCode DB rows, logs, and tool outputs, then make recommendations.

Pros: smallest implementation; closest to a pure prompt workflow.

Cons: raw session data pollutes supervisor context, increases cost, risks exposing secrets, and makes filtering/schema behavior hard to test.

Decision: rejected.

### Approach B: Scheduled skill plus deterministic sanitized analyzer

A project-local analyzer reads whitelisted OpenCode data sources and emits a compact sanitized evidence package. The scheduled skill uses that package plus prior reports to decide what to implement and what to defer.

Pros: safer privacy boundary, lower context cost, testable redaction/schema behavior, better evidence consistency, and cleaner subagent handoffs.

Cons: more implementation work and a schema contract to maintain.

Decision: selected.

### Approach C: Report-only weekly audit

The automation would only write a report and leave all changes for humans.

Pros: safest autonomy boundary.

Cons: does not satisfy the goal of automatically implementing confident improvements.

Decision: keep as a fail-closed fallback when confidence is too low, but not the primary workflow.

## Architecture

### Components

1. **Weekly automation skill**
   - Repository-local OpenCode skill modeled after `daily-devlog-automation`.
   - Owns preconditions, branch workflow, analyzer execution, improvement selection, implementer/reviewer dispatch, validation, report creation, push/PR/auto-merge, and fail-closed behavior.

2. **Supervisor routing and permissions**
   - Adds trigger routing for weekly agent workflow automation.
   - Adds narrow external-directory permission rules for the OpenCode DB/tool-output/log paths and Space worktree discovery.
   - Adds branch/PR allow rules for `automation/weekly-agent-workflow/YYYY-Www`.

3. **Sanitized session analyzer**
   - Deterministic script/tool run by the skill.
   - Opens the OpenCode DB read-only.
   - Queries only whitelisted columns from `project`, `workspace`, `session`, `message`, and `part` as needed.
   - Detects sessions for this project across sibling worktrees by matching repository identity rather than assuming only the current worktree.
   - Reads `tool-output/` and `log/` only when needed and only through bounded extraction.
   - Emits a sanitized evidence artifact under an automation workspace path or generated report input path.

4. **Report documentation**
   - Canonical setup page under `docs/dev/**` explaining Orca configuration and prompt.
   - Weekly reports under a stable docs path such as `docs/dev/reports/agent-workflow/YYYY-MM-DD.md`.

5. **Optional workflow improvements**
   - Changes may touch `.opencode/skills/**`, `.opencode/agents/**`, `AGENTS.md`, docs, constraints, source, tests, or scripts when justified.
   - All changes are routed through the existing implementer/reviewer process.

### Data Flow

1. Orca starts OpenCode with the short weekly prompt.
2. Supervisor invokes the weekly automation skill.
3. Skill verifies clean checkout, fetches `origin/main`, and creates/switches to the dated automation branch.
4. Skill runs the sanitized analyzer.
5. Analyzer discovers relevant project worktrees, extracts recent session metrics/evidence, redacts sensitive content, and writes a compact evidence package.
6. Supervisor reviews the evidence package and prior reports, then decides which improvements are high-confidence.
7. Implementer makes bounded changes and the report; reviewer verifies them.
8. Validation runs. Failures enter systematic debugging and reviewed fix loops.
9. Skill commits reviewed changes, pushes the branch, opens a PR, verifies branch protection/checks, and enables auto-merge when safe.

## Evidence Model

The analyzer should surface patterns such as:

- repeated syntax/compile/test failures;
- repeated reviewer findings or fix-loop churn;
- frequent wrong-skill or missing-skill routing;
- supervisor context pollution or excessive direct exploration;
- subagent underuse/overuse;
- mismatched model strength for common tasks;
- permission prompts that block unattended runs;
- expensive sessions with low output value;
- recurring validation or environment friction;
- recurring Fennel constraint gaps or noisy constraints.

Each finding should include:

- finding id/category;
- count/frequency and date range;
- involved agents/models;
- affected worktrees/sessions;
- sanitized excerpt when useful;
- confidence level;
- suggested improvement category;
- whether it was implemented, deferred, or parked.

## Report Contract

Each weekly report should include:

1. date/range analyzed;
2. data sources and redaction status;
3. summary of sessions, agents, costs/tokens when available;
4. top findings with sanitized evidence;
5. changes implemented in this run;
6. recommendations deferred and why;
7. validation performed;
8. risks/noise observed;
9. signals to re-check next week.

Reports must not include raw secrets, raw auth data, full prompt dumps, full tool-output dumps, or credential-bearing environment values.

## Testing and Validation

- Analyzer unit/integration tests should use fixture SQLite data and fixture tool-output/log files covering:
  - project worktree detection;
  - non-project session exclusion;
  - credential/account table avoidance;
  - redaction of common secret patterns;
  - bounded excerpt extraction;
  - repeated-failure aggregation;
  - schema drift/fail-closed behavior.
- Skill creation/editing must follow the `writing-skills` process, including baseline failure scenarios where practical.
- OpenCode config/agent changes must be validated for startup-safe shape.
- Fennel-facing changes must run the Fennel validation ladder.
- Full branch validation should run the project default test command before completion.

## Fail-Closed Behavior

The automation stops without push/PR/auto-merge when:

- checkout is dirty before starting;
- OpenCode DB is missing, unreadable, locked beyond retry, or has unsupported schema drift;
- sanitizer detects unredacted high-risk secrets in its output;
- branch creation from `origin/main` is unsafe;
- implementer/reviewer gates fail;
- validation fails and systematic debugging cannot resolve it;
- `gh` authentication, branch protection, required checks, PR creation, or auto-merge verification fails;
- diff contains unexpected files not justified by the report.

## Open Decisions Resolved

- Scope: analyze OpenCode sessions for this project across all worktrees, not unrelated projects.
- External access: grant narrow unattended reads to the OpenCode DB/tool-output/log paths and Space worktree discovery paths; avoid auth and credential data.
- Automatic implementation: allowed for any file category when confidence is high and normal reviewed validation gates pass.
- PR behavior: push, create PR to `main`, and auto-merge when branch protection/checks are verified.
- Report evidence: sanitized excerpts are allowed.

## Out of Scope

- Analyzing unrelated projects' OpenCode sessions.
- Reading OpenCode credentials, auth tokens, or account state.
- Directly pushing to `main`.
- Bypassing implementer/reviewer discipline because the run is automated.
- Guaranteeing every recommendation is implemented in the same weekly run.
