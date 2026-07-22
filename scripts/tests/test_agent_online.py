import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
import unittest

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SCRIPT_ROOT.parent
sys.path.insert(0, str(SCRIPT_ROOT))

import agent


def require_online() -> None:
    if shutil.which("opencode") is None:
        raise AssertionError("opencode executable is not available")


def load_repo_config() -> dict:
    with (REPO_ROOT / "agent.toml").open("rb") as handle:
        config = tomllib.load(handle)
    for role, model in config.get("models", {}).items():
        if str(model).startswith("REPLACE_WITH_"):
            raise AssertionError(f"agent.toml models.{role} is not configured")
    return config


def make_test_workspace(prefix: str) -> tuple[tempfile.TemporaryDirectory | None, Path]:
    if os.environ.get("SPACE_AGENT_ONLINE_KEEP_ARTIFACTS") == "1":
        path = Path(tempfile.mkdtemp(prefix=prefix))
        return None, path
    temporary = tempfile.TemporaryDirectory(prefix=prefix)
    return temporary, Path(temporary.name)


def extract_first_json(text: str, required: list[str]) -> dict:
    decoder = json.JSONDecoder()
    for index, char in enumerate(text):
        if char != "{":
            continue
        try:
            value, _ = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and all(key in value for key in required):
            return value
    raise AssertionError(f"no JSON object with required keys {required} found in output:\n{text}")


def write_temp_config(base_config: dict, state_dir: Path, config_path: Path) -> None:
    workflow = {
        "review_round_budget": 1,
        "fix_attempt_budget": 1,
        "max_model_limit_wait_seconds": 0,
        "state_dir": str(state_dir),
        "state_file": str(state_dir / "STATE.json"),
        "plan_file": str(state_dir / "PLAN.md"),
        "task_file": str(state_dir / "TASK.md"),
        "exploration_file": str(state_dir / "EXPLORATION.md"),
    }
    lines = ["[models]"]
    for role, model in base_config["models"].items():
        lines.append(f'{role} = {json.dumps(str(model))}')
    lines.extend(["", "[workflow]"])
    for key, value in workflow.items():
        if isinstance(value, int):
            lines.append(f"{key} = {value}")
        else:
            lines.append(f"{key} = {json.dumps(str(value))}")
    lines.extend(
        [
            "",
            "[notifications]",
            "enabled = false",
            "",
            "[validation]",
            'after_implementation = ["true"]',
            'after_fix = ["true"]',
            'final = ["true"]',
        ]
    )
    config_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


class AgentOnlineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        require_online()
        cls.config = load_repo_config()

    def setUp(self) -> None:
        self.tmp, self.tmp_path = make_test_workspace("space-agent-online-")
        self.state_dir = self.tmp_path / "state"
        self.state_dir.mkdir(parents=True)
        self.config_path = self.tmp_path / "agent.toml"
        write_temp_config(self.config, self.state_dir, self.config_path)
        with self.config_path.open("rb") as handle:
            self.isolated_config = tomllib.load(handle)

    def tearDown(self) -> None:
        if self.tmp is None:
            print(f"keeping online test artifacts: {self.tmp_path}")
            return
        self.tmp.cleanup()

    def opencode_run(self, role: str, prompt: str, attachments: list[Path] | None = None, timeout: int = 180) -> str:
        command = [
            "opencode",
            "run",
            "--agent",
            role,
            "--model",
            str(self.config["models"][role]),
            "--title",
            f"online {role} smoke {int(time.time())}",
        ]
        for attachment in attachments or []:
            command.append(f"--file={attachment}")
        if attachments:
            command.append("--")
        command.append(prompt)
        result = subprocess.run(
            command,
            cwd=REPO_ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(
                "opencode failed\n"
                + "command: "
                + " ".join(command)
                + f"\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
        return result.stdout

    def test_real_opencode_file_prompt_separator(self) -> None:
        task = self.state_dir / "TASK.md"
        task.write_text("# Task\n\nONLINE_SENTINEL_PANEL_TRANSFER\n", encoding="utf-8")
        output = self.opencode_run(
            "supervisor",
            (
                "Read the attached file and return only this JSON object shape: "
                "{\"status\": \"ok\", \"saw_sentinel\": true}. "
                "Set saw_sentinel to true only if ONLINE_SENTINEL_PANEL_TRANSFER is present."
            ),
            [task],
        )
        data = extract_first_json(output, ["status", "saw_sentinel"])
        self.assertEqual(data["status"], "ok")
        self.assertIs(data["saw_sentinel"], True)

    def test_real_supervisor_route_json(self) -> None:
        task = self.state_dir / "TASK.md"
        task.write_text(
            "# Task\n\nIn commit 9152dc76 we added a panel transfer feature. How can I use/test it?\n",
            encoding="utf-8",
        )
        route = agent.route_task_with_supervisor(self.isolated_config, task)
        agent.validate_supervisor_route(route, self.state_dir / "route.json")
        self.assertEqual(route["intent"], "research")
        self.assertIn(route["recommended_next_step"], {"answer", "explore", "ask_human"})

    def test_real_readonly_roles_smoke(self) -> None:
        task = self.state_dir / "TASK.md"
        task.write_text("# Task\n\nExplain where panel transfer behavior is implemented and how to test it.\n", encoding="utf-8")

        exploration = self.state_dir / "EXPLORATION.md"
        agent.opencode(
            config=self.isolated_config,
            role="explorer",
            title="Online explorer smoke",
            output=exploration,
            attachments=[task],
            prompt="Explore this repository question and return Markdown with concrete files or commands when available.",
        )
        exploration_text = exploration.read_text(encoding="utf-8", errors="replace")
        self.assertGreater(len(exploration_text.strip()), 100)

        plan = self.state_dir / "PLAN.proposed.md"
        agent.opencode(
            config=self.isolated_config,
            role="planner",
            title="Online planner smoke",
            output=plan,
            attachments=[task, exploration],
            prompt="Create a tiny documentation-only implementation plan. Return Markdown suitable for PLAN.md.",
        )
        plan_text = plan.read_text(encoding="utf-8", errors="replace")
        self.assertIn("Objective", plan_text)

        review_raw = self.state_dir / "review.raw.txt"
        agent.opencode(
            config=self.isolated_config,
            role="reviewer",
            title="Online reviewer smoke",
            output=review_raw,
            attachments=[plan],
            prompt=(
                "FULL REVIEW MODE. There is no code diff to review in this smoke test. "
                "Return only the full-review JSON object required by your instructions, with pass status."
            ),
        )
        review = extract_first_json(review_raw.read_text(encoding="utf-8", errors="replace"), ["mode", "status", "candidate_findings"])
        agent.validate_full_review(review, self.state_dir / "review.json")

        candidate_report = self.state_dir / "candidate-review.json"
        candidate_report.write_text(
            json.dumps(
                {
                    "mode": "full",
                    "status": "candidates_found",
                    "summary": "synthetic candidate for adjudicator smoke",
                    "candidate_findings": [
                        {
                            "id": "R1-1",
                            "category": "correctness",
                            "severity": "medium",
                            "confidence": 0.5,
                            "plan_requirement": None,
                            "file": "scripts/agent.py",
                            "line": 1,
                            "scenario": "synthetic unsupported finding",
                            "expected": "supported evidence",
                            "actual": "no real evidence supplied",
                            "impact": "none; smoke test only",
                            "evidence": ["scripts/agent.py:1"],
                            "smallest_required_fix": "none",
                        }
                    ],
                }
            )
            + "\n",
            encoding="utf-8",
        )
        adjudication_raw = self.state_dir / "adjudication.raw.txt"
        agent.opencode(
            config=self.isolated_config,
            role="adjudicator",
            title="Online adjudicator smoke",
            output=adjudication_raw,
            attachments=[plan, candidate_report],
            prompt=(
                "Adjudicate only the attached synthetic candidate finding. It is unsupported by a real diff; "
                "return only the required adjudication JSON object and reject it."
            ),
        )
        adjudication = extract_first_json(adjudication_raw.read_text(encoding="utf-8", errors="replace"), ["status", "findings"])
        agent.validate_adjudication(adjudication, {"R1-1"}, self.state_dir / "adjudication.json")

    def test_real_conversational_research_e2e(self) -> None:
        env = os.environ.copy()
        env["SPACE_AGENT_CONFIG"] = str(self.config_path)
        task_text = "In commit 9152dc76 we added a panel transfer feature. How can I use/test it?\n"
        result = subprocess.run(
            [str(REPO_ROOT / "scripts" / "agent")],
            cwd=REPO_ROOT,
            input=task_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=600,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(f"scripts/agent failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        state = json.loads((self.state_dir / "STATE.json").read_text(encoding="utf-8"))
        self.assertIn(state["phase"], {"task_ready", "explored"})
        self.assertTrue((self.state_dir / "ANSWER.md").exists())
        self.assertFalse((self.state_dir / "PLAN.md").exists())
        self.assertNotIn("File not found:", result.stderr)

if __name__ == "__main__":
    unittest.main()
