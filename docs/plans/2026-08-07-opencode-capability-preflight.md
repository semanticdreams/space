# OpenCode Capability Preflight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repo-local preflight that catches missing OpenCode capability agents and wrapper scripts before finishing or PR integration.

**Architecture:** Extend the existing static permission checker with explicit capability dependency validation and wrapper-path consistency checks. Expose the check through a Makefile target and CI step, and document the branch/config-skew failure mode.

**Tech Stack:** Python 3 standard library, pytest, Makefile, GitHub Actions, OpenCode project agent/skill files, repo documentation.

## Global Constraints

- Detect missing OpenCode capability agents or wrapper scripts before finishing or PR integration work begins.
- Fail with a clear diagnostic that points to the missing dependency and the likely branch/config skew.
- Keep the check repo-local, deterministic, and runnable by agents, humans, and CI.
- Cover the exact mismatch class: active capability routing requires wrappers that are absent from the checked-out tree.
- Preserve the capability-boundary discipline; do not loosen supervisor rules or reintroduce direct privileged Git/GitHub permissions.
- No automatic repair, rebase, force-push, or broad Git fallback when capability files are missing.
- No live OpenCode session reload mechanism. Users still need to restart after `.opencode/**` changes.
- No broad validation of every possible OpenCode instruction sentence. The first pass focuses on required capability files and wrapper path consistency.
- No credential or GitHub network checks in this static preflight.

---

## File Structure

- `scripts/check_opencode_permissions.py` — add static capability dependency and wrapper reference checks.
- `scripts/tests/test_check_opencode_permissions.py` — add regression tests for missing agents, missing wrappers, and bad wrapper references.
- `Makefile` — add `opencode-check` target that runs the static checker and OpenCode capability script tests.
- `.github/workflows/test.yml` — add lightweight CI step for `make opencode-check` or equivalent commands.
- `docs/dev/features/opencode-agent-workflow.md` — document the preflight and branch/config-skew failure mode.

## Validation Commands

Use these commands for this plan:

```bash
python3 -m pytest scripts/tests/test_check_opencode_permissions.py scripts/tests/test_opencode_capabilities.py scripts/tests/test_opencode_git_integrate.py scripts/tests/test_opencode_pr_operator.py
python3 scripts/check_opencode_permissions.py --repo-root .
make opencode-check
```

Because this touches CI/Makefile and scripts, final validation should also run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

---

### Task 1: Capability Dependency Checker

**Files:**
- Modify: `scripts/check_opencode_permissions.py`
- Test: `scripts/tests/test_check_opencode_permissions.py`

**Interfaces:**
- Produces: static checker failures for missing required capability files.
- Produces: static checker failures for wrapper paths referenced from capability agent allowlists that do not exist.
- Consumes: existing `check_repo(repo_root: Path) -> list[str]` behavior.

- [ ] **Step 1: Write failing tests for required files**

  In `scripts/tests/test_check_opencode_permissions.py`, first extend the
  existing `make_repo(tmp_path, ...)` helper so synthetic repos include minimal
  required capability files by default. Add a helper inside the test file:

  ```python
  def write_capability_files(root: Path) -> None:
      write_file(root / ".opencode" / "agents" / "git-integrator.md", agent("git-integrator", "  edit: deny\n  bash:\n    \"python3 scripts/opencode_git_integrate.py status --repo-root .\": allow\n"))
      write_file(root / ".opencode" / "agents" / "github-operator.md", agent("github-operator", "  edit: deny\n  bash:\n    \"python3 scripts/opencode_pr_operator.py auth-status --repo-root .\": allow\n"))
      write_file(root / ".opencode" / "agents" / "config-auditor.md", agent("config-auditor", "  edit: deny\n  bash:\n    \"python3 scripts/verify_opencode_home_config.py --repo-root . --require-clean\": allow\n"))
      for script in ["opencode_capabilities.py", "opencode_git_integrate.py", "opencode_pr_operator.py", "verify_opencode_home_config.py"]:
          write_file(root / "scripts" / script, "#!/usr/bin/env python3\n")
  ```

  Call `write_capability_files(root)` from `make_repo` before returning `root`.
  Then add tests that simulate missing files:

  ```python
  def test_check_repo_fails_when_required_capability_agent_missing(tmp_path):
      repo = make_repo(tmp_path)
      (repo / ".opencode/agents/git-integrator.md").unlink()
      issues = checker.check_repo(repo)
      assert any(violation.code == "capability-dependency" and ".opencode/agents/git-integrator.md" in violation.message for violation in issues)

  def test_check_repo_fails_when_required_wrapper_missing(tmp_path):
      repo = make_repo(tmp_path)
      (repo / "scripts/opencode_git_integrate.py").unlink()
      issues = checker.check_repo(repo)
      assert any(violation.code == "capability-dependency" and "scripts/opencode_git_integrate.py" in violation.message for violation in issues)
  ```

  Use the test file's actual fixture/helper names. Do not mutate the real repo.

- [ ] **Step 2: Write failing test for bad allowlisted wrapper path**

  Add a test that appends or replaces an allowed command in a capability agent with a nonexistent wrapper path:

  ```python
  def test_check_repo_fails_when_agent_allowlist_references_missing_wrapper(tmp_path):
      repo = make_repo(tmp_path)
      agent = repo / ".opencode/agents/git-integrator.md"
      agent.write_text(agent.read_text() + '\n- `python3 scripts/missing_wrapper.py status --repo-root .`\n', encoding="utf-8")
      issues = checker.check_repo(repo)
      assert any(violation.code == "capability-dependency" and "missing wrapper script" in violation.message and "scripts/missing_wrapper.py" in violation.message for violation in issues)
  ```

- [ ] **Step 3: Run tests to verify RED**

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py
  ```

  Expected: FAIL because the checker does not yet validate required capability files or referenced wrapper existence.

- [ ] **Step 4: Implement capability checks**

  In `scripts/check_opencode_permissions.py`:
  - Add a constant list for required capability dependencies:

    ```python
    REQUIRED_CAPABILITY_FILES = (
        ".opencode/agents/git-integrator.md",
        ".opencode/agents/github-operator.md",
        ".opencode/agents/config-auditor.md",
        "scripts/opencode_capabilities.py",
        "scripts/opencode_git_integrate.py",
        "scripts/opencode_pr_operator.py",
        "scripts/verify_opencode_home_config.py",
    )
    ```

  - Add `_check_required_capability_files(repo_root: Path) -> list[str]` that reports:

    ```text
    missing capability dependency: <path>
    ```

  - Add `_check_agent_wrapper_references(repo_root: Path) -> list[str]` that scans `.opencode/agents/*.md` for substrings matching `scripts/<name>.py` inside command text and reports:

    ```text
    missing wrapper script referenced by <agent path>: <script path>
    ```

    when the referenced script is absent.

  - Call both functions from `check_repo` before returning issues.
  - Keep the checker read-only; do not import or execute wrapper scripts.

- [ ] **Step 5: Run checker tests and current repo check**

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py
  python3 scripts/check_opencode_permissions.py --repo-root .
  ```

  Expected: PASS.

- [ ] **Step 6: Commit**

  ```bash
  git add scripts/check_opencode_permissions.py scripts/tests/test_check_opencode_permissions.py
  git commit -m "fix(scripts): verify OpenCode capability dependencies"
  ```

---

### Task 2: Local and CI Preflight Wiring

**Files:**
- Modify: `Makefile`
- Modify: `.github/workflows/test.yml`

**Interfaces:**
- Produces: `make opencode-check`

- [ ] **Step 1: Add failing Makefile/CI expectation tests by inspection**

  In this repository there is no Makefile unit test. Before implementation, run these commands and record that they fail or do not find the target/CI step:

  ```bash
  make -n opencode-check
  rg "opencode-check|check_opencode_permissions.py" .github/workflows/test.yml Makefile
  ```

  Expected before implementation: `make -n opencode-check` fails with no rule or `rg` shows no CI wiring.

- [ ] **Step 2: Add `opencode-check` target**

  In `Makefile`, add `opencode-check` to `.PHONY` and define:

  ```make
  opencode-check:
	python3 scripts/check_opencode_permissions.py --repo-root .
	python3 -m pytest scripts/tests/test_check_opencode_permissions.py scripts/tests/test_opencode_capabilities.py scripts/tests/test_opencode_git_integrate.py scripts/tests/test_opencode_pr_operator.py
  ```

  Keep command indentation as tabs.

- [ ] **Step 3: Add CI preflight step**

  In `.github/workflows/test.yml`, add a lightweight step before or near the normal build/test step:

  ```yaml
  - name: Check OpenCode capability wiring
    run: make opencode-check
  ```

  Do not remove existing test/build steps.

- [ ] **Step 4: Run local target**

  ```bash
  make opencode-check
  ```

  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add Makefile .github/workflows/test.yml
  git commit -m "ci(scripts): check OpenCode capability wiring"
  ```

---

### Task 3: Documentation and Final Validation

**Files:**
- Modify: `docs/dev/features/opencode-agent-workflow.md`

**Interfaces:**
- Consumes: `make opencode-check`
- Produces: developer documentation for capability preflight and branch/config skew.

- [ ] **Step 1: Update docs**

  Add a concise section to `docs/dev/features/opencode-agent-workflow.md` titled `Capability preflight`. It must state:
  - privileged Git/GitHub/config operations route through capability agents and repo-local wrapper scripts;
  - run `make opencode-check` before finishing or after merging `.opencode/**` changes;
  - if an agent reports a missing wrapper such as `scripts/opencode_git_integrate.py`, the likely cause is branch/config skew and the branch should be updated from `origin/main` rather than bypassing with direct Git commands;
  - users should restart OpenCode after `.opencode/**` changes.

- [ ] **Step 2: Run documentation consistency search**

  ```bash
  rg "opencode-check|opencode_git_integrate.py|branch/config skew|restart OpenCode" docs/dev/features/opencode-agent-workflow.md
  ```

  Expected: all terms are present in the new section.

- [ ] **Step 3: Run final local validation**

  ```bash
  make opencode-check
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: PASS.

- [ ] **Step 4: Commit**

  ```bash
  git add docs/dev/features/opencode-agent-workflow.md
  git commit -m "docs(scripts): document OpenCode capability preflight"
  ```

## Acceptance Criteria

- Removing a required capability agent causes `check_opencode_permissions.py` to fail with a clear diagnostic.
- Removing a required wrapper script causes `check_opencode_permissions.py` to fail with a clear diagnostic.
- Adding an allowlisted wrapper command for a nonexistent script causes the checker to fail.
- The current repository passes the enhanced checker.
- `make opencode-check` exists and passes locally.
- CI includes the capability preflight.
- Documentation explains the branch/config-skew failure mode and points to the preflight command.
