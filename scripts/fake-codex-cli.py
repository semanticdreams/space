#!/usr/bin/env python3
import json
import os
import sys
import time


def log_request(argv, stdin_text):
    path = os.environ.get("FAKE_CODEX_LOG")
    if not path:
        return
    payload = {
        "argv": argv,
        "stdin": stdin_text,
        "env": {
            "OPENAI_BASE_URL": os.environ.get("OPENAI_BASE_URL"),
            "CODEX_API_KEY": os.environ.get("CODEX_API_KEY"),
            "CODEX_INTERNAL_ORIGINATOR_OVERRIDE": os.environ.get(
                "CODEX_INTERNAL_ORIGINATOR_OVERRIDE"
            ),
        },
    }
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)


def emit(event):
    sys.stdout.write(json.dumps(event) + "\n")
    sys.stdout.flush()


def parse_thread_id(argv):
    if "resume" in argv:
        index = argv.index("resume")
        if index + 1 < len(argv):
            return argv[index + 1]
    return os.environ.get("FAKE_CODEX_THREAD_ID", "thread_fake_123")


def main():
    argv = sys.argv[1:]
    stdin_text = sys.stdin.read()
    log_request(argv, stdin_text)

    scenario = os.environ.get("FAKE_CODEX_SCENARIO", "success")
    thread_id = parse_thread_id(argv)
    message = os.environ.get("FAKE_CODEX_MESSAGE", "Hi!")

    if scenario == "malformed":
        sys.stdout.write("{bad json\n")
        sys.stdout.flush()
        return 0

    emit({"type": "thread.started", "thread_id": thread_id})
    emit({"type": "turn.started"})

    if scenario == "turn_failed":
        emit({"type": "turn.failed", "error": {"message": "simulated turn failure"}})
        return 0

    if scenario == "unknowns":
        emit(
            {
                "type": "item.completed",
                "item": {
                    "id": "mystery_1",
                    "type": "mystery_item",
                    "value": 123,
                },
            }
        )
        emit(
            {
                "type": "mystery.event",
                "payload": {"hello": "world"},
            }
        )

    if scenario == "slow_stream":
        emit(
            {
                "type": "item.started",
                "item": {
                    "id": "reasoning_1",
                    "type": "reasoning",
                    "text": "Thinking",
                },
            }
        )
        time.sleep(0.05)
        emit(
            {
                "type": "item.completed",
                "item": {
                    "id": "reasoning_1",
                    "type": "reasoning",
                    "text": "Thinking",
                },
            }
        )
        time.sleep(0.05)

    if scenario == "cancel_wait":
        emit(
            {
                "type": "item.started",
                "item": {
                    "id": "reasoning_1",
                    "type": "reasoning",
                    "text": "Waiting",
                },
            }
        )
        time.sleep(5)
        return 0

    emit(
        {
            "type": "item.completed",
            "item": {
                "id": "message_1",
                "type": "agent_message",
                "text": message,
            },
        }
    )
    emit(
        {
            "type": "turn.completed",
            "usage": {
                "input_tokens": 42,
                "cached_input_tokens": 12,
                "output_tokens": 5,
            },
        }
    )

    if scenario == "exit_error":
        sys.stderr.write("simulated process failure")
        sys.stderr.flush()
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
