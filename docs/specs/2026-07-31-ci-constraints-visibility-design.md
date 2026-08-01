# CI Constraints Visibility Design

## Purpose

The experimental Fennel constraints gate is already part of local validation and CTest, but GitHub Actions currently surfaces it only indirectly through the broader CTest run. CI should make constraint failures obvious and early so agents and humans can diagnose architecture violations before reading full test logs.

## Design Direction

Keep the existing `space_experimental_constraints` CTest fixture as the authoritative blocking integration. Add an explicit `make constraints` step to `.github/workflows/test.yml` after the Linux build and before the general CTest suite. This gives fast, clearly named CI feedback while preserving the existing CTest fixture as defense in depth.

## Components

- `.github/workflows/test.yml`: add a Linux job step named clearly, such as `Run experimental constraints`, before `Run test suite`.
- Existing environment: reuse the job-level `SKIP_KEYRING_TESTS`, `XDG_DATA_HOME`, and `SPACE_DISABLE_AUDIO`; set or rely on the Makefile-provided `SPACE_ASSETS_PATH`, `FENNEL_PATH`, and `FENNEL_MACRO_PATH` through `make constraints`.
- Documentation: update `docs/dev/experimental-constraints.md` to state that GitHub CI has an explicit constraints step and that CTest still gates Fennel tests.

## Out of Scope

- Do not create new workflows.
- Do not change build, release, docs Pages, or devlog workflows.
- Do not change constraint runner output or Makefile behavior.
- Do not alter Windows test behavior in this slice; Windows fast tests do not currently run through the Linux `make constraints` target.

## Error Handling

If `make constraints` exits with `violations`, `fail`, or `interrupted`, the CI job fails before the broader test suite. Because CTest still includes the constraints fixture, removing or bypassing the explicit step later does not silently remove the underlying gate.

## Acceptance Criteria

- `.github/workflows/test.yml` contains an explicit Linux CI step that runs `make constraints` after build and before the broader CTest step.
- The broader CTest step remains unchanged enough to continue exercising the `space_experimental_constraints` fixture.
- Documentation states both the explicit CI step and fixture-based gate.
- No other workflow files are modified.
- Local validation confirms `make constraints` still passes.
