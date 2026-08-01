import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER = REPO_ROOT / "scripts" / "build-log-runner.sh"


def run_runner(tmp_path: Path, *command: str, tail_lines: str = "3") -> subprocess.CompletedProcess[str]:
    log_path = tmp_path / "logs" / "build.log"
    return subprocess.run(
        [
            str(RUNNER),
            "--log",
            str(log_path),
            "--label",
            "test build",
            "--tail-lines",
            tail_lines,
            "--",
            *command,
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=REPO_ROOT,
    )


def test_success_is_quiet_and_writes_complete_transcript(tmp_path: Path) -> None:
    log_path = tmp_path / "logs" / "build.log"

    result = run_runner(
        tmp_path,
        "bash",
        "-c",
        "echo hidden stdout; echo hidden stderr >&2",
    )

    assert result.returncode == 0
    assert f"Log: {log_path.resolve()}" in result.stdout
    assert "OK: test build complete." in result.stdout
    assert "hidden stdout" not in result.stdout
    assert "hidden stderr" not in result.stdout
    assert "hidden stdout" not in result.stderr
    assert "hidden stderr" not in result.stderr
    assert log_path.read_text(encoding="utf-8") == "hidden stdout\nhidden stderr\n"


def test_failure_preserves_exit_code_and_prints_bounded_tail(tmp_path: Path) -> None:
    log_path = tmp_path / "logs" / "build.log"

    result = run_runner(
        tmp_path,
        "bash",
        "-c",
        "for i in $(seq 1 10); do echo line-$i; done; echo error-line >&2; exit 7",
        tail_lines="4",
    )

    assert result.returncode == 7
    assert f"Log: {log_path.resolve()}" in result.stdout
    assert "FAILED: test build exited with status 7." in result.stderr
    assert f"--- Last 4 lines of {log_path.resolve()} ---" in result.stderr
    # Use line-boundary matching to avoid substring collisions
    # (e.g. "line-1" matching inside "line-10").
    stderr_lines = result.stderr.splitlines()
    assert "line-1" not in stderr_lines
    assert "line-7" not in stderr_lines
    assert "line-8" in stderr_lines
    assert "line-9" in stderr_lines
    assert "line-10" in stderr_lines
    assert "error-line" in stderr_lines
    assert log_path.read_text(encoding="utf-8").startswith("line-1\nline-2\n")


def test_missing_command_returns_wrapper_usage_error(tmp_path: Path) -> None:
    log_path = tmp_path / "logs" / "build.log"

    result = subprocess.run(
        [
            str(RUNNER),
            "--log",
            str(log_path),
            "--label",
            "test build",
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=REPO_ROOT,
    )

    assert result.returncode == 2
    assert "usage: build-log-runner.sh" in result.stderr
