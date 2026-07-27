# Validation Failure Recovery Design

## Context

A prior agent completed implementation and review, then stopped during finishing
because the required full suite failed. The current `finishing-a-development-branch`
skill explicitly says to report test failures and stop, while supervisor guidance
says to report `BLOCKED` when required checks fail. That prevents the agent from
owning the next necessary step: diagnosing the failed validation and routing a
proper reviewed fix before integration.

## Requirement

After implementation, review, and commit, failed required validation is a gate
and a debugging task. The agent must not finish, push, create a PR, merge, or
clean up while required validation is red. It must invoke `systematic-debugging`,
identify root cause with evidence, route any fix through `implementer` →
`reviewer` → pass, commit reviewed fixes, rerun validation, and restart finishing
checks from the top. If the failure cannot be resolved without human input or is
external/environmental/unreproducible with available evidence, the agent reports
`BLOCKED` or `HUMAN_DECISION_REQUIRED` with evidence instead of claiming done.

## Approaches Considered

1. **Only update `AGENTS.md`.** This creates project-wide policy, but it leaves
   contradictory skill text telling agents to stop on failed tests.
2. **Only update the finishing skill.** This fixes the immediate stop condition,
   but always-on supervisor instructions would still say required checks failing
   should be reported as `BLOCKED`.
3. **Update the policy and the operational handoff points.** Put concise policy
   in `AGENTS.md`, concrete loop mechanics in `finishing-a-development-branch`,
   remove the contradictory supervisor stop rule, and clarify the SDD finish
   handoff. This is the recommended approach because future agents see a
   consistent contract at every decision point.

## Design

Update these instruction layers:

- `AGENTS.md`: add a repository-level rule that required validation failures
  trigger systematic debugging and reviewed fixes before integration.
- `.opencode/agents/supervisor.md`: change completion discipline so failed
  validation enters the debugging/fix loop before `BLOCKED`; `BLOCKED` is only
  for evidence-backed unresolved, external, environmental, or human-decision
  cases.
- `.opencode/skills/finishing-a-development-branch/SKILL.md`: make failed tests
  an explicit recovery loop: capture failure details, invoke
  `systematic-debugging`, identify root cause, route fixes through
  `implementer` → `reviewer`, rerun from Step 0, and forbid integration while
  red.
- `.opencode/skills/subagent-driven-development/SKILL.md`: clarify that final
  review hands off to the finishing skill, and failed finishing validation stays
  in coordination mode rather than stopping.
- `docs/dev/features/development-tooling.md`: document the workflow for future
  maintainers.

No production code, runtime tests, or OpenCode schema/config changes are in
scope.

## Error Handling

The recovery loop must preserve existing safety rules: no silent failures, no
test weakening, no supervisor edits to non-allowlisted files, and no unreviewed
patches. If systematic debugging establishes that the failure is unrelated but
the required suite remains red, the branch is still not finished; the agent
reports a blocker with evidence.

## Testing

This is an instruction/documentation change. Focused validation should check
that all edited instruction files contain consistent wording for failed
validation, `systematic-debugging`, `implementer` → `reviewer`, and green-suite
integration. Run `git diff --check`. A full product test suite is not required
unless implementation unexpectedly edits product code, tests, build files, or
runtime assets.
