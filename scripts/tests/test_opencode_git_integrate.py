import json
import sys
from pathlib import Path

import pytest

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_ROOT))

import opencode_capabilities as capabilities
import opencode_git_integrate as git_integrate


def command_result(args: list[str], stdout: str = "", returncode: int = 0, stderr: str = "") -> capabilities.CommandResult:
    return capabilities.CommandResult(args=args, returncode=returncode, stdout=stdout, stderr=stderr)


class GitRunner:
    def __init__(self, outputs: dict[tuple[str, ...], str | capabilities.CommandResult]) -> None:
        self.outputs = outputs
        self.calls: list[list[str]] = []

    def __call__(self, args, cwd: Path, check: bool = True):
        del cwd, check
        args = list(args)
        self.calls.append(args)
        output = self.outputs.get(tuple(args), "")
        if isinstance(output, capabilities.CommandResult):
            return output
        return command_result(args, output)


@pytest.fixture
def trusted_repo(monkeypatch, tmp_path: Path) -> Path:
    repo = tmp_path / "space"
    repo.mkdir()
    monkeypatch.setattr(git_integrate, "ensure_space_repo", lambda repo_root: repo)
    return repo


def test_status_reports_branch_head_dirty_and_origin_main_merge_base(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "rev-parse", "HEAD"): "abc123\n",
            ("git", "status", "--porcelain"): " M file.py\n",
            ("git", "merge-base", "HEAD", "origin/main"): "base456\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.git_status(trusted_repo)

    assert result["status"] == "pass"
    assert result["evidence"] == {
        "branch": "feature/opencode-capabilities",
        "head_sha": "abc123",
        "dirty": True,
        "origin_main_merge_base": "base456",
    }


def test_merge_origin_main_refuses_dirty_worktree(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): " M task.py\n",
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.merge_origin_main(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert ["git", "fetch", "origin", "main"] not in runner.calls
    assert ["git", "merge", "--no-edit", "origin/main"] not in runner.calls


def test_merge_origin_main_refuses_main_branch(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "main\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.merge_origin_main(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert ["git", "fetch", "origin", "main"] not in runner.calls


def test_merge_origin_main_runs_only_fetch_origin_main_then_no_edit_merge(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "fetch", "origin", "main"): "",
            ("git", "merge", "--no-edit", "origin/main"): "Already up to date.\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.merge_origin_main(trusted_repo)

    assert result["status"] == "pass"
    assert runner.calls == [
        ["git", "status", "--porcelain"],
        ["git", "branch", "--show-current"],
        ["git", "fetch", "origin", "main"],
        ["git", "merge", "--no-edit", "origin/main"],
    ]


def test_push_current_refuses_main_invalid_branch_and_pushes_only_head_to_current_branch(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "main\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)
    assert git_integrate.push_current(trusted_repo)["status"] == "human_decision_required"

    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "bad branch\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)
    assert git_integrate.push_current(trusted_repo)["status"] == "human_decision_required"

    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "push", "origin", "HEAD:refs/heads/feature/opencode-capabilities"): "",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)
    result = git_integrate.push_current(trusted_repo)

    assert result["status"] == "pass"
    assert runner.calls == [
        ["git", "status", "--porcelain"],
        ["git", "branch", "--show-current"],
        ["git", "push", "origin", "HEAD:refs/heads/feature/opencode-capabilities"],
    ]


def test_cli_emits_json_and_returns_nonzero_on_unsafe_state(monkeypatch, trusted_repo: Path, capsys) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "main\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    exit_code = git_integrate.main(["push-current", "--repo-root", str(trusted_repo)])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert payload["status"] == "human_decision_required"
    assert set(payload) == {"status", "action", "message", "evidence"}
