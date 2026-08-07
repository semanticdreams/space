# OpenCode Capability Preflight Design

## Context

The active supervisor policy now routes privileged Git, GitHub, and OpenCode
home-config checks through capability agents and repo-local wrapper scripts. A
feature branch that was behind `origin/main` exposed a mismatch: the running
agent instructions required `git-integrator` and `scripts/opencode_git_integrate.py`,
but the checked-out branch did not yet contain the wrapper scripts. Finishing
stopped late in the workflow with a missing-file error instead of identifying
that the branch was missing required capability support.

The repo already contains capability agents, wrapper scripts, and Python tests
after merging `origin/main`. The existing `scripts/check_opencode_permissions.py`
checks unsafe permissions in files that exist, but it does not assert that the
required capability agents and wrappers exist together or that wrapper paths in
agent allowlists point to real files.

## Goals

- Detect missing OpenCode capability agents or wrapper scripts before finishing
  or PR integration work begins.
- Fail with a clear diagnostic that points to the missing dependency and the
  likely branch/config skew.
- Keep the check repo-local, deterministic, and runnable by agents, humans, and
  CI.
- Cover the exact mismatch class: active capability routing requires wrappers
  that are absent from the checked-out tree.
- Preserve the capability-boundary discipline; do not loosen supervisor rules or
  reintroduce direct privileged Git/GitHub permissions.

## Non-Goals

- No automatic repair, rebase, force-push, or broad Git fallback when capability
  files are missing.
- No live OpenCode session reload mechanism. Users still need to restart after
  `.opencode/**` changes.
- No broad validation of every possible OpenCode instruction sentence. The first
  pass focuses on required capability files and wrapper path consistency.
- No credential or GitHub network checks in this static preflight.

## Design

Extend `scripts/check_opencode_permissions.py` with a capability dependency
check. The checker should require the repo to contain:

- `.opencode/agents/git-integrator.md`
- `.opencode/agents/github-operator.md`
- `.opencode/agents/config-auditor.md`
- `scripts/opencode_capabilities.py`
- `scripts/opencode_git_integrate.py`
- `scripts/opencode_pr_operator.py`
- `scripts/verify_opencode_home_config.py`

It should also inspect capability agent allowlists for wrapper invocations and
verify each referenced `scripts/*.py` file exists. If an agent allows a command
such as `python3 scripts/opencode_git_integrate.py ...`, the checker should fail
if `scripts/opencode_git_integrate.py` is absent.

Failure output should remain in the existing checker style: a nonzero exit with
human-readable diagnostics naming the missing file/path. Diagnostics should use
terms like `missing capability dependency` or `missing wrapper script` so future
agents can quickly identify branch/config skew.

Add tests to `scripts/tests/test_check_opencode_permissions.py` for:

1. current repository passes;
2. missing required capability agent fails;
3. missing required wrapper script fails;
4. an agent allowlist referencing a nonexistent wrapper script fails.

Add a Makefile target, `opencode-check`, that runs the static checker and the
OpenCode capability Python tests. This gives agents and humans one local command
for the capability preflight.

Wire the preflight into CI if the existing workflow has a suitable Python step
or room for a short script validation step. The CI gate should be lightweight:
run the static checker and the Python unit tests under `scripts/tests` that cover
OpenCode capability helpers/operators. This prevents branches that modify
`.opencode/**` or capability scripts inconsistently from landing.

Update developer documentation for OpenCode agent workflow to mention that a
missing wrapper means the branch is missing required capability support and the
preflight should be run before finishing.

## Error Handling

- Missing required agent or script fails the checker with a specific file path.
- Missing wrapper referenced from a capability agent allowlist fails the checker
  with the agent file and referenced script path.
- The checker should not attempt network calls, Git fetches, pushes, or GitHub
  authentication.
- The checker should not create, delete, or modify files.

## Testing Strategy

- Unit tests mutate temporary repo copies or monkeypatched paths to simulate
  missing agents/wrappers without changing the real working tree.
- Existing wrapper tests continue to validate exact guarded command surfaces.
- `make opencode-check` validates the static checker and wrapper unit tests as a
  local preflight.
- CI runs the same lightweight command or equivalent script-test commands.

## Acceptance Criteria

- Removing a required capability agent causes `check_opencode_permissions.py` to
  fail with a clear diagnostic.
- Removing a required wrapper script causes `check_opencode_permissions.py` to
  fail with a clear diagnostic.
- Adding an allowlisted wrapper command for a nonexistent script causes the
  checker to fail.
- The current repository passes the enhanced checker.
- `make opencode-check` exists and passes locally.
- CI or the standard validation workflow includes the capability preflight.
- Documentation explains the branch/config-skew failure mode and points to the
  preflight command.
