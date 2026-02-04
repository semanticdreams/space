---
name: git-commit
description: Commit changes (git commit) for this repo and write consistent commit messages (type(scope) prefix, impact/risk, what/why/how, testing summary, follow-ups, references).
---

# Git Commit Messages (space)

Use this skill whenever you're about to create a commit (or when asked to "commit", "write a commit message", "draft a commit", etc.).

## Workflow and safety

- Verify the change set:
  - `git status`
  - `git diff`
  - `git diff --staged`
- Stage only what you intend to ship; prefer `git add -p` for mixed diffs.
- Never commit secrets/credentials. When in doubt:
  - `git diff --staged | rg -n -i "api[_-]?key|secret|token|password|-----begin|private key"`
- Avoid destructive history ops unless explicitly asked (`reset --hard`, `clean -fdx`, `rebase`, `--amend`, force-push).

## Commit subject line

- Format: `type(scope): <imperative subject>` (scope optional).
- Keep it <= 72 chars and in imperative mood ("Add", "Fix", "Refactor").
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- Scopes (when useful): `engine`, `render`, `physics`, `audio`, `lua`, `ui`, `assets`, `scripts`.
- Breaking changes: append an exclamation mark after type/scope (e.g. feat!:) and call it out in Impact + Risk.

## Body (required for non-trivial changes)

Be explicit about **impact** (user-visible) vs **what** changed (code/data). Include **risk** when plausible.

Template:

```
type(scope): Short imperative subject (<= 72 chars)

Impact:
- <user-visible result / behavior change; include repro if useful>

What:
- <key code/data changes>

Why:
- <motivation / constraints>

How:
- <implementation approach, key files/systems>

Risk:
- <what could go wrong + mitigations/rollback>

Testing:
- <commands run + brief summary; DO NOT paste full logs>

Follow-ups:
- <next steps / cleanup / tech debt>

References:
- Refs: #123
```

## Testing section expectations

- Prefer running the full suite before committing:
  - `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`
- For targeted runs, include the command and a short result summary (e.g., “passed” / “failed: <test name>”).
- Do not paste full test output into the commit message; keep it to a couple lines.

## Practical: avoid shell-quoting footguns

- Prefer writing the message to a file and committing with `-F`, especially if the body contains backticks:
  - `cat > /tmp/commitmsg.txt <<'EOF' ... EOF`
  - `git commit -F /tmp/commitmsg.txt`
