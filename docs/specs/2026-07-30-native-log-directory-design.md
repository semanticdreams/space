# Native Log Directory Discovery

## Context

The runtime asset discovery work makes `space` usable from arbitrary working
directories, but native logging still has a similar portability gap. The C++
logger defaults to `gl.log`, and `apps/space/main.cpp` calls `log_init` before
Fennel startup. Later, `assets/lua/main.fnl` redirects normal app logs to
`SPACE_LOG_DIR` or `appdirs.user-log-dir "space"`, but entry modes such as
`space -c`, stdin, file execution, and the REPL do not depend on `main.fnl`.
Those modes can still create `gl.log` in whichever directory launched the
runtime.

The project currently uses `SPACE_LOG_DIR` as the log-directory environment
override. `LOGS_DIR` is not a runtime convention and should not be added as a
new alias.

## Goals

- Make native logging choose a deliberate log path before the first C++
  `log_init` call.
- Preserve non-empty `SPACE_LOG_DIR` as the explicit log directory override.
- Default to `get_user_log_dir("space") / "space.log"` when no override is set.
- Ensure CLI, stdin, file, REPL, and module modes do not write `gl.log` in an
  arbitrary current working directory.
- Fail loudly if the selected log directory cannot be created or used.
- Keep the existing Lua/Fennel `logging.init {:path ...}` API usable.

## Non-Goals

- Adding `LOGS_DIR` or other environment variable aliases.
- Changing runtime asset discovery behavior.
- Redesigning auxiliary logs such as terrain issue logs.
- Changing the existing spdlog rotation policy.

## Considered Approaches

### Keep Fennel-owned log setup

This preserves current behavior but does not solve CLI or early-startup logs,
because `main.fnl` is not loaded for every entry mode and native logging starts
before Fennel can reconfigure it.

### Require shell/profile or wrapper configuration

Setting `SPACE_LOG_DIR` in a shell profile or wrapper works locally, but it has
the same weakness as the old asset-path behavior: it does not reliably cover
direct binary execution, desktop launchers, services, CI jobs, or other users.

### Resolve the native log path during C++ bootstrap

The recommended design is to resolve the Space executable's log path in C++
before the first `log_init`. This makes every runtime mode consistent, keeps
`SPACE_LOG_DIR` as an explicit override, and aligns with existing appdirs
support. Fennel `main.fnl` should preserve the native-selected path instead of
duplicating the directory-selection policy.

## Design

Add a small Space-specific log path resolver that is separate from the generic
logger. It will provide:

- `space_log::resolve_log_dir()` — returns non-empty `SPACE_LOG_DIR` when set,
  otherwise `get_user_log_dir("space")`.
- `space_log::resolve_log_path()` — appends `space.log` to the resolved
  directory.
- `space_log::ensure_log_directory(path)` — creates the parent directory for the
  selected log file and throws an explicit error if the parent exists as a file
  or cannot be created.

Extend `LogConfig` with an optional `output_path` string. `log_init` should use
`config.output_path` when non-empty, persist the selected path, and initialize
the rotating file sink there. `log_set_output_path` remains supported for
existing callers, but should update `LogConfig::output_path` and reinitialize
through the same path-handling logic. The Lua `logging.init` binding should
populate `LogConfig::output_path` from `:path` instead of reinitializing the
logger as a parse side effect.

In `apps/space/main.cpp`, resolve and validate the log path before the first
`log_init(LOG_CONFIG)`. On failure, print `error: failed to initialize logging:
<details>` to stderr and exit non-zero. This keeps the no-silent-failures rule
and prevents the runtime from silently falling back to CWD logs.

Update `assets/lua/main.fnl` so normal app startup preserves the native-selected
path using `logging.get-output-path` rather than recomputing `SPACE_LOG_DIR` and
`appdirs.user-log-dir` itself. Existing level adjustments remain unchanged.

## Expected Behavior

- `space --no-dotenv -c ...` from any directory writes native logs to
  `get_user_log_dir("space") / "space.log"` by default.
- On Linux, the default path is
  `${XDG_CACHE_HOME:-~/.cache}/space/log/space.log`.
- `SPACE_LOG_DIR=/tmp/space/log space --no-dotenv -c ...` writes native logs to
  `/tmp/space/log/space.log`.
- No supported entry mode creates `gl.log` in the current working directory as a
  normal bootstrap path.
- Invalid log directory setup fails with an explicit startup error and a non-zero
  exit code.

## Testing

Add focused C++ tests for log path resolution and integration tests that spawn
the built `space` executable from an unrelated temporary directory. Coverage
must verify default appdirs behavior, `SPACE_LOG_DIR` override behavior, absence
of CWD `gl.log`, and loud failure for invalid log directory setup. Run the full
CTest suite because logging initializes in every runtime mode.

## Documentation

Update `docs/dev/building.md` near the runtime asset discovery section with the
native log location, the `SPACE_LOG_DIR` override, Linux default behavior, and
the guarantee that CLI modes do not write `gl.log` into arbitrary launch
directories.
