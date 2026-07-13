import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_ROOT))

import agent


class FakeStdin(io.StringIO):
    def __init__(self, text: str, *, tty: bool) -> None:
        super().__init__(text)
        self._tty = tty

    def isatty(self) -> bool:
        return self._tty


class AgentWorkflowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.root_patch = mock.patch.object(agent, "ROOT", self.root)
        self.root_patch.start()
        self.config = {
            "workflow": {
                "state_dir": ".agent-workflow",
                "task_file": ".agent-workflow/TASK.md",
                "exploration_file": ".agent-workflow/EXPLORATION.md",
                "plan_file": ".agent-workflow/PLAN.md",
                "review_round_budget": 1,
                "fix_attempt_budget": 1,
            },
            "models": {
                "explorer": "test/explorer",
                "supervisor": "REPLACE_WITH_SUPERVISOR_MODEL",
                "planner": "test/planner",
                "implementer": "test/implementer",
                "fixer": "test/fixer",
                "reviewer": "test/reviewer",
                "adjudicator": "test/adjudicator",
            },
            "validation": {},
        }

    def tearDown(self) -> None:
        self.root_patch.stop()
        self.tmp.cleanup()

    def write_json(self, path: Path, value: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value) + "\n", encoding="utf-8")

    def fake_extract_json(self, source: Path, destination: Path, required: list[str]) -> dict:
        value = json.loads(source.read_text(encoding="utf-8"))
        destination.write_text(json.dumps(value) + "\n", encoding="utf-8")
        return value

    def review_pass(self) -> dict:
        return {"mode": "full", "status": "pass", "summary": "ok", "candidate_findings": []}

    def candidate_finding(self) -> dict:
        return {
            "id": "R1-1",
            "category": "correctness",
            "severity": "high",
            "confidence": 0.9,
            "plan_requirement": None,
            "file": "src/example.cpp",
            "line": 1,
            "scenario": "scenario",
            "expected": "expected",
            "actual": "actual",
            "impact": "impact",
            "evidence": ["src/example.cpp:1"],
            "smallest_required_fix": "fix",
        }

    def review_with_candidate(self) -> dict:
        return {"mode": "full", "status": "candidates_found", "summary": "found", "candidate_findings": [self.candidate_finding()]}

    def test_task_from_command_line_arguments(self) -> None:
        task_path = self.root / "TASK.md"
        agent.acquire_task_text(task_path, ["Add", "department", "filtering"], allow_reuse=False)

        text = task_path.read_text(encoding="utf-8")
        self.assertIn("# Task\n\nAdd department filtering", text)
        self.assertIn("## Human constraints", text)

    def test_task_from_piped_stdin(self) -> None:
        task_path = self.root / "TASK.md"
        stdin = FakeStdin("Fix the patient import race condition\n", tty=False)

        agent.acquire_task_text(task_path, [], allow_reuse=False, stdin=stdin)

        self.assertIn("Fix the patient import race condition", task_path.read_text(encoding="utf-8"))

    def test_interactive_task_entry(self) -> None:
        task_path = self.root / "TASK.md"
        stdin = FakeStdin("Line one\nLine two\n", tty=True)
        stdout = io.StringIO()

        agent.acquire_task_text(task_path, [], allow_reuse=False, stdin=stdin, stdout=stdout)

        self.assertEqual(stdout.getvalue(), "Describe the task:\n")
        self.assertIn("Line one\nLine two", task_path.read_text(encoding="utf-8"))

    def test_empty_piped_input_is_rejected(self) -> None:
        stdin = FakeStdin("\n", tty=False)

        with mock.patch.object(sys, "stderr", io.StringIO()), self.assertRaises(SystemExit):
            agent.acquire_task_text(self.root / "TASK.md", [], allow_reuse=False, stdin=stdin)

    def test_existing_task_can_be_reused(self) -> None:
        task_path = self.root / "TASK.md"
        task_path.write_text("# Task\n\nExisting task\n", encoding="utf-8")
        stdin = FakeStdin("\n", tty=True)
        stdout = io.StringIO()

        result = agent.acquire_task_text(task_path, [], allow_reuse=True, stdin=stdin, stdout=stdout)

        self.assertIsNone(result)
        self.assertEqual(task_path.read_text(encoding="utf-8"), "# Task\n\nExisting task\n")
        self.assertIn("Reuse the existing task", stdout.getvalue())

    def test_notify_human_required_launches_sound_and_desktop(self) -> None:
        config = {
            "notifications": {
                "enabled": True,
                "sound": ["paplay", "message.oga"],
                "desktop": ["notify-send"],
            }
        }
        popen = mock.Mock()

        with mock.patch.object(agent.shutil, "which", mock.Mock(return_value="/usr/bin/tool")), \
            mock.patch.object(agent.subprocess, "Popen", popen):
            agent.notify_human_required(config, "Plan Ready", "Review the plan")

        self.assertEqual(popen.call_count, 2)
        self.assertEqual(popen.call_args_list[0].args[0], ["paplay", "message.oga"])
        self.assertEqual(popen.call_args_list[1].args[0], ["notify-send", "Plan Ready", "Review the plan"])

    def test_notify_human_required_disabled_does_nothing(self) -> None:
        config = {"notifications": {"enabled": False, "sound": ["paplay"], "desktop": ["notify-send"]}}

        with mock.patch.object(agent.subprocess, "Popen", mock.Mock(side_effect=AssertionError("should not launch"))):
            agent.notify_human_required(config, "Plan Ready", "Review the plan")

    def test_notify_human_required_missing_command_does_not_fail(self) -> None:
        config = {"notifications": {"enabled": True, "sound": ["missing-sound"], "desktop": ["missing-notify", "Agent"]}}

        with mock.patch.object(agent.shutil, "which", mock.Mock(return_value=None)), \
            mock.patch.object(agent.subprocess, "Popen", mock.Mock(side_effect=AssertionError("should not launch"))):
            agent.notify_human_required(config, "Plan Ready", "Review the plan")

    def test_plan_replaces_existing_task(self) -> None:
        task_path = agent.state_path(self.config, "task_file")
        task_path.parent.mkdir(parents=True)
        task_path.write_text("# Task\n\nOld task\n", encoding="utf-8")
        agent.state_path(self.config, "plan_file").write_text("# Old approved plan\n", encoding="utf-8")

        def fake_opencode(**kwargs) -> None:
            kwargs["output"].write_text("# Proposed plan\n", encoding="utf-8")

        with mock.patch.object(agent, "opencode", fake_opencode), mock.patch.object(sys, "stdout", io.StringIO()):
            agent.cmd_plan(self.config, ["New", "task"])

        self.assertIn("New task", task_path.read_text(encoding="utf-8"))
        proposed = agent.ROOT / self.config["workflow"]["state_dir"] / "PLAN.proposed.md"
        self.assertEqual(proposed.read_text(encoding="utf-8"), "# Proposed plan\n")
        self.assertFalse(agent.state_path(self.config, "plan_file").exists())
        self.assertEqual(agent.load_workflow_state(self.config)["phase"], "plan_proposed")

    def test_plan_with_new_task_does_not_attach_stale_exploration(self) -> None:
        task_path = agent.state_path(self.config, "task_file")
        task_path.parent.mkdir(parents=True)
        exploration = agent.state_path(self.config, "exploration_file")
        exploration.write_text("# Old exploration\n", encoding="utf-8")
        seen_attachments = []

        def fake_opencode(**kwargs) -> None:
            seen_attachments.extend(path.name for path in kwargs["attachments"])
            kwargs["output"].write_text("# Proposed plan\n", encoding="utf-8")

        with mock.patch.object(agent, "opencode", fake_opencode), mock.patch.object(sys, "stdout", io.StringIO()):
            agent.cmd_plan(self.config, ["New", "task"])

        self.assertEqual(seen_attachments, ["TASK.md"])
        self.assertFalse(exploration.exists())

    def test_plan_reuse_keeps_current_exploration(self) -> None:
        task_path = agent.state_path(self.config, "task_file")
        task_path.parent.mkdir(parents=True)
        task_path.write_text("# Task\n\nExisting task\n", encoding="utf-8")
        exploration = agent.state_path(self.config, "exploration_file")
        exploration.write_text("# Current exploration\n", encoding="utf-8")
        seen_attachments = []

        def fake_opencode(**kwargs) -> None:
            seen_attachments.extend(path.name for path in kwargs["attachments"])
            kwargs["output"].write_text("# Proposed plan\n", encoding="utf-8")

        with mock.patch.object(sys, "stdin", FakeStdin("\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "opencode", fake_opencode):
            agent.cmd_plan(self.config, [])

        self.assertEqual(seen_attachments, ["TASK.md", "EXPLORATION.md"])

    def test_start_cancel_stops_before_approval_and_run(self) -> None:
        with mock.patch.object(sys, "stdin", FakeStdin("n\nc\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_plan", lambda config, **kwargs: None), \
            mock.patch.object(agent, "cmd_explore", lambda config, **kwargs: None), \
            mock.patch.object(agent, "approve_plan", mock.Mock(side_effect=AssertionError("approve_plan should not run"))), \
            mock.patch.object(agent, "cmd_run", mock.Mock(side_effect=AssertionError("cmd_run should not run"))):
            agent.cmd_start(self.config, ["Task"])

    def test_start_external_edit_stops_before_approval_and_run(self) -> None:
        with mock.patch.object(sys, "stdin", FakeStdin("n\ne\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_plan", lambda config, **kwargs: None), \
            mock.patch.object(agent, "cmd_explore", lambda config, **kwargs: None), \
            mock.patch.object(agent, "approve_plan", mock.Mock(side_effect=AssertionError("approve_plan should not run"))), \
            mock.patch.object(agent, "cmd_run", mock.Mock(side_effect=AssertionError("cmd_run should not run"))):
            agent.cmd_start(self.config, ["Task"])

    def test_start_creates_checkpoint_before_run_when_artifacts_are_dirty(self) -> None:
        approved = agent.state_path(self.config, "plan_file")
        run = mock.Mock()

        with mock.patch.object(sys, "stdin", FakeStdin("n\ny\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_plan", lambda config, **kwargs: None), \
            mock.patch.object(agent, "approve_plan", mock.Mock(return_value=approved)), \
            mock.patch.object(agent, "is_worktree_clean", mock.Mock(return_value=False)), \
            mock.patch.object(agent, "create_checkpoint_commit", mock.Mock(return_value="abc123def456")), \
            mock.patch.object(agent, "cmd_run", run):
            agent.cmd_start(self.config, ["Task"])

        run.assert_called_once_with(self.config)

    def test_start_checkpoint_prompt_notifies_human(self) -> None:
        approved = agent.state_path(self.config, "plan_file")
        notify = mock.Mock()

        with mock.patch.object(sys, "stdin", FakeStdin("n\ny\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_plan", lambda config, **kwargs: None), \
            mock.patch.object(agent, "approve_plan", mock.Mock(return_value=approved)), \
            mock.patch.object(agent, "is_worktree_clean", mock.Mock(return_value=False)), \
            mock.patch.object(agent, "create_checkpoint_commit", mock.Mock(return_value=None)), \
            mock.patch.object(agent, "cmd_run", mock.Mock()), \
            mock.patch.object(agent, "notify_human_required", notify):
            agent.cmd_start(self.config, ["Task"])

        notify.assert_any_call(
            self.config,
            "Checkpoint Required",
            "Approve checkpoint commit before implementation starts.",
        )

    def test_approval_refuses_human_decision_required(self) -> None:
        state = agent.ROOT / self.config["workflow"]["state_dir"]
        state.mkdir(parents=True)
        (state / "PLAN.proposed.md").write_text("HUMAN_DECISION_REQUIRED\n", encoding="utf-8")

        with mock.patch.object(sys, "stderr", io.StringIO()), self.assertRaises(SystemExit):
            agent.approve_plan(self.config)

        self.assertFalse((state / "PLAN.md").exists())

    def test_full_review_accepts_design_and_documentation_categories(self) -> None:
        for category in ("design_integrity", "documentation"):
            finding = self.candidate_finding()
            finding["category"] = category
            review = {
                "mode": "full",
                "status": "candidates_found",
                "summary": "found",
                "candidate_findings": [finding],
            }

            agent.validate_full_review(review, self.root / f"{category}.json")

    def test_extract_human_decisions_from_plan_section(self) -> None:
        plan = """# Objective

# Human decisions required

- HUMAN_DECISION_REQUIRED: choose storage location.
- Pick whether migration is allowed.

# Risks and rollback
"""

        decisions = agent.extract_human_decisions(plan)

        self.assertEqual(
            decisions,
            [
                "- HUMAN_DECISION_REQUIRED: choose storage location.",
                "- Pick whether migration is allowed.",
            ],
        )

    def test_supervisor_resolves_plan_human_decisions_by_replanning(self) -> None:
        state = agent.ROOT / self.config["workflow"]["state_dir"]
        state.mkdir(parents=True)
        task = agent.state_path(self.config, "task_file")
        task.write_text("# Task\n\nBuild thing\n", encoding="utf-8")
        proposed = state / "PLAN.proposed.md"
        proposed.write_text("# Human decisions required\n\n- HUMAN_DECISION_REQUIRED: choose behavior\n", encoding="utf-8")

        def fake_plan(config, **kwargs) -> None:
            proposed.write_text("# Objective\n\nResolved plan\n", encoding="utf-8")
            agent.update_workflow_state(config, phase="plan_proposed")

        with mock.patch.object(sys, "stdin", FakeStdin("Use the simple behavior\n\ne\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_plan", fake_plan):
            agent.supervisor_approve_or_revise(self.config, {"phase": "plan_proposed"})

        self.assertIn("Resolved planner decisions", task.read_text(encoding="utf-8"))
        self.assertIn("Use the simple behavior", task.read_text(encoding="utf-8"))
        self.assertNotIn("HUMAN_DECISION_REQUIRED", proposed.read_text(encoding="utf-8"))

    def test_supervisor_plan_pause_notifies_human(self) -> None:
        state = agent.ROOT / self.config["workflow"]["state_dir"]
        state.mkdir(parents=True)
        proposed = state / "PLAN.proposed.md"
        proposed.write_text("# Objective\n\nReady\n", encoding="utf-8")
        notify = mock.Mock()

        with mock.patch.object(sys, "stdin", FakeStdin("e\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "notify_human_required", notify):
            agent.supervisor_approve_or_revise(self.config, {"phase": "plan_proposed"})

        notify.assert_called_once_with(
            self.config,
            "Plan Ready",
            "Review the proposed plan and approve, revise, edit, or cancel.",
        )

    def test_status_runs_existing_git_status_commands(self) -> None:
        calls = []

        def fake_run(command, **kwargs):
            calls.append(command)

        with mock.patch.object(agent.subprocess, "run", fake_run), mock.patch.object(sys, "stdout", io.StringIO()):
            agent.cmd_status(self.config)

        self.assertEqual(calls, [["git", "status", "--short"], ["git", "diff", "--stat"]])

    def test_validation_failure_notifies_human(self) -> None:
        notify = mock.Mock()

        with mock.patch.object(agent, "notify_human_required", notify), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(sys, "stderr", io.StringIO()), \
            self.assertRaises(SystemExit):
            agent.run_commands(
                self.config,
                ["false", "true"],
                "final",
                self.root / "validation.log",
                {"resume_command": "run", "run_dir": ".agent-workflow/runs/1", "base_commit": "base", "run_step": "full_review"},
            )

        notify.assert_called_once_with(self.config, "Validation Failed", "Validation failed during final: false")
        state = agent.load_workflow_state(self.config)
        self.assertEqual(state["phase"], "blocked_validation")
        self.assertEqual(state["validation_stage"], "final")
        self.assertEqual(state["validation_command"], "false")
        self.assertEqual(state["validation_remaining_commands"], ["false", "true"])

    def test_run_resumes_blocked_validation_before_review_loop(self) -> None:
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_validation",
                "resume_command": "run",
                "run_dir": ".agent-workflow/runs/1",
                "base_commit": "base",
                "run_step": "full_review",
                "review_round": 1,
                "validation_stage": "after initial implementation",
                "validation_command": "make build",
                "validation_log": ".agent-workflow/runs/1/validation.log",
                "validation_remaining_commands": ["make build"],
            },
        )

        with mock.patch.object(agent, "run_commands", mock.Mock()), \
            mock.patch.object(agent, "cmd_run_resume", mock.Mock()) as resume, \
            mock.patch.object(sys, "stdout", io.StringIO()):
            agent.cmd_run(self.config)

        resume.assert_called_once()

    def test_blocked_validation_retry_failure_preserves_blocked_state(self) -> None:
        run = self.root / ".agent-workflow" / "runs" / "1"
        run.mkdir(parents=True)
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_validation",
                "resume_command": "run",
                "run_dir": ".agent-workflow/runs/1",
                "base_commit": "base",
                "run_step": "full_review",
                "review_round": 1,
                "validation_stage": "after initial implementation",
                "validation_command": "false",
                "validation_log": ".agent-workflow/runs/1/validation.log",
                "validation_remaining_commands": ["false", "true"],
            },
        )

        with mock.patch.object(agent, "notify_human_required", mock.Mock()), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(sys, "stderr", io.StringIO()), \
            self.assertRaises(SystemExit):
            agent.cmd_run(self.config)

        state = agent.load_workflow_state(self.config)
        self.assertEqual(state["phase"], "blocked_validation")
        self.assertEqual(state["validation_remaining_commands"], ["false", "true"])
        self.assertEqual(state["run_step"], "full_review")

    def test_blocked_validation_final_success_moves_to_human_test(self) -> None:
        run = self.root / ".agent-workflow" / "runs" / "1"
        run.mkdir(parents=True)
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_validation",
                "run_dir": ".agent-workflow/runs/1",
                "base_commit": "base",
                "validation_stage": "final",
                "validation_command": "make test",
                "validation_log": ".agent-workflow/runs/1/validation.log",
                "validation_remaining_commands": ["make test"],
                "validation_resume_action": "ready_for_human_test",
                "validation_success_text": "Passed after 1 full review round(s).\n",
            },
        )

        with mock.patch.object(agent, "run_commands", mock.Mock()), \
            mock.patch.object(agent, "notify_human_required", mock.Mock()), \
            mock.patch.object(sys, "stdout", io.StringIO()):
            agent.cmd_run(self.config)

        state = agent.load_workflow_state(self.config)
        self.assertEqual(state["phase"], "ready_for_human_test")
        self.assertEqual((run / "SUCCESS").read_text(encoding="utf-8"), "Passed after 1 full review round(s).\n")

    def test_run_keeps_clean_tree_gate(self) -> None:
        agent.save_workflow_state(self.config, {"phase": "approved"})
        agent.state_path(self.config, "task_file").parent.mkdir(parents=True, exist_ok=True)
        agent.state_path(self.config, "task_file").write_text("# Task\n\nExisting task\n", encoding="utf-8")
        agent.state_path(self.config, "plan_file").write_text("# Approved plan\n", encoding="utf-8")
        with mock.patch.object(agent, "require_clean_tree", mock.Mock(side_effect=SystemExit(1))) as clean_tree:
            with self.assertRaises(SystemExit):
                agent.cmd_run(self.config)

        clean_tree.assert_called_once_with()

    def test_run_refuses_stale_plan_without_approved_state(self) -> None:
        agent.state_path(self.config, "plan_file").parent.mkdir(parents=True, exist_ok=True)
        agent.state_path(self.config, "task_file").write_text("# Task\n\nExisting task\n", encoding="utf-8")
        agent.state_path(self.config, "plan_file").write_text("# Old plan\n", encoding="utf-8")
        agent.save_workflow_state(self.config, {"phase": "plan_proposed"})

        with mock.patch.object(sys, "stderr", io.StringIO()), \
            mock.patch.object(agent, "require_clean_tree", mock.Mock(side_effect=AssertionError("should not check tree"))), \
            self.assertRaises(SystemExit):
            agent.cmd_run(self.config)

    def test_run_allows_committed_plan_when_state_is_absent(self) -> None:
        agent.state_path(self.config, "task_file").parent.mkdir(parents=True, exist_ok=True)
        agent.state_path(self.config, "task_file").write_text("# Task\n\nExisting task\n", encoding="utf-8")
        agent.state_path(self.config, "plan_file").write_text("# Approved plan\n", encoding="utf-8")

        with mock.patch.object(agent, "require_clean_tree", mock.Mock(side_effect=SystemExit(1))) as clean_tree:
            with self.assertRaises(SystemExit):
                agent.cmd_run(self.config)

        clean_tree.assert_called_once_with()

    def test_run_refuses_committed_plan_when_proposed_differs(self) -> None:
        state_dir = agent.ROOT / self.config["workflow"]["state_dir"]
        state_dir.mkdir(parents=True, exist_ok=True)
        agent.state_path(self.config, "task_file").write_text("# Task\n\nExisting task\n", encoding="utf-8")
        agent.state_path(self.config, "plan_file").write_text("# Approved plan\n", encoding="utf-8")
        (state_dir / "PLAN.proposed.md").write_text("# Different proposed plan\n", encoding="utf-8")

        with mock.patch.object(sys, "stderr", io.StringIO()), \
            mock.patch.object(agent, "require_clean_tree", mock.Mock(side_effect=AssertionError("should not check tree"))), \
            self.assertRaises(SystemExit):
            agent.cmd_run(self.config)

    def test_run_refuses_approved_plan_with_unresolved_decision(self) -> None:
        state_dir = agent.ROOT / self.config["workflow"]["state_dir"]
        state_dir.mkdir(parents=True, exist_ok=True)
        agent.state_path(self.config, "task_file").write_text("# Task\n\nExisting task\n", encoding="utf-8")
        agent.state_path(self.config, "plan_file").write_text(
            "# Approved plan\n\nHUMAN_DECISION_REQUIRED: choose behavior\n",
            encoding="utf-8",
        )

        with mock.patch.object(sys, "stderr", io.StringIO()), \
            mock.patch.object(agent, "require_clean_tree", mock.Mock(side_effect=AssertionError("should not check tree"))), \
            self.assertRaises(SystemExit):
            agent.cmd_run(self.config)

    def test_run_refuses_missing_task_before_clean_tree_gate(self) -> None:
        agent.state_path(self.config, "plan_file").parent.mkdir(parents=True, exist_ok=True)
        agent.state_path(self.config, "plan_file").write_text("# Approved plan\n", encoding="utf-8")

        with mock.patch.object(sys, "stderr", io.StringIO()), \
            mock.patch.object(agent, "require_clean_tree", mock.Mock(side_effect=AssertionError("should not check tree"))), \
            self.assertRaises(SystemExit):
            agent.cmd_run(self.config)

    def test_untracked_context_includes_new_file_contents(self) -> None:
        (self.root / "new-file.fnl").write_text("(print :new)\n", encoding="utf-8")

        with mock.patch.object(agent, "git", mock.Mock(return_value="new-file.fnl")):
            artifact = agent.write_untracked_context(self.root / "untracked.txt")

        text = artifact.read_text(encoding="utf-8")
        self.assertIn("## new-file.fnl", text)
        self.assertIn("(print :new)", text)

    def test_workflow_checkpoint_artifacts_exclude_state_file(self) -> None:
        state_dir = self.root / self.config["workflow"]["state_dir"]
        state_dir.mkdir(parents=True)
        for name in ("TASK.md", "PLAN.proposed.md", "PLAN.md", "STATE.json"):
            (state_dir / name).write_text(name, encoding="utf-8")

        paths = agent.workflow_artifact_paths(self.config)

        self.assertIn(".agent-workflow/TASK.md", paths)
        self.assertIn(".agent-workflow/PLAN.proposed.md", paths)
        self.assertIn(".agent-workflow/PLAN.md", paths)
        self.assertNotIn(".agent-workflow/STATE.json", paths)

    def test_checkpoint_allows_deleted_optional_exploration_artifact(self) -> None:
        task = agent.state_path(self.config, "task_file")
        task.parent.mkdir(parents=True, exist_ok=True)
        task.write_text("# Task\n\nExisting task\n", encoding="utf-8")
        calls = []

        def fake_git(*args, capture=True):
            calls.append(args)
            if args == ("rev-parse", "HEAD"):
                return "abc123def456"
            return ""

        class Result:
            returncode = 1

        with mock.patch.object(
            agent,
            "git_status_paths",
            mock.Mock(return_value={".agent-workflow/EXPLORATION.md", ".agent-workflow/TASK.md"}),
        ), mock.patch.object(agent, "git", fake_git), mock.patch.object(agent.subprocess, "run", mock.Mock(return_value=Result())):
            commit = agent.create_checkpoint_commit(self.config)

        self.assertEqual(commit, "abc123def456")
        self.assertIn(("add", "--", ".agent-workflow/EXPLORATION.md", ".agent-workflow/TASK.md"), calls)
        self.assertIn(("commit", "-m", "Approve agent plan: Existing task"), calls)

    def test_supervisor_fresh_session_captures_task_and_reaches_plan(self) -> None:
        def fake_plan(config, **kwargs) -> None:
            state = agent.ROOT / config["workflow"]["state_dir"]
            state.mkdir(parents=True, exist_ok=True)
            (state / "PLAN.proposed.md").write_text("# Proposed\n", encoding="utf-8")
            agent.update_workflow_state(config, phase="plan_proposed")

        with mock.patch.object(sys, "stdin", FakeStdin("Build the thing\n\nn\ne\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_plan", fake_plan), \
            mock.patch.object(agent, "cmd_explore", mock.Mock(side_effect=AssertionError("explore should not run"))):
            agent.cmd_supervise(self.config)

        task = agent.state_path(self.config, "task_file").read_text(encoding="utf-8")
        self.assertIn("Build the thing", task)
        self.assertEqual(agent.load_workflow_state(self.config)["phase"], "plan_proposed")

    def test_supervisor_resumes_approved_state_with_checkpoint_then_run(self) -> None:
        agent.save_workflow_state(self.config, {"phase": "approved"})
        task = agent.state_path(self.config, "task_file")
        task.parent.mkdir(parents=True, exist_ok=True)
        task.write_text("# Task\n\nExisting\n", encoding="utf-8")
        run = mock.Mock()

        with mock.patch.object(sys, "stdin", FakeStdin("", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "is_worktree_clean", mock.Mock(return_value=False)), \
            mock.patch.object(agent, "create_checkpoint_commit", mock.Mock(return_value="abc123def456")), \
            mock.patch.object(agent, "cmd_run", run):
            agent.cmd_supervise(self.config)

        run.assert_called_once_with(self.config)
        self.assertEqual(agent.load_workflow_state(self.config)["phase"], "ready_to_run")

    def test_supervisor_ready_for_human_test_can_be_accepted(self) -> None:
        agent.save_workflow_state(self.config, {"phase": "ready_for_human_test", "run_dir": ".agent-workflow/runs/1"})

        with mock.patch.object(sys, "stdin", FakeStdin("y\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()):
            agent.cmd_supervise(self.config)

        self.assertEqual(agent.load_workflow_state(self.config)["phase"], "human_accepted")

    def test_human_test_handoff_artifact_includes_validation_and_manual_checks(self) -> None:
        run = self.root / ".agent-workflow" / "runs" / "1"
        run.mkdir(parents=True)
        agent.state_path(self.config, "task_file").write_text("# Task\n\nBuild thing\n", encoding="utf-8")
        agent.state_path(self.config, "plan_file").write_text("# Objective\n\nDo it\n", encoding="utf-8")
        (run / "SUCCESS").write_text("Passed.\n", encoding="utf-8")
        (run / "validation.log").write_text("make build passed\n", encoding="utf-8")

        handoff = agent.write_human_test_handoff(self.config, {"run_dir": ".agent-workflow/runs/1"})

        self.assertIsNotNone(handoff)
        text = handoff.read_text(encoding="utf-8")
        self.assertIn("# Human Test Handoff", text)
        self.assertIn("make build passed", text)
        self.assertIn("Verify actual behavior", text)

    def test_limit_classification_requires_evidence_for_auto_wait(self) -> None:
        classified = agent.validate_limit_classification(
            {
                "classification": "short_retryable_limit",
                "wait_seconds": 60,
                "confidence": 0.9,
                "evidence": [],
                "summary": "looks temporary",
            }
        )

        self.assertEqual(classified["classification"], "unknown_model_limit")

    def test_opencode_limit_failure_saves_blocked_state_and_stderr(self) -> None:
        output = self.root / ".agent-workflow" / "stage.raw.txt"
        output.parent.mkdir(parents=True)

        class Result:
            returncode = 1

        def fake_run(command, **kwargs):
            kwargs["stderr"].write("rate limit reached; try again later\n")
            return Result()

        config = dict(self.config)
        config["models"] = dict(self.config["models"])
        config["models"].pop("supervisor")

        with mock.patch.object(agent.subprocess, "run", fake_run), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            self.assertRaises(SystemExit):
            agent.opencode(
                config=config,
                role="planner",
                title="Create proposed plan",
                output=output,
                prompt="plan",
                block_state={"resume_command": "plan"},
            )

        state = agent.load_workflow_state(config)
        self.assertEqual(state["phase"], "blocked_model_limit")
        self.assertEqual(state["resume_command"], "plan")
        stderr_path = self.root / state["blocked_stderr"]
        self.assertIn("rate limit reached", stderr_path.read_text(encoding="utf-8"))

    def test_initial_model_limit_failure_notifies_human(self) -> None:
        output = self.root / ".agent-workflow" / "stage.raw.txt"
        output.parent.mkdir(parents=True)
        stderr = output.with_name("stage.stderr.txt")
        output.write_text("", encoding="utf-8")
        stderr.write_text("rate limit reached\n", encoding="utf-8")
        error = agent.OpenCodeStageError(
            title="Create proposed plan",
            role="planner",
            model="test/planner",
            output=output,
            stderr=stderr,
            returncode=1,
        )
        notify = mock.Mock()

        with mock.patch.object(
            agent,
            "classify_model_failure",
            mock.Mock(
                return_value={
                    "classification": "unknown_model_limit",
                    "retry_at": None,
                    "wait_seconds": None,
                    "confidence": 0.5,
                    "evidence": ["rate limit reached"],
                    "summary": "blocked",
                }
            ),
        ), mock.patch.object(agent, "notify_human_required", notify), mock.patch.object(sys, "stdout", io.StringIO()):
            with self.assertRaises(SystemExit):
                agent.handle_opencode_stage_failure(self.config, error, {"resume_command": "plan"})

        notify.assert_called_once_with(self.config, "Agent Blocked", "Model/provider limit during Create proposed plan.")

    def test_short_model_limit_auto_wait_does_not_notify(self) -> None:
        output = self.root / ".agent-workflow" / "stage.raw.txt"
        output.parent.mkdir(parents=True)
        stderr = output.with_name("stage.stderr.txt")
        output.write_text("", encoding="utf-8")
        stderr.write_text("try again in one minute\n", encoding="utf-8")
        error = agent.OpenCodeStageError(
            title="Create proposed plan",
            role="planner",
            model="test/planner",
            output=output,
            stderr=stderr,
            returncode=1,
        )
        notify = mock.Mock(side_effect=AssertionError("should not notify during auto-wait"))

        with mock.patch.object(
            agent,
            "classify_model_failure",
            mock.Mock(
                return_value={
                    "classification": "short_retryable_limit",
                    "retry_at": None,
                    "wait_seconds": 60,
                    "confidence": 0.9,
                    "evidence": ["try again in one minute"],
                    "summary": "short wait",
                }
            ),
        ), mock.patch.object(agent, "notify_human_required", notify), \
            mock.patch.object(agent, "sleep_until_retry", mock.Mock()), \
            mock.patch.object(sys, "stdout", io.StringIO()):
            should_retry = agent.handle_opencode_stage_failure(self.config, error, {"resume_command": "plan"})

        self.assertTrue(should_retry)

    def test_supervisor_resumes_blocked_plan_after_retry_time(self) -> None:
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_model_limit",
                "resume_command": "plan",
                "blocked_stage": "Create proposed plan",
                "blocked_role": "planner",
                "blocked_model": "test/planner",
                "retry_at": "2000-01-01T00:00:00Z",
                "limit_classification": "short_retryable_limit",
                "wait_seconds": 1,
                "limit_evidence": ["try again later"],
            },
        )
        plan = mock.Mock()

        with mock.patch.object(sys, "stdin", FakeStdin("", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_plan", plan):
            agent.cmd_supervise(self.config)

        plan.assert_called_once_with(self.config, suggest_next=False)

    def test_optional_supervisor_failure_does_not_stop_workflow(self) -> None:
        config = dict(self.config)
        config["models"] = dict(self.config["models"])
        config["models"]["supervisor"] = "test/supervisor"
        output = self.root / ".agent-workflow" / "SUPERVISOR.plan.md"
        stderr = self.root / ".agent-workflow" / "SUPERVISOR.plan.stderr.md"

        def fail_once(**kwargs) -> None:
            raise agent.OpenCodeStageError(
                title=kwargs["title"],
                role="supervisor",
                model="test/supervisor",
                output=output,
                stderr=stderr,
                returncode=1,
            )

        with mock.patch.object(agent, "opencode_once", fail_once), mock.patch.object(sys, "stdout", io.StringIO()):
            result = agent.optional_supervisor(
                config=config,
                title="Supervisor plan summary",
                output=output,
                attachments=[],
                prompt="summarize",
            )

        self.assertIsNone(result)

    def test_successful_auto_retry_restores_previous_state(self) -> None:
        output = self.root / ".agent-workflow" / "PLAN.raw.txt"
        output.parent.mkdir(parents=True)
        error = agent.OpenCodeStageError(
            title="Create proposed plan",
            role="planner",
            model="test/planner",
            output=output,
            stderr=output.with_name("PLAN.raw.stderr.txt"),
            returncode=1,
        )
        calls = {"count": 0}

        def fake_once(**kwargs) -> None:
            calls["count"] += 1
            if calls["count"] == 1:
                raise error
            kwargs["output"].write_text("# Plan\n", encoding="utf-8")

        def fake_handle(config, stage_error, block_state) -> bool:
            agent.save_workflow_state(config, {"phase": "blocked_model_limit", "resume_command": "plan"})
            return True

        with mock.patch.object(agent, "opencode_once", fake_once), \
            mock.patch.object(agent, "handle_opencode_stage_failure", fake_handle):
            agent.opencode(
                config=self.config,
                role="planner",
                title="Create proposed plan",
                output=output,
                prompt="plan",
                block_state={"resume_command": "plan", "phase_before_block": "task_ready", "task_file": ".agent-workflow/TASK.md"},
            )

        state = agent.load_workflow_state(self.config)
        self.assertEqual(state["phase"], "task_ready")
        self.assertEqual(state["task_file"], ".agent-workflow/TASK.md")

    def test_unknown_limit_with_retry_at_does_not_auto_wait(self) -> None:
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_model_limit",
                "resume_command": "plan",
                "blocked_stage": "Create proposed plan",
                "blocked_role": "planner",
                "blocked_model": "test/planner",
                "limit_classification": "unknown_model_limit",
                "retry_at": agent.utc_timestamp_after(3600),
                "wait_seconds": 3600,
                "limit_evidence": ["try again in one hour"],
            },
        )

        with mock.patch.object(sys, "stdin", FakeStdin("", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "sleep_until_retry", mock.Mock(side_effect=AssertionError("should not sleep"))), \
            mock.patch.object(agent, "cmd_plan", mock.Mock(side_effect=AssertionError("should not retry"))):
            agent.cmd_supervise(self.config)

    def test_short_limit_with_saved_evidence_waits_and_retries(self) -> None:
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_model_limit",
                "resume_command": "plan",
                "blocked_stage": "Create proposed plan",
                "blocked_role": "planner",
                "blocked_model": "test/planner",
                "limit_classification": "short_retryable_limit",
                "retry_at": agent.utc_timestamp_after(3600),
                "wait_seconds": 3600,
                "limit_evidence": ["try again in one hour"],
            },
        )
        sleep = mock.Mock()
        plan = mock.Mock()

        with mock.patch.object(sys, "stdin", FakeStdin("y\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "sleep_until_retry", sleep), \
            mock.patch.object(agent, "cmd_plan", plan):
            agent.cmd_supervise(self.config)

        sleep.assert_called_once()
        plan.assert_called_once_with(self.config, suggest_next=False)

    def test_unknown_expired_retry_at_prompts_before_retrying(self) -> None:
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_model_limit",
                "resume_command": "plan",
                "blocked_stage": "Create proposed plan",
                "blocked_role": "planner",
                "blocked_model": "test/planner",
                "limit_classification": "unknown_model_limit",
                "retry_at": "2000-01-01T00:00:00Z",
                "wait_seconds": 1,
                "limit_evidence": ["try again later"],
            },
        )

        with mock.patch.object(sys, "stdin", FakeStdin("n\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_plan", mock.Mock(side_effect=AssertionError("should not retry"))):
            agent.cmd_supervise(self.config)

    def test_invalid_retry_at_prompts_before_retrying(self) -> None:
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_model_limit",
                "resume_command": "plan",
                "blocked_stage": "Create proposed plan",
                "blocked_role": "planner",
                "blocked_model": "test/planner",
                "limit_classification": "short_retryable_limit",
                "retry_at": "not-a-time",
                "wait_seconds": 1,
                "limit_evidence": ["try again later"],
            },
        )

        with mock.patch.object(sys, "stdin", FakeStdin("n\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_plan", mock.Mock(side_effect=AssertionError("should not retry"))):
            agent.cmd_supervise(self.config)

    def test_blocked_write_stage_does_not_call_run_resume(self) -> None:
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_model_limit",
                "resume_command": "run",
                "run_step": "implementation",
                "blocked_stage": "Initial implementation",
                "blocked_role": "implementer",
                "blocked_model": "test/implementer",
                "retry_at": "2000-01-01T00:00:00Z",
                "limit_classification": "short_retryable_limit",
                "wait_seconds": 1,
                "limit_evidence": ["try again later"],
            },
        )

        with mock.patch.object(sys, "stdin", FakeStdin("", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_run_resume", mock.Mock(side_effect=AssertionError("should not resume"))):
            agent.cmd_supervise(self.config)

    def test_cmd_run_blocked_write_stage_uses_resume_gate(self) -> None:
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_model_limit",
                "resume_command": "run",
                "run_step": "implementation",
                "blocked_stage": "Initial implementation",
                "blocked_role": "implementer",
                "blocked_model": "test/implementer",
                "retry_at": "2000-01-01T00:00:00Z",
                "limit_classification": "short_retryable_limit",
                "wait_seconds": 1,
                "limit_evidence": ["try again later"],
            },
        )

        with mock.patch.object(sys, "stdin", FakeStdin("", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_run_resume", mock.Mock(side_effect=AssertionError("should not resume"))), \
            mock.patch.object(agent, "require_clean_tree", mock.Mock(side_effect=AssertionError("should not start new run"))):
            agent.cmd_run(self.config)

    def test_cmd_run_unknown_expired_retry_at_prompts_before_resume(self) -> None:
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_model_limit",
                "resume_command": "run",
                "run_step": "full_review",
                "review_round": 1,
                "run_dir": ".agent-workflow/runs/1",
                "base_commit": "base",
                "blocked_stage": "Full review 1",
                "blocked_role": "reviewer",
                "blocked_model": "test/reviewer",
                "limit_classification": "unknown_model_limit",
                "retry_at": "2000-01-01T00:00:00Z",
                "wait_seconds": 1,
                "limit_evidence": ["try again later"],
            },
        )

        with mock.patch.object(sys, "stdin", FakeStdin("n\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_run_resume", mock.Mock(side_effect=AssertionError("should not resume"))), \
            mock.patch.object(agent, "require_clean_tree", mock.Mock(side_effect=AssertionError("should not start new run"))):
            agent.cmd_run(self.config)

    def test_cmd_run_future_short_retry_waits_before_resume(self) -> None:
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_model_limit",
                "resume_command": "run",
                "run_step": "full_review",
                "review_round": 1,
                "run_dir": ".agent-workflow/runs/1",
                "base_commit": "base",
                "blocked_stage": "Full review 1",
                "blocked_role": "reviewer",
                "blocked_model": "test/reviewer",
                "limit_classification": "short_retryable_limit",
                "retry_at": agent.utc_timestamp_after(3600),
                "wait_seconds": 3600,
                "limit_evidence": ["try again in one hour"],
            },
        )
        sleep = mock.Mock()
        resume = mock.Mock()

        with mock.patch.object(sys, "stdin", FakeStdin("y\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "sleep_until_retry", sleep), \
            mock.patch.object(agent, "cmd_run_resume", resume), \
            mock.patch.object(agent, "require_clean_tree", mock.Mock(side_effect=AssertionError("should not start new run"))):
            agent.cmd_run(self.config)

        sleep.assert_called_once()
        resume.assert_called_once()

    def test_supervisor_continues_blocked_review_budget(self) -> None:
        agent.save_workflow_state(
            self.config,
            {
                "phase": "blocked_review_budget",
                "resume_command": "run",
                "run_step": "full_review",
                "review_round": 2,
                "run_dir": ".agent-workflow/runs/1",
                "base_commit": "base",
                "budget_summary": "Review round budget exhausted.",
            },
        )
        resume = mock.Mock()

        with mock.patch.object(sys, "stdin", FakeStdin("y\n", tty=True)), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            mock.patch.object(agent, "cmd_run_resume", resume), \
            mock.patch.object(agent, "notify_human_required", mock.Mock()):
            agent.cmd_supervise(self.config)

        resume.assert_called_once()

    def test_run_resume_full_review_does_not_rerun_implementation(self) -> None:
        run = self.root / ".agent-workflow" / "runs" / "1"
        run.mkdir(parents=True)
        agent.state_path(self.config, "plan_file").write_text("# Plan\n", encoding="utf-8")
        calls = []
        notify = mock.Mock()

        def fake_opencode(**kwargs) -> None:
            calls.append((kwargs["role"], kwargs["title"]))
            kwargs["output"].write_text(json.dumps(self.review_pass()) + "\n", encoding="utf-8")

        with mock.patch.object(agent, "write_full_review_context", mock.Mock(return_value=[])), \
            mock.patch.object(agent, "opencode", fake_opencode), \
            mock.patch.object(agent, "extract_json", self.fake_extract_json), \
            mock.patch.object(agent, "run_commands", mock.Mock()), \
            mock.patch.object(agent, "notify_human_required", notify), \
            mock.patch.object(sys, "stdout", io.StringIO()):
            agent.cmd_run_resume(
                self.config,
                {"run_dir": ".agent-workflow/runs/1", "base_commit": "base", "run_step": "full_review", "review_round": 1},
            )

        self.assertEqual(calls, [("reviewer", "Full review 1")])
        self.assertEqual(agent.load_workflow_state(self.config)["phase"], "ready_for_human_test")
        notify.assert_called_once_with(
            self.config,
            "Ready For Human Test",
            "Automation passed. Perform final behavior review.",
        )

    def test_run_resume_adjudication_uses_existing_review(self) -> None:
        run = self.root / ".agent-workflow" / "runs" / "1"
        run.mkdir(parents=True)
        agent.state_path(self.config, "plan_file").write_text("# Plan\n", encoding="utf-8")
        self.write_json(run / "full-review-01.json", self.review_with_candidate())
        calls = []

        def fake_opencode(**kwargs) -> None:
            calls.append((kwargs["role"], kwargs["title"]))
            kwargs["output"].write_text(
                json.dumps(
                    {
                        "status": "no_action",
                        "summary": "reject",
                        "findings": [
                            {
                                "id": "R1-1",
                                "decision": "reject",
                                "reason": "not blocking",
                                "evidence": [],
                                "required_fix_scope": None,
                            }
                        ],
                    }
                )
                + "\n",
                encoding="utf-8",
            )

        with mock.patch.object(agent, "write_full_review_context", mock.Mock(return_value=[])), \
            mock.patch.object(agent, "opencode", fake_opencode), \
            mock.patch.object(agent, "extract_json", self.fake_extract_json), \
            mock.patch.object(agent, "run_commands", mock.Mock()), \
            mock.patch.object(sys, "stdout", io.StringIO()):
            agent.cmd_run_resume(
                self.config,
                {"run_dir": ".agent-workflow/runs/1", "base_commit": "base", "run_step": "adjudication", "review_round": 1},
            )

        self.assertEqual(calls, [("adjudicator", "Adjudicate review 1")])
        self.assertEqual(agent.load_workflow_state(self.config)["phase"], "ready_for_human_test")

    def test_review_budget_exhaustion_saves_resumable_state(self) -> None:
        run = self.root / ".agent-workflow" / "runs" / "1"
        run.mkdir(parents=True)
        agent.state_path(self.config, "plan_file").write_text("# Plan\n", encoding="utf-8")

        def fake_opencode(**kwargs) -> None:
            title = kwargs["title"]
            if title.startswith("Full review"):
                kwargs["output"].write_text(json.dumps(self.review_with_candidate()) + "\n", encoding="utf-8")
            elif title.startswith("Adjudicate"):
                kwargs["output"].write_text(
                    json.dumps(
                        {
                            "status": "ready_to_fix",
                            "summary": "accept",
                            "findings": [
                                {
                                    "id": "R1-1",
                                    "decision": "accept",
                                    "reason": "real",
                                    "evidence": ["src/example.cpp:1"],
                                    "required_fix_scope": "fix",
                                }
                            ],
                        }
                    )
                    + "\n",
                    encoding="utf-8",
                )
            elif title.startswith("Verify"):
                kwargs["output"].write_text(
                    json.dumps(
                        {
                            "mode": "verify",
                            "status": "verified",
                            "summary": "fixed",
                            "findings": [
                                {
                                    "id": "R1-1",
                                    "status": "verified_fixed",
                                    "reason": "fixed",
                                    "evidence": ["src/example.cpp:1"],
                                    "remaining_problem": None,
                                }
                            ],
                        }
                    )
                    + "\n",
                    encoding="utf-8",
                )
            else:
                kwargs["output"].write_text("fixed\n", encoding="utf-8")

        with mock.patch.object(agent, "write_full_review_context", mock.Mock(return_value=[])), \
            mock.patch.object(agent, "opencode", fake_opencode), \
            mock.patch.object(agent, "extract_json", self.fake_extract_json), \
            mock.patch.object(agent, "run_commands", mock.Mock()), \
            mock.patch.object(agent, "git", mock.Mock(return_value="diff\n")), \
            mock.patch.object(agent, "notify_human_required", mock.Mock()), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            self.assertRaises(SystemExit):
            agent.run_review_loop(self.config, run, "base", run / "validation.log")

        state = agent.load_workflow_state(self.config)
        self.assertEqual(state["phase"], "blocked_review_budget")
        self.assertEqual(state["run_step"], "full_review")
        self.assertEqual(state["review_round"], 2)

    def test_fix_budget_exhaustion_saves_resumable_state(self) -> None:
        run = self.root / ".agent-workflow" / "runs" / "1"
        run.mkdir(parents=True)
        agent.state_path(self.config, "plan_file").write_text("# Plan\n", encoding="utf-8")

        def fake_opencode(**kwargs) -> None:
            title = kwargs["title"]
            if title.startswith("Full review"):
                kwargs["output"].write_text(json.dumps(self.review_with_candidate()) + "\n", encoding="utf-8")
            elif title.startswith("Adjudicate"):
                kwargs["output"].write_text(
                    json.dumps(
                        {
                            "status": "ready_to_fix",
                            "summary": "accept",
                            "findings": [
                                {
                                    "id": "R1-1",
                                    "decision": "accept",
                                    "reason": "real",
                                    "evidence": ["src/example.cpp:1"],
                                    "required_fix_scope": "fix",
                                }
                            ],
                        }
                    )
                    + "\n",
                    encoding="utf-8",
                )
            elif title.startswith("Verify"):
                kwargs["output"].write_text(
                    json.dumps(
                        {
                            "mode": "verify",
                            "status": "fix_failed",
                            "summary": "still broken",
                            "findings": [
                                {
                                    "id": "R1-1",
                                    "status": "fix_failed",
                                    "reason": "still broken",
                                    "evidence": ["src/example.cpp:1"],
                                    "remaining_problem": "bug remains",
                                }
                            ],
                        }
                    )
                    + "\n",
                    encoding="utf-8",
                )
            else:
                kwargs["output"].write_text("fixed\n", encoding="utf-8")

        with mock.patch.object(agent, "write_full_review_context", mock.Mock(return_value=[])), \
            mock.patch.object(agent, "opencode", fake_opencode), \
            mock.patch.object(agent, "extract_json", self.fake_extract_json), \
            mock.patch.object(agent, "run_commands", mock.Mock()), \
            mock.patch.object(agent, "git", mock.Mock(return_value="diff\n")), \
            mock.patch.object(agent, "notify_human_required", mock.Mock()), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            self.assertRaises(SystemExit):
            agent.run_review_loop(self.config, run, "base", run / "validation.log")

        state = agent.load_workflow_state(self.config)
        self.assertEqual(state["phase"], "blocked_review_budget")
        self.assertEqual(state["run_step"], "fix")
        self.assertEqual(state["review_round"], 1)
        self.assertEqual(state["attempt"], 2)

    def test_run_resume_verification_skips_fix_attempt_and_continues_full_review(self) -> None:
        config = dict(self.config)
        config["workflow"] = dict(self.config["workflow"])
        config["workflow"]["review_round_budget"] = 2
        run = self.root / ".agent-workflow" / "runs" / "1"
        run.mkdir(parents=True)
        agent.state_path(config, "plan_file").write_text("# Plan\n", encoding="utf-8")
        self.write_json(run / "full-review-01.json", self.review_with_candidate())
        adjudication = {
            "status": "ready_to_fix",
            "summary": "accept",
            "findings": [
                {
                    "id": "R1-1",
                    "decision": "accept",
                    "reason": "real",
                    "evidence": ["src/example.cpp:1"],
                    "required_fix_scope": "fix",
                }
            ],
        }
        self.write_json(run / "adjudication-01.json", adjudication)
        self.write_json(run / "accepted-01.json", {"status": "ready_to_fix", "summary": "accept", "findings": adjudication["findings"]})
        (run / "before-fix-01-attempt-01.patch").write_text("diff\n", encoding="utf-8")
        calls = []

        def fake_opencode(**kwargs) -> None:
            calls.append((kwargs["role"], kwargs["title"]))
            if kwargs["title"].startswith("Verify fixes"):
                kwargs["output"].write_text(
                    json.dumps(
                        {
                            "mode": "verify",
                            "status": "verified",
                            "summary": "fixed",
                            "findings": [
                                {
                                    "id": "R1-1",
                                    "status": "verified_fixed",
                                    "reason": "fixed",
                                    "evidence": ["src/example.cpp:1"],
                                    "remaining_problem": None,
                                }
                            ],
                        }
                    )
                    + "\n",
                    encoding="utf-8",
                )
            else:
                kwargs["output"].write_text(json.dumps(self.review_pass()) + "\n", encoding="utf-8")

        with mock.patch.object(agent, "write_full_review_context", mock.Mock(return_value=[])), \
            mock.patch.object(agent, "opencode", fake_opencode), \
            mock.patch.object(agent, "extract_json", self.fake_extract_json), \
            mock.patch.object(agent, "run_commands", mock.Mock()), \
            mock.patch.object(sys, "stdout", io.StringIO()):
            agent.cmd_run_resume(
                config,
                {
                    "run_dir": ".agent-workflow/runs/1",
                    "base_commit": "base",
                    "run_step": "verification",
                    "review_round": 1,
                    "attempt": 1,
                },
            )

        self.assertEqual(calls, [("reviewer", "Verify fixes 1.1"), ("reviewer", "Full review 2")])
        self.assertNotIn(("fixer", "Fix review 1, attempt 1"), calls)
        self.assertEqual(agent.load_workflow_state(config)["phase"], "ready_for_human_test")

    def test_run_resume_verification_preserves_review_budget_end(self) -> None:
        config = dict(self.config)
        config["workflow"] = dict(self.config["workflow"])
        config["workflow"]["review_round_budget"] = 10
        run = self.root / ".agent-workflow" / "runs" / "1"
        run.mkdir(parents=True)
        agent.state_path(config, "plan_file").write_text("# Plan\n", encoding="utf-8")
        self.write_json(run / "full-review-01.json", self.review_with_candidate())
        adjudication = {
            "status": "ready_to_fix",
            "summary": "accept",
            "findings": [
                {
                    "id": "R1-1",
                    "decision": "accept",
                    "reason": "real",
                    "evidence": ["src/example.cpp:1"],
                    "required_fix_scope": "fix",
                }
            ],
        }
        self.write_json(run / "adjudication-01.json", adjudication)
        self.write_json(run / "accepted-01.json", {"status": "ready_to_fix", "summary": "accept", "findings": adjudication["findings"]})
        (run / "before-fix-01-attempt-01.patch").write_text("diff\n", encoding="utf-8")
        calls = []

        def fake_opencode(**kwargs) -> None:
            calls.append((kwargs["role"], kwargs["title"]))
            kwargs["output"].write_text(
                json.dumps(
                    {
                        "mode": "verify",
                        "status": "verified",
                        "summary": "fixed",
                        "findings": [
                            {
                                "id": "R1-1",
                                "status": "verified_fixed",
                                "reason": "fixed",
                                "evidence": ["src/example.cpp:1"],
                                "remaining_problem": None,
                            }
                        ],
                    }
                )
                + "\n",
                encoding="utf-8",
            )

        with mock.patch.object(agent, "write_full_review_context", mock.Mock(return_value=[])), \
            mock.patch.object(agent, "opencode", fake_opencode), \
            mock.patch.object(agent, "extract_json", self.fake_extract_json), \
            mock.patch.object(agent, "run_commands", mock.Mock()), \
            mock.patch.object(agent, "notify_human_required", mock.Mock()), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            self.assertRaises(SystemExit):
            agent.cmd_run_resume(
                config,
                {
                    "run_dir": ".agent-workflow/runs/1",
                    "base_commit": "base",
                    "run_step": "verification",
                    "review_round": 1,
                    "attempt": 1,
                    "review_budget_end": 1,
                    "fix_budget_end": 1,
                },
            )

        self.assertEqual(calls, [("reviewer", "Verify fixes 1.1")])
        state = agent.load_workflow_state(config)
        self.assertEqual(state["phase"], "blocked_review_budget")
        self.assertEqual(state["run_step"], "full_review")
        self.assertEqual(state["review_round"], 2)

    def test_run_resume_fix_preserves_fix_budget_end(self) -> None:
        config = dict(self.config)
        config["workflow"] = dict(self.config["workflow"])
        config["workflow"]["review_round_budget"] = 10
        config["workflow"]["fix_attempt_budget"] = 5
        run = self.root / ".agent-workflow" / "runs" / "1"
        run.mkdir(parents=True)
        agent.state_path(config, "plan_file").write_text("# Plan\n", encoding="utf-8")
        self.write_json(run / "full-review-01.json", self.review_with_candidate())
        adjudication = {
            "status": "ready_to_fix",
            "summary": "accept",
            "findings": [
                {
                    "id": "R1-1",
                    "decision": "accept",
                    "reason": "real",
                    "evidence": ["src/example.cpp:1"],
                    "required_fix_scope": "fix",
                }
            ],
        }
        self.write_json(run / "adjudication-01.json", adjudication)
        self.write_json(run / "accepted-01.json", {"status": "ready_to_fix", "summary": "accept", "findings": adjudication["findings"]})
        calls = []

        def fake_opencode(**kwargs) -> None:
            calls.append((kwargs["role"], kwargs["title"]))
            if kwargs["title"].startswith("Verify fixes"):
                kwargs["output"].write_text(
                    json.dumps(
                        {
                            "mode": "verify",
                            "status": "fix_failed",
                            "summary": "still broken",
                            "findings": [
                                {
                                    "id": "R1-1",
                                    "status": "fix_failed",
                                    "reason": "still broken",
                                    "evidence": ["src/example.cpp:1"],
                                    "remaining_problem": "bug remains",
                                }
                            ],
                        }
                    )
                    + "\n",
                    encoding="utf-8",
                )
            else:
                kwargs["output"].write_text("fixed\n", encoding="utf-8")

        with mock.patch.object(agent, "write_full_review_context", mock.Mock(return_value=[])), \
            mock.patch.object(agent, "opencode", fake_opencode), \
            mock.patch.object(agent, "extract_json", self.fake_extract_json), \
            mock.patch.object(agent, "run_commands", mock.Mock()), \
            mock.patch.object(agent, "git", mock.Mock(return_value="diff\n")), \
            mock.patch.object(agent, "notify_human_required", mock.Mock()), \
            mock.patch.object(sys, "stdout", io.StringIO()), \
            self.assertRaises(SystemExit):
            agent.cmd_run_resume(
                config,
                {
                    "run_dir": ".agent-workflow/runs/1",
                    "base_commit": "base",
                    "run_step": "fix",
                    "review_round": 1,
                    "attempt": 2,
                    "review_budget_end": 10,
                    "fix_budget_end": 2,
                },
            )

        self.assertEqual(calls, [("fixer", "Fix review 1, attempt 2"), ("reviewer", "Verify fixes 1.2")])
        state = agent.load_workflow_state(config)
        self.assertEqual(state["phase"], "blocked_review_budget")
        self.assertEqual(state["run_step"], "fix")
        self.assertEqual(state["attempt"], 3)

    def test_run_resume_rejects_review_budget_end_before_review_round(self) -> None:
        with mock.patch.object(agent, "run_review_loop", mock.Mock(side_effect=AssertionError("should not run"))), \
            mock.patch.object(sys, "stderr", io.StringIO()), \
            self.assertRaises(SystemExit):
            agent.cmd_run_resume(
                self.config,
                {
                    "run_dir": ".agent-workflow/runs/1",
                    "base_commit": "base",
                    "run_step": "full_review",
                    "review_round": 3,
                    "review_budget_end": 2,
                },
            )

    def test_run_resume_rejects_oversized_review_budget_end(self) -> None:
        with mock.patch.object(agent, "run_review_loop", mock.Mock(side_effect=AssertionError("should not run"))), \
            mock.patch.object(sys, "stderr", io.StringIO()), \
            self.assertRaises(SystemExit):
            agent.cmd_run_resume(
                self.config,
                {
                    "run_dir": ".agent-workflow/runs/1",
                    "base_commit": "base",
                    "run_step": "full_review",
                    "review_round": 1,
                    "review_budget_end": 2,
                },
            )

    def test_run_resume_rejects_fix_budget_end_before_attempt(self) -> None:
        with mock.patch.object(agent, "run_review_loop", mock.Mock(side_effect=AssertionError("should not run"))), \
            mock.patch.object(sys, "stderr", io.StringIO()), \
            self.assertRaises(SystemExit):
            agent.cmd_run_resume(
                self.config,
                {
                    "run_dir": ".agent-workflow/runs/1",
                    "base_commit": "base",
                    "run_step": "fix",
                    "review_round": 1,
                    "attempt": 4,
                    "fix_budget_end": 3,
                },
            )

    def test_run_resume_rejects_oversized_fix_budget_end(self) -> None:
        with mock.patch.object(agent, "run_review_loop", mock.Mock(side_effect=AssertionError("should not run"))), \
            mock.patch.object(sys, "stderr", io.StringIO()), \
            self.assertRaises(SystemExit):
            agent.cmd_run_resume(
                self.config,
                {
                    "run_dir": ".agent-workflow/runs/1",
                    "base_commit": "base",
                    "run_step": "fix",
                    "review_round": 1,
                    "attempt": 1,
                    "fix_budget_end": 2,
                },
            )

    def test_run_resume_verification_requires_before_fix_patch(self) -> None:
        run = self.root / ".agent-workflow" / "runs" / "1"
        run.mkdir(parents=True)
        agent.state_path(self.config, "plan_file").write_text("# Plan\n", encoding="utf-8")
        self.write_json(run / "full-review-01.json", self.review_with_candidate())
        adjudication = {
            "status": "ready_to_fix",
            "summary": "accept",
            "findings": [
                {
                    "id": "R1-1",
                    "decision": "accept",
                    "reason": "real",
                    "evidence": ["src/example.cpp:1"],
                    "required_fix_scope": "fix",
                }
            ],
        }
        self.write_json(run / "adjudication-01.json", adjudication)
        self.write_json(run / "accepted-01.json", {"status": "ready_to_fix", "summary": "accept", "findings": adjudication["findings"]})

        with mock.patch.object(agent, "write_full_review_context", mock.Mock(return_value=[])), \
            mock.patch.object(sys, "stderr", io.StringIO()), \
            self.assertRaises(SystemExit):
            agent.cmd_run_resume(
                self.config,
                {
                    "run_dir": ".agent-workflow/runs/1",
                    "base_commit": "base",
                    "run_step": "verification",
                    "review_round": 1,
                    "attempt": 1,
                },
            )


if __name__ == "__main__":
    unittest.main()
