#!/usr/bin/env python3
"""Verify a global OpenCode home uses bounded Space project config links."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import opencode_capabilities as capabilities


def exit_code_for(result: dict[str, object]) -> int:
    status = result.get("status")
    if status == "pass":
        return 0
    if status == "human_decision_required":
        return 2
    return 3


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--opencode-home", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = capabilities.audit_opencode_home(args.repo_root, args.opencode_home)
    except Exception as error:  # noqa: BLE001 - CLI must convert unexpected exceptions into structured JSON.
        result = capabilities.failure(
            "audit_opencode_home",
            "Local validation failed before OpenCode home could be verified",
            {"error_type": type(error).__name__, "error": str(error)},
        )
    print(json.dumps(result, indent=2, sort_keys=True))
    return exit_code_for(result)


if __name__ == "__main__":
    raise SystemExit(main())
