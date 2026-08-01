# Local Quiet CEF-Light Build Design

## Context

Fresh agent worktrees pay the full first-build cost. The recent concise validation output work reduced Fennel validation JSON noise, but it intentionally left C/C++ build output and CEF build behavior unchanged. In practice, the default Makefile build still streams all CMake/compiler output into the agent context and configures with CEF enabled, which can trigger CEF archive download progress, extraction of a large SDK, `libcef_dll_wrapper` compilation, and runtime file copies before an agent can run tests.

The repository already has the right lower-level abstraction: `SPACE_BUILD_PROFILE=minimal` forces `SPACE_ENABLE_CEF=OFF`, while full/release scripts can explicitly request CEF. The Makefile is the main mismatch because `make cmake` hardcodes `-DSPACE_ENABLE_CEF=ON`.

The build-output side should not hide diagnostics. Instead, the default `make build` workflow should capture the full configure/build transcript in a known log file, print that log path before work starts so a human can `tail -f` it, and keep terminal output to a short start/success/failure summary. On failure, the terminal should include the last bounded chunk of the log plus the full log path.

## Explored Approaches

### Approach A: Quiet logged build plus default minimal/CEF-off profile

`make build` captures configure/build output to `build/logs/build.log`, prints the log path up front, and uses the minimal profile with CEF disabled. New explicit targets such as `make cmake-full` and `make build-full` configure the full CEF-enabled profile; `make build-full` uses the same logged-output behavior. Packaging targets that are expected to include CEF use the full path.

Trade-offs: this directly improves normal agentic development in fresh worktrees, avoids streaming compiler noise into agent context, and uses the existing CMake profile model. The risks are wrapper correctness and the need for CEF/browser work to use the full target, so the log behavior and target names need tests and documentation.

### Approach B: Keep full/noisy default, add optional quiet or minimal targets

This preserves existing behavior and adds optional targets such as `make build-minimal` or `make build-agent` for agents.

Trade-offs: lowest surprise, but it does not solve the default-path problem. Agents and humans will continue running the noisy path unless every prompt and workflow remembers the new target.

### Approach C: Only adjust CEF internals

This would keep streamed build output as-is and attempt to reduce output and disk churn by skipping selected CEF runtime-copy or progress steps while preserving CEF compile coverage.

Trade-offs: it avoids changing default feature coverage, but it still requires CEF download/extraction and wrapper compilation. It can also create a configured CEF build that cannot actually run browser surfaces or package correctly, which is worse than a clear CEF-off build.

## Recommended Direction

Use Approach A. Default local/agent Makefile builds should be concise on stdout/stderr, save the full transcript to `build/logs/build.log`, and use the minimal CEF-off profile. CEF-enabled work remains available through explicit full Make targets and existing release/build scripts.

This is a local Makefile workflow change, not a rewrite of CEF integration. It should not alter `cmake/cef.cmake`, CEF source/runtime code, or release-script profile semantics. It should make the local Makefile default align with the common agentic case where CEF is not relevant and where full build logs should be available as a file rather than streamed into context.

## Design

### Architecture

- Keep CMake's existing `SPACE_BUILD_PROFILE` model and `SPACE_ENABLE_CEF` option.
- Add a small build-log wrapper used by Makefile build targets. It creates `build/logs/`, prints the full log path before running commands, redirects the full transcript to `build/logs/build.log`, prints concise success output, and prints a bounded log tail on failure.
- Change Makefile defaults so `make cmake` delegates to a minimal configure target and `make build` runs the logged minimal build path.
- Add explicit full Make targets that pass both `-DSPACE_BUILD_PROFILE=full` and `-DSPACE_ENABLE_CEF=ON`.
- Make `make build-full` use the same log-file mechanism as `make build`, but configure the full CEF-enabled profile.
- Ensure full/package-oriented targets that require CEF depend on the full build path.
- Document that CEF/browser-surface development must use the full path.

### User-Facing Behavior

- `make build` prints the full log path immediately, writes full configure/build output to `build/logs/build.log`, prints concise completion status, and performs the default local developer build with CEF disabled.
- `make build-full` has the same logged-output behavior and performs a CEF-enabled build for browser-surface development and full packaging checks.
- `make cmake`, `make cmake-minimal`, and `make cmake-full` make configure intent explicit.
- Existing release script behavior remains profile-based; full release profiles still enable CEF.

### Error Handling and Compatibility

- Same build directory reconfiguration is allowed, but Makefile recipes should pass both profile and CEF flags explicitly so switching between minimal and full is deterministic.
- The build log path must be printed before configure/build commands start so a human can inspect or follow the log while the build is running.
- The full log file is the debugging escape hatch. The default design does not need a separate verbose build mode because failures include a bounded tail and the complete transcript remains on disk.
- Build wrapper failures must preserve the underlying command exit code.
- If a developer runs browser features from a minimal build, existing runtime guards should continue to fail clearly for missing CEF support.
- Direct `cmake -B build` defaults are out of scope; this design targets local Makefile workflows.

### Testing

Focused tests should assert the build-log wrapper prints the log path, writes full command output to a log, preserves exit codes, and prints bounded failure tails. Makefile dry-run behavior should cover default minimal and explicit full targets. Validation should inspect `build/CMakeCache.txt` after configure to confirm profile/CEF values, then run the normal test suite from the default minimal build. Full CEF packaging/build checks should be available for CEF-specific or release validation when network/cache availability permits.

## Scope

In scope:

- Makefile profile-target wiring for minimal default and explicit full builds.
- Build-log capture for Makefile build targets, including up-front log path output and bounded failure summaries.
- Documentation updates for local default builds and CEF development builds.
- Tests or dry-run checks that pin expected Makefile and build-log behavior.

Out of scope:

- Changing CEF integration code, runtime files, browser behavior, or CEF source guards.
- Changing `cmake/cef.cmake` download/extract/copy behavior.
- Changing direct CMake defaults outside Makefile workflows.
- Changing GitHub Actions, release matrices, or packaging scripts except where a Makefile packaging target must preserve full CEF behavior.
- General compiler-output filtering outside the logged Makefile build workflow.

## Self-Review Notes

- No placeholders remain.
- The design uses existing profile abstractions instead of inventing a parallel CEF-disable mechanism.
- The design preserves debuggability by making the full build transcript a first-class log file.
- The scope is intentionally limited to local Makefile build/log defaults and documentation so release/profile behavior remains stable.
