# Local Quiet CEF-Light Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make default local `make build` quiet, logged, and CEF-off while preserving explicit full CEF build targets and documentation.

**Architecture:** Add one small Bash log-runner script that owns quiet command execution, log creation, summary output, failure-tail output, and exit-code preservation. Wire Makefile defaults to minimal CEF-off configure/build commands, add explicit full CEF targets using the same log runner, and pin behavior with Python pytest tests over the wrapper and Makefile dry-runs.

**Tech Stack:** GNU Make, Bash, CMake, Python 3 pytest, Markdown/VitePress docs.

## Global Constraints

- `make build` captures configure/build output to `build/logs/build.log`, prints the log path up front, and uses the minimal profile with CEF disabled.
- `make build-full` has the same logged-output behavior and performs a CEF-enabled build for browser-surface development and full packaging checks.
- `make cmake`, `make cmake-minimal`, and `make cmake-full` make configure intent explicit.
- Same build directory reconfiguration is allowed, but Makefile recipes should pass both profile and CEF flags explicitly so switching between minimal and full is deterministic.
- The build log path must be printed before configure/build commands start so a human can inspect or follow the log while the build is running.
- Build wrapper failures must preserve the underlying command exit code.
- Existing release script behavior remains profile-based; full release profiles still enable CEF.
- Direct `cmake -B build` defaults are out of scope; this design targets local Makefile workflows.
- This is a local Makefile workflow change, not a rewrite of CEF integration.

---

## File Structure

- Create `scripts/build-log-runner.sh`: focused Bash helper that runs one command quietly, writes combined stdout/stderr to a log file, prints the absolute log path before execution, prints concise success/failure summaries, prints a bounded tail on failure, and exits with the wrapped command status.
- Create `scripts/tests/test_build_log_runner.py`: pytest coverage for log path output, quiet success behavior, full transcript capture, bounded failure tail, and exit-code preservation.
- Modify `Makefile`: add minimal/full CMake command variables, add `cmake-minimal`, `cmake-full`, and `build-full`, make `cmake` default to minimal, make `build` run configure+build through the log runner, and make package-oriented local targets use the full build path.
- Create `scripts/tests/test_makefile_build_workflow.py`: pytest dry-run assertions that default targets are minimal/CEF-off, full targets are CEF-on, logged build targets use `build/logs/build.log`, and packaging targets depend on full build behavior.
- Modify `docs/dev/building.md`: document quiet default build behavior, full log location, failure-tail behavior, default minimal/CEF-off profile, explicit full CEF targets, and package target expectations. No new `docs/dev/**` page is needed because `docs/dev/building.md` is already the canonical developer build workflow page.

---

### Task 1: Build Log Runner

**Files:**
- Create: `scripts/build-log-runner.sh`
- Create: `scripts/tests/test_build_log_runner.py`

**Interfaces:**
- Consumes: Bash command passed after `--`.
- Produces: executable CLI `scripts/build-log-runner.sh --log <path> --label <label> [--tail-lines <n>] -- <command> [args...]`; Makefile targets rely on this exact interface.

- [ ] **Step 1: Write failing pytest coverage for the wrapper**

Create `scripts/tests/test_build_log_runner.py` with:

```python
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
    assert "line-1" not in result.stderr
    assert "line-7" not in result.stderr
    assert "line-8" in result.stderr
    assert "line-9" in result.stderr
    assert "line-10" in result.stderr
    assert "error-line" in result.stderr
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
```

- [ ] **Step 2: Run wrapper tests and verify they fail because the script does not exist**

Run:

```bash
python3 -m pytest scripts/tests/test_build_log_runner.py -q
```

Expected: FAIL with an error that `scripts/build-log-runner.sh` is missing.

- [ ] **Step 3: Add the build log runner implementation**

Create `scripts/build-log-runner.sh` with:

```bash
#!/usr/bin/env bash
set -u

usage() {
    echo "usage: build-log-runner.sh --log <path> --label <label> [--tail-lines <n>] -- <command> [args...]" >&2
}

LOG_PATH=""
LABEL="build"
TAIL_LINES="${SPACE_BUILD_LOG_TAIL_LINES:-80}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                usage
                exit 2
            fi
            LOG_PATH="$2"
            shift 2
            ;;
        --label)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                usage
                exit 2
            fi
            LABEL="$2"
            shift 2
            ;;
        --tail-lines)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                usage
                exit 2
            fi
            TAIL_LINES="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [[ -z "${LOG_PATH}" || $# -eq 0 ]]; then
    usage
    exit 2
fi

if ! [[ "${TAIL_LINES}" =~ ^[0-9]+$ ]] || [[ "${TAIL_LINES}" -lt 1 ]]; then
    echo "error: --tail-lines must be a positive integer" >&2
    exit 2
fi

LOG_DIR="$(dirname "${LOG_PATH}")"
LOG_BASENAME="$(basename "${LOG_PATH}")"

if ! mkdir -p "${LOG_DIR}"; then
    echo "error: failed to create log directory: ${LOG_DIR}" >&2
    exit 2
fi

LOG_DIR_ABS="$(cd "${LOG_DIR}" && pwd)"
LOG_ABS="${LOG_DIR_ABS}/${LOG_BASENAME}"

if ! : > "${LOG_ABS}"; then
    echo "error: failed to initialize log file: ${LOG_ABS}" >&2
    exit 2
fi

printf '==> %s\n' "${LABEL}"
printf 'Log: %s\n' "${LOG_ABS}"
printf 'Running quietly; full transcript is being written to the log.\n'

"$@" >"${LOG_ABS}" 2>&1
STATUS=$?

if [[ "${STATUS}" -eq 0 ]]; then
    printf 'OK: %s complete. Full log: %s\n' "${LABEL}" "${LOG_ABS}"
    exit 0
fi

{
    printf 'FAILED: %s exited with status %d. Full log: %s\n' "${LABEL}" "${STATUS}" "${LOG_ABS}"
    printf '%s\n' "--- Last ${TAIL_LINES} lines of ${LOG_ABS} ---"
    tail -n "${TAIL_LINES}" "${LOG_ABS}" 2>/dev/null || true
    printf '%s\n' "--- End log tail ---"
} >&2

exit "${STATUS}"
```

- [ ] **Step 4: Mark the wrapper executable**

Run:

```bash
chmod +x scripts/build-log-runner.sh
```

- [ ] **Step 5: Run wrapper tests and verify they pass**

Run:

```bash
python3 -m pytest scripts/tests/test_build_log_runner.py -q
```

Expected: PASS.

- [ ] **Step 6: Commit wrapper and wrapper tests**

Run:

```bash
git add scripts/build-log-runner.sh scripts/tests/test_build_log_runner.py
git commit -m "feat(scripts): add quiet build log runner"
```

---

### Task 2: Makefile Minimal/Full Build Wiring

**Files:**
- Modify: `Makefile`
- Create: `scripts/tests/test_makefile_build_workflow.py`

**Interfaces:**
- Consumes: `scripts/build-log-runner.sh --log <path> --label <label> [--tail-lines <n>] -- <command> [args...]`.
- Produces: Make targets `cmake`, `cmake-minimal`, `cmake-full`, `build`, and `build-full`; default `build` writes `build/logs/build.log`; `appimage` and `pack` use `build-full`.

- [ ] **Step 1: Write failing Makefile dry-run tests**

Create `scripts/tests/test_makefile_build_workflow.py` with:

```python
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def dry_run(target: str) -> str:
    result = subprocess.run(
        ["make", "-n", target],
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout + result.stderr


def assert_has_profile_flags(output: str, *, profile: str, cef: str) -> None:
    assert f"-DSPACE_BUILD_PROFILE={profile}" in output
    assert f"-DSPACE_ENABLE_CEF={cef}" in output


def test_default_build_uses_single_logged_minimal_configure_and_build() -> None:
    output = dry_run("build")

    assert output.count("./scripts/build-log-runner.sh") == 1
    assert "--log build/logs/build.log" in output
    assert '--label "space minimal build"' in output
    assert "cmake -B build" in output
    assert "cmake --build build -- -j" in output
    assert_has_profile_flags(output, profile="minimal", cef="OFF")
    assert "-DSPACE_ENABLE_CEF=ON" not in output
    assert "cd build && make" not in output


def test_full_build_uses_same_log_mechanism_with_cef_enabled() -> None:
    output = dry_run("build-full")

    assert output.count("./scripts/build-log-runner.sh") == 1
    assert "--log build/logs/build.log" in output
    assert '--label "space full CEF build"' in output
    assert "cmake -B build" in output
    assert "cmake --build build -- -j" in output
    assert_has_profile_flags(output, profile="full", cef="ON")


def test_cmake_aliases_make_profile_intent_explicit() -> None:
    cmake_output = dry_run("cmake")
    cmake_minimal_output = dry_run("cmake-minimal")
    cmake_full_output = dry_run("cmake-full")

    assert "./scripts/build-log-runner.sh" not in cmake_output
    assert "./scripts/build-log-runner.sh" not in cmake_minimal_output
    assert "./scripts/build-log-runner.sh" not in cmake_full_output
    assert_has_profile_flags(cmake_output, profile="minimal", cef="OFF")
    assert_has_profile_flags(cmake_minimal_output, profile="minimal", cef="OFF")
    assert_has_profile_flags(cmake_full_output, profile="full", cef="ON")


def test_package_oriented_local_targets_use_full_build_path() -> None:
    appimage_output = dry_run("appimage")
    pack_output = dry_run("pack")

    assert_has_profile_flags(appimage_output, profile="full", cef="ON")
    assert_has_profile_flags(pack_output, profile="full", cef="ON")
    assert "./scripts/build-log-runner.sh" in appimage_output
    assert "./scripts/build-log-runner.sh" in pack_output
    assert "./scripts/build-appimage.sh" in appimage_output
    assert "cd build && cpack" in pack_output
```

- [ ] **Step 2: Run Makefile tests and verify they fail on the current default CEF-on/noisy build**

Run:

```bash
python3 -m pytest scripts/tests/test_makefile_build_workflow.py -q
```

Expected: FAIL because `make build` does not use `scripts/build-log-runner.sh`, does not set `SPACE_BUILD_PROFILE=minimal`, and currently sets `SPACE_ENABLE_CEF=ON`.

- [ ] **Step 3: Update Makefile phony targets and shared variables**

Modify the top of `Makefile` so the phony declaration includes the new targets:

```make
.PHONY: build build-full cmake cmake-minimal cmake-full debug run pack appimage install install-deb install-rpm clean dump-seed load-seed act release fennel-check constraints test test-e2e test-live-hot-reload test-slow test-integration test-all-lua profile commit prof download-models-data resize-logo docs devlog test-windows-wine
```

After the existing `VALIDATION_OUTPUT = $(if $(VERBOSE),json,summary)` line, add:

```make
BUILD_DIR = build
BUILD_LOG = $(BUILD_DIR)/logs/build.log
BUILD_JOBS = $(shell nproc)
CMAKE_RELEASE = cmake -B $(BUILD_DIR) -DCMAKE_BUILD_TYPE=Release
CMAKE_MINIMAL = $(CMAKE_RELEASE) -DSPACE_BUILD_PROFILE=minimal -DSPACE_ENABLE_CEF=OFF
CMAKE_FULL = $(CMAKE_RELEASE) -DSPACE_BUILD_PROFILE=full -DSPACE_ENABLE_CEF=ON
BUILD_LOG_RUNNER = ./scripts/build-log-runner.sh --log $(BUILD_LOG)
```

- [ ] **Step 4: Replace default configure/build targets with minimal and full variants**

Replace the existing `cmake` and `build` recipes with:

```make
cmake: cmake-minimal

cmake-minimal:
	$(CMAKE_MINIMAL) .

cmake-full:
	$(CMAKE_FULL) .

build:
	@$(BUILD_LOG_RUNNER) --label "space minimal build" -- bash -lc '$(CMAKE_MINIMAL) . && cmake --build $(BUILD_DIR) -- -j$(BUILD_JOBS)'

build-full:
	@$(BUILD_LOG_RUNNER) --label "space full CEF build" -- bash -lc '$(CMAKE_FULL) . && cmake --build $(BUILD_DIR) -- -j$(BUILD_JOBS)'
```

Use literal tab characters before recipe command lines.

- [ ] **Step 5: Make local package-oriented targets depend on the full CEF build path**

Change the `pack` and `appimage` targets to:

```make
pack: build-full
	cd build && cpack

appimage: build-full
	./scripts/build-appimage.sh
```

- [ ] **Step 6: Run focused Makefile dry-run tests**

Run:

```bash
python3 -m pytest scripts/tests/test_makefile_build_workflow.py -q
```

Expected: PASS.

- [ ] **Step 7: Run combined wrapper and Makefile tests**

Run:

```bash
python3 -m pytest scripts/tests/test_build_log_runner.py scripts/tests/test_makefile_build_workflow.py -q
```

Expected: PASS.

- [ ] **Step 8: Commit Makefile wiring and tests**

Run:

```bash
git add Makefile scripts/tests/test_makefile_build_workflow.py
git commit -m "feat(build): default local make build to quiet minimal profile"
```

---

### Task 3: Build Documentation

**Files:**
- Modify: `docs/dev/building.md`

**Interfaces:**
- Consumes: Make targets `make build`, `make build-full`, `make cmake`, `make cmake-minimal`, `make cmake-full`, `make appimage`, and `make pack`.
- Produces: documented developer contract for quiet default builds, full CEF builds, log behavior, and package target behavior.

- [ ] **Step 1: Update the normal Build and run section**

In `docs/dev/building.md`, replace the current `Build and run:` block with:

```markdown
Build and run for normal local development:

```bash
make build
make run
```

`make build` is the quiet default local build. It prints the full build log path before configure/build work starts, writes the complete CMake and compiler transcript to `build/logs/build.log`, and prints a concise success or failure summary. On failure, the terminal includes a bounded tail from `build/logs/build.log`; inspect the full log file for the complete transcript.

The default local Makefile profile is minimal and CEF-off. `make build`, `make cmake`, and `make cmake-minimal` configure with `-DSPACE_BUILD_PROFILE=minimal -DSPACE_ENABLE_CEF=OFF`.

For browser-surface development, CEF integration work, or full local packaging checks, use the explicit full profile:

```bash
make build-full
make cmake-full
```

The full profile configures with `-DSPACE_BUILD_PROFILE=full -DSPACE_ENABLE_CEF=ON` and uses the same `build/logs/build.log` quiet build mechanism for `make build-full`.

To run the app directly, use `./build/space -m main`.
By default, `./build/space` also starts the main app; use `./build/space --repl` for the embedded Fennel REPL.
```

- [ ] **Step 2: Update local AppImage/package wording**

Replace the local AppImage paragraph with:

```markdown
Build an AppImage (portable Linux bundle) from the full CEF-enabled local profile:

```bash
make appimage
```

`make appimage` depends on `make build-full` so local AppImage checks include browser/CEF runtime files. `make pack` also depends on `make build-full` before running CPack. Minimal release artifacts remain available through `scripts/build-linux.sh --profile minimal`.

This writes `build/space-<version>-x86_64.AppImage`.
```

- [ ] **Step 3: Replace the stale CEF default wording**

Replace the CEF paragraph with:

```markdown
CEF embedded browser integration is Linux-only right now. The normal local `make build` path is intentionally CEF-off for faster agent and developer feedback. Use the explicit full Makefile path when browser surfaces, CEF helper behavior, or CEF packaging contents are relevant:

```bash
make cmake-full
make build-full
```
```

Leave the pinned CEF override sentence that follows intact:

```markdown
If you need to override the pinned build, you can still pass:
`-DSPACE_CEF_VERSION=... -DSPACE_CEF_URL=... -DSPACE_CEF_SHA256=...`
```

- [ ] **Step 4: Verify docs mention the new behavior and no longer claim CEF is enabled by default for Makefile builds**

Run:

```bash
rg "build/logs/build.log|make build-full|make cmake-full|SPACE_BUILD_PROFILE=minimal|SPACE_ENABLE_CEF=OFF" docs/dev/building.md
```

Expected: at least one match for each required phrase.

Run:

```bash
if rg "enabled by default in the project `make cmake` flow" docs/dev/building.md; then
  echo "stale CEF default wording remains" >&2
  exit 1
fi
```

Expected: exits 0 with no output.

- [ ] **Step 5: Build docs**

Run:

```bash
npm --prefix docs run docs:build
```

Expected: PASS.

- [ ] **Step 6: Commit documentation**

Run:

```bash
git add docs/dev/building.md
git commit -m "docs: document quiet minimal and full CEF build paths"
```

---

### Task 4: Integration Validation and Acceptance

**Files:**
- No file changes.

**Interfaces:**
- Consumes: all interfaces from Tasks 1-3.
- Produces: validation evidence that the implementation satisfies the committed spec.

- [ ] **Step 1: Run focused Python tests**

Run:

```bash
python3 -m pytest scripts/tests/test_build_log_runner.py scripts/tests/test_makefile_build_workflow.py -q
```

Expected: PASS.

- [ ] **Step 2: Inspect Makefile dry-runs for default and full target intent**

Run:

```bash
make -n build
make -n build-full
make -n cmake
make -n cmake-minimal
make -n cmake-full
make -n appimage
make -n pack
```

Expected:
- `make -n build`, `make -n cmake`, and `make -n cmake-minimal` include `-DSPACE_BUILD_PROFILE=minimal -DSPACE_ENABLE_CEF=OFF`.
- `make -n build-full`, `make -n cmake-full`, `make -n appimage`, and `make -n pack` include `-DSPACE_BUILD_PROFILE=full -DSPACE_ENABLE_CEF=ON`.
- `make -n build` and `make -n build-full` include `./scripts/build-log-runner.sh --log build/logs/build.log`.

- [ ] **Step 3: Run the default quiet build**

Run with the repository-standard long build timeout when using automation:

```bash
make build
```

Expected:
- Terminal output starts with the absolute path to `build/logs/build.log`.
- Terminal output does not stream CMake configure lines or compiler lines on success.
- `build/logs/build.log` exists and contains the complete configure/build transcript.
- Exit code is 0.

- [ ] **Step 4: Verify the default configured cache is minimal and CEF-off**

Run:

```bash
grep -E '^SPACE_BUILD_PROFILE:STRING=minimal$' build/CMakeCache.txt
grep -E '^SPACE_ENABLE_CEF:BOOL=OFF$' build/CMakeCache.txt
```

Expected: both commands print one matching line and exit 0.

- [ ] **Step 5: Run the relevant runtime suite from the minimal build**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: PASS.

- [ ] **Step 6: Run docs validation**

Run:

```bash
npm --prefix docs run docs:build
```

Expected: PASS.

- [ ] **Step 7: Run full CEF build validation when CEF archive/cache availability permits**

If the environment has the pinned CEF archive cached or network access suitable for the CEF download, run with the repository-standard long build timeout:

```bash
make build-full
grep -E '^SPACE_BUILD_PROFILE:STRING=full$' build/CMakeCache.txt
grep -E '^SPACE_ENABLE_CEF:BOOL=ON$' build/CMakeCache.txt
```

Expected:
- `make build-full` uses `build/logs/build.log` and concise terminal output.
- Both `grep` commands print one matching line and exit 0.

If the environment cannot access or cache the pinned CEF archive, do not substitute another CEF version. Record that full CEF execution was skipped due network/cache availability and rely on the focused Makefile dry-run tests for target wiring.

- [ ] **Step 8: Confirm git state is clean**

Run:

```bash
git status --short
```

Expected: no output.

---

## Acceptance Criteria

- `make build` prints the full `build/logs/build.log` path before configure/build work starts.
- `make build` writes the complete CMake configure and build transcript to `build/logs/build.log`.
- Successful `make build` terminal output is concise and does not stream configure/compiler output.
- Failed wrapped builds preserve the wrapped command exit code and print only a bounded log tail plus the full log path.
- Default `make build`, `make cmake`, and `make cmake-minimal` use `-DSPACE_BUILD_PROFILE=minimal -DSPACE_ENABLE_CEF=OFF`.
- Explicit `make build-full` and `make cmake-full` use `-DSPACE_BUILD_PROFILE=full -DSPACE_ENABLE_CEF=ON`.
- `make build-full` uses the same `build/logs/build.log` quiet log mechanism as `make build`.
- Local package-oriented targets `make appimage` and `make pack` depend on the full CEF build path.
- `docs/dev/building.md` explains default minimal/CEF-off behavior, explicit full CEF targets, the log path, success/failure output behavior, and package target behavior.
- `python3 -m pytest scripts/tests/test_build_log_runner.py scripts/tests/test_makefile_build_workflow.py -q` passes.
- No CEF integration code, CEF download/extract logic, runtime browser behavior, release matrix, or direct CMake defaults are changed.

---

## Validation Ladder

1. Focused tests during implementation:

   ```bash
   python3 -m pytest scripts/tests/test_build_log_runner.py -q
   python3 -m pytest scripts/tests/test_makefile_build_workflow.py -q
   ```

2. Complete relevant suite for this change:

   ```bash
   python3 -m pytest scripts/tests/test_build_log_runner.py scripts/tests/test_makefile_build_workflow.py -q
   make build
   grep -E '^SPACE_BUILD_PROFILE:STRING=minimal$' build/CMakeCache.txt
   grep -E '^SPACE_ENABLE_CEF:BOOL=OFF$' build/CMakeCache.txt
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
   npm --prefix docs run docs:build
   ```

3. Broader final checks justified by CEF/package risk:

   ```bash
   make -n build-full appimage pack
   ```

   Expected: dry-run output shows the full CEF profile and the shared log runner.

   When CEF archive/cache availability permits:

   ```bash
   make build-full
   grep -E '^SPACE_BUILD_PROFILE:STRING=full$' build/CMakeCache.txt
   grep -E '^SPACE_ENABLE_CEF:BOOL=ON$' build/CMakeCache.txt
   ```

Use timeout `600000` for configure-only validation and timeout `14400000` for `make build`, `make build-full`, and `make test` when invoking through automation.

---

## Out of Scope

- Changing `cmake/cef.cmake`, CEF source/runtime files, browser feature behavior, or runtime CEF guards.
- Changing CMake defaults for direct `cmake -B build` invocations outside Makefile workflows.
- Changing GitHub Actions, release matrices, or `scripts/build-linux.sh` profile semantics.
- Adding a verbose Makefile mode beyond the full log file and bounded failure tail.
- Filtering compiler output outside the logged Makefile build workflow.
- Adding new non-standard Python, Bash, or Make dependencies.

---

## Self-Review

- Spec coverage: Tasks 1-4 cover quiet default build output, pre-work log path output, complete `build/logs/build.log` transcript capture, concise success/failure summaries, bounded failure tails, exit-code preservation, default minimal/CEF-off profile, explicit full CEF targets, package target full-profile behavior, docs, and tests.
- Placeholder scan: no unresolved placeholders or deferred implementation steps remain.
- Interface consistency: the wrapper interface defined in Task 1 is the same interface consumed by Task 2; Makefile target names match the docs and tests.
- Documentation decision: `docs/dev/building.md` is the exact `docs/dev/**` page for this operational build workflow, so no new `docs/dev/features/**` or `docs/dev/notes/**` page is needed.
- HUMAN_DECISION_REQUIRED: none.
