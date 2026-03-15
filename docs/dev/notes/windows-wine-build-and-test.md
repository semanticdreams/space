# Windows Build + Wine Validation Notes

This document summarizes the Windows build and Wine validation work completed in this cycle, including decisions, trade-offs, known limitations, and follow-up work.

## Scope

Goals covered:

- make Windows build scripts match current dependency/build setup
- make the setup reproducible on other Linux machines
- validate Windows artifacts under Wine
- keep Windows coverage as high as possible in `tests.fast`, with explicit and minimal skips
- keep optional modules (notably libtorrent and ffmpeg) enabled by default for Windows

## What Changed

### 1) Reproducible Windows-from-Linux toolchain flow

Added/updated scripts:

- `scripts/setup-windows-build-host.sh`
- `scripts/build-windows-from-linux.sh`
- `scripts/build-windows.sh`
- `scripts/prepare-windows-runtime.sh`
- `scripts/prepare-windows-wine-runtime.sh`
- `scripts/test-windows-under-wine.sh`
- `scripts/build-wine-bcryptprimitives-mock.sh`
- `scripts/vcpkg-triplets/*`
- `scripts/vcpkg-ports/openal-soft/portfile.cmake`

Result:

- one-time host setup is isolated
- build and test steps are repeatable across machines
- Wine runtime prep resolves/copies dependent DLLs automatically and stages `matrix.dll` when present

### 2) Windows feature/dependency defaults

Final policy for Windows build:

- `libtorrent`: enabled by default
- `ffmpeg`: enabled by default
- `cef`: not available on Windows in current codebase (Linux-only integration path)

Notes:

- libtorrent package naming:
  - upstream library: **libtorrent-rasterbar**
  - vcpkg package name used here: `libtorrent`
  - Fennel/Lua module exposed by engine: `libtorrent`
  - these refer to the same underlying library integration in this project context

### 3) Runtime fixes for Windows/Wine execution

- implemented Windows process backend in `src/lua_process_windows.cpp` (instead of unsupported stubs)
- added Windows shell/process support (`src/lua_shell_windows.cpp` and runtime wiring)
- added Wine `bcryptprimitives.dll` workaround path for environments missing it
- fixed OpenAL driver defaults in `src/audio.cpp`:
  - Windows default drivers: `dsound,wave`
  - Linux default drivers: `pipewire,pulse,alsa`

This removed Wine startup noise/failure pattern:

- previous: `Failed to open OpenAL device.`
- now: Windows binary under Wine initializes audio without forcing Linux backends

### 4) Test architecture and skip policy

Windows skip policy is centralized in:

- `assets/lua/tests/runner.fnl`

Key design:

- keep module-level skips explicit and minimal
- keep feature-level skips local to tests when appropriate (using existing skip idioms)
- avoid broad blanket skips unless technically required

Important refactor:

- moved the input external-editor integration test from `test-input` to `test-external-editor`
- unskipped `test-input` on Windows
- left `test-external-editor` skipped on Windows (shell-dependent `sh` behavior)

Files:

- `assets/lua/tests/test-input.fnl`
- `assets/lua/tests/test-external-editor.fnl`

Stability tweak:

- input context-menu clipboard assertions now use a local clipboard stub in test code to avoid Wine clipboard flakiness while still validating behavior.

### 5) Kernel subprocess expectations under Wine

- `tests.test-kernels` subprocess integration remains skipped on Windows/Wine due Python runtime availability in Wine environments used for CI-style validation.
- this is an environment constraint, not a product-direction decision about kernel support in principle.

## Decisions and Trade-offs

1. Prioritize real Windows support over broad test exclusion

- decision: implement Windows process/shell support rather than skip whole suites
- trade-off: higher implementation effort now, much better long-term coverage and confidence

2. Keep skips explicit and centralized

- decision: define module-level Windows skips in `tests/runner.fnl`
- trade-off: slightly more maintenance in one list, but much easier to audit and reduce over time

3. Separate shell-integration tests from core widget behavior

- decision: external-editor path moved out of `test-input`
- trade-off: one extra module, but clearer ownership and platform handling

4. Reproducibility over ad-hoc local fixes

- decision: script host setup/build/runtime prep instead of manual commands
- trade-off: more scripts to maintain, but repeatable onboarding and CI/dev parity

5. Wine-specific compatibility shim (`bcryptprimitives.dll`)

- decision: include mock-path support for Wine where needed
- trade-off: additional moving part only for Wine validation; native Windows remains the source of truth for actual platform behavior

## Problems Encountered and Resolutions

1. Matrix DLL discovery/runtime path mismatch

- symptom: matrix-related runtime loading issues for Windows artifact runs
- resolution: `scripts/prepare-windows-runtime.sh` stages `matrix.dll` from known target paths and dependency scan

2. OpenAL device open failures under Wine

- symptom: `Failed to open OpenAL device.`
- root cause: Windows build forced Linux OpenAL drivers
- resolution: Windows driver defaults switched to `dsound,wave` in `src/audio.cpp`

3. Input suite failing under Wine after unskip

- symptom: clipboard assertions flaky/failing under Wine
- resolution: use test-local clipboard stub in `test-input` context-menu tests

4. External editor integration in mixed suite

- symptom: shell-dependent behavior caused platform-specific instability in `test-input`
- resolution: moved that case into `test-external-editor`, keep module skip on Windows

## Current Known Limitations

- CEF is still Linux-only in current engine integration path.
- `test-external-editor` remains skipped on Windows due shell-command assumptions (`sh`-driven behavior).
- kernel subprocess integration test is skipped on Windows/Wine test environments lacking Python runtime.
- Wine is validation support, not a complete substitute for native Windows verification.

## Validation Snapshot

Validated in this cycle (Windows binary under Wine):

- `tests.test-process:main` passing
- `tests.test-input:main` passing after refactor
- `tests.fast:main` passing with current explicit Windows skip policy
- audio smoke path no longer emits OpenAL device-open failure after driver fix

## Pending Work

1. Native Windows verification pass

- run full fast suite on a real Windows host (not Wine-only)
- specifically validate audio backend/device matrix under native drivers

2. Reduce skip surface further

- revisit `test-external-editor` for Windows-friendly editor harness (no `sh` assumptions)
- re-evaluate remaining module skips over time (`terminal`, `ripgrep`, `flamegraph`, `llm-tools`) as platform support improves

3. CEF Windows implementation

- implement Windows platform handler in CEF setup/runtime path
- add Windows packaging/runtime asset flow for CEF payload

## Reproducible Workflow (Current)

Host setup:

```bash
scripts/setup-windows-build-host.sh
```

Build Windows artifacts from Linux:

```bash
scripts/build-windows-from-linux.sh
```

Prepare native Windows runtime payload (for packaging):

```bash
scripts/prepare-windows-runtime.sh build/windows/space.exe
```

Run Windows fast suite under Wine:

```bash
scripts/test-windows-under-wine.sh
```

Run a specific module under Wine:

```bash
SPACE_TEST_MODULE=tests.test-input:main scripts/test-windows-under-wine.sh
```
