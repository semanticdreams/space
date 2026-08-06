#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Sequence


class AnalyzerError(Exception):
    pass


class SchemaDriftError(AnalyzerError):
    pass


@dataclass
class AnalyzerConfig:
    repo_root: Path
    opencode_data_dir: Path
    worktree_parent: Path
    output: Path | None = None
    report_dir: Path | None = None
    since_days: int = 7
    max_excerpt_chars: int = 500
    now: datetime | None = None


SENSITIVE_TABLE_PARTS = ("auth", "account", "credential", "token", "secret")
REQUIRED_COLUMNS = {
    "project": {"id", "worktree", "name", "time_created", "time_updated"},
    "session": {
        "id",
        "project_id",
        "directory",
        "title",
        "agent",
        "model",
        "cost",
        "tokens_input",
        "tokens_output",
        "tokens_reasoning",
        "time_created",
        "time_updated",
    },
    "message": {"id", "session_id", "time_created", "time_updated", "data"},
    "part": {"id", "message_id", "session_id", "time_created", "time_updated", "data"},
}

SECRET_PATTERNS = [
    (
        "private-key",
        re.compile(
            r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(?:-----END [A-Z ]*PRIVATE KEY-----|\Z)",
            re.DOTALL,
        ),
    ),
    ("authorization", re.compile(r"(?i)(authorization\s*[:=]\s*)(?:bearer\s+)?[^\s,;]+")),
    ("bearer-token", re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{8,}")),
    (
        "secret-assignment",
        re.compile(
            r"(?i)(?<![A-Za-z0-9_-])"
            r"([\"']?(?:api[_-]?key|apikey|token|secret|password|authorization|x-api-key)[\"']?\s*[:=]\s*)"
            r"(?:\"([^\"]*)\"|'([^']*)'|([^\s,;}]+))"
        ),
    ),
    (
        "token-prefix",
        re.compile(r"\b(?:sk-proj-|sk-|ghp_|github_pat_|xoxb-|AKIA|ASIA)[A-Za-z0-9_\-]{6,}"),
    ),
]

VALIDATION_RE = re.compile(r"(?i)\b(make test|pytest|ctest|fennel-check|constraints|failed|fail|error)\b")
REVIEW_FIX_RE = re.compile(r"(?is)reviewer finding|finding.+(?:follow-up|fix|fixed|addressed)")
PERMISSION_RE = re.compile(r"(?i)permission (?:prompt|denied)|denied tool|tool .* denied")
SKILL_RE = re.compile(r"(?i)missing skill|wrong skill|should have used .*skill|skill routing")
PERMISSION_CLASS_PATTERNS = {
    "routine-project-scoped": [
        re.compile(r"(?i)\bmake\s+test\b"),
        re.compile(r"(?i)\bpytest\b"),
        re.compile(r"(?i)\bctest\b"),
        re.compile(r"(?i)\bgit\s+status\b"),
        re.compile(r"(?i)\bgit\s+diff\b"),
    ],
    "privileged-bounded": [
        re.compile(r"(?i)\bgit\s+fetch\s+origin\s+main\b"),
        re.compile(r"(?i)\bgit\s+merge\s+--no-edit\s+origin/main\b"),
        re.compile(r"(?i)\bgit\s+push\s+origin\s+HEAD:refs/heads/(?!main\b)\S+"),
        re.compile(r"(?i)\bgh\s+pr\s+create\b"),
        re.compile(r"(?i)\bgh\s+pr\s+view\b"),
        re.compile(r"(?i)\bgh\s+pr\s+merge\s+--auto\b"),
        re.compile(r"(?i)\bgh\s+run\s+list\b"),
        re.compile(r"(?i)\bgh\s+run\s+watch\b"),
    ],
    "role-mismatch": [
        re.compile(r"(?i)\breviewer\b.*\b(?:edit|bash)\b|\b(?:edit|bash)\b.*\breviewer\b"),
        re.compile(r"(?i)\bimplementer\b.*\b(?:push|external)\b|\b(?:push|external)\b.*\bimplementer\b"),
        re.compile(r"(?i)\bweb-researcher\b.*\b(?:local\s+read|read\s+local|local|bash)\b"),
    ],
    "destructive-ambiguous": [
        re.compile(r"(?i)\b(?:force-push|force\s+push)\b|\bgit\s+push\b[^\n]*\s--force\b|\s--force-with-lease\b"),
        re.compile(r"(?i)\bgit\s+rebase\b"),
        re.compile(r"(?i)\bgit\s+reset\b"),
        re.compile(r"(?i)\bgit\s+clean\b"),
        re.compile(r"(?i)\brm\s+-[A-Za-z]*r[A-Za-z]*f\b|\brm\s+-[A-Za-z]*f[A-Za-z]*r\b"),
        re.compile(r"(?i)\bsudo\b|\b(?:apt|apt-get|dnf|yum|pacman|brew)\s+(?:install|remove|upgrade|update)\b|package\s+manager"),
        re.compile(r"(?i)\bgit\s+push\s+origin\s+(?:main|HEAD:refs/heads/main)\b"),
        re.compile(r"(?i)\bauth(?:\.json|\s+file|\s+files)?\b|\bcredential\b|\btoken\b"),
        re.compile(r"(?i)\bbroad\s+(?:home|root)\b|\bhome\s+access\b|\bhome\s+directory\b|\broot\s+(?:access|directory)\b|/(?:home|root)\b"),
    ],
}


def classify_permission_friction(text: str) -> list[str]:
    classes: list[str] = []
    for class_id, patterns in PERMISSION_CLASS_PATTERNS.items():
        if any(pattern.search(text) for pattern in patterns):
            classes.append(class_id)
    if not classes and PERMISSION_RE.search(text):
        return ["destructive-ambiguous"]
    return classes


def _permission_friction_text(text: str) -> str:
    lines = [line for line in text.splitlines() if PERMISSION_RE.search(line)]
    return "\n".join(lines)


def redact_text(text: str) -> tuple[str, list[str]]:
    redacted = text
    labels: list[str] = []
    for label, pattern in SECRET_PATTERNS:
        if pattern.search(redacted):
            labels.append(label)

            def replacement(match: re.Match[str], *, item: str = label) -> str:
                if item == "authorization" and match.lastindex and match.lastindex >= 1:
                    return f"{match.group(1)}[REDACTED:{item}]"
                if item == "secret-assignment" and match.lastindex and match.lastindex >= 4:
                    if match.group(2) is not None:
                        return f'{match.group(1)}"[REDACTED:{item}]"'
                    if match.group(3) is not None:
                        return f"{match.group(1)}'[REDACTED:{item}]'"
                    return f"{match.group(1)}[REDACTED:{item}]"
                return f"[REDACTED:{item}]"

            redacted = pattern.sub(replacement, redacted)
    return redacted, sorted(set(labels))


def bounded_excerpt(text: str, max_chars: int) -> str:
    if max_chars < 0:
        max_chars = 0
    if len(text) <= max_chars:
        return text
    if max_chars <= 1:
        return "…"[:max_chars]
    return text[: max_chars - 1].rstrip() + "…"


def discover_worktrees(repo_root: Path, worktree_parent: Path) -> list[dict[str, str]]:
    repo_root = repo_root.resolve()
    origin = _origin_url(repo_root)
    if not origin:
        return []
    candidates = [repo_root]
    if worktree_parent.exists():
        candidates.extend(child.resolve() for child in worktree_parent.iterdir() if child.is_dir())
    seen: set[Path] = set()
    result: list[dict[str, str]] = []
    for path in candidates:
        if path in seen:
            continue
        seen.add(path)
        if _origin_url(path) == origin:
            result.append({"label": path.name, "path": str(path)})
    return sorted(result, key=lambda item: item["label"])


def analyze(config: AnalyzerConfig) -> dict[str, Any]:
    db_path = config.opencode_data_dir / "opencode.db"
    if not db_path.exists():
        raise AnalyzerError(f"missing OpenCode database: {db_path}")
    worktrees = discover_worktrees(config.repo_root, config.worktree_parent)
    included_paths = [Path(item["path"]).resolve() for item in worktrees]
    now = _normalize_now(config.now)
    cutoff_ms = int((now - timedelta(days=config.since_days)).timestamp() * 1000)

    with _connect_read_only(db_path) as conn:
        _verify_schema(conn)
        projects = _load_projects(conn)
        workspace_paths = _load_workspace_paths(conn)
        rows = _load_session_rows(conn, cutoff_ms)
        raw_sessions = [row for row in rows if _session_in_scope(row, projects, workspace_paths, included_paths)]
        texts = _load_session_texts(conn, [row["id"] for row in raw_sessions])

    sessions = []
    for row in raw_sessions:
        session_ref = _session_ref(row["id"])
        evidence_texts = texts.get(row["id"], [])
        text_blob = "\n".join(evidence_texts)
        safe_title, title_redactions = redact_text(row.get("title") or "")
        safe_agent, _ = redact_text(row.get("agent") or "")
        safe_model, model_redactions = redact_text(row.get("model") or "")
        excerpts = _external_excerpts(config, row["id"], session_ref)
        evidence_excerpt, evidence_redactions = _sanitized_excerpt(
            text_blob,
            config.max_excerpt_chars,
            row["id"],
            session_ref,
        )
        if evidence_excerpt:
            excerpts.insert(
                0,
                {"source": "database", "text": evidence_excerpt, "redactions": evidence_redactions},
            )
        sessions.append(
            {
                "session_ref": session_ref,
                "title": safe_title,
                "agent": safe_agent,
                "model": safe_model,
                "cost": row.get("cost") or 0,
                "tokens": {
                    "input": row.get("tokens_input") or 0,
                    "output": row.get("tokens_output") or 0,
                    "reasoning": row.get("tokens_reasoning") or 0,
                },
                "time_created": row.get("time_created"),
                "time_updated": row.get("time_updated"),
                "redactions": sorted(set(title_redactions + model_redactions)),
                "excerpts": excerpts[:3],
                "evidence_text": text_blob,
                "_raw_session_id": row["id"],
            }
        )

    findings = _findings(sessions)
    for session in sessions:
        del session["evidence_text"]
        del session["_raw_session_id"]
    result = {
        "schema_version": 1,
        "sources": {
            "repo_root": str(config.repo_root.resolve()),
            "opencode_db": str(db_path),
            "opencode_data_dir": str(config.opencode_data_dir),
            "worktree_parent": str(config.worktree_parent),
            "since_days": config.since_days,
        },
        "redaction": {
            "max_excerpt_chars": config.max_excerpt_chars,
            "patterns": [label for label, _ in SECRET_PATTERNS],
        },
        "worktrees": worktrees,
        "sessions": sessions,
        "findings": findings,
        "prior_reports": _prior_reports(config),
    }
    serialized = json.dumps(result, ensure_ascii=False)
    leaked, labels = redact_text(serialized)
    if leaked != serialized:
        raise AnalyzerError(f"sanitizer leak detected: {', '.join(labels)}")
    return result


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Emit sanitized weekly agent workflow evidence JSON.")
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--opencode-data-dir", type=Path, required=True)
    parser.add_argument("--worktree-parent", type=Path, required=True)
    parser.add_argument("--since-days", type=int, default=7)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--report-dir", type=Path)
    parser.add_argument("--max-excerpt-chars", type=int, default=500)
    args = parser.parse_args(argv)
    for path in (args.repo_root, args.opencode_data_dir, args.worktree_parent):
        if not path.exists():
            print(f"missing input path: {path}", file=sys.stderr)
            return 2
    if not (args.opencode_data_dir / "opencode.db").exists():
        print(f"missing input path: {args.opencode_data_dir / 'opencode.db'}", file=sys.stderr)
        return 2
    config = AnalyzerConfig(
        repo_root=args.repo_root,
        opencode_data_dir=args.opencode_data_dir,
        worktree_parent=args.worktree_parent,
        output=args.output,
        report_dir=args.report_dir,
        since_days=args.since_days,
        max_excerpt_chars=args.max_excerpt_chars,
    )
    try:
        result = analyze(config)
    except SchemaDriftError as exc:
        print(str(exc), file=sys.stderr)
        return 3
    except AnalyzerError as exc:
        message = str(exc)
        print(message, file=sys.stderr)
        return 4 if "sanitizer leak" in message else 3
    except (sqlite3.Error, OSError) as exc:
        print(f"database access failed: {exc}", file=sys.stderr)
        return 3
    payload = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8")
    else:
        print(payload, end="")
    return 0


def _origin_url(path: Path) -> str | None:
    try:
        completed = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=path,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return completed.stdout.strip() or None


def _connect_read_only(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=5.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA query_only = ON")

    def authorizer(action: int, arg1: str | None, arg2: str | None, dbname: str | None, source: str | None) -> int:
        del dbname, source
        table_name = arg1 if action == sqlite3.SQLITE_READ else arg2 or arg1
        if table_name and any(part in table_name.lower() for part in SENSITIVE_TABLE_PARTS):
            return sqlite3.SQLITE_DENY
        return sqlite3.SQLITE_OK

    conn.set_authorizer(authorizer)
    return conn


def _verify_schema(conn: sqlite3.Connection) -> None:
    for table, required in REQUIRED_COLUMNS.items():
        try:
            rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
        except sqlite3.DatabaseError as exc:
            raise SchemaDriftError(f"cannot inspect {table}: {exc}") from exc
        present = {row["name"] for row in rows}
        missing = sorted(required - present)
        if missing:
            raise SchemaDriftError(f"schema drift in {table}: missing {', '.join(missing)}")


def _load_projects(conn: sqlite3.Connection) -> dict[str, sqlite3.Row]:
    return {row["id"]: row for row in conn.execute("SELECT id, worktree, name FROM project")}


def _load_workspace_paths(conn: sqlite3.Connection) -> dict[str, list[str]]:
    if not _table_exists(conn, "workspace"):
        return {}
    rows = conn.execute("PRAGMA table_info(workspace)").fetchall()
    columns = {row["name"] for row in rows}
    if "project_id" not in columns:
        return {}
    path_columns = [name for name in ("path", "directory", "worktree", "root") if name in columns]
    if not path_columns:
        return {}
    select_columns = ", ".join(["project_id", *path_columns])
    paths: dict[str, list[str]] = {}
    for row in conn.execute(f"SELECT {select_columns} FROM workspace"):
        project_paths = paths.setdefault(row["project_id"], [])
        for column in path_columns:
            value = row[column]
            if value:
                project_paths.append(value)
    return paths


def _table_exists(conn: sqlite3.Connection, table_name: str) -> bool:
    row = conn.execute("SELECT 1 FROM sqlite_master WHERE type IN ('table', 'view') AND name = ?", (table_name,)).fetchone()
    return row is not None


def _load_session_rows(conn: sqlite3.Connection, cutoff_ms: int) -> list[dict[str, Any]]:
    query = """
        SELECT id, project_id, directory, title, agent, model, cost, tokens_input, tokens_output,
               tokens_reasoning, time_created, time_updated
        FROM session
        WHERE time_updated >= ? OR time_created >= ?
        ORDER BY time_created, id
    """
    return [dict(row) for row in conn.execute(query, (cutoff_ms, cutoff_ms))]


def _session_in_scope(
    row: dict[str, Any],
    projects: dict[str, sqlite3.Row],
    workspace_paths: dict[str, list[str]],
    included_paths: list[Path],
) -> bool:
    project = projects.get(row.get("project_id"))
    candidates = [row.get("directory")]
    if project is not None:
        candidates.append(project["worktree"])
    candidates.extend(workspace_paths.get(row.get("project_id"), []))
    for value in candidates:
        if value and _path_is_under(Path(value), included_paths):
            return True
    return False


def _path_is_under(path: Path, roots: list[Path]) -> bool:
    try:
        resolved = path.resolve()
    except OSError:
        resolved = path.absolute()
    return any(resolved == root or root in resolved.parents for root in roots)


def _load_session_texts(conn: sqlite3.Connection, session_ids: list[str]) -> dict[str, list[str]]:
    if not session_ids:
        return {}
    placeholders = ",".join("?" for _ in session_ids)
    rows = conn.execute(
        f"SELECT session_id, data FROM part WHERE session_id IN ({placeholders}) ORDER BY time_created",
        session_ids,
    )
    texts: dict[str, list[str]] = {session_id: [] for session_id in session_ids}
    for row in rows:
        parsed = _json_data(row["data"])
        text = parsed.get("text") if isinstance(parsed, dict) else None
        if isinstance(text, str):
            texts.setdefault(row["session_id"], []).append(text)
    return texts


def _json_data(value: str) -> Any:
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return {}


def _external_excerpts(config: AnalyzerConfig, raw_session_id: str, session_ref: str) -> list[dict[str, Any]]:
    excerpts: list[dict[str, Any]] = []
    for subdir in ("tool-output", "log"):
        root = config.opencode_data_dir / subdir
        if not root.exists():
            continue
        for path in sorted(item for item in root.rglob("*") if item.is_file()):
            if len(excerpts) >= 3:
                return excerpts
            try:
                text = path.read_text(encoding="utf-8", errors="replace")[: 16 * 1024]
            except OSError:
                continue
            if raw_session_id not in path.name and raw_session_id not in text:
                continue
            safe, labels = _sanitized_excerpt(text, config.max_excerpt_chars, raw_session_id, session_ref)
            excerpts.append(
                {
                    "source": subdir,
                    "path": _replace_session_id(path.name, raw_session_id, session_ref),
                    "text": safe,
                    "redactions": labels,
                }
            )
    return excerpts


def _session_ref(raw_session_id: str) -> str:
    return hashlib.sha256(raw_session_id.encode("utf-8")).hexdigest()[:12]


def _replace_session_id(text: str, raw_session_id: str, session_ref: str) -> str:
    return text.replace(raw_session_id, f"session:{session_ref}")


def _sanitized_excerpt(
    text: str,
    max_chars: int,
    raw_session_id: str | None = None,
    session_ref: str | None = None,
) -> tuple[str, list[str]]:
    if raw_session_id and session_ref:
        text = _replace_session_id(text, raw_session_id, session_ref)
    safe, labels = redact_text(text)
    return bounded_excerpt(safe, max_chars), labels


def _findings(sessions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    specs = [
        ("repeated-validation-failure", VALIDATION_RE, 2),
        ("review-fix-loop-churn", REVIEW_FIX_RE, 1),
        ("permission-friction", PERMISSION_RE, 1),
        ("skill-routing-gap", SKILL_RE, 1),
    ]
    findings: list[dict[str, Any]] = []
    for finding_id, pattern, threshold in specs:
        count = 0
        refs: list[str] = []
        evidence: list[str] = []
        for session in sessions:
            text = str(session.get("evidence_text", "")) + "\n" + "\n".join(
                excerpt.get("text", "") for excerpt in session.get("excerpts", [])
            )
            matches = pattern.findall(text)
            if matches:
                count += len(matches)
                refs.append(session["session_ref"])
                safe, _ = _sanitized_excerpt(text, 200, session.get("_raw_session_id"), session["session_ref"])
                evidence.append(safe)
        if count >= threshold:
            finding = {
                "id": finding_id,
                "count": count,
                "session_refs": sorted(set(refs)),
                "evidence": evidence[:3],
            }
            if finding_id == "permission-friction":
                classes: dict[str, int] = {}
                refs_by_class: dict[str, set[str]] = {}
                for session in sessions:
                    text = str(session.get("evidence_text", "")) + "\n" + "\n".join(
                        excerpt.get("text", "") for excerpt in session.get("excerpts", [])
                    )
                    permission_text = _permission_friction_text(text)
                    if not permission_text:
                        continue
                    for class_id in classify_permission_friction(permission_text):
                        classes[class_id] = classes.get(class_id, 0) + 1
                        refs_by_class.setdefault(class_id, set()).add(session["session_ref"])
                finding["classes"] = dict(sorted(classes.items()))
                finding["session_refs_by_class"] = {
                    class_id: sorted(class_refs) for class_id, class_refs in sorted(refs_by_class.items())
                }
            findings.append(finding)
    return findings


def _prior_reports(config: AnalyzerConfig) -> list[str]:
    report_dir = config.report_dir or (config.repo_root / "docs/dev/reports/agent-workflow")
    if not report_dir.exists():
        return []
    lines: list[str] = []
    for path in sorted(report_dir.glob("*.md")):
        try:
            content = path.read_text(encoding="utf-8")
        except OSError:
            continue
        for line in content.splitlines():
            stripped = line.strip()
            if stripped.startswith("#") or re.search(r"(?i)finding id|deferred|re-check", stripped):
                safe, _ = _sanitized_excerpt(stripped, config.max_excerpt_chars)
                lines.append(safe)
    return lines[:50]


def _normalize_now(now: datetime | None) -> datetime:
    current = now or datetime.now(timezone.utc)
    if current.tzinfo is None:
        return current.replace(tzinfo=timezone.utc)
    return current.astimezone(timezone.utc)


if __name__ == "__main__":
    raise SystemExit(main())
