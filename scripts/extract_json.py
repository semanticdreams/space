#!/usr/bin/env python3
"""Extract the first JSON object matching required top-level keys."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("destination")
    parser.add_argument("--require", action="append", default=[])
    args = parser.parse_args()

    text = Path(args.source).read_text(encoding="utf-8", errors="replace")
    decoder = json.JSONDecoder()

    for index, char in enumerate(text):
        if char != "{":
            continue
        try:
            value, _ = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        if not isinstance(value, dict):
            continue
        if not all(key in value for key in args.require):
            continue
        Path(args.destination).write_text(
            json.dumps(value, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        return 0

    required = ", ".join(args.require) or "(none)"
    raise SystemExit(
        f"No valid JSON object containing required keys {required} found in {args.source}"
    )


if __name__ == "__main__":
    raise SystemExit(main())
