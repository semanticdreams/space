# Concise Validation Output Design

## Context

Space validation commands are often run by agents with limited context budgets. The current `make constraints` target already suppresses the Make command echo, but both `tools.fennel-check` and `constraints.runner` print raw JSON for every successful run. That is useful for machine consumers and debugging, but noisy for the default human/agent workflow. The constraints documentation already records runner output verbosity as a deferred follow-up.

Existing command patterns support concise defaults with opt-in detail: `ctest-summary.py` uses quiet CTest output plus failure details, AGENTS.md recommends `ctest -V` or `TEST_VERBOSE=1` only while debugging, and Fennel modules already use false-by-default `:verbose` style options.

## Explored Approaches

### Approach A: Change every direct validation CLI to concise output by default

Direct invocations of `./build/space -m tools.fennel-check:main` and `./build/space -m constraints.runner:main` would print summaries unless a verbose or JSON flag is passed.

Trade-offs: maximizes concision everywhere, but risks breaking scripts or future tooling that expect the existing JSON schema from direct CLI entrypoints.

### Approach B: Keep direct CLI JSON defaults, make Make/CMake validation commands request summaries

Add an explicit output mode at the validation CLI boundary. Direct CLI calls keep the current JSON default. `make fennel-check`, `make constraints`, and the CTest constraint fixture pass a summary mode. `VERBOSE=1` on the Make command restores JSON output.

Trade-offs: slightly more plumbing, but preserves compatibility while making the normal build/validation workflow concise.

### Approach C: Only shorten successful constraints output

Leave `fennel-check` unchanged and make `constraints.runner` print a one-line success summary, preserving full JSON on failures.

Trade-offs: smallest change, but creates inconsistent behavior between the two commands chained by `make constraints`, and still leaves raw JSON in successful compile checks.

## Recommended Direction

Use Approach B. This change is needed and makes sense because `make constraints` is a frequent validation gate, its current success output is known deferred noise, and the repository already prefers concise defaults with verbose/debug escape hatches.

The design should add output-mode support to the validation entrypoints, not to the constraint engine or validation service internals. The result schemas and exit-code semantics stay unchanged. Only CLI formatting changes.

## Design

### Architecture

- Add a small shared validation-output helper for parsing output-mode arguments such as `--output summary` and `--output json`.
- Update `tools.fennel-check` and `constraints.runner` entrypoints to format either existing JSON or concise summaries.
- Keep lower-level `run`, `run-target`, service, rule, baseline, and diagnostic data structures unchanged.
- Update Makefile validation targets to pass summary output by default and JSON output when `VERBOSE=1` is supplied.
- Update the CTest experimental constraints command to request summary output so verbose CTest logs are still readable.

### User-Facing Behavior

- `make fennel-check` prints a concise compile-check summary.
- `make constraints` prints concise compile-check and constraint summaries.
- `make fennel-check VERBOSE=1` and `make constraints VERBOSE=1` print the current JSON payloads.
- Direct commands without `--output` remain JSON-compatible:
  - `./build/space -m tools.fennel-check:main -- --target repo`
  - `./build/space -m constraints.runner:main -- --target repo`
- Direct commands can opt into summaries with `--output summary`.

### Failure Handling

Concise failure output must remain actionable. It should include command status, diagnostic counts, relevant file/location where available, diagnostic messages, hints when available, and a rerun instruction showing how to get JSON output for deeper debugging.

Exit codes remain blocking: constraints exit successfully only for `pass`; fennel-check exits successfully only for `ok`.

### Testing

Focused tests should cover parser behavior, JSON compatibility defaults, summary success output, summary failure output, `--output` stripping before target resolution, and invalid output-mode errors. Relevant validation includes focused Fennel CLI tests, dry-run Make wiring, `make fennel-check`, `make constraints`, and the full standard `make test` command when implementation is complete.

## Scope

In scope:

- Concise default output for Make/CMake validation commands that agents commonly run.
- Verbose JSON escape hatch for debugging and machine-readable output.
- Documentation updates for the constraints workflow and validation command usage.

Out of scope:

- Making C/C++ compilation output quieter.
- Replacing `ctest-summary.py`.
- Changing constraint rules, baselines, or diagnostic schemas.
- Changing broader GitHub Actions workflow structure unless validation proves it necessary.

## Self-Review Notes

- No placeholders remain.
- The recommendation preserves direct CLI compatibility while solving the noisy Make workflow.
- The design is scoped to validation output formatting and avoids unrelated build-system changes.
