#!/usr/bin/env python3
"""Guarded GitHub PR operations for OpenCode capability agents."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

from opencode_capabilities import CapabilityError, ensure_space_repo, failure, human_decision, run_command, success, validate_branch_name

SPACE_REPO = "semanticdreams/space2"
PR_VIEW_FIELDS = "state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url"
NONTERMINAL_STATES = {"queued", "waiting", "pending", "in_progress", "in-progress", "expected", None}


def _exit_code_for(result: dict[str, object]) -> int:
    if result.get("status") == "pass":
        return 0
    if result.get("status") == "human_decision_required":
        return 2
    return 3


def _safe_branch(action: str, branch: str) -> tuple[str | None, dict[str, object] | None]:
    try:
        return validate_branch_name(branch), None
    except CapabilityError as error:
        return None, human_decision(action, error.message, {"code": error.code, "details": error.details, "branch": branch})


def _json_loads(text: str) -> Any:
    return json.loads(text) if text.strip() else None


def _contains_test_status(value: Any) -> bool:
    if isinstance(value, dict):
        for key, item in value.items():
            lowered = str(key).lower()
            if lowered in {"contexts", "checks", "required_status_checks"} and _contains_test_status(item):
                return True
            if isinstance(item, str) and item == "test":
                return True
            if _contains_test_status(item):
                return True
    if isinstance(value, list):
        return any(_contains_test_status(item) for item in value)
    return value == "test"


def _contains_merge_queue(value: Any) -> bool:
    if isinstance(value, dict):
        return any("merge_queue" in str(item).lower() or "merge queue" in str(item).lower() or _contains_merge_queue(item) for item in value.values())
    if isinstance(value, list):
        return any(_contains_merge_queue(item) for item in value)
    return False


def pr_auth_status(repo_root: Path) -> dict[str, object]:
    action = "pr_auth_status"
    try:
        repo = ensure_space_repo(repo_root)
        result = run_command(["gh", "auth", "status"], repo, check=False)
        if result.returncode != 0:
            return human_decision(action, "GitHub CLI authentication is missing or invalid", {"returncode": result.returncode})
        return success(action, "GitHub CLI authentication is available", {"args": result.args})
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})


def check_main_protection(repo_root: Path) -> dict[str, object]:
    action = "check_main_protection"
    try:
        repo = ensure_space_repo(repo_root)
        protection_result = run_command(["gh", "api", f"repos/{SPACE_REPO}/branches/main/protection"], repo, check=False)
        rulesets_result = run_command(["gh", "api", f"repos/{SPACE_REPO}/rulesets"], repo, check=False)
        protection = _json_loads(protection_result.stdout) if protection_result.returncode == 0 else None
        rulesets = _json_loads(rulesets_result.stdout) if rulesets_result.returncode == 0 else None
    except (CapabilityError, json.JSONDecodeError) as error:
        details = {"error_type": type(error).__name__, "error": str(error)}
        if isinstance(error, CapabilityError):
            details = {"code": error.code, "details": error.details}
        return human_decision(action, "Could not prove required main protection and merge queue from GitHub responses", details)

    has_test = _contains_test_status(protection) or _contains_test_status(rulesets)
    has_queue = _contains_merge_queue(protection) or _contains_merge_queue(rulesets)
    evidence = {
        "classic_protection_available": protection is not None,
        "rulesets_available": rulesets is not None,
        "required_test_check_proven": has_test,
        "merge_queue_proven": has_queue,
    }
    if not has_test or not has_queue:
        return human_decision(action, "Main protection does not prove both required test and merge queue", evidence)
    return success(action, "Main protection proves required test and merge queue", evidence)


def create_pr(repo_root: Path, head: str) -> dict[str, object]:
    action = "create_pr"
    try:
        repo = ensure_space_repo(repo_root)
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})
    branch, unsafe = _safe_branch(action, head)
    if unsafe is not None:
        return unsafe
    try:
        result = run_command(["gh", "pr", "create", "--base", "main", "--head", branch, "--fill"], repo)
        return success(action, "Created pull request targeting main", {"branch": branch, "url": result.stdout.strip(), "args": result.args})
    except CapabilityError as error:
        return human_decision(action, error.message, {"code": error.code, "details": error.details, "branch": branch})


def enable_auto_merge(repo_root: Path, branch: str) -> dict[str, object]:
    action = "enable_auto_merge"
    try:
        repo = ensure_space_repo(repo_root)
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})
    safe, unsafe = _safe_branch(action, branch)
    if unsafe is not None:
        return unsafe
    protection = check_main_protection(repo_root)
    if protection.get("status") != "pass":
        return human_decision(action, "Auto-merge requires proven main protection and merge queue", {"branch": safe, "protection": protection})
    try:
        result = run_command(["gh", "pr", "merge", safe, "--auto", "--merge"], repo, check=False)
        output = f"{result.stdout}\n{result.stderr}".lower()
        if result.returncode != 0 or "rebase" in output:
            return human_decision(action, "Auto-merge could not be enabled safely", {"branch": safe, "returncode": result.returncode})
        return success(action, "Enabled auto-merge with merge commits", {"branch": safe, "args": result.args})
    except CapabilityError as error:
        return human_decision(action, error.message, {"code": error.code, "details": error.details, "branch": safe})


def view_pr(repo_root: Path, branch: str) -> dict[str, object]:
    action = "view_pr"
    try:
        repo = ensure_space_repo(repo_root)
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})
    safe, unsafe = _safe_branch(action, branch)
    if unsafe is not None:
        return unsafe
    try:
        result = run_command(["gh", "pr", "view", safe, "--json", PR_VIEW_FIELDS], repo)
        data = _json_loads(result.stdout)
        if not isinstance(data, dict):
            return human_decision(action, "GitHub PR view response was ambiguous", {"branch": safe})
        return success(action, "Loaded pull request status", {"branch": safe, "pr": data})
    except (CapabilityError, json.JSONDecodeError) as error:
        return human_decision(action, "Could not load pull request status safely", {"error_type": type(error).__name__, "error": str(error), "branch": safe})


def _failed_rollup(data: dict[str, Any]) -> bool:
    for check in data.get("statusCheckRollup") or []:
        conclusion = check.get("conclusion") if isinstance(check, dict) else None
        if conclusion in {"failure", "failed", "cancelled", "timed_out", "action_required"}:
            return True
    return False


def _has_missing_rollup_conclusion(data: dict[str, Any]) -> bool:
    for check in data.get("statusCheckRollup") or []:
        if isinstance(check, dict) and check.get("conclusion") is None:
            return True
    return False


def poll_merge_queue(repo_root: Path, branch: str, timeout_seconds: int, interval_seconds: int) -> dict[str, object]:
    action = "poll_merge_queue"
    try:
        repo = ensure_space_repo(repo_root)
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})
    safe, unsafe = _safe_branch(action, branch)
    if unsafe is not None:
        return unsafe
    deadline = time.monotonic() + max(timeout_seconds, 0)
    attempts = 0
    try:
        while True:
            attempts += 1
            result = run_command(["gh", "pr", "view", safe, "--json", PR_VIEW_FIELDS], repo)
            data = _json_loads(result.stdout)
            if not isinstance(data, dict):
                return human_decision(action, "GitHub PR view response was ambiguous", {"branch": safe, "attempts": attempts})
            if data.get("mergedAt"):
                return success(action, "Pull request has merged", {"branch": safe, "merged_at": data.get("mergedAt"), "attempts": attempts})
            if data.get("state") == "CLOSED":
                return human_decision(action, "Pull request closed without mergedAt", {"branch": safe, "attempts": attempts})
            if _failed_rollup(data):
                return human_decision(action, "Required merge queue check failed", {"branch": safe, "attempts": attempts})
            merge_state = data.get("mergeStateStatus")
            normalized_merge_state = merge_state.lower() if isinstance(merge_state, str) else merge_state
            if normalized_merge_state not in NONTERMINAL_STATES and not _has_missing_rollup_conclusion(data):
                return human_decision(action, "Pull request merge queue state is ambiguous or unsupported", {"branch": safe, "merge_state": merge_state, "attempts": attempts})
            if time.monotonic() >= deadline:
                return human_decision(action, "Timed out waiting for merge queue to merge pull request", {"branch": safe, "attempts": attempts})
            time.sleep(interval_seconds)
    except (CapabilityError, json.JSONDecodeError) as error:
        return human_decision(action, "Could not poll merge queue safely", {"error_type": type(error).__name__, "error": str(error), "branch": safe})


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("auth-status", "check-main-protection"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--repo-root", required=True, type=Path)
    create = subparsers.add_parser("create")
    create.add_argument("--repo-root", required=True, type=Path)
    create.add_argument("--head", required=True)
    for command in ("enable-auto-merge", "view"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--repo-root", required=True, type=Path)
        subparser.add_argument("--branch", required=True)
    poll = subparsers.add_parser("poll-merge-queue")
    poll.add_argument("--repo-root", required=True, type=Path)
    poll.add_argument("--branch", required=True)
    poll.add_argument("--timeout-seconds", required=True, type=int)
    poll.add_argument("--interval-seconds", required=True, type=int)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.command == "auth-status":
            result = pr_auth_status(args.repo_root)
        elif args.command == "check-main-protection":
            result = check_main_protection(args.repo_root)
        elif args.command == "create":
            result = create_pr(args.repo_root, args.head)
        elif args.command == "enable-auto-merge":
            result = enable_auto_merge(args.repo_root, args.branch)
        elif args.command == "view":
            result = view_pr(args.repo_root, args.branch)
        else:
            result = poll_merge_queue(args.repo_root, args.branch, args.timeout_seconds, args.interval_seconds)
    except Exception as error:  # noqa: BLE001 - CLIs must fail closed with structured JSON.
        result = failure(args.command.replace("-", "_"), "Local GitHub capability wrapper failed unexpectedly", {"error_type": type(error).__name__, "error": str(error)})
    print(json.dumps(result, indent=2, sort_keys=True))
    return _exit_code_for(result)


if __name__ == "__main__":
    raise SystemExit(main())
