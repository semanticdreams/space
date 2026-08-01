# Origin Main Constraint Integration Design

## Purpose

The local branch contains the experimental Fennel constraint system and related workflow updates, while `origin/main` has advanced with architectural and design improvements. The goal is to bring those mainline updates into this work, reconcile any drift between the new architecture and the constraint contracts, and produce a validated branch that can be pushed or proposed back to `origin/main`.

## Current State

- The worktree is clean.
- The current branch is local `main`.
- Local `main` is ahead of `origin/main` by many commits and behind `origin/main` by many commits, so the integration is not a fast-forward.
- The local side includes Fennel validation and constraint-system work.
- `origin/main` includes architectural changes such as runtime asset discovery, native log path configuration, and automation/documentation updates.

## Approaches Considered

### Safety integration branch from local `main` — selected

Create a new branch from the current local state, merge `origin/main`, resolve conflicts there, and validate. This keeps the current local branch recoverable, gives reviewers a single integration surface, and lets constraint or production-code fixes go through the normal implementer/reviewer loop. It is slightly more ceremony than merging directly, but it is the lowest-risk option for a large divergence.

### Direct merge into local `main`

This is mechanically simple and preserves history, but a large merge directly on the branch carrying the local work makes rollback and review harder. Because constraint rules may need contract changes, direct integration is too risky as the default.

### Rebase or cherry-pick onto `origin/main`

This can create a tidier final history, but replaying hundreds of local commits over architectural changes is high-risk and likely to repeat conflict work. It should be reserved for a later history-cleanup request, not the first functional reconciliation pass.

## Design Direction

Use a safety branch and merge `origin/main` into it. During conflict resolution and validation, treat the newer `origin/main` architecture as the default contract unless a local constraint encodes an explicitly still-current invariant. Constraint failures are triaged as follows:

- If production code violates a still-current constraint, fix production code.
- If a constraint encodes an old contract contradicted by the accepted `origin/main` architecture, update the constraint rule, focused tests, and docs together.
- If the intended contract is ambiguous, pause and ask for a decision rather than weakening the rule or contorting production code.

The implementation should not add broad baselines or allowlists just to make the merge green. Baseline-data changes are acceptable only for reviewed, precise known exceptions.

## Components

- Git branch state: create and work on a safety integration branch, preserving local `main` as a recovery point.
- Fennel constraints: `assets/lua/constraints/**` and `assets/lua/tests/test-constraints-*.fnl` remain the authoritative constraint contract and regression suite.
- Fennel UI/layout/lifecycle code: merged code must continue following widget ownership, layout dirtiness, context assertion, and teardown doctrine.
- Runtime path code: origin mainline runtime asset discovery and native log path behavior should be preserved unless a reviewed conflict resolution intentionally changes it.
- Documentation: `docs/dev/experimental-constraints.md` is updated if constraint behavior changes; runtime-path docs are updated if integration changes developer-visible path behavior.

## Data Flow

1. Fetch `origin/main` and create a safety branch from the current local state.
2. Merge `origin/main` into that branch.
3. Resolve textual conflicts by preserving mainline architecture and local constraint-system intent where they are compatible.
4. Run the Fennel validation ladder: compile check, constraints, focused tests, then broader tests.
5. For each validation failure, classify whether code, constraint contract, tests, or documentation must change.
6. Commit reviewed fixes and finish with a clean, validated integration branch targeting `main`.

## Error Handling

- Merge conflicts are resolved through implementation review, not by supervisor production-code edits.
- Constraint statuses other than `pass` block readiness and require diagnosis.
- Test or build failures after the merge are handled through systematic debugging before any fix is dispatched.
- Ambiguous architecture/constraint conflicts are escalated for human decision.

## Testing

Validation follows the project Fennel ladder:

1. `make fennel-check`
2. `make constraints`
3. Focused tests for changed constraint/runtime areas
4. `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`

If validation fails, fix through the implementer/reviewer loop and rerun the relevant command sequence.

## Acceptance Criteria

- The integration branch includes `origin/main` and the local constraint-system work.
- There are no unresolved merge conflicts.
- Constraint rules accurately reflect the merged architecture and are not weakened for convenience.
- Any changed constraint behavior is covered by focused tests and documented.
- Runtime asset/log path behavior from `origin/main` is preserved or intentionally documented.
- The required validation commands pass.
- The final worktree is clean and ready for the repository’s default PR flow targeting `main`.
