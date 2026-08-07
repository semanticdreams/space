from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
CHECKER = REPO_ROOT / "scripts" / "check_opencode_permissions.py"


def load_checker():
    assert CHECKER.exists(), "policy checker script should exist"
    spec = importlib.util.spec_from_file_location("check_opencode_permissions", CHECKER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_file(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def agent(name: str, permission_text: str) -> str:
    return f"""---
description: Test {name} agent
mode: subagent
model: openai/gpt-5.5
permission:
{permission_text}
---

Test agent body.
"""


def skill(name: str) -> str:
    return f"""---
name: {name}
description: Use when testing {name}
---

# {name}
"""


def write_capability_files(root: Path) -> None:
    write_file(
        root / ".opencode" / "agents" / "git-integrator.md",
        agent(
            "git-integrator",
            '  edit: deny\n  task: deny\n  external_directory: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  bash:\n    "python3 scripts/opencode_git_integrate.py status --repo-root .": allow\n',
        ),
    )
    write_file(
        root / ".opencode" / "agents" / "github-operator.md",
        agent(
            "github-operator",
            '  edit: deny\n  task: deny\n  external_directory: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  bash:\n    "python3 scripts/opencode_pr_operator.py auth-status --repo-root .": allow\n',
        ),
    )
    write_file(
        root / ".opencode" / "agents" / "config-auditor.md",
        agent(
            "config-auditor",
            '  edit: deny\n  task: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  external_directory:\n    "~/.config/opencode/**": allow\n    "~/.config/opencode/**/*auth.json*": deny\n    "~/.config/opencode/**/*auth.jsonc*": deny\n    "~/.config/opencode/**/*secret*": deny\n    "~/.config/opencode/**/*token*": deny\n  bash:\n    "python3 scripts/verify_opencode_home_config.py --repo-root . --require-clean": allow\n',
        ),
    )
    for script in [
        "opencode_capabilities.py",
        "opencode_git_integrate.py",
        "opencode_pr_operator.py",
        "verify_opencode_home_config.py",
    ]:
        write_file(root / "scripts" / script, "#!/usr/bin/env python3\n")


def make_repo(tmp_path: Path, *, agent_name: str = "example-agent", permission_text: str = "  bash: deny\n") -> Path:
    root = tmp_path / "repo"
    write_file(root / ".opencode" / "opencode.json", json.dumps({"default_agent": "supervisor"}))
    write_capability_files(root)
    write_file(root / ".opencode" / "agents" / f"{agent_name}.md", agent(agent_name, permission_text))
    write_file(root / ".opencode" / "skills" / "example" / "SKILL.md", skill("example"))
    return root


def violation_codes(repo: Path) -> set[str]:
    checker = load_checker()
    return {violation.code for violation in checker.check_repo(repo)}


def test_current_repo_policy_passes_after_task_3_changes():
    checker = load_checker()
    assert checker.check_repo(REPO_ROOT) == []


def test_cli_emits_pass_or_fail_json(tmp_path: Path):
    repo = make_repo(tmp_path)
    result = subprocess.run(
        [sys.executable, str(CHECKER), "--repo-root", str(repo)],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    payload = json.loads(result.stdout)
    assert result.returncode == 0
    assert payload == {"status": "pass", "violations": []}
    assert result.stderr == ""


def test_check_repo_fails_when_required_capability_agent_missing(tmp_path: Path):
    repo = make_repo(tmp_path)
    (repo / ".opencode" / "agents" / "git-integrator.md").unlink()

    checker = load_checker()
    issues = checker.check_repo(repo)

    assert any(
        violation.code == "capability-dependency"
        and ".opencode/agents/git-integrator.md" in violation.message
        for violation in issues
    )


def test_check_repo_fails_when_required_wrapper_missing(tmp_path: Path):
    repo = make_repo(tmp_path)
    (repo / "scripts" / "opencode_git_integrate.py").unlink()

    checker = load_checker()
    issues = checker.check_repo(repo)

    assert any(
        violation.code == "capability-dependency"
        and "scripts/opencode_git_integrate.py" in violation.message
        for violation in issues
    )


def test_check_repo_fails_when_agent_allowlist_references_missing_wrapper(tmp_path: Path):
    repo = make_repo(tmp_path)
    agent_path = repo / ".opencode" / "agents" / "git-integrator.md"
    agent_text = agent_path.read_text(encoding="utf-8")
    agent_path.write_text(
        agent_text.replace(
            '    "python3 scripts/opencode_git_integrate.py status --repo-root .": allow\n',
            '    "python3 scripts/opencode_git_integrate.py status --repo-root .": allow\n    "python3 scripts/missing_wrapper.py status --repo-root .": allow\n',
        ),
        encoding="utf-8",
    )

    checker = load_checker()
    issues = checker.check_repo(repo)

    assert any(
        violation.code == "capability-dependency"
        and "missing wrapper script" in violation.message
        and "scripts/missing_wrapper.py" in violation.message
        for violation in issues
    )


def test_reviewer_with_bash_allow_fails(tmp_path: Path):
    repo = make_repo(tmp_path, agent_name="reviewer", permission_text="  bash: allow\n")
    assert "role-boundary" in violation_codes(repo)


def test_implementer_with_git_push_allow_fails(tmp_path: Path):
    repo = make_repo(tmp_path, agent_name="implementer", permission_text="  bash:\n    \"git push*\": allow\n")
    assert "role-boundary" in violation_codes(repo)


def test_web_researcher_with_local_read_fails(tmp_path: Path):
    repo = make_repo(tmp_path, agent_name="web-researcher", permission_text="  read:\n    \"*\": allow\n")
    assert "role-boundary" in violation_codes(repo)


def test_capability_agent_with_edit_allow_fails(tmp_path: Path):
    repo = make_repo(tmp_path, agent_name="git-integrator", permission_text="  edit: allow\n  bash: deny\n")
    assert "capability-boundary" in violation_codes(repo)


@pytest.mark.parametrize(
    "permission_text",
    [
        '  bash:\n    "git push origin main": allow\n',
        '  bash:\n    "git -C * push origin main": allow\n',
        '  bash:\n    "git push origin HEAD:refs/heads/main": allow\n',
        '  bash:\n    "git push origin HEAD:main": allow\n',
        '  bash:\n    "git push origin refs/heads/main": allow\n',
        '  bash:\n    "git -C * push origin HEAD:refs/heads/main": ask\n',
        '  bash:\n    "git -C * push origin HEAD:main": ask\n',
        '  bash:\n    "git -C * push origin refs/heads/main": ask\n',
        "  bash:\n    'git push origin main': ask\n",
        '  bash:\n    "git push *--force*": allow\n',
        '  bash:\n    "git -C * push *--force*": allow\n',
        "  bash:\n    'git push -f *': ask\n",
        '  bash:\n    "git commit --amend*": allow\n',
        '  bash:\n    "git -C * commit --amend*": allow\n',
        '  bash:\n    "git rebase*": allow\n',
        '  bash:\n    "git -C * rebase*": allow\n',
        "  bash:\n    'git rebase*': ask\n",
        "  bash:\n    'git -C * rebase*': ask\n",
        '  bash:\n    "git reset*": allow\n',
        '  bash:\n    "git -C * reset*": allow\n',
        "  bash:\n    'git reset*': ask\n",
        "  bash:\n    'git -C * reset*': ask\n",
        '  bash:\n    "git clean*": allow\n',
        '  bash:\n    "git -C * clean*": allow\n',
        "  bash:\n    'git clean*': ask\n",
        '  bash:\n    "git push origin --delete *": allow\n',
        '  bash:\n    "rm -rf*": allow\n',
        "  bash:\n    'rm -r*': ask\n",
        '  bash:\n    "find * -delete*": allow\n',
        '  bash:\n    "sudo *": allow\n',
        "  bash:\n    'sudo *': ask\n",
        '  bash:\n    "su *": allow\n',
        '  bash:\n    "doas *": ask\n',
        '  bash:\n    "apt *": allow\n',
        "  bash:\n    'apt-get *': ask\n",
        '  bash:\n    "dnf *": allow\n',
        '  bash:\n    "pacman *": ask\n',
        '  bash:\n    "brew *": allow\n',
        '  bash:\n    "gh *": ask\n',
        "  bash:\n    'gh *': allow\n",
        '  external_directory:\n    "*": allow\n',
        "  external_directory:\n    '~/**': ask\n",
        '  external_directory:\n    "/**": allow\n',
        '  external_directory:\n    "/home/**": ask\n',
    ],
)
def test_each_unsafe_permission_pattern_fails_independently(tmp_path: Path, permission_text: str):
    repo = make_repo(tmp_path, agent_name="supervisor", permission_text=permission_text)
    codes = violation_codes(repo)
    assert "unsafe-permission" in codes


def test_opencode_json_must_parse_and_keep_supervisor_default(tmp_path: Path):
    repo = make_repo(tmp_path)
    write_file(repo / ".opencode" / "opencode.json", '{"default_agent":"implementer"}')
    assert "opencode-json" in violation_codes(repo)


def test_agent_and_skill_frontmatter_required(tmp_path: Path):
    repo = make_repo(tmp_path)
    write_file(repo / ".opencode" / "agents" / "broken.md", "---\ndescription: Broken\n---\n")
    write_file(repo / ".opencode" / "skills" / "broken" / "SKILL.md", "---\nname: broken\n---\n")
    codes = violation_codes(repo)
    assert "agent-frontmatter" in codes
    assert "skill-frontmatter" in codes


@pytest.mark.parametrize(
    "permission_text",
    [
        '  edit: deny\n  task: deny\n  external_directory: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  bash:\n    "python3 scripts/opencode_pr_operator.py create --repo-root . --head *": allow\n',
        '  edit: deny\n  task: deny\n  external_directory: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  bash:\n    "python3 scripts/opencode_pr_operator.py enable-auto-merge --repo-root . --branch *": allow\n',
        '  edit: deny\n  task: deny\n  external_directory: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  bash:\n    "python3 scripts/opencode_pr_operator.py poll-merge-queue --repo-root . --branch * --timeout-seconds * --interval-seconds *": allow\n',
    ],
)
def test_github_operator_rejects_wrapper_bash_permissions_with_untrusted_suffix_wildcards(
    tmp_path: Path, permission_text: str
):
    repo = make_repo(tmp_path, agent_name="github-operator", permission_text=permission_text)

    codes = violation_codes(repo)

    assert "capability-boundary" in codes
