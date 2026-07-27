# Autonomous Flow Approval Design

## Goal

Make the existing brainstorming → design spec → implementation plan → subagent-driven-development flow proceed without manual user approval gates after the design spec or implementation plan are created.

## Requirements

- Keep the initial collaborative discussion and clarification behavior: the agent should still ask questions when requirements are ambiguous.
- After the agent writes, self-reviews, and commits a design spec, it should automatically transition to implementation planning.
- After the agent writes, self-reviews, and commits an implementation plan, it should automatically invoke subagent-driven-development.
- The agent should only stop for the user when there is unresolved ambiguity, the user explicitly requested a review checkpoint, a tool/permission prompt requires it, or the process is blocked.
- Preserve quality gates that do not depend on manual review: project exploration, spec self-review, plan self-review, commit checkpoints, implementer → reviewer loops, tests, final commit/clean-tree requirements.
- Changes must be made to opencode skill/configuration documentation only through implementer → reviewer because supervisor direct edits are not allowed for skill files.

## Scope

In scope:

- Update `skills/brainstorming/SKILL.md` to remove manual approval gates for the presented design and written spec, replacing them with automatic progression after self-review and commit.
- Update `skills/writing-plans/SKILL.md` to remove the execution approval gate and require automatic SDD handoff after the committed plan.
- Adjust wording that currently says “get user approval,” “ask user to review,” “offer execution choice,” or “if approved.”

Out of scope:

- Changing implementer/reviewer/adjudicator mechanics.
- Removing commit checkpoints, self-review, test requirements, or final clean-tree completion requirements.
- Changing opencode runtime schema/config fields.

## Design

The flow remains deliberative but not permission-bound. Brainstorming still explores context, clarifies requirements, proposes approaches, and produces a committed design spec. The difference is that presenting the design and writing the spec become informational checkpoints, not approval gates. If the agent can resolve details from the discussion and repository context, it proceeds. If it cannot, it asks a focused question.

Writing-plans continues to produce a detailed, self-reviewed, committed plan. Its handoff section becomes deterministic: after the plan commit, the supervisor invokes subagent-driven-development and tells the user execution is starting, rather than asking for permission.

## Validation

- Search the changed skill files for stale approval-gate language related to design spec review or plan execution.
- Verify the new wording still contains self-review and commit checkpoints before automatic progression.
- Have reviewer confirm the flow matches the user request and does not weaken implementer/reviewer/final completion gates.
