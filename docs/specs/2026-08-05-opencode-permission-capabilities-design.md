# OpenCode Permission Capabilities Design

## Context

OpenCode workflows for Space should run with as few human permission prompts as
possible on the dedicated project host. Recent scheduled automation exposed two
classes of friction: reviewers could not verify approved global OpenCode config
state directly, and automation workflows could encounter `git`/`gh` command
permission asks even when the intended operation was routine and bounded. The
current permission model correctly uses agent permissions for role separation,
so reducing prompts must not turn reviewers, implementers, or the supervisor
into all-powerful operators.

## Goal

Replace routine `ask` prompts with pre-authorized, bounded capabilities while
leaving truly destructive, credentialed, cross-project, or ambiguous operations
blocked by design. When an operation is unsafe or outside an approved workflow,
the system should fail closed with `HUMAN_DECISION_REQUIRED` rather than opening
an ad hoc permission prompt.

## Non-Goals

- Do not grant every subagent broad shell, GitHub, edit, web, or external
  directory access.
- Do not allow direct pushes to `origin/main`, force-push, history rewrite,
  broad branch deletion, `git reset`, `git clean`, broad recursive removal,
  package-manager/system changes, or credential/auth-file access.
- Do not inspect raw OpenCode database rows, raw logs, raw tool-output dumps, or
  secret-bearing files to diagnose permission friction.
- Do not solve every possible future permission prompt speculatively; add a
  framework and the highest-confidence capabilities first.

## Permission Classes

OpenCode permissions should be classified before changing any rule:

1. **Routine project-scoped operations:** repository reads, file search, local
   build/test commands, clean status inspection, diff inspection, and structured
   local validation. These should generally be allowed for agents whose role
   needs them.
2. **Privileged bounded operations:** remote Git/GitHub actions, approved
   external-directory verification, merge-queue polling, and branch integration.
   These should be exposed through dedicated capability agents and guarded
   scripts, not broad permissions on existing agents.
3. **Role-breaking operations:** reviewer edits, implementer pushes, web access
   from local-code agents, raw OpenCode data browsing by general agents, or
   global config mutation by non-operator agents. These should remain denied.
4. **Destructive or ambiguous operations:** force-push, rebase unless explicitly
   requested, direct main pushes, broad deletes, resets/cleans, package-manager
   or sudo operations, credential access, and broad home/root access. These
   should remain denied and surface as `HUMAN_DECISION_REQUIRED` when genuinely
   needed.

## Architecture

### Capability agents

Keep existing agents narrow and add specialized agents for privileged bounded
work:

- **git-integrator:** read-only/edit-denied local Git operator for safe branch
  integration tasks. It can inspect status/diffs/logs, fetch, safe-merge from
  `origin/main` when a workflow permits it, and push only non-main workflow or
  feature branches. It cannot edit files, reset, clean, rebase, force-push, push
  main, or delete branches broadly.
- **github-operator:** GitHub-only operator for PR creation, PR status checks,
  auto-merge/merge-queue handoff, and merge-group polling. It can run only
  guarded `gh` flows or wrapper scripts and cannot edit files or run arbitrary
  shell commands.
- **config-auditor:** read-only auditor for approved OpenCode configuration
  locations. It can verify symlinks and expected non-secret files such as agent,
  skill, and plugin presence, but cannot edit global config or read auth/token
  files.
- **artifact-auditor:** read-only auditor for sanitized OpenCode analyzer
  artifacts and approved local tool-output/log paths. It consumes redacted
  evidence and must not browse raw sensitive data directly.

The supervisor remains the coordinator. It dispatches a capability agent when a
workflow reaches that capability boundary instead of requesting human permission
or expanding the authority of implementer/reviewer.

### Guarded scripts

Privileged command families should move behind repo-local scripts where command
arguments and invariants can be validated once. Permissions should allow these
scripts rather than brittle broad command patterns. Initial script candidates:

- `scripts/verify_opencode_home_config.py` for global OpenCode config symlink
  and plugin verification.
- `scripts/opencode_git_integrate.py` for safe fetch/status/current-branch/base
  checks and permitted `origin/main` merge operations.
- `scripts/opencode_pr_operator.py` for PR creation, protection/ruleset checks,
  auto-merge enablement, merge-queue polling, and merge-group run inspection.

Each script must verify it is operating on the Space repository, reject dirty or
unsafe states where appropriate, reject direct `main` pushes, reject force or
history-rewrite operations, and emit structured JSON suitable for reviewer or
supervisor handoff.

## Data Flow

1. A normal workflow proceeds with supervisor, planner, implementer, and
   reviewer using their existing narrow permissions.
2. When a workflow reaches a privileged boundary, the supervisor dispatches the
   relevant capability agent with a narrow brief.
3. The capability agent runs only the approved wrapper or exact bounded command
   surface and returns structured evidence.
4. The reviewer verifies repository changes and may verify captured operator
   evidence, but does not gain external-directory, edit, GitHub, or shell access.
5. If the requested operation is outside the bounded capability, the capability
   agent returns `HUMAN_DECISION_REQUIRED` with evidence and a recommendation.

## Error Handling

- Guard scripts must fail closed on unknown repository, unexpected branch,
  dirty worktree where clean state is required, missing branch protection,
  missing merge queue, missing authentication, unexpected files, or unsupported
  command arguments.
- Capability agents must not ask the user for direct permission. They either
  complete the bounded operation or report `HUMAN_DECISION_REQUIRED`.
- Existing destructive operations remain hard-denied so accidental tool use
  cannot bypass the framework.

## Permission Policy Changes

The project should trend toward no `ask` entries in routine workflows. Existing
`ask` rules should be reviewed and converted as follows:

- Convert routine project-scoped asks to `allow` for the role that needs them.
- Convert destructive or role-breaking asks to `deny`.
- Replace privileged bounded asks with capability-agent permissions to guarded
  scripts.

Any remaining `ask` rule should have a documented reason and a signal to replace
it with either `allow`, `deny`, or a capability-agent wrapper in a later pass.

## Testing and Validation

- Unit-test guard scripts with success and fail-closed cases.
- Add text-policy checks that reviewers remain edit/bash/external-denied,
  implementers remain push/external-denied, and no direct main push or broad
  force/history rewrite permissions are introduced.
- Validate OpenCode JSON/frontmatter shapes and document that OpenCode must be
  restarted after agent/config/skill changes.
- Extend the weekly workflow analyzer/reporting to classify permission friction
  into routine, privileged bounded, role mismatch, and destructive/ambiguous
  categories using sanitized evidence only.

## Rollout

Implement this incrementally:

1. Add guard-script infrastructure and policy checks.
2. Add the highest-confidence capability agent(s) and route one or two current
   workflows through them.
3. Convert proven safe `ask` rules to `allow` or `deny` based on the permission
   classes.
4. Use weekly sanitized analysis to identify the next permission prompt class to
   eliminate.

This keeps automation moving toward zero routine permission prompts without
weakening role separation or authorizing destructive operations.
