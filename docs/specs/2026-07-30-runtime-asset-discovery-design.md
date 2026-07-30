# Runtime Asset Discovery From Arbitrary Working Directories

## Context

The `space` executable currently requires asset roots to be discoverable through
`SPACE_ASSETS_PATH`, a user data assets directory, the process working
directory's `./assets`, or the hardcoded `/usr/share/space/assets` path. This
makes direct runtime use brittle: running a built `space` binary from an
unrelated working directory fails with `Asset not found: lua` unless the shell
sets `SPACE_ASSETS_PATH` or happens to start inside a directory containing the
right `assets/` tree.

That is acceptable as an explicit override, but not as the default user and
developer experience. It also does not cover desktop launchers, services,
non-login shells, CI jobs, package installs under custom prefixes, or portable
tarball layouts. AppImage already solves this with a wrapper that exports
`SPACE_ASSETS_PATH`, but direct binary execution remains fragile.

## Goals

- Allow the runtime to start from arbitrary working directories for developer
  builds, installed packages, and portable bundles.
- Preserve `SPACE_ASSETS_PATH` as the highest-priority explicit override.
- Preserve user data assets and existing working-directory fallback behavior.
- Avoid making `~/.profile` or wrapper scripts required for correctness.
- Fail loudly when required assets are unavailable, including enough searched
  path context to diagnose the problem.

## Non-Goals

- Removing `SPACE_ASSETS_PATH` support.
- Reworking packaging layouts or hot-reload semantics.
- Supporting multi-entry asset path lists.
- Making missing required assets a recoverable no-op.

## Considered Approaches

### User shell profile environment variable

Adding `SPACE_ASSETS_PATH` to `~/.profile` is a useful local workaround but is
not a clean product design. It affects every shell, is user-specific, does not
cover desktop launchers or services reliably, and leaves packaged or portable
distributions dependent on manual setup.

### Wrapper script only

A wrapper can compute an asset root and export `SPACE_ASSETS_PATH`; AppImage
already uses this pattern. Wrappers remain useful for bundle-specific setup, but
making them the only supported mechanism keeps direct binary execution broken
and duplicates launcher logic across distribution formats.

### Binary self-discovery

The runtime should resolve its executable path once at startup and let the asset
manager probe executable-relative asset roots. This keeps the binary usable on
its own, works for developer and installed layouts, and lets wrappers remain an
optional compatibility layer. This is the recommended approach.

## Design

Introduce a shared executable-path utility that resolves the current executable
using platform-native mechanisms when available, falling back to `argv[0]` and
`PATH` lookup. `main.cpp` will provide the resolved executable path to
`AssetManager` before `LuaRuntime::init()` configures package paths. CEF helper
resolution can use the same utility so executable-relative behavior is not
duplicated.

`AssetManager::getAssetPath(relativePath)` will keep the explicit override first
and add executable-relative roots before falling back to the current working
directory and legacy system path. The intended search order is:

1. `SPACE_ASSETS_PATH`, when non-empty.
2. User data assets: `get_user_data_dir("space") / "assets"`.
3. Developer/build sibling assets: `<exe_dir>/assets`.
4. Install or portable layout: `<exe_dir>/../share/space/assets`.
5. macOS-style bundle layout, if applicable: `<exe_dir>/../Resources/assets`.
6. Existing working-directory fallback: `<cwd>/assets`.
7. Existing legacy system fallback: `/usr/share/space/assets`.

Equivalent candidate roots should be deduplicated before probing to avoid noisy
errors and repeated filesystem checks. A found root is valid only when the
requested relative path exists under that root, preserving the current behavior
that `getAssetPath("lua")` requires an actual `lua` asset directory.

When no candidate contains the requested asset, the thrown error should include
the requested relative path and the candidate paths that were searched. This
keeps the project rule against silent failures while making startup failures
actionable.

## Expected Behavior

- From any working directory, `build/space -c '(+ 5 3)'` can find
  `build/assets/lua` after a normal build copies assets into the build tree.
- A packaged `/usr/bin/space` can find `/usr/share/space/assets` without a shell
  profile variable.
- A portable layout with `bin/space` and `share/space/assets` can be extracted
  anywhere and run directly.
- AppImage and other wrappers may continue exporting `SPACE_ASSETS_PATH`; that
  value remains authoritative.
- If a user intentionally points `SPACE_ASSETS_PATH` elsewhere, that explicit
  asset root wins over bundled and system assets.

## Testing

Add focused tests for asset resolution order and CLI startup:

- Unit-level `AssetManager` coverage for env override, executable sibling
  `assets`, executable-relative `../share/space/assets`, CWD fallback, and
  missing-asset error text.
- Isolation of `SPACE_ASSETS_PATH`, `XDG_DATA_HOME`, and process working
  directory in tests so lookup tiers do not leak into each other.
- An integration smoke test that runs the built `space` executable from an
  unrelated temporary working directory with `SPACE_ASSETS_PATH` unset and
  verifies a simple `-c` invocation reaches the Fennel runtime.
- Existing full-suite validation remains required because startup path changes
  affect the whole runtime.

## Documentation

Update developer/build documentation to state that direct binary execution is
supported from arbitrary working directories for build, installed, and portable
layouts. Document the asset search order and clarify that `SPACE_ASSETS_PATH` is
an override, not a routine requirement.
