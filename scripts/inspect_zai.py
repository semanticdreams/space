#!/usr/bin/env python3
import argparse
import json
import os
import sys
import urllib.error
import urllib.request


def build_payload(model: str, system: str, prompt: str, temperature: float):
    return {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
        "temperature": temperature,
        "stream": False,
    }


def request_chat_completion(api_key: str, payload: dict, timeout: int):
    url = "https://api.z.ai/api/paas/v4/chat/completions"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        method="POST",
        data=data,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept-Language": "en-US,en",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read().decode("utf-8")
        return resp.status, resp.headers, body


def validate_response(payload: dict):
    if not isinstance(payload, dict):
        raise ValueError("Response payload is not an object")
    if "choices" not in payload or not isinstance(payload["choices"], list) or not payload["choices"]:
        raise ValueError("Response missing choices array")
    message = payload["choices"][0].get("message")
    if not isinstance(message, dict):
        raise ValueError("Response missing choices[0].message")
    role = message.get("role")
    content = message.get("content")
    if role != "assistant":
        raise ValueError(f"Unexpected role: {role}")
    if not isinstance(content, str):
        raise ValueError("Message content is not a string")
    usage = payload.get("usage")
    if usage is None or not isinstance(usage, dict):
        raise ValueError("Response missing usage object")
    for key in ("prompt_tokens", "completion_tokens", "total_tokens"):
        if key not in usage:
            raise ValueError(f"Response usage missing {key}")


def main():
    parser = argparse.ArgumentParser(description="Online ZAI chat completion sanity check.")
    parser.add_argument("--model", default="glm-4.7")
    parser.add_argument("--system", default="You are a helpful AI assistant.")
    parser.add_argument("--prompt", default="Hello, please introduce yourself.")
    parser.add_argument("--temperature", type=float, default=1.0)
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--write-response", help="Optional path to write the raw JSON response.")
    args = parser.parse_args()

    api_key = os.getenv("ZAI_API_KEY")
    if not api_key:
        print("Missing ZAI_API_KEY in environment.", file=sys.stderr)
        return 2

    payload = build_payload(args.model, args.system, args.prompt, args.temperature)
    try:
        status, headers, body = request_chat_completion(api_key, payload, args.timeout)
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        print(f"HTTP error {exc.code}: {raw}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"Request failed: {exc}", file=sys.stderr)
        return 1

    try:
        response_json = json.loads(body)
    except json.JSONDecodeError as exc:
        print(f"Invalid JSON response: {exc}", file=sys.stderr)
        print(body, file=sys.stderr)
        return 1

    try:
        validate_response(response_json)
    except ValueError as exc:
        print(f"Validation failed: {exc}", file=sys.stderr)
        print(json.dumps(response_json, indent=2), file=sys.stderr)
        return 1

    print(f"Status: {status}")
    request_id = response_json.get("request_id") or headers.get("x-request-id") or headers.get("request-id")
    if request_id:
        print(f"Request ID: {request_id}")
    usage = response_json.get("usage", {})
    print(
        "Usage:",
        f"prompt_tokens={usage.get('prompt_tokens')},",
        f"completion_tokens={usage.get('completion_tokens')},",
        f"total_tokens={usage.get('total_tokens')}",
    )
    message = response_json["choices"][0]["message"]
    preview = message.get("content", "")[:200].replace("\n", " ")
    print(f"Assistant preview: {preview}")

    if args.write_response:
        with open(args.write_response, "w", encoding="utf-8") as handle:
            json.dump(response_json, handle, ensure_ascii=False, indent=2)
        print(f"Wrote response to {args.write_response}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
