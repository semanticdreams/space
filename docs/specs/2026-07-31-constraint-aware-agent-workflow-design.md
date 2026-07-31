# Constraint-Aware Agent Workflow Design

## Purpose

The experimental Fennel constraints gate is now complete and blocking locally. The next step is to make agents use it as fast feedback rather than discovering constraint failures during late review or final validation. The workflow should reduce review/fix cycles, not create a ritual around satisfying constraints for their own sake.

## Scope

This change updates repo-visible instructions and project-local OpenCode agent/skill guidance so implementation and review workflows use constraints deliberately. It does not create GitHub Actions workflows and does not change constraint runner output formatting; those remain follow-up slices after the workflow contract is in place and real usage produces evidence.

## Design Direction

Use a lightweight workflow contract:

- For Fennel-facing work, implementers run `make constraints` before focused tests and report the result before `DONE`.
- Reviewers check whether the implementer reported relevant constraint validation and treat unaddressed constraint failures as validation findings.
- Planning/subagent workflow prompts include a small “constraint impact” check after feature or bugfix work: whether the change suggests a new constraint, a changed constraint, a stale/noisy constraint, or no constraint change.
- The Space testing skill surfaces `make constraints` as the fast pre-test gate, while `AGENTS.md` remains the canonical command source.
- Documentation frames constraints as feedback accelerators. If a useful architecture change conflicts with a constraint, the correct response is to update the code and constraint contract together through review, not blindly obey the old rule or bypass it.

## Components

- `AGENTS.md`: canonical developer instructions for when to run constraints and how to treat failures.
- `docs/dev/experimental-constraints.md`: longer explanation of agent workflow, philosophy, and constraint-impact reporting.
- `.opencode/agents/implementer.md`: implementation report and validation discipline.
- `.opencode/agents/reviewer.md`: review criteria for constraint validation evidence and misuse.
- `.opencode/skills/space-testing-runtime/SKILL.md`: concise runtime command reference for constraints before focused tests.
- `.opencode/skills/subagent-driven-development/SKILL.md`: prompt/reporting guidance so task briefs and ledgers can carry constraint impact information.

## Skill-Edit Testing

Edits under `.opencode/skills/**` must be tested as process documentation. The implementation should include baseline/verification pressure scenarios in the report, at minimum:

1. An implementer-style scenario where a Fennel task has passing focused tests but would be tempted to skip `make constraints`.
2. A reviewer-style scenario where the implementer report omits constraint validation.
3. A design-change scenario where a constraint conflicts with an intentional architecture change and the expected behavior is to update the constraint contract, not blindly contort production code.

These scenarios must be run as read-only pressure checks before and after the skill/agent text changes where practical, with results documented in the implementation report. The checks may simulate the relevant old/new instruction snippets in fresh subagent prompts; they do not need persistent repo test artifacts unless a natural repo test exists.

## Error Handling

Constraint statuses remain the source of truth:

- `pass`: proceed to the relevant test suite.
- `violations`: fix code, tests, constraints, or reviewed baseline data depending on root cause.
- `fail` or `interrupted`: debug as a validation failure; do not bypass.

No instruction should imply that constraints replace tests or human review.

## Deferred Follow-Ups

- GitHub Actions: no checked-in `.github/workflows` exists in this worktree. Add CI in a separate slice once the desired workflow is known.
- Output ergonomics: measure real pass/fail output first. If agent context is polluted, add a quiet/summarized command or runner mode later.
- Aggregation: begin with a lightweight report field rather than a new database or log format.

## Acceptance Criteria

- Agents have clear instructions to run and report constraints for Fennel-facing work before claiming readiness.
- Reviewers have clear instructions to verify constraint evidence and to reject bypasses or stale/noisy constraints that should be fixed.
- Documentation explains the efficiency goal and the non-dogmatic treatment of constraints during architecture changes.
- Skill edits include documented pressure-scenario evidence in the implementer report.
- No CI workflow or runner-output behavior is changed in this slice.
