import json
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_ROOT))

import weekly_agent_workflow_analyzer as analyzer


def create_fixture_space_worktrees(tmp_path: Path) -> tuple[Path, Path]:
    parent = tmp_path / "space-parent"
    repo = parent / "space"
    sibling = parent / "space-feature"
    unrelated = parent / "other"
    for path in (repo, sibling, unrelated):
        path.mkdir(parents=True)
        subprocess.run(["git", "init"], cwd=path, check=True, stdout=subprocess.DEVNULL)
    for path in (repo, sibling):
        subprocess.run(
            ["git", "remote", "add", "origin", "git@example.com:semanticdreams/space.git"], cwd=path, check=True
        )
    subprocess.run(["git", "remote", "add", "origin", "git@example.com:someone/other.git"], cwd=unrelated, check=True)
    return repo, parent


def create_fixture_db(data_dir: Path, repo: Path, *, repeated_failures: bool = False) -> None:
    conn = sqlite3.connect(data_dir / "opencode.db")
    conn.execute(
        "CREATE TABLE project (id text primary key, worktree text, name text, time_created integer, time_updated integer)"
    )
    conn.execute(
        "CREATE TABLE session (id text primary key, project_id text, directory text, title text, agent text, model text, cost real, tokens_input integer, tokens_output integer, tokens_reasoning integer, time_created integer, time_updated integer)"
    )
    conn.execute(
        "CREATE TABLE message (id text primary key, session_id text, time_created integer, time_updated integer, data text)"
    )
    conn.execute(
        "CREATE TABLE part (id text primary key, message_id text, session_id text, time_created integer, time_updated integer, data text)"
    )
    conn.execute("CREATE TABLE account (id text, secret text)")
    conn.execute("INSERT INTO account VALUES ('acct', 'sk-live-sensitive')")
    conn.execute("INSERT INTO project VALUES ('space-project', ?, 'space', 1, 1)", (str(repo),))
    conn.execute("INSERT INTO project VALUES ('other-project', ?, 'other', 1, 1)", (str(repo.parent / "other"),))
    conn.execute(
        "INSERT INTO session VALUES ('project-session-1', 'space-project', ?, 'Project session', 'implementer', '{\"id\":\"deepseek\"}', 1.2, 100, 20, 5, 1785500000000, 1785500100000)",
        (str(repo),),
    )
    conn.execute(
        "INSERT INTO session VALUES ('unrelated-session', 'other-project', ?, 'Other session', 'supervisor', '{}', 0, 1, 1, 0, 1785500000000, 1785500100000)",
        (str(repo.parent / "other"),),
    )
    texts = ["make test failed with FAIL"]
    if repeated_failures:
        texts = ["make test failed", "fennel-check error", "constraints FAIL"]
    for index, text in enumerate(texts):
        message_id = f"msg-{index}"
        part_id = f"part-{index}"
        conn.execute(
            "INSERT INTO message VALUES (?, 'project-session-1', 1785500000000, 1785500000000, ?)",
            (message_id, json.dumps({"role": "assistant"})),
        )
        conn.execute(
            "INSERT INTO part VALUES (?, ?, 'project-session-1', 1785500000000, 1785500000000, ?)",
            (part_id, message_id, json.dumps({"type": "text", "text": text})),
        )
    conn.commit()
    conn.close()


def config_for(tmp_path: Path, *, repeated_failures: bool = False) -> analyzer.AnalyzerConfig:
    repo, parent = create_fixture_space_worktrees(tmp_path)
    data_dir = tmp_path / "opencode-data"
    data_dir.mkdir()
    create_fixture_db(data_dir, repo, repeated_failures=repeated_failures)
    return analyzer.AnalyzerConfig(
        repo_root=repo,
        opencode_data_dir=data_dir,
        worktree_parent=parent,
        since_days=7,
        now=datetime(2026, 7, 31, 12, 0, tzinfo=timezone.utc),
    )


def append_fixture_part(data_dir: Path, session_id: str, text: str, index: int) -> None:
    conn = sqlite3.connect(data_dir / "opencode.db")
    message_id = f"extra-msg-{index}"
    part_id = f"extra-part-{index}"
    conn.execute(
        "INSERT INTO message VALUES (?, ?, 1785500000000, 1785500000000, ?)",
        (message_id, session_id, json.dumps({"role": "assistant"})),
    )
    conn.execute(
        "INSERT INTO part VALUES (?, ?, ?, 1785500000000, 1785500000000, ?)",
        (part_id, message_id, session_id, json.dumps({"type": "text", "text": text})),
    )
    conn.commit()
    conn.close()


def long_private_key(secret: str = "private-key-body-should-not-leak") -> str:
    return "-----BEGIN PRIVATE KEY-----\n" + ("A" * 120) + secret + "\n-----END PRIVATE KEY-----"


def test_redact_text_removes_common_secrets() -> None:
    private_key = "-----BEGIN PRIVATE KEY-----\nabc123\n-----END PRIVATE KEY-----"
    text = (
        "Authorization: Bearer bearer-token-value sk-proj-projectsecret password=hunter2 "
        "x-api-key: ghp_abcdefghijklmnopqrstuvwxyz " + private_key
    )

    redacted, labels = analyzer.redact_text(text)

    assert "bearer-token-value" not in redacted
    assert "sk-proj-projectsecret" not in redacted
    assert "hunter2" not in redacted
    assert "ghp_abcdefghijklmnopqrstuvwxyz" not in redacted
    assert "abc123" not in redacted
    assert "[REDACTED" in redacted
    assert {"authorization", "secret-assignment", "token-prefix", "private-key"}.issubset(set(labels))


def test_redact_text_removes_json_style_secret_assignments() -> None:
    text = '{"password": "hunter2", "api_key": "plain-secret-value", "token": "opaque-session-value"}'

    redacted, labels = analyzer.redact_text(text)

    assert "hunter2" not in redacted
    assert "plain-secret-value" not in redacted
    assert "opaque-session-value" not in redacted
    assert "secret-assignment" in labels


def test_analyze_redacts_json_style_secret_assignments(tmp_path: Path) -> None:
    config = config_for(tmp_path)
    append_fixture_part(
        config.opencode_data_dir,
        "project-session-1",
        '{"password": "hunter2", "api_key": "plain-secret-value", "token": "opaque-session-value"}',
        1,
    )

    result = analyzer.analyze(config)
    serialized = json.dumps(result)

    assert "hunter2" not in serialized
    assert "plain-secret-value" not in serialized
    assert "opaque-session-value" not in serialized


def test_discover_worktrees_includes_matching_origin_only(tmp_path: Path) -> None:
    repo, parent = create_fixture_space_worktrees(tmp_path)

    worktrees = analyzer.discover_worktrees(repo, parent)

    assert {item["label"] for item in worktrees} == {"space", "space-feature"}
    assert all("other" not in item["path"] for item in worktrees)


def test_analyze_excludes_unrelated_sessions_and_sensitive_tables(tmp_path: Path) -> None:
    result = analyzer.analyze(config_for(tmp_path))
    serialized = json.dumps(result)

    assert result["schema_version"] == 1
    assert [session["title"] for session in result["sessions"]] == ["Project session"]
    assert "unrelated-session" not in serialized
    assert "sk-live-sensitive" not in serialized
    assert result["sessions"][0]["session_ref"] != "project-session-1"
    assert len(result["sessions"][0]["session_ref"]) == 12


def test_analyze_adds_bounded_redacted_tool_output_excerpts(tmp_path: Path) -> None:
    config = config_for(tmp_path)
    tool_dir = config.opencode_data_dir / "tool-output"
    tool_dir.mkdir()
    (tool_dir / "project-session-1-output.txt").write_text(
        "project-session-1 Authorization: Bearer raw-token " + ("x" * 200), encoding="utf-8"
    )
    config.max_excerpt_chars = 80

    result = analyzer.analyze(config)

    excerpts = [excerpt for excerpt in result["sessions"][0]["excerpts"] if excerpt["source"] == "tool-output"]
    assert len(excerpts) == 1
    assert len(excerpts[0]["text"]) <= 80
    assert "raw-token" not in excerpts[0]["text"]
    assert "project-session-1" not in excerpts[0]["text"]
    assert excerpts[0]["redactions"]


def test_analyze_redacts_long_private_keys_before_database_excerpt_truncation(tmp_path: Path) -> None:
    config = config_for(tmp_path)
    config.max_excerpt_chars = 80
    append_fixture_part(config.opencode_data_dir, "project-session-1", long_private_key(), 1)

    result = analyzer.analyze(config)
    serialized = json.dumps(result)

    assert "private-key-body-should-not-leak" not in serialized
    assert "AAAAAAAAAAAAAAAAAAAAAAAA" not in serialized
    assert "BEGIN PRIVATE KEY" not in serialized


def test_analyze_redacts_long_private_keys_before_external_excerpt_truncation(tmp_path: Path) -> None:
    config = config_for(tmp_path)
    config.max_excerpt_chars = 80
    for dirname in ("tool-output", "log"):
        directory = config.opencode_data_dir / dirname
        directory.mkdir(exist_ok=True)
        (directory / "project-session-1-sensitive-output.txt").write_text(
            "project-session-1 " + long_private_key(f"{dirname}-secret-should-not-leak"),
            encoding="utf-8",
        )

    result = analyzer.analyze(config)
    serialized = json.dumps(result)

    assert "project-session-1" not in serialized
    assert "tool-output-secret-should-not-leak" not in serialized
    assert "log-secret-should-not-leak" not in serialized
    assert "BEGIN PRIVATE KEY" not in serialized


def test_repeated_validation_failure_aggregates_evidence(tmp_path: Path) -> None:
    result = analyzer.analyze(config_for(tmp_path, repeated_failures=True))

    finding = next(item for item in result["findings"] if item["id"] == "repeated-validation-failure")
    assert finding["count"] >= 3
    assert finding["session_refs"] == [result["sessions"][0]["session_ref"]]


def test_finding_evidence_redacts_long_private_keys_before_truncation(tmp_path: Path) -> None:
    config = config_for(tmp_path, repeated_failures=True)
    config.max_excerpt_chars = 80
    append_fixture_part(
        config.opencode_data_dir,
        "project-session-1",
        "pytest failed " + long_private_key("finding-secret-should-not-leak"),
        1,
    )

    result = analyzer.analyze(config)
    serialized = json.dumps(result)

    finding = next(item for item in result["findings"] if item["id"] == "repeated-validation-failure")

    assert finding["evidence"]
    assert "finding-secret-should-not-leak" not in serialized
    assert "BEGIN PRIVATE KEY" not in serialized


def test_schema_drift_raises_for_missing_required_columns(tmp_path: Path) -> None:
    repo, parent = create_fixture_space_worktrees(tmp_path)
    data_dir = tmp_path / "opencode-data"
    data_dir.mkdir()
    conn = sqlite3.connect(data_dir / "opencode.db")
    conn.execute("CREATE TABLE project (id text primary key)")
    conn.commit()
    conn.close()

    with pytest.raises(analyzer.SchemaDriftError):
        analyzer.analyze(
            analyzer.AnalyzerConfig(
                repo_root=repo,
                opencode_data_dir=data_dir,
                worktree_parent=parent,
                now=datetime(2026, 7, 31, 12, 0, tzinfo=timezone.utc),
            )
        )
