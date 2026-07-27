---
name: humpback-testing-runtime
description: Use when running, adding, or debugging Humpback tests, E2E snapshots, remote-control debugging, profiling, build commands, or runtime harnesses.
---

# Humpback Testing Runtime

## Use When

Running, adding, or debugging Humpback tests, E2E snapshots, remote-control debugging, profiling, build commands, or runtime harnesses.

## Canonical Commands

`AGENTS.md` is the canonical source for build/test command spellings and timeout expectations.

## Runtime Test Environment

- Default full suite: `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`.
- Use absolute `SPACE_ASSETS_PATH=$(pwd)/assets` for direct Lua/Fennel test runs.

## E2E Snapshots

- E2E snapshots use `make test-e2e`.
- Goldens live under `assets/lua/tests/data/snapshots/`.
- PNGs must be visually inspected after snapshot changes.

## Remote Control And Profiling

- Remote-control debugging uses the running app endpoint and `tools.remote-control-client`.
- Profilers run through `make prof target=<name>`.

## Canonical References

- `AGENTS.md`
- `docs/dev/features/development-tooling.md`
