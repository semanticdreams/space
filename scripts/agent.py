#!/usr/bin/env python3
"""OpenCode plan/implement/review/adjudicate workflow.

Uses only the Python standard library (Python 3.11+ for tomllib).
"""

from __future__ import annotations

import argparse
import calendar
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
import tomllib
from typing import Any, TextIO


ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "agent.toml"
TASK_TEMPLATE_SUFFIX = """

## Human constraints

- Preserve backward compatibility unless explicitly approved otherwise.
- Avoid unrelated refactoring.
""".lstrip()
MODEL_LIMIT_HINTS = (
    "429",
    "rate limit",
    "ratelimit",
    "quota",
    "usage limit",
    "too many requests",
    "model limit",
    "message limit",
    "weekly limit",
    "five-hour",
    "5-hour",
)
MODEL_LIMIT_CLASSIFICATIONS = {
    "short_retryable_limit",
    "long_or_weekly_limit",
    "unknown_model_limit",
    "not_model_limit",
    "classifier_failed",
}
DEFAULT_MAX_MODEL_LIMIT_WAIT_SECONDS = 6 * 60 * 60


class OpenCodeStageError(Exception):
    def __init__(
        self,
        *,
        title: str,
        role: str,
        model: str,
        output: Path,
        stderr: Path,
        returncode: int,
    ) -> None:
        super().__init__(title)
        self.title = title
        self.role = role
        self.model = model
        self.output = output
        self.stderr = stderr
        self.returncode = returncode


def die(message: str, code: int = 1) -> "NoReturn":
    print(f"agent: {message}", file=sys.stderr)
    raise SystemExit(code)


def load_config() -> dict[str, Any]:
    if not CONFIG_PATH.exists():
        die(f"missing {CONFIG_PATH}")
    with CONFIG_PATH.open("rb") as handle:
        return tomllib.load(handle)


def state_path(config: dict[str, Any], key: str) -> Path:
    return ROOT / config["workflow"][key]


def workflow_state_path(config: dict[str, Any]) -> Path:
    configured = config["workflow"].get("state_file")
    if configured:
        return ROOT / configured
    return ROOT / config["workflow"]["state_dir"] / "STATE.json"


def load_workflow_state(config: dict[str, Any]) -> dict[str, Any]:
    path = workflow_state_path(config)
    if not path.exists():
        return {"phase": "new"}
    with path.open(encoding="utf-8") as handle:
        state = json.load(handle)
    if not isinstance(state, dict):
        die(f"workflow state must be a JSON object: {path}")
    state.setdefault("phase", "new")
    return state


def save_workflow_state(config: dict[str, Any], state: dict[str, Any]) -> None:
    path = workflow_state_path(config)
    path.parent.mkdir(parents=True, exist_ok=True)
    state = dict(state)
    state["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def update_workflow_state(config: dict[str, Any], **updates: Any) -> None:
    state = load_workflow_state(config)
    state.update(updates)
    save_workflow_state(config, state)


def normalize_task_text(text: str) -> str:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    return "\n".join(line.rstrip() for line in normalized.split("\n")).strip()


def task_markdown(task_text: str) -> str:
    return f"# Task\n\n{task_text}\n\n{TASK_TEMPLATE_SUFFIX}"


def write_task_file(path: Path, task_text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(task_markdown(task_text), encoding="utf-8")
    temporary.replace(path)


def read_yes_no(
    prompt: str,
    *,
    default: bool,
    stdin: TextIO | None = None,
    stdout: TextIO | None = None,
) -> bool:
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    suffix = " [Y/n] " if default else " [y/N] "
    stdout.write(prompt + suffix)
    stdout.flush()
    answer = stdin.readline()
    if answer == "":
        return default
    answer = answer.strip().lower()
    if not answer:
        return default
    return answer in {"y", "yes"}


def read_approval_choice(stdin: TextIO | None = None, stdout: TextIO | None = None) -> str:
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    while True:
        stdout.write("Approve plan? [y]es / [e]dit externally / [c]ancel ")
        stdout.flush()
        answer = stdin.readline()
        if answer == "":
            return "c"
        answer = answer.strip().lower()
        if answer in {"y", "yes"}:
            return "y"
        if answer in {"e", "edit"}:
            return "e"
        if answer in {"c", "cancel"}:
            return "c"
        stdout.write("Please answer y, e, or c.\n")


def read_task_interactively(stdin: TextIO | None = None, stdout: TextIO | None = None) -> str:
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    stdout.write("Describe the task:\n")
    stdout.flush()
    return stdin.read()


def acquire_task_text(
    task_path: Path,
    task_args: list[str],
    *,
    allow_reuse: bool,
    stdin: TextIO | None = None,
    stdout: TextIO | None = None,
) -> str | None:
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    if task_args:
        task_text = normalize_task_text(" ".join(task_args))
        if not task_text:
            die("task text is empty")
        write_task_file(task_path, task_text)
        return task_text

    if not stdin.isatty():
        task_text = normalize_task_text(stdin.read())
        if not task_text:
            die("task text is empty; pass a task argument or pipe non-empty input")
        write_task_file(task_path, task_text)
        return task_text

    if allow_reuse and task_path.exists() and read_yes_no(
        f"Reuse the existing task from {task_path.relative_to(ROOT)}?",
        default=True,
        stdin=stdin,
        stdout=stdout,
    ):
        return None

    task_text = normalize_task_text(read_task_interactively(stdin, stdout))
    if not task_text:
        die("task text is empty")
    write_task_file(task_path, task_text)
    return task_text


def run_dir(config: dict[str, Any]) -> Path:
    base = ROOT / config["workflow"]["state_dir"] / "runs"
    base.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    candidate = base / stamp
    counter = 1
    while candidate.exists():
        candidate = base / f"{stamp}-{counter}"
        counter += 1
    candidate.mkdir(parents=True)
    return candidate


def notification_command(value: Any) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        return []
    return value


def launch_notification_command(command: list[str]) -> None:
    if not command or shutil.which(command[0]) is None:
        return
    try:
        subprocess.Popen(
            command,
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        return


def notify_human_required(config: dict[str, Any], title: str, message: str) -> None:
    notifications = config.get("notifications", {})
    if not isinstance(notifications, dict) or notifications.get("enabled", False) is not True:
        return

    sound = notification_command(notifications.get("sound"))
    desktop = notification_command(notifications.get("desktop"))
    launch_notification_command(sound)
    if desktop:
        launch_notification_command([*desktop, title, message])


def require_tools() -> None:
    for tool in ("opencode", "git"):
        if shutil.which(tool) is None:
            die(f"required executable not found: {tool}")
    if sys.version_info < (3, 11):
        die("Python 3.11 or newer is required")


def git(*args: str, capture: bool = True) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    if result.returncode != 0:
        detail = (result.stderr or "").strip()
        die(f"git {' '.join(args)} failed: {detail}")
    return (result.stdout or "").strip()


def git_status_paths() -> set[str]:
    paths: set[str] = set()
    for line in git("status", "--porcelain").splitlines():
        if not line:
            continue
        path = line[3:]
        if " -> " in path:
            _, path = path.split(" -> ", 1)
        paths.add(path)
    return paths


def workflow_artifact_paths(config: dict[str, Any]) -> set[str]:
    state_dir = ROOT / config["workflow"]["state_dir"]
    candidates = {
        state_path(config, "task_file"),
        state_path(config, "exploration_file"),
        state_path(config, "plan_file"),
        state_dir / "PLAN.proposed.md",
    }
    return {
        str(path.relative_to(ROOT))
        for path in candidates
    }


def task_derived_artifact_paths(config: dict[str, Any]) -> list[Path]:
    state_dir = ROOT / config["workflow"]["state_dir"]
    return [
        state_path(config, "exploration_file"),
        state_path(config, "plan_file"),
        state_dir / "PLAN.proposed.md",
    ]


def reset_task_derived_artifacts(config: dict[str, Any]) -> None:
    for path in task_derived_artifact_paths(config):
        path.unlink(missing_ok=True)


def save_task_ready_state(config: dict[str, Any], task: Path) -> None:
    save_workflow_state(config, {"phase": "task_ready", "task_file": str(task.relative_to(ROOT))})


def proposed_plan_path(config: dict[str, Any]) -> Path:
    return ROOT / config["workflow"]["state_dir"] / "PLAN.proposed.md"


def require_current_plan_for_run(config: dict[str, Any], state: dict[str, Any]) -> None:
    phase = state.get("phase", "new")
    task = state_path(config, "task_file")
    plan = state_path(config, "plan_file")
    if not task.exists():
        die(f"missing task file: {task}")
    if not plan.exists():
        die(f"missing approved plan: {plan}")
    if "HUMAN_DECISION_REQUIRED" in plan.read_text(encoding="utf-8"):
        die("approved plan still contains HUMAN_DECISION_REQUIRED; resolve it before running")

    if phase in {"approved", "ready_to_run"}:
        return

    proposed = proposed_plan_path(config)
    if phase == "new":
        if proposed.exists() and proposed.read_text(encoding="utf-8") != plan.read_text(encoding="utf-8"):
            die("run requires an approved current plan; PLAN.proposed.md differs from PLAN.md")
        return

    die("run requires an approved current plan; run `scripts/agent approve-plan` first")


def create_checkpoint_commit(config: dict[str, Any]) -> str | None:
    allowed = workflow_artifact_paths(config)
    dirty = git_status_paths()
    unrelated = dirty - allowed
    if unrelated:
        die(
            "cannot create workflow checkpoint with unrelated dirty files: "
            + ", ".join(sorted(unrelated))
        )
    if not dirty:
        return None

    workflow_dirty = dirty & allowed
    git("add", "--", *sorted(workflow_dirty), capture=False)
    staged = subprocess.run(
        ["git", "diff", "--cached", "--quiet", "--", *sorted(workflow_dirty)],
        cwd=ROOT,
        check=False,
    )
    if staged.returncode == 0:
        return None

    task = task_body_from_file(state_path(config, "task_file"))
    summary = task.splitlines()[0] if task else "agent workflow"
    message = f"Approve agent plan: {summary[:60]}"
    git("commit", "-m", message, capture=False)
    return git("rev-parse", "HEAD")


def require_git_repo() -> None:
    if git("rev-parse", "--is-inside-work-tree") != "true":
        die("run this inside a Git worktree")


def require_clean_tree() -> None:
    status = git("status", "--porcelain")
    if status:
        die(
            "working tree must be clean before `run`; commit the agent files, "
            "PLAN.md, and any existing work first"
        )


def is_worktree_clean() -> bool:
    return git("status", "--porcelain") == ""


def opencode_stderr_path(output: Path) -> Path:
    if output.suffix:
        return output.with_name(f"{output.stem}.stderr{output.suffix}")
    return output.with_name(f"{output.name}.stderr.txt")


def opencode_once(
    *,
    config: dict[str, Any],
    role: str,
    prompt: str,
    title: str,
    output: Path,
    attachments: list[Path] | None = None,
) -> None:
    model = str(config["models"][role])
    if str(model).startswith("REPLACE_WITH_"):
        die(
            f"configure models.{role} in agent.toml; "
            "use `opencode models --refresh` for exact identifiers"
        )
    command = [
        "opencode",
        "run",
        "--agent",
        role,
        "--model",
        model,
        "--title",
        title,
    ]
    for attachment in attachments or []:
        command.extend(["--file", str(attachment)])
    command.append(prompt)

    print(f"\n=== {title} ===")
    print(f"agent={role} model={model}")
    stderr_path = opencode_stderr_path(output)
    with output.open("w", encoding="utf-8") as handle:
        with stderr_path.open("w", encoding="utf-8") as error_handle:
            result = subprocess.run(
                command,
                cwd=ROOT,
                text=True,
                stdout=handle,
                stderr=error_handle,
                check=False,
            )
    if result.returncode != 0:
        raise OpenCodeStageError(
            title=title,
            role=role,
            model=model,
            output=output,
            stderr=stderr_path,
            returncode=result.returncode,
        )
    stderr_path.unlink(missing_ok=True)


def opencode(
    *,
    config: dict[str, Any],
    role: str,
    prompt: str,
    title: str,
    output: Path,
    attachments: list[Path] | None = None,
    block_state: dict[str, Any] | None = None,
) -> None:
    retried_after_limit = False
    while True:
        try:
            opencode_once(
                config=config,
                role=role,
                prompt=prompt,
                title=title,
                output=output,
                attachments=attachments,
            )
            if retried_after_limit:
                restore_after_limit_retry(config, block_state)
            return
        except OpenCodeStageError as error:
            if handle_opencode_stage_failure(config, error, block_state):
                retried_after_limit = True
                continue
            die(f"OpenCode stage failed: {title}; stderr: {error.stderr}")


def role_model_configured(config: dict[str, Any], role: str) -> bool:
    model = config.get("models", {}).get(role)
    return bool(model) and not str(model).startswith("REPLACE_WITH_")


def utc_timestamp_after(seconds: int) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + seconds))


def seconds_until(timestamp: str) -> int | None:
    try:
        parsed = time.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None
    return max(0, int(calendar.timegm(parsed) - time.time()))


def read_artifact_text(path: Path, *, max_chars: int = 12000) -> str:
    if not path.exists():
        return ""
    text = path.read_text(encoding="utf-8", errors="replace")
    if len(text) <= max_chars:
        return text
    return text[-max_chars:]


def model_limit_hint_present(text: str) -> bool:
    lowered = text.lower()
    return any(hint in lowered for hint in MODEL_LIMIT_HINTS)


def should_auto_wait_for_limit(config: dict[str, Any], classification: dict[str, Any]) -> bool:
    wait_seconds = classification.get("wait_seconds")
    evidence = classification.get("evidence")
    return (
        classification.get("classification") == "short_retryable_limit"
        and isinstance(wait_seconds, int)
        and wait_seconds <= max_model_limit_wait_seconds(config)
        and isinstance(evidence, list)
        and bool(evidence)
    )


def normalized_saved_limit_state(state: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(state)
    if "classification" not in normalized and isinstance(state.get("limit_classification"), str):
        normalized["classification"] = state["limit_classification"]
    if "summary" not in normalized and isinstance(state.get("limit_summary"), str):
        normalized["summary"] = state["limit_summary"]
    if "evidence" not in normalized and isinstance(state.get("limit_evidence"), list):
        normalized["evidence"] = state["limit_evidence"]
    return validate_limit_classification(normalized)


def validate_limit_classification(value: dict[str, Any]) -> dict[str, Any]:
    classification = value.get("classification")
    if classification not in MODEL_LIMIT_CLASSIFICATIONS:
        classification = "classifier_failed"
    evidence = value.get("evidence")
    if not isinstance(evidence, list) or not all(isinstance(item, str) for item in evidence):
        evidence = []
    summary = value.get("summary")
    if not isinstance(summary, str):
        summary = ""
    confidence = value.get("confidence")
    if isinstance(confidence, bool) or not isinstance(confidence, int | float):
        confidence = 0.0
    confidence = max(0.0, min(1.0, float(confidence)))
    wait_seconds = value.get("wait_seconds")
    if isinstance(wait_seconds, bool) or not isinstance(wait_seconds, int) or wait_seconds < 0:
        wait_seconds = None
    retry_at = value.get("retry_at")
    if retry_at is not None and not isinstance(retry_at, str):
        retry_at = None

    # Never auto-wait on an inferred reset. The model must quote evidence and
    # provide a bounded wait value from the failure text.
    if classification == "short_retryable_limit" and (wait_seconds is None or not evidence):
        classification = "unknown_model_limit"

    return {
        "classification": classification,
        "retry_at": retry_at,
        "wait_seconds": wait_seconds,
        "confidence": confidence,
        "evidence": evidence,
        "summary": summary,
    }


def fallback_limit_classification(error_text: str) -> dict[str, Any]:
    if not model_limit_hint_present(error_text):
        return validate_limit_classification(
            {
                "classification": "not_model_limit",
                "confidence": 0.6,
                "evidence": [],
                "summary": "Failure text does not look like a model usage limit.",
            }
        )
    return validate_limit_classification(
        {
            "classification": "unknown_model_limit",
            "confidence": 0.5,
            "evidence": [],
            "summary": "Failure text looks limit-related, but no reset time was classified.",
        }
    )


def classify_model_failure(config: dict[str, Any], error: OpenCodeStageError) -> dict[str, Any]:
    error_text = "\n".join(
        [
            f"role={error.role}",
            f"model={error.model}",
            f"stage={error.title}",
            read_artifact_text(error.output),
            read_artifact_text(error.stderr),
        ]
    )
    if not model_limit_hint_present(error_text):
        return fallback_limit_classification(error_text)
    if not role_model_configured(config, "supervisor"):
        return fallback_limit_classification(error_text)

    state_dir = ROOT / config["workflow"]["state_dir"]
    state_dir.mkdir(parents=True, exist_ok=True)
    source = error.stderr.with_name(f"{error.stderr.stem}.limit-input.txt")
    raw = error.stderr.with_name(f"{error.stderr.stem}.limit-classifier.raw.txt")
    parsed = error.stderr.with_name(f"{error.stderr.stem}.limit-classifier.json")
    source.write_text(error_text, encoding="utf-8")
    try:
        opencode_once(
            config=config,
            role="supervisor",
            title=f"Classify model-limit failure: {error.title}",
            output=raw,
            attachments=[source],
            prompt=(
                "Classify the attached OpenCode failure output. Return only one "
                "valid JSON object with keys classification, retry_at, wait_seconds, "
                "confidence, evidence, and summary. Allowed classification values: "
                "short_retryable_limit, long_or_weekly_limit, unknown_model_limit, "
                "not_model_limit. Only use short_retryable_limit when the text "
                "explicitly says when to retry or how long to wait. Do not invent "
                "reset times. evidence must quote the exact relevant text."
            ),
        )
        classified = extract_json(raw, parsed, ["classification", "evidence", "summary"])
        return validate_limit_classification(classified)
    except (OpenCodeStageError, SystemExit, json.JSONDecodeError):
        fallback = fallback_limit_classification(error_text)
        fallback["classification"] = "classifier_failed" if fallback["classification"] != "not_model_limit" else "not_model_limit"
        fallback["summary"] = "Supervisor classifier failed; stopping for manual resume."
        return validate_limit_classification(fallback)


def max_model_limit_wait_seconds(config: dict[str, Any]) -> int:
    value = config.get("workflow", {}).get("max_model_limit_wait_seconds")
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return DEFAULT_MAX_MODEL_LIMIT_WAIT_SECONDS
    return value


def sleep_until_retry(wait_seconds: int) -> None:
    end = time.time() + wait_seconds
    while True:
        remaining = int(end - time.time())
        if remaining <= 0:
            return
        print(f"Waiting for model limit reset: {remaining} second(s) remaining. Ctrl-C stops safely.")
        time.sleep(min(remaining, 300))


def save_blocked_model_limit_state(
    config: dict[str, Any],
    error: OpenCodeStageError,
    classification: dict[str, Any],
    block_state: dict[str, Any] | None,
) -> None:
    state = dict(block_state or {})
    wait_seconds = classification.get("wait_seconds")
    retry_at = classification.get("retry_at")
    if not retry_at and should_auto_wait_for_limit(config, classification) and isinstance(wait_seconds, int):
        retry_at = utc_timestamp_after(wait_seconds)
    state.update(
        {
            "phase": "blocked_model_limit",
            "blocked_role": error.role,
            "blocked_model": error.model,
            "blocked_stage": error.title,
            "blocked_output": str(error.output.relative_to(ROOT)),
            "blocked_stderr": str(error.stderr.relative_to(ROOT)),
            "limit_classification": classification.get("classification"),
            "limit_summary": classification.get("summary"),
            "limit_evidence": classification.get("evidence", []),
        }
    )
    if retry_at:
        state["retry_at"] = retry_at
    if isinstance(wait_seconds, int):
        state["wait_seconds"] = wait_seconds
    save_workflow_state(config, state)


def restore_after_limit_retry(config: dict[str, Any], block_state: dict[str, Any] | None) -> None:
    current = load_workflow_state(config)
    if current.get("phase") != "blocked_model_limit":
        return
    if not block_state:
        save_workflow_state(config, {"phase": "new"})
        return

    phase = block_state.get("phase_before_block")
    if not isinstance(phase, str):
        phase = "running" if block_state.get("resume_command") == "run" else "task_ready"
    restored: dict[str, Any] = {"phase": phase}
    for key in ("task_file", "run_dir", "base_commit", "checkpoint_commit"):
        if isinstance(block_state.get(key), str):
            restored[key] = block_state[key]
    save_workflow_state(config, restored)


def handle_opencode_stage_failure(
    config: dict[str, Any],
    error: OpenCodeStageError,
    block_state: dict[str, Any] | None,
) -> bool:
    classification = classify_model_failure(config, error)
    if classification["classification"] == "not_model_limit":
        return False

    save_blocked_model_limit_state(config, error, classification, block_state)
    print(f"\nOpenCode stage hit a model/provider limit: {error.title}")
    print(f"role={error.role} model={error.model}")
    print(f"stderr: {error.stderr}")
    print(f"classification: {classification['classification']}")
    if classification.get("summary"):
        print(classification["summary"])

    wait_seconds = classification.get("wait_seconds")
    if should_auto_wait_for_limit(config, classification):
        try:
            sleep_until_retry(int(wait_seconds))
        except KeyboardInterrupt:
            print("Stopped while waiting. Run scripts/agent to resume when the limit resets.")
            raise SystemExit(4)
        return True

    notify_human_required(config, "Agent Blocked", f"Model/provider limit during {error.title}.")
    print("Workflow state is saved as blocked_model_limit. Run scripts/agent to resume after the limit resets.")
    raise SystemExit(4)


def optional_supervisor(
    *,
    config: dict[str, Any],
    title: str,
    output: Path,
    attachments: list[Path] | None,
    prompt: str,
) -> Path | None:
    if not role_model_configured(config, "supervisor"):
        return None
    try:
        opencode_once(
            config=config,
            role="supervisor",
            title=title,
            output=output,
            attachments=[path for path in attachments or [] if path.exists()],
            prompt=prompt,
        )
    except OpenCodeStageError as error:
        print(f"Warning: optional supervisor summary failed; stderr: {error.stderr}")
        return None
    print_artifact_excerpt(output, title)
    return output


def extract_json(source: Path, destination: Path, required: list[str]) -> dict[str, Any]:
    command = [
        sys.executable,
        str(ROOT / "scripts" / "extract_json.py"),
        str(source),
        str(destination),
    ]
    for key in required:
        command.extend(["--require", key])
    result = subprocess.run(command, cwd=ROOT, check=False)
    if result.returncode != 0:
        die(f"could not parse structured output from {source}")
    with destination.open(encoding="utf-8") as handle:
        return json.load(handle)


def read_json_artifact(path: Path, label: str) -> dict[str, Any]:
    if not path.exists():
        die(f"missing {label} artifact for resume: {path}")
    try:
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError as error:
        die(f"corrupt {label} artifact for resume: {path}: {error}")
    if not isinstance(data, dict):
        die(f"malformed {label} artifact for resume: {path}: expected JSON object")
    return data


def require_string(value: dict[str, Any], key: str, path: Path) -> None:
    if not isinstance(value.get(key), str):
        die(f"malformed structured output in {path}: {key} must be a string")


def require_string_or_null(value: dict[str, Any], key: str, path: Path) -> None:
    item = value.get(key)
    if item is not None and not isinstance(item, str):
        die(f"malformed structured output in {path}: {key} must be a string or null")


def require_string_list(value: dict[str, Any], key: str, path: Path) -> None:
    items = value.get(key)
    if not isinstance(items, list) or not all(isinstance(item, str) for item in items):
        die(f"malformed structured output in {path}: {key} must be a string array")


def require_unique_ids(items: list[dict[str, Any]], path: Path) -> set[str]:
    ids: set[str] = set()
    for item in items:
        item_id = item.get("id")
        if not isinstance(item_id, str) or not item_id:
            die(f"malformed structured output in {path}: finding id must be a non-empty string")
        if item_id in ids:
            die(f"malformed structured output in {path}: duplicate finding id {item_id}")
        ids.add(item_id)
    return ids


def validate_full_review(review: dict[str, Any], path: Path) -> None:
    if review.get("mode") != "full":
        die(f"malformed structured output in {path}: mode must be full")
    if review.get("status") not in {"pass", "candidates_found", "requires_human"}:
        die(f"malformed structured output in {path}: invalid review status")
    require_string(review, "summary", path)
    candidates = review.get("candidate_findings")
    if not isinstance(candidates, list) or not all(isinstance(item, dict) for item in candidates):
        die(f"malformed structured output in {path}: candidate_findings must be an object array")
    if review["status"] == "pass" and candidates:
        die(f"malformed structured output in {path}: pass status cannot include candidate findings")
    if review["status"] == "candidates_found" and not candidates:
        die(f"malformed structured output in {path}: candidates_found requires candidate findings")

    require_unique_ids(candidates, path)
    for item in candidates:
        if item.get("category") not in {
            "correctness",
            "security",
            "data_integrity",
            "concurrency",
            "compatibility",
            "api_contract",
            "performance",
            "testing",
            "design_integrity",
            "documentation",
            "validation",
        }:
            die(f"malformed structured output in {path}: invalid finding category")
        if item.get("severity") not in {"critical", "high", "medium"}:
            die(f"malformed structured output in {path}: invalid finding severity")
        confidence = item.get("confidence")
        if isinstance(confidence, bool) or not isinstance(confidence, int | float) or confidence < 0 or confidence > 1:
            die(f"malformed structured output in {path}: confidence must be between 0 and 1")
        require_string_or_null(item, "plan_requirement", path)
        require_string(item, "file", path)
        if isinstance(item.get("line"), bool) or not isinstance(item.get("line"), int):
            die(f"malformed structured output in {path}: line must be an integer")
        for key in ("scenario", "expected", "actual", "impact", "smallest_required_fix"):
            require_string(item, key, path)
        require_string_list(item, "evidence", path)


def validate_adjudication(adjudication: dict[str, Any], candidate_ids: set[str], path: Path) -> None:
    if adjudication.get("status") not in {"ready_to_fix", "no_action", "requires_human"}:
        die(f"malformed structured output in {path}: invalid adjudication status")
    require_string(adjudication, "summary", path)
    findings = adjudication.get("findings")
    if not isinstance(findings, list) or not all(isinstance(item, dict) for item in findings):
        die(f"malformed structured output in {path}: findings must be an object array")
    finding_ids = require_unique_ids(findings, path)
    if finding_ids != candidate_ids:
        die(f"malformed structured output in {path}: adjudication must cover every candidate finding exactly once")

    decisions = set()
    for item in findings:
        decision = item.get("decision")
        if decision not in {"accept", "reject", "escalate"}:
            die(f"malformed structured output in {path}: invalid adjudication decision")
        decisions.add(decision)
        require_string(item, "reason", path)
        require_string_list(item, "evidence", path)
        require_string_or_null(item, "required_fix_scope", path)

    status = adjudication["status"]
    if "escalate" in decisions:
        if status != "requires_human":
            die(f"malformed structured output in {path}: escalated findings require requires_human status")
    elif "accept" in decisions and status != "ready_to_fix":
        die(f"malformed structured output in {path}: accepted findings require ready_to_fix status")
    elif decisions <= {"reject"} and status != "no_action":
        die(f"malformed structured output in {path}: rejected-only adjudication requires no_action status")


def validate_verification(verification: dict[str, Any], expected_ids: set[str], path: Path) -> None:
    if verification.get("mode") != "verify":
        die(f"malformed structured output in {path}: mode must be verify")
    if verification.get("status") not in {"verified", "fix_failed", "requires_human"}:
        die(f"malformed structured output in {path}: invalid verification status")
    require_string(verification, "summary", path)
    findings = verification.get("findings")
    if not isinstance(findings, list) or not all(isinstance(item, dict) for item in findings):
        die(f"malformed structured output in {path}: findings must be an object array")
    finding_ids = require_unique_ids(findings, path)
    if finding_ids != expected_ids:
        die(f"malformed structured output in {path}: verification must cover every accepted finding exactly once")

    statuses = set()
    for item in findings:
        status = item.get("status")
        if status not in {"verified_fixed", "fix_failed", "cannot_verify"}:
            die(f"malformed structured output in {path}: invalid finding verification status")
        statuses.add(status)
        require_string(item, "reason", path)
        require_string_list(item, "evidence", path)
        require_string_or_null(item, "remaining_problem", path)

    status = verification["status"]
    if "cannot_verify" in statuses:
        if status != "requires_human":
            die(f"malformed structured output in {path}: cannot_verify requires requires_human status")
    elif statuses == {"verified_fixed"} and status != "verified":
        die(f"malformed structured output in {path}: all-fixed verification requires verified status")
    elif "fix_failed" in statuses and status != "fix_failed":
        die(f"malformed structured output in {path}: fix_failed findings require fix_failed status")


def save_blocked_validation_state(
    config: dict[str, Any],
    stage: str,
    command: str,
    log: Path,
    block_state: dict[str, Any] | None,
    remaining_commands: list[str],
) -> None:
    state = dict(block_state or {})
    state.update(
        {
            "phase": "blocked_validation",
            "validation_stage": stage,
            "validation_command": command,
            "validation_log": str(log.relative_to(ROOT)),
            "validation_remaining_commands": remaining_commands,
        }
    )
    save_workflow_state(config, state)
    notify_human_required(config, "Validation Failed", f"Validation failed during {stage}: {command}")
    die(f"validation command failed ({stage}): {command}; see {log}")


def run_commands(
    config: dict[str, Any],
    commands: list[str],
    stage: str,
    log: Path,
    block_state: dict[str, Any] | None = None,
) -> None:
    if not commands:
        print(f"\n=== Validation: {stage} (no external commands configured) ===")
        return

    print(f"\n=== Validation: {stage} ===")
    with log.open("a", encoding="utf-8") as handle:
        for index, command in enumerate(commands):
            print(f"+ {command}")
            handle.write(f"\n$ {command}\n")
            handle.flush()
            result = subprocess.run(
                command,
                cwd=ROOT,
                shell=True,
                executable="/bin/bash",
                stdout=handle,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                save_blocked_validation_state(config, stage, command, log, block_state, commands[index:])


def parse_positive_state_int(state: dict[str, Any], key: str, default: int | None = None) -> int | None:
    if key not in state:
        return default
    value = state[key]
    if isinstance(value, bool):
        die(f"blocked run state has invalid {key}; inspect STATE.json")
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        die(f"blocked run state has invalid {key}; inspect STATE.json")
    if parsed < 1:
        die(f"blocked run state has invalid {key}; inspect STATE.json")
    return parsed


def parse_positive_config_int(config: dict[str, Any], key: str) -> int:
    value = config.get("workflow", {}).get(key)
    if isinstance(value, bool):
        die(f"workflow config has invalid {key}")
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        die(f"workflow config has invalid {key}")
    if parsed < 1:
        die(f"workflow config has invalid {key}")
    return parsed


def cmd_explore(config: dict[str, Any], task_args: list[str] | None = None, *, suggest_next: bool = True) -> None:
    task = state_path(config, "task_file")
    if task_args is not None:
        captured = acquire_task_text(task, task_args, allow_reuse=False)
        if captured is not None:
            reset_task_derived_artifacts(config)
            save_task_ready_state(config, task)
    if not task.exists():
        die(f"missing task file: {task}")
    out = state_path(config, "exploration_file")
    raw = out.with_suffix(".raw.txt")
    opencode(
        config=config,
        role="explorer",
        title="Explore task",
        output=raw,
        attachments=[task],
        block_state={
            "resume_command": "explore",
            "phase_before_block": "task_ready",
            "task_file": str(task.relative_to(ROOT)),
        },
        prompt=(
            "Explore the attached task in the current repository. Produce the "
            "Markdown exploration report required by your agent instructions."
        ),
    )
    out.write_text(raw.read_text(encoding="utf-8"), encoding="utf-8")
    raw.unlink(missing_ok=True)
    update_workflow_state(config, phase="explored", exploration_file=str(out.relative_to(ROOT)))
    print(f"Wrote {out}")
    if suggest_next:
        print("Next: scripts/agent plan")


def cmd_plan(config: dict[str, Any], task_args: list[str] | None = None, *, suggest_next: bool = True) -> None:
    task = state_path(config, "task_file")
    if task_args is not None:
        captured = acquire_task_text(task, task_args, allow_reuse=True)
        if captured is not None:
            reset_task_derived_artifacts(config)
            save_task_ready_state(config, task)
    exploration = state_path(config, "exploration_file")
    proposed = proposed_plan_path(config)
    raw = proposed.with_suffix(".raw.txt")

    attachments = [task]
    if exploration.exists():
        attachments.append(exploration)

    opencode(
        config=config,
        role="planner",
        title="Create proposed plan",
        output=raw,
        attachments=attachments,
        block_state={
            "resume_command": "plan",
            "phase_before_block": "task_ready",
            "task_file": str(task.relative_to(ROOT)),
        },
        prompt=(
            "Create a proposed PLAN.md from the attached task and optional "
            "exploration report. Human comments or selected direction written "
            "in TASK.md take precedence. Return only the plan Markdown."
        ),
    )
    proposed.write_text(raw.read_text(encoding="utf-8"), encoding="utf-8")
    raw.unlink(missing_ok=True)
    update_workflow_state(config, phase="plan_proposed", proposed_plan_file=str(proposed.relative_to(ROOT)))
    print(f"Wrote {proposed}")
    if suggest_next:
        print("Review/edit it, then run: scripts/agent approve-plan")


def approve_plan(config: dict[str, Any]) -> Path:
    proposed = proposed_plan_path(config)
    approved = state_path(config, "plan_file")
    if not proposed.exists():
        die(f"missing proposed plan: {proposed}")
    text = proposed.read_text(encoding="utf-8")
    if "HUMAN_DECISION_REQUIRED" in text:
        die(
            "proposed plan still contains HUMAN_DECISION_REQUIRED; resolve it "
            "before approval"
        )
    approved.write_text(text, encoding="utf-8")
    update_workflow_state(config, phase="approved", plan_file=str(approved.relative_to(ROOT)))
    return approved


def cmd_approve_plan(config: dict[str, Any]) -> None:
    approved = approve_plan(config)
    print(f"Approved plan copied to {approved}")
    print("Commit the agent files and approved plan before running automation.")


def read_multiline_prompt(
    prompt: str,
    help_text: str,
    *,
    stdin: TextIO | None = None,
    stdout: TextIO | None = None,
) -> str:
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    if not stdin.isatty():
        return stdin.read()

    stdout.write(prompt + "\n")
    stdout.write(help_text + "\n> ")
    stdout.flush()
    lines: list[str] = []
    while True:
        line = stdin.readline()
        if line == "":
            break
        if line in {"\n", "\r\n"}:
            break
        lines.append(line)
        if len(lines) == 1:
            stdout.write("> ")
            stdout.flush()
    return "".join(lines)


def read_task_from_supervisor(stdin: TextIO | None = None, stdout: TextIO | None = None) -> str:
    return read_multiline_prompt(
        "What do you want to work on?",
        "Enter a short task, or paste multiple lines and finish with a blank line.",
        stdin=stdin,
        stdout=stdout,
    )


def task_body_from_file(path: Path) -> str:
    if not path.exists():
        return ""
    text = path.read_text(encoding="utf-8")
    marker = "\n## Human constraints"
    if text.startswith("# Task\n\n"):
        text = text[len("# Task\n\n"):]
    if marker in text:
        text = text.split(marker, 1)[0]
    return normalize_task_text(text)


def should_recommend_exploration(task_text: str) -> tuple[bool, str]:
    lowered = task_text.lower()
    triggers = (
        "investigate",
        "explore",
        "options",
        "architecture",
        "design",
        "migration",
        "refactor",
        "cross-cutting",
        "unclear",
        "ambiguous",
        "performance",
        "concurrency",
        "data integrity",
    )
    if any(trigger in lowered for trigger in triggers):
        return True, "the task looks architectural or ambiguous"
    if len(task_text) > 240:
        return True, "the task has enough detail that a divergent pass may find risks"
    return False, "the task looks localized enough to plan directly"


def print_artifact_excerpt(path: Path, title: str, *, max_lines: int = 80) -> None:
    if not path.exists():
        return
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    print(f"\n=== {title}: {path} ===")
    for line in lines[:max_lines]:
        print(line)
    if len(lines) > max_lines:
        print(f"... ({len(lines) - max_lines} more line(s); see {path})")


def append_task_note(task_path: Path, note: str) -> None:
    current = task_path.read_text(encoding="utf-8") if task_path.exists() else "# Task\n\n"
    note = normalize_task_text(note)
    if not note:
        die("revision note is empty")
    updated = current.rstrip() + "\n\n## Supervisor notes\n\n" + note + "\n"
    temporary = task_path.with_name(f".{task_path.name}.tmp")
    temporary.write_text(updated, encoding="utf-8")
    temporary.replace(task_path)


def extract_human_decisions(plan_text: str) -> list[str]:
    lines = plan_text.splitlines()
    decisions: list[str] = []
    in_section = False
    for line in lines:
        stripped = line.strip()
        if stripped.lower().startswith("# human decisions required"):
            in_section = True
            continue
        if in_section and stripped.startswith("#"):
            break
        if "HUMAN_DECISION_REQUIRED" in stripped:
            decisions.append(stripped)
            continue
        if in_section and stripped and stripped.lower() not in {"none", "n/a", "no decisions required"}:
            decisions.append(stripped)

    if decisions:
        return decisions
    return [line.strip() for line in lines if "HUMAN_DECISION_REQUIRED" in line]


def plan_requires_human_decision(plan_path: Path) -> bool:
    return plan_path.exists() and "HUMAN_DECISION_REQUIRED" in plan_path.read_text(encoding="utf-8")


def resolve_plan_human_decisions(config: dict[str, Any], proposed: Path) -> bool:
    text = proposed.read_text(encoding="utf-8")
    decisions = extract_human_decisions(text)
    print("\nThe planner requires human decisions before approval.")
    notify_human_required(config, "Planner Needs Decisions", "Resolve HUMAN_DECISION_REQUIRED items before approval.")
    if decisions:
        print("Decisions to resolve:")
        for decision in decisions:
            print(f"- {decision}")
    optional_supervisor(
        config=config,
        title="Supervisor decision summary",
        output=ROOT / config["workflow"]["state_dir"] / "SUPERVISOR.decisions.md",
        attachments=[state_path(config, "task_file"), proposed],
        prompt=(
            "Summarize the HUMAN_DECISION_REQUIRED items in the proposed plan. "
            "Do not answer for Sam. Explain the tradeoffs and the next action."
        ),
    )

    if not sys.stdin.isatty():
        print(f"Resolve the decisions in {proposed}, then run: scripts/agent")
        return False

    answer = read_multiline_prompt(
        "How should these decisions be resolved?",
        "Enter decisions for the planner and finish with a blank line.",
    )
    answer = normalize_task_text(answer)
    if not answer:
        print(f"No decisions recorded. Resolve {proposed} externally, then run: scripts/agent")
        return False

    task = state_path(config, "task_file")
    append_task_note(task, "Resolved planner decisions:\n\n" + answer)
    update_workflow_state(config, phase="task_ready", task_file=str(task.relative_to(ROOT)))
    cmd_plan(config, suggest_next=False)
    print_artifact_excerpt(proposed, "Revised Proposed Plan")
    return True


def ensure_supervisor_task(config: dict[str, Any], state: dict[str, Any]) -> dict[str, Any]:
    task = state_path(config, "task_file")
    phase = state.get("phase", "new")
    if task.exists() and phase not in {"new", "complete"}:
        print(f"Resuming workflow at phase: {phase}")
        return state

    task_text = normalize_task_text(read_task_from_supervisor())
    if not task_text:
        die("task text is empty")
    write_task_file(task, task_text)
    reset_task_derived_artifacts(config)
    save_task_ready_state(config, task)
    return load_workflow_state(config)


def supervisor_maybe_explore(config: dict[str, Any], state: dict[str, Any]) -> dict[str, Any]:
    phase = state.get("phase")
    if phase not in {"task_ready"}:
        return state

    task = state_path(config, "task_file")
    task_text = task_body_from_file(task)
    recommend, reason = should_recommend_exploration(task_text)
    print(f"I {'recommend' if recommend else 'do not think we need'} exploration because {reason}.")
    if read_yes_no("Run exploration before planning?", default=recommend):
        cmd_explore(config, suggest_next=False)
        exploration = state_path(config, "exploration_file")
        print_artifact_excerpt(exploration, "Exploration Results")
        optional_supervisor(
            config=config,
            title="Supervisor exploration summary",
            output=ROOT / config["workflow"]["state_dir"] / "SUPERVISOR.exploration.md",
            attachments=[task, exploration],
            prompt=(
                "Summarize the exploration report for Sam. Highlight the viable "
                "approaches, tradeoffs, unresolved decisions, and recommended "
                "next action. Do not create an implementation plan."
            ),
        )
        return load_workflow_state(config)
    return state


def supervisor_plan(config: dict[str, Any], state: dict[str, Any]) -> dict[str, Any]:
    if state.get("phase") not in {"task_ready", "explored"}:
        return state
    cmd_plan(config, suggest_next=False)
    proposed = proposed_plan_path(config)
    print_artifact_excerpt(proposed, "Proposed Plan")
    optional_supervisor(
        config=config,
        title="Supervisor plan summary",
        output=ROOT / config["workflow"]["state_dir"] / "SUPERVISOR.plan.md",
        attachments=[state_path(config, "task_file"), state_path(config, "exploration_file"), proposed],
        prompt=(
            "Summarize the proposed plan for approval. Highlight the chosen "
            "approach, validation scope, risks, and any HUMAN_DECISION_REQUIRED "
            "items. Do not edit the plan or perform code review."
        ),
    )
    return load_workflow_state(config)


def supervisor_approve_or_revise(config: dict[str, Any], state: dict[str, Any]) -> dict[str, Any]:
    if state.get("phase") != "plan_proposed":
        return state

    proposed = proposed_plan_path(config)
    while True:
        if plan_requires_human_decision(proposed):
            if resolve_plan_human_decisions(config, proposed):
                continue
            return state
        notify_human_required(config, "Plan Ready", "Review the proposed plan and approve, revise, edit, or cancel.")
        print(f"\nProposed plan: {proposed}")
        print("Choose: [a]pprove / [r]evise with feedback / [e]dit externally / [c]ancel")
        answer = sys.stdin.readline().strip().lower() if sys.stdin.isatty() else "e"
        if answer in {"a", "approve", "y", "yes"}:
            approved = approve_plan(config)
            print(f"Approved plan copied to {approved}")
            return load_workflow_state(config)
        if answer in {"r", "revise"}:
            task = state_path(config, "task_file")
            note = read_multiline_prompt(
                "What should change in the plan?",
                "Paste feedback for the planner and finish with a blank line.",
            )
            append_task_note(task, note)
            update_workflow_state(config, phase="task_ready", task_file=str(task.relative_to(ROOT)))
            cmd_plan(config, suggest_next=False)
            print_artifact_excerpt(proposed, "Revised Proposed Plan")
            continue
        if answer in {"e", "edit"}:
            print(f"Edit externally, then run: scripts/agent")
            print(f"Plan path: {proposed}")
            return state
        if answer in {"c", "cancel"}:
            print("Cancelled; run scripts/agent to resume later.")
            return state
        print("Please answer a, r, e, or c.")


def supervisor_run_or_handoff(config: dict[str, Any], state: dict[str, Any]) -> None:
    if state.get("phase") not in {"approved", "ready_to_run"}:
        return
    if state.get("phase") == "approved" and not is_worktree_clean():
        notify_human_required(config, "Checkpoint Required", "Approve checkpoint commit before implementation starts.")
        if not read_yes_no("Create a workflow checkpoint commit and start implementation?", default=True):
            print("Commit the approved task/plan artifacts, then run: scripts/agent")
            return
        commit = create_checkpoint_commit(config)
        if commit:
            update_workflow_state(config, phase="ready_to_run", checkpoint_commit=commit)
            print(f"Created workflow checkpoint commit {commit[:12]}.")
    cmd_run(config)


def supervisor_human_test_handoff(config: dict[str, Any], state: dict[str, Any]) -> None:
    if state.get("phase") == "ready_for_human_test":
        run_path = state.get("run_dir")
        print("Implementation and automated review are complete.")
        notify_human_required(config, "Ready For Human Test", "Automation passed. Perform final behavior review.")
        if run_path:
            print(f"Run artifacts: {ROOT / run_path}")
        handoff = write_human_test_handoff(config, state)
        if handoff:
            print(f"Human test handoff: {handoff}")
            print_artifact_excerpt(handoff, "Human Test Handoff", max_lines=80)
            optional_supervisor(
                config=config,
                title="Supervisor human test checklist",
                output=handoff.with_name("human-test-supervisor.md"),
                attachments=[state_path(config, "task_file"), state_path(config, "plan_file"), handoff],
                prompt=(
                    "Create a concise manual test checklist for Sam from the "
                    "handoff artifact. Highlight actual behavior to verify, "
                    "validation already run, residual risks, and the next action. "
                    "Do not review code or adjudicate findings."
                ),
            )
        print("Perform the final human behavior review against the approved plan before accepting.")
        if read_yes_no("Did the human review pass?", default=False):
            update_workflow_state(config, phase="human_accepted")
            print("Marked human review as accepted.")
            print_final_commit_handoff()
        return

    if state.get("phase") == "human_accepted":
        print("Human review has been accepted.")
        print_final_commit_handoff()


def resume_blocked_model_limit(config: dict[str, Any], state: dict[str, Any]) -> None:
    print("Workflow is blocked on a model/provider limit.")
    notify_human_required(config, "Agent Blocked", "Workflow is blocked on a model/provider limit.")
    print(f"stage: {state.get('blocked_stage')}")
    print(f"role: {state.get('blocked_role')} model: {state.get('blocked_model')}")
    if state.get("blocked_stderr"):
        print(f"stderr: {ROOT / str(state['blocked_stderr'])}")
    if state.get("limit_classification"):
        print(f"classification: {state.get('limit_classification')}")
    if state.get("limit_summary"):
        print(str(state["limit_summary"]))

    saved_classification = normalized_saved_limit_state(state)
    retry_at = state.get("retry_at")
    if isinstance(retry_at, str):
        remaining = seconds_until(retry_at)
        if remaining is None:
            print(f"retry_at is invalid: {retry_at}")
            if not sys.stdin.isatty():
                die("blocked model limit has invalid retry_at; rerun interactively after limits reset", 4)
            if not read_yes_no("Retry the blocked stage now?", default=False):
                print("Stopped. Run scripts/agent after the limit resets.")
                return
            remaining = 0
        if remaining is not None and remaining > 0:
            print(f"retry_at: {retry_at} ({remaining} second(s) from now)")
            if not should_auto_wait_for_limit(config, saved_classification):
                print("Saved retry time is not an explicit short retryable limit. Run scripts/agent after the limit resets.")
                return
            if remaining > max_model_limit_wait_seconds(config):
                print("Retry time is beyond the configured auto-wait window. Run scripts/agent after the limit resets.")
                return
            if not sys.stdin.isatty():
                die("model limit has not reset yet; rerun scripts/agent later", 4)
            if not read_yes_no("Wait and retry automatically?", default=True):
                print("Stopped. Run scripts/agent after the limit resets.")
                return
            try:
                sleep_until_retry(remaining)
            except KeyboardInterrupt:
                print("Stopped while waiting. Run scripts/agent to resume later.")
                return
        elif not should_auto_wait_for_limit(config, saved_classification):
            if not sys.stdin.isatty():
                die("blocked model limit is not an explicit short retryable limit; rerun interactively after limits reset", 4)
            if not read_yes_no("Retry the blocked stage now?", default=False):
                print("Stopped. Run scripts/agent after the limit resets.")
                return

    if not isinstance(retry_at, str) and sys.stdin.isatty():
        if not read_yes_no("Retry the blocked stage now?", default=False):
            print("Stopped. Run scripts/agent after the limit resets.")
            return
    elif not isinstance(retry_at, str):
        die("blocked model limit has no retry time; rerun interactively after limits reset", 4)

    command = state.get("resume_command")
    if command == "explore":
        clean_state = {"phase": "task_ready"}
        if isinstance(state.get("task_file"), str):
            clean_state["task_file"] = state["task_file"]
        save_workflow_state(config, clean_state)
        cmd_explore(config, suggest_next=False)
        return
    if command == "plan":
        clean_state = {"phase": "task_ready"}
        if isinstance(state.get("task_file"), str):
            clean_state["task_file"] = state["task_file"]
        save_workflow_state(config, clean_state)
        cmd_plan(config, suggest_next=False)
        return
    if command == "run":
        run_step = state.get("run_step")
        if run_step in {"implementation", "fix"}:
            print("The blocked stage writes code and cannot be resumed safely automatically.")
            print("Inspect the current diff and run artifacts before deciding how to continue.")
            return
        cmd_run_resume(config, state)
        return
    die("blocked model limit state has no supported resume command; inspect STATE.json", 4)


def resume_blocked_review_budget(config: dict[str, Any], state: dict[str, Any]) -> None:
    print("Workflow stopped after exhausting the configured review/fix budget.")
    if state.get("budget_summary"):
        print(str(state["budget_summary"]))
    run_dir_value = state.get("run_dir")
    if isinstance(run_dir_value, str):
        print(f"Run artifacts: {ROOT / run_dir_value}")
    notify_human_required(config, "Review Budget Exhausted", "Decide whether to continue another review/fix budget window.")

    if not sys.stdin.isatty():
        die("review budget exhausted; rerun scripts/agent interactively to continue", 3)
    if not read_yes_no("Continue another review/fix budget window?", default=True):
        print("Stopped. Inspect the diff and run artifacts before continuing.")
        return
    cmd_run_resume(config, state)


def resume_blocked_validation(config: dict[str, Any], state: dict[str, Any]) -> None:
    stage = state.get("validation_stage")
    command = state.get("validation_command")
    log_value = state.get("validation_log")
    remaining = state.get("validation_remaining_commands")
    if not isinstance(stage, str) or not isinstance(command, str) or not isinstance(log_value, str):
        die("blocked validation state is incomplete; inspect STATE.json")
    if not isinstance(remaining, list) or not all(isinstance(item, str) for item in remaining):
        die("blocked validation state has invalid remaining commands; inspect STATE.json")

    print("Workflow stopped after a validation command failed.")
    print(f"stage: {stage}")
    print(f"failed command: {command}")
    print(f"validation log: {ROOT / log_value}")
    run_commands(config, remaining, stage, ROOT / log_value, state)

    action = state.get("validation_resume_action")
    if action == "ready_for_human_test":
        run_dir_value = state.get("run_dir")
        if not isinstance(run_dir_value, str):
            die("blocked validation state is missing run_dir; inspect STATE.json")
        current_run = ROOT / run_dir_value
        success_text = state.get("validation_success_text")
        if isinstance(success_text, str):
            (current_run / "SUCCESS").write_text(success_text, encoding="utf-8")
        update_workflow_state(config, phase="ready_for_human_test", run_dir=run_dir_value)
        notify_human_required(config, "Ready For Human Test", "Automation passed. Perform final behavior review.")
        print("\nWorkflow passed. Ready for final human testing and review.")
        print(f"Run artifacts: {current_run}")
        return

    if state.get("resume_command") == "run":
        cmd_run_resume(config, state)
        return
    die("blocked validation state has no supported resume command; inspect STATE.json")


def cmd_supervise(config: dict[str, Any]) -> None:
    print("Space agent supervisor")
    state = load_workflow_state(config)
    if state.get("phase") == "blocked_model_limit":
        resume_blocked_model_limit(config, state)
        return
    if state.get("phase") == "blocked_review_budget":
        resume_blocked_review_budget(config, state)
        return
    if state.get("phase") == "blocked_validation":
        resume_blocked_validation(config, state)
        return
    if state.get("phase") in {"ready_for_human_test", "human_accepted"}:
        supervisor_human_test_handoff(config, state)
        return
    state = ensure_supervisor_task(config, state)
    state = supervisor_maybe_explore(config, state)
    state = supervisor_plan(config, load_workflow_state(config))
    state = supervisor_approve_or_revise(config, state)
    supervisor_run_or_handoff(config, load_workflow_state(config))


def cmd_start(config: dict[str, Any], task_args: list[str]) -> None:
    task = state_path(config, "task_file")
    captured = acquire_task_text(task, task_args, allow_reuse=False)
    if captured is not None:
        reset_task_derived_artifacts(config)
        save_task_ready_state(config, task)

    if read_yes_no("Run exploration before planning?", default=False):
        cmd_explore(config, suggest_next=False)

    cmd_plan(config, suggest_next=False)
    proposed = ROOT / config["workflow"]["state_dir"] / "PLAN.proposed.md"
    print(f"Proposed plan: {proposed}")
    notify_human_required(config, "Plan Ready", "Review the proposed plan and approve, edit, or cancel.")

    choice = read_approval_choice()
    if choice == "e":
        print(f"Edit externally, then run: scripts/agent approve-plan && scripts/agent run")
        print(f"Plan path: {proposed}")
        return
    if choice == "c":
        print("Cancelled; approved plan was not modified.")
        return

    approved = approve_plan(config)
    print(f"Approved plan copied to {approved}")
    if not is_worktree_clean():
        notify_human_required(config, "Checkpoint Required", "Approve checkpoint commit before implementation starts.")
        if not read_yes_no("Create a workflow checkpoint commit and start implementation?", default=True):
            print("Commit the approved task/plan artifacts, then run: scripts/agent run")
            return
        commit = create_checkpoint_commit(config)
        if commit:
            update_workflow_state(config, phase="ready_to_run", checkpoint_commit=commit)
            print(f"Created workflow checkpoint commit {commit[:12]}.")
    cmd_run(config)


def accepted_findings(adjudication: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        item
        for item in adjudication.get("findings", [])
        if item.get("decision") == "accept"
    ]


def escalated_findings(adjudication: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        item
        for item in adjudication.get("findings", [])
        if item.get("decision") == "escalate"
    ]


def write_subset(data: dict[str, Any], findings: list[dict[str, Any]], path: Path) -> None:
    subset = {
        "status": "ready_to_fix" if findings else "no_action",
        "summary": data.get("summary", ""),
        "findings": findings,
    }
    path.write_text(json.dumps(subset, indent=2) + "\n", encoding="utf-8")


def write_text_artifact(path: Path, text: str) -> Path:
    path.write_text(text + ("" if text.endswith("\n") else "\n"), encoding="utf-8")
    return path


def read_untracked_file(path: Path, *, max_bytes: int = 262_144) -> str:
    if not path.is_file():
        return "[skipped: not a regular file]\n"
    size = path.stat().st_size
    if size > max_bytes:
        return f"[skipped: file is {size} bytes, larger than {max_bytes} byte limit]\n"
    return path.read_bytes().decode("utf-8", errors="replace")


def write_untracked_context(path: Path) -> Path:
    paths = [line for line in git("ls-files", "--others", "--exclude-standard").splitlines() if line]
    if not paths:
        return write_text_artifact(path, "No untracked files.")

    sections = ["# Untracked Files", ""]
    for rel_path in paths:
        sections.append(f"## {rel_path}")
        sections.append("")
        sections.append("```text")
        sections.append(read_untracked_file(ROOT / rel_path).rstrip("\n"))
        sections.append("```")
        sections.append("")
    return write_text_artifact(path, "\n".join(sections).rstrip("\n"))


def write_full_review_context(current_run: Path, base_commit: str, round_no: int) -> list[Path]:
    prefix = current_run / f"full-review-{round_no:02d}"
    return [
        write_text_artifact(prefix.with_suffix(".git-status.txt"), git("status", "--short")),
        write_text_artifact(prefix.with_suffix(".diff-stat.txt"), git("diff", "--stat", base_commit)),
        write_text_artifact(prefix.with_suffix(".base-to-head.patch"), git("diff", f"{base_commit}...HEAD")),
        write_text_artifact(prefix.with_suffix(".base-to-worktree.patch"), git("diff", base_commit)),
        write_untracked_context(prefix.with_suffix(".untracked.txt")),
    ]


def try_git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        return f"[unavailable: git {' '.join(args)} failed]"
    return result.stdout.strip()


def capped_text(path: Path, *, max_chars: int = 6000) -> str:
    if not path.exists():
        return "[missing]"
    text = path.read_text(encoding="utf-8", errors="replace").strip()
    if len(text) <= max_chars:
        return text
    return text[-max_chars:]


def latest_run_artifact(run_path: Path, pattern: str) -> Path | None:
    matches = sorted(run_path.glob(pattern))
    return matches[-1] if matches else None


def write_human_test_handoff(config: dict[str, Any], state: dict[str, Any]) -> Path | None:
    run_dir_value = state.get("run_dir")
    if not isinstance(run_dir_value, str):
        return None
    run_path = ROOT / run_dir_value
    if not run_path.exists():
        return None

    plan = state_path(config, "plan_file")
    task = state_path(config, "task_file")
    validation_log = run_path / "validation.log"
    success = run_path / "SUCCESS"
    latest_review = latest_run_artifact(run_path, "full-review-*.json")
    latest_adjudication = latest_run_artifact(run_path, "adjudication-*.json")
    diff_stat = try_git("diff", "--stat")
    status = try_git("status", "--short")

    lines = [
        "# Human Test Handoff",
        "",
        "## Task",
        capped_text(task, max_chars=2000),
        "",
        "## Approved Plan",
        str(plan.relative_to(ROOT)) if plan.exists() else "[missing]",
        "",
        "## Automation Result",
        capped_text(success, max_chars=1000),
        "",
        "## Current Worktree",
        "```text",
        status or "[clean]",
        "```",
        "",
        "## Diff Stat",
        "```text",
        diff_stat or "[no diff]",
        "```",
        "",
        "## Validation Log",
        "```text",
        capped_text(validation_log),
        "```",
    ]
    if latest_review:
        lines.extend(["", "## Latest Full Review", "```json", capped_text(latest_review), "```"])
    if latest_adjudication:
        lines.extend(["", "## Latest Adjudication", "```json", capped_text(latest_adjudication), "```"])
    lines.extend(
        [
            "",
            "## Manual Checks",
            "- Verify actual behavior against the approved plan.",
            "- Inspect the entire accumulated diff for unrelated changes.",
            "- Run or manually exercise tests that matter but were not in configured gates.",
            "- For UI/layout work, verify desktop and mobile behavior where applicable.",
            "- Confirm migrations, persistence, rollback, and operational risks where applicable.",
        ]
    )

    handoff = run_path / "human-test-handoff.md"
    handoff.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return handoff


def print_final_commit_handoff() -> None:
    print("Next: create the final commit with the normal git-commit workflow.")
    print("Suggested pre-commit checks: git status --short, git diff --stat, git diff")
    print("Commit only the intended implementation and workflow artifacts.")


def full_review_prompt(base_commit: str, round_no: int) -> str:
    return f"""
FULL REVIEW MODE.

Base commit: {base_commit}
Full review round: {round_no}

Read the approved PLAN.md and inspect the attached review context:
- git status --short
- git diff --stat {base_commit}
- git diff {base_commit}...HEAD
- git diff {base_commit}
- untracked file contents, capped per file

Use repository read/search tools for surrounding code and tests. Ignore prior review conclusions.
Treat review-driven fixes as untrusted. Return only the full-review JSON object
required by your agent instructions.
""".strip()


def run_block_state(
    current_run: Path,
    base_commit: str,
    step: str,
    review_round: int,
    attempt: int | None = None,
    review_budget_end: int | None = None,
    fix_budget_end: int | None = None,
) -> dict[str, Any]:
    state: dict[str, Any] = {
        "resume_command": "run",
        "phase_before_block": "running",
        "run_dir": str(current_run.relative_to(ROOT)),
        "base_commit": base_commit,
        "run_step": step,
        "review_round": review_round,
    }
    if attempt is not None:
        state["attempt"] = attempt
    if review_budget_end is not None:
        state["review_budget_end"] = review_budget_end
    if fix_budget_end is not None:
        state["fix_budget_end"] = fix_budget_end
    return state


def final_validation_block_state(
    current_run: Path,
    base_commit: str,
    review_round: int,
    success_text: str,
    review_budget_end: int | None = None,
) -> dict[str, Any]:
    state = run_block_state(
        current_run,
        base_commit,
        "full_review",
        review_round,
        review_budget_end=review_budget_end,
    )
    state.update(
        {
            "validation_resume_action": "ready_for_human_test",
            "validation_success_text": success_text,
        }
    )
    return state


def save_blocked_review_budget_state(
    config: dict[str, Any],
    current_run: Path,
    base_commit: str,
    step: str,
    review_round: int,
    summary: str,
    attempt: int | None = None,
) -> None:
    state = run_block_state(current_run, base_commit, step, review_round, attempt)
    state.update(
        {
            "phase": "blocked_review_budget",
            "budget_summary": summary,
        }
    )
    save_workflow_state(config, state)
    notify_human_required(config, "Review Budget Exhausted", summary)
    print(f"\n{summary}")
    print("Workflow state is saved as blocked_review_budget. Run scripts/agent to continue another budget window.")
    raise SystemExit(3)


def run_review_loop(
    config: dict[str, Any],
    current_run: Path,
    base_commit: str,
    validation_log: Path,
    *,
    start_round: int = 1,
    resume_step: str | None = None,
    resume_attempt: int = 1,
    review_budget_end: int | None = None,
    fix_budget_end: int | None = None,
) -> None:
    plan = state_path(config, "plan_file")
    review_round_budget = int(config["workflow"]["review_round_budget"])
    fix_attempt_budget = int(config["workflow"]["fix_attempt_budget"])
    max_rounds = review_budget_end if review_budget_end is not None else start_round + review_round_budget - 1
    validation = config.get("validation", {})

    for review_round in range(start_round, max_rounds + 1):
        review_json = current_run / f"full-review-{review_round:02d}.json"
        review_context = write_full_review_context(current_run, base_commit, review_round)
        if resume_step in {"adjudication", "verification", "fix"} and review_round == start_round:
            review = read_json_artifact(review_json, "full review")
            validate_full_review(review, review_json)
        else:
            review_raw = current_run / f"full-review-{review_round:02d}.raw.txt"
            opencode(
                config=config,
                role="reviewer",
                title=f"Full review {review_round}",
                output=review_raw,
                attachments=[plan, *review_context],
                block_state=run_block_state(
                    current_run,
                    base_commit,
                    "full_review",
                    review_round,
                    review_budget_end=max_rounds,
                ),
                prompt=full_review_prompt(base_commit, review_round),
            )
            review = extract_json(
                review_raw, review_json, ["mode", "status", "candidate_findings"]
            )
            validate_full_review(review, review_json)

        if review.get("status") == "requires_human":
            notify_human_required(config, "Review Needs Human", f"Full review {review_round} requires human judgment.")
            die(f"review requires human judgment; see {review_json}", 2)

        candidates = review.get("candidate_findings", [])
        if review.get("status") == "pass" and not candidates:
            success_text = f"Passed after {review_round} full review round(s).\n"
            run_commands(
                config,
                list(validation.get("final", [])),
                "final",
                validation_log,
                final_validation_block_state(current_run, base_commit, review_round, success_text, max_rounds),
            )
            (current_run / "SUCCESS").write_text(success_text, encoding="utf-8")
            update_workflow_state(config, phase="ready_for_human_test", run_dir=str(current_run.relative_to(ROOT)))
            notify_human_required(config, "Ready For Human Test", "Automation passed. Perform final behavior review.")
            print("\nWorkflow passed. Ready for final human testing and review.")
            print(f"Run artifacts: {current_run}")
            return

        adjudication_json = current_run / f"adjudication-{review_round:02d}.json"
        if resume_step in {"verification", "fix"} and review_round == start_round:
            adjudication = read_json_artifact(adjudication_json, "adjudication")
            validate_adjudication(adjudication, {item["id"] for item in candidates}, adjudication_json)
        else:
            adjudication_raw = current_run / f"adjudication-{review_round:02d}.raw.txt"
            opencode(
                config=config,
                role="adjudicator",
                title=f"Adjudicate review {review_round}",
                output=adjudication_raw,
                attachments=[plan, review_json, *review_context],
                    block_state=run_block_state(
                        current_run,
                        base_commit,
                        "adjudication",
                        review_round,
                        review_budget_end=max_rounds,
                    ),
                prompt=(
                    "Adjudicate only the candidate findings in the attached full "
                    "review against PLAN.md and the current repository. Do not "
                    "perform a new review. Return only the required JSON object."
                ),
            )
            adjudication = extract_json(adjudication_raw, adjudication_json, ["status", "findings"])
            validate_adjudication(adjudication, {item["id"] for item in candidates}, adjudication_json)

        escalations = escalated_findings(adjudication)
        if escalations or adjudication.get("status") == "requires_human":
            notify_human_required(config, "Adjudication Needs Human", f"Review round {review_round} requires human judgment.")
            die(f"adjudication requires human judgment; see {adjudication_json}", 2)

        accepted_json = current_run / f"accepted-{review_round:02d}.json"
        accepted = accepted_findings(adjudication)
        if resume_step in {"verification", "fix"} and review_round == start_round:
            accepted_data = read_json_artifact(accepted_json, "accepted findings")
            accepted = accepted_data.get("findings", [])
            if not isinstance(accepted, list) or not all(isinstance(item, dict) for item in accepted):
                die(f"malformed accepted findings artifact for resume: {accepted_json}")
        elif not accepted:
            success_text = f"No accepted findings after review round {review_round}.\n"
            run_commands(
                config,
                list(validation.get("final", [])),
                "final",
                validation_log,
                final_validation_block_state(current_run, base_commit, review_round, success_text, max_rounds),
            )
            (current_run / "SUCCESS").write_text(success_text, encoding="utf-8")
            update_workflow_state(config, phase="ready_for_human_test", run_dir=str(current_run.relative_to(ROOT)))
            notify_human_required(config, "Ready For Human Test", "Automation passed. Perform final behavior review.")
            print("\nWorkflow passed after adjudication rejected all candidates.")
            print("Ready for final human testing and review.")
            print(f"Run artifacts: {current_run}")
            return
        else:
            write_subset(adjudication, accepted, accepted_json)

        verified = False
        first_attempt = resume_attempt if resume_step in {"verification", "fix"} and review_round == start_round else 1
        max_fix_attempt = (
            fix_budget_end
            if fix_budget_end is not None and resume_step in {"verification", "fix"} and review_round == start_round
            else first_attempt + fix_attempt_budget - 1
        )
        for attempt in range(first_attempt, max_fix_attempt + 1):
            before_path = current_run / f"before-fix-{review_round:02d}-attempt-{attempt:02d}.patch"
            skip_fix = resume_step == "verification" and review_round == start_round and attempt == first_attempt
            if skip_fix and not before_path.exists():
                die(f"missing before-fix patch artifact for resume: {before_path}")
            if not skip_fix:
                fix_raw = current_run / f"fix-{review_round:02d}-attempt-{attempt:02d}.raw.txt"
                before_path.write_text(git("diff", base_commit), encoding="utf-8")
                opencode(
                    config=config,
                    role="fixer",
                    title=f"Fix review {review_round}, attempt {attempt}",
                    output=fix_raw,
                    attachments=[plan, accepted_json],
                    block_state=run_block_state(
                        current_run,
                        base_commit,
                        "fix",
                        review_round,
                        attempt,
                        review_budget_end=max_rounds,
                        fix_budget_end=max_fix_attempt,
                    ),
                    prompt=(
                        "Fix only the accepted findings in the attached "
                        "adjudication report. Use focused regression tests first, "
                        "then the complete relevant suite from PLAN.md. Do not "
                        "apply rejected or optional suggestions."
                    ),
                )
                run_commands(
                    config,
                    list(validation.get("after_fix", [])),
                    f"after fix round {review_round}, attempt {attempt}",
                    validation_log,
                    run_block_state(
                        current_run,
                        base_commit,
                        "verification",
                        review_round,
                        attempt,
                        review_budget_end=max_rounds,
                        fix_budget_end=max_fix_attempt,
                    ),
                )

            verification_raw = current_run / f"verification-{review_round:02d}-attempt-{attempt:02d}.raw.txt"
            verification_json = current_run / f"verification-{review_round:02d}-attempt-{attempt:02d}.json"
            opencode(
                config=config,
                role="reviewer",
                title=f"Verify fixes {review_round}.{attempt}",
                output=verification_raw,
                attachments=[plan, accepted_json, before_path],
                block_state=run_block_state(
                    current_run,
                    base_commit,
                    "verification",
                    review_round,
                    attempt,
                    review_budget_end=max_rounds,
                    fix_budget_end=max_fix_attempt,
                ),
                prompt=(
                    "TARGETED VERIFICATION MODE. Verify only the accepted "
                    "findings and their attempted corrections. The attached "
                    "before-fix patch records the accumulated state before this "
                    "attempt; compare it with the current repository. Do not "
                    "perform a general review. Return only the required "
                    "verification JSON object."
                ),
            )
            verification = extract_json(verification_raw, verification_json, ["mode", "status", "findings"])
            expected_ids = {item["id"] for item in accepted}
            validate_verification(verification, expected_ids, verification_json)

            if verification.get("status") == "requires_human":
                notify_human_required(config, "Verification Needs Human", f"Fix verification {review_round}.{attempt} requires human judgment.")
                die(f"verification requires human judgment; see {verification_json}", 2)

            finding_states = {item.get("id"): item.get("status") for item in verification.get("findings", [])}
            if expected_ids and all(finding_states.get(item_id) == "verified_fixed" for item_id in expected_ids):
                verified = True
                break

            failed_ids = [item_id for item_id in expected_ids if finding_states.get(item_id) != "verified_fixed"]
            failed_findings = [item for item in accepted if item["id"] in failed_ids]
            write_subset(adjudication, failed_findings, accepted_json)
            accepted = failed_findings

        if not verified:
            save_blocked_review_budget_state(
                config,
                current_run,
                base_commit,
                "fix",
                review_round,
                f"Fix attempt budget exhausted after attempt {max_fix_attempt} in review round {review_round}.",
                max_fix_attempt + 1,
            )

        resume_step = None

    save_blocked_review_budget_state(
        config,
        current_run,
        base_commit,
        "full_review",
        max_rounds + 1,
        f"Review round budget exhausted after full review round {max_rounds}.",
    )


def cmd_run_resume(config: dict[str, Any], state: dict[str, Any]) -> None:
    run_dir_value = state.get("run_dir")
    base_commit = state.get("base_commit")
    if not isinstance(run_dir_value, str) or not isinstance(base_commit, str):
        die("blocked run state is incomplete; inspect STATE.json and run artifacts")
    current_run = ROOT / run_dir_value
    start_round = parse_positive_state_int(state, "review_round", 1)
    resume_attempt = parse_positive_state_int(state, "attempt", 1)
    review_budget_end = parse_positive_state_int(state, "review_budget_end")
    fix_budget_end = parse_positive_state_int(state, "fix_budget_end")
    resume_step = state.get("run_step")
    if resume_step not in {"full_review", "adjudication", "verification", "fix"}:
        die("blocked run state cannot be resumed automatically; inspect run artifacts")
    if review_budget_end is not None and review_budget_end < start_round:
        die("blocked run state has review_budget_end before review_round; inspect STATE.json")
    if fix_budget_end is not None and fix_budget_end < resume_attempt:
        die("blocked run state has fix_budget_end before attempt; inspect STATE.json")
    if fix_budget_end is not None and resume_step not in {"verification", "fix"}:
        die("blocked run state has fix_budget_end outside a fix/verification step; inspect STATE.json")
    review_round_budget = parse_positive_config_int(config, "review_round_budget")
    fix_attempt_budget = parse_positive_config_int(config, "fix_attempt_budget")
    if review_budget_end is not None and review_budget_end - start_round + 1 > review_round_budget:
        die("blocked run state review_budget_end exceeds configured review_round_budget; inspect STATE.json")
    if fix_budget_end is not None and fix_budget_end - resume_attempt + 1 > fix_attempt_budget:
        die("blocked run state fix_budget_end exceeds configured fix_attempt_budget; inspect STATE.json")
    save_workflow_state(config, {"phase": "running", "run_dir": run_dir_value, "base_commit": base_commit})
    run_review_loop(
        config,
        current_run,
        base_commit,
        current_run / "validation.log",
        start_round=start_round,
        resume_step=str(resume_step),
        resume_attempt=resume_attempt,
        review_budget_end=review_budget_end,
        fix_budget_end=fix_budget_end,
    )


def cmd_run(config: dict[str, Any]) -> None:
    state = load_workflow_state(config)
    if state.get("phase") == "blocked_model_limit":
        resume_blocked_model_limit(config, state)
        return
    if state.get("phase") == "blocked_review_budget":
        resume_blocked_review_budget(config, state)
        return
    if state.get("phase") == "blocked_validation":
        resume_blocked_validation(config, state)
        return

    require_current_plan_for_run(config, state)

    require_clean_tree()
    plan = state_path(config, "plan_file")
    task = state_path(config, "task_file")

    current_run = run_dir(config)
    update_workflow_state(config, phase="running", run_dir=str(current_run.relative_to(ROOT)))
    base_commit = git("rev-parse", "HEAD")
    (current_run / "base_commit.txt").write_text(base_commit + "\n")
    validation_log = current_run / "validation.log"
    validation = config.get("validation", {})

    implementation_raw = current_run / "implementation.raw.txt"
    opencode(
        config=config,
        role="implementer",
        title="Initial implementation",
        output=implementation_raw,
        attachments=[task, plan],
        block_state={
            "resume_command": "run",
            "phase_before_block": "running",
            "run_dir": str(current_run.relative_to(ROOT)),
            "base_commit": base_commit,
            "run_step": "implementation",
        },
        prompt=(
            "Implement the complete approved plan. Use focused tests during "
            "development, then run the complete relevant suite and checks "
            "defined by PLAN.md. Preserve scope and report exact validation."
        ),
    )
    run_commands(
        config,
        list(validation.get("after_implementation", [])),
        "after initial implementation",
        validation_log,
        run_block_state(current_run, base_commit, "full_review", 1),
    )
    run_review_loop(config, current_run, base_commit, validation_log)


def cmd_status(config: dict[str, Any]) -> None:
    state = ROOT / config["workflow"]["state_dir"]
    runs = state / "runs"
    workflow_state = load_workflow_state(config)
    if workflow_state.get("phase") == "blocked_model_limit":
        print("Workflow blocked on model/provider limit:")
        print(f"  stage: {workflow_state.get('blocked_stage')}")
        print(f"  role: {workflow_state.get('blocked_role')} model: {workflow_state.get('blocked_model')}")
        if workflow_state.get("retry_at"):
            print(f"  retry_at: {workflow_state.get('retry_at')}")
        if workflow_state.get("blocked_stderr"):
            print(f"  stderr: {ROOT / str(workflow_state['blocked_stderr'])}")
        print("")
    if workflow_state.get("phase") == "blocked_review_budget":
        print("Workflow blocked on review/fix budget:")
        print(f"  step: {workflow_state.get('run_step')}")
        print(f"  review_round: {workflow_state.get('review_round')}")
        if workflow_state.get("attempt"):
            print(f"  next_attempt: {workflow_state.get('attempt')}")
        if workflow_state.get("budget_summary"):
            print(f"  summary: {workflow_state.get('budget_summary')}")
        print("")
    if workflow_state.get("phase") == "blocked_validation":
        print("Workflow blocked on validation:")
        print(f"  stage: {workflow_state.get('validation_stage')}")
        print(f"  command: {workflow_state.get('validation_command')}")
        if workflow_state.get("validation_log"):
            print(f"  log: {ROOT / str(workflow_state['validation_log'])}")
        print("")
    print("Git status:")
    subprocess.run(["git", "status", "--short"], cwd=ROOT, check=False)
    print("\nDiff summary:")
    subprocess.run(["git", "diff", "--stat"], cwd=ROOT, check=False)
    if runs.exists():
        latest = sorted((p for p in runs.iterdir() if p.is_dir()), reverse=True)
        if latest:
            print(f"\nLatest run: {latest[0]}")
            success = latest[0] / "SUCCESS"
            if success.exists():
                print(success.read_text(encoding="utf-8").strip())


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="agent",
        description="OpenCode plan/implement/review/adjudicate workflow.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""examples:
  scripts/agent
  scripts/agent plan "Add department filtering to appointments"
  cat task-description.md | scripts/agent plan
  scripts/agent plan
  scripts/agent start "Implement appointment department filtering"
""",
    )
    subparsers = parser.add_subparsers(dest="command")

    explore_parser = subparsers.add_parser(
        "explore",
        help="capture a task and run exploration",
    )
    explore_parser.add_argument("task", nargs="*")

    plan_parser = subparsers.add_parser(
        "plan",
        help="capture or reuse a task and create PLAN.proposed.md",
    )
    plan_parser.add_argument("task", nargs="*")

    start_parser = subparsers.add_parser(
        "start",
        help="capture a task, optionally explore, plan, approve, and run",
    )
    start_parser.add_argument("task", nargs="*")

    subparsers.add_parser("approve-plan", help="copy PLAN.proposed.md to PLAN.md after approval checks")
    subparsers.add_parser("run", help="run the autonomous implementation/review pipeline")
    subparsers.add_parser("status", help="show Git status and latest run result")

    args = parser.parse_args()

    require_tools()
    require_git_repo()
    config = load_config()

    if args.command is None:
        cmd_supervise(config)
    elif args.command == "explore":
        cmd_explore(config, args.task)
    elif args.command == "plan":
        cmd_plan(config, args.task)
    elif args.command == "start":
        cmd_start(config, args.task)
    elif args.command == "approve-plan":
        cmd_approve_plan(config)
    elif args.command == "run":
        cmd_run(config)
    elif args.command == "status":
        cmd_status(config)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
