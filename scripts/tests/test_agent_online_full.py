import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tomllib
import unittest

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SCRIPT_ROOT.parent
sys.path.insert(0, str(SCRIPT_ROOT))

from test_agent_online import load_repo_config, make_test_workspace, require_online, write_temp_config


def overlay_current_agent_files(worktree: Path) -> None:
    paths = [
        "agent.toml",
        "scripts/agent",
        "scripts/agent.py",
        "scripts/extract_json.py",
        "scripts/tests/test_agent_online.py",
        "scripts/tests/test_agent_online_full.py",
        ".opencode/.gitignore",
        ".opencode/agents/adjudicator.md",
        ".opencode/agents/explorer.md",
        ".opencode/agents/fixer.md",
        ".opencode/agents/implementer.md",
        ".opencode/agents/planner.md",
        ".opencode/agents/reviewer.md",
        ".opencode/agents/supervisor.md",
    ]
    for relative in paths:
        source = REPO_ROOT / relative
        destination = worktree / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def commit_overlay(worktree: Path) -> None:
    subprocess.run(["git", "add", "--", "agent.toml", "scripts", ".opencode"], cwd=worktree, check=True)
    diff = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=worktree, check=False)
    if diff.returncode == 0:
        return
    subprocess.run(
        [
            "git",
            "-c",
            "user.name=Space Agent Online Test",
            "-c",
            "user.email=space-agent-online@example.invalid",
            "commit",
            "-m",
            "Prepare current agent workflow for online test",
        ],
        cwd=worktree,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def remove_worktree_after_test(worktree: Path, *, keep_artifacts: bool) -> None:
    if keep_artifacts:
        return
    subprocess.run(["git", "worktree", "remove", "--force", str(worktree)], cwd=REPO_ROOT, check=False)


class AgentOnlineFullTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        require_online()
        cls.config = load_repo_config()

    def setUp(self) -> None:
        self.tmp, self.tmp_path = make_test_workspace("space-agent-online-full-")

    def tearDown(self) -> None:
        if self.tmp is None:
            print(f"keeping online full test artifacts: {self.tmp_path}")
            return
        self.tmp.cleanup()

    def test_real_minimal_implementation_pipeline_in_disposable_worktree(self) -> None:
        worktree = self.tmp_path / "worktree"
        subprocess.run(["git", "worktree", "add", "--detach", str(worktree), "HEAD"], cwd=REPO_ROOT, check=True)
        try:
            overlay_current_agent_files(worktree)
            commit_overlay(worktree)
            state_dir = self.tmp_path / "implementation-state"
            state_dir.mkdir()
            config_path = self.tmp_path / "implementation-agent.toml"
            write_temp_config(self.config, state_dir, config_path)
            task = state_dir / "TASK.md"
            plan = state_dir / "PLAN.md"
            task.write_text(
                "# Task\n\nCreate docs/dev/agent-online-smoke.md with one sentence explaining this is an online smoke test.\n",
                encoding="utf-8",
            )
            plan.write_text(
                "# Objective\n\nCreate docs/dev/agent-online-smoke.md.\n\n"
                "# Approved approach\n\nAdd one small documentation file only.\n\n"
                "# Implementation steps\n\n1. Add docs/dev/agent-online-smoke.md with one sentence.\n\n"
                "# Acceptance criteria\n\n- The file exists.\n\n"
                "# Validation\n\nRun true.\n",
                encoding="utf-8",
            )
            (state_dir / "STATE.json").write_text(json.dumps({"phase": "approved"}) + "\n", encoding="utf-8")
            env = os.environ.copy()
            env["SPACE_AGENT_CONFIG"] = str(config_path)
            result = subprocess.run(
                [str(worktree / "scripts" / "agent"), "run"],
                cwd=worktree,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                timeout=1200,
                check=False,
            )
            if result.returncode not in {0, 3}:
                raise AssertionError(f"implementation pipeline failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}")
            state = json.loads((state_dir / "STATE.json").read_text(encoding="utf-8"))
            if result.returncode == 3:
                self.assertEqual(state["phase"], "blocked_review_budget")
            self.assertIn(state["phase"], {"ready_for_human_test", "blocked_review_budget"})
            self.assertTrue((worktree / "docs" / "dev" / "agent-online-smoke.md").exists())
            if state["phase"] == "blocked_review_budget":
                run_dir = Path(state["run_dir"])
                self.assertTrue((run_dir / "full-review-01.json").exists())
                self.assertTrue((run_dir / "adjudication-01.json").exists())
                self.assertTrue((run_dir / "fix-01-attempt-01.raw.txt").exists())
                self.assertTrue((run_dir / "verification-01-attempt-01.json").exists())
        finally:
            remove_worktree_after_test(worktree, keep_artifacts=self.tmp is None)


if __name__ == "__main__":
    unittest.main()
