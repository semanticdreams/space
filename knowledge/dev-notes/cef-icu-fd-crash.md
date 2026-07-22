---
type: dev-note
tags:
  - note
---

# CEF ICU FD Crash on Linux During SDL3 Migration

Date: February 25, 2026

## Summary

When running browser surfaces (for example `SPACE_BROWSER_CUBE_DEMO=1`), the app crashed with Chromium's ICU startup error:

```
[ERROR:base/i18n/icu_util.cc:232] Invalid file descriptor to ICU data received.
Trace/breakpoint trap (core dumped)
```

This did not reproduce on plain startup when no browser surface was created, because CEF initialization is lazy.

## Reproduction

From repo root:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets SPACE_BROWSER_CUBE_DEMO=1 ./build/space -m main
```

Expected bad behavior before fix:
- process exits with signal `SIGTRAP` / code `133`
- ICU FD error appears

## Root Cause

CEF/Chromium attempted to load `icudtl.dat` from the directory containing `libcef.so`:

- `${SPACE_CEF_ROOT}/Release/icudtl.dat`

But in our fetched CEF layout, ICU and other runtime payload files were only in:

- `${SPACE_CEF_ROOT}/Resources/`

So Chromium failed to initialize ICU data and aborted.

## Fix Implemented

### 1) Stage runtime payloads next to `libcef.so`

File: `cmake/cef.cmake`

At configure time, copy these files from `Resources/` to `Release/` if present:

- `icudtl.dat`
- `resources.pak`
- `v8_context_snapshot.bin`
- `snapshot_blob.bin`
- `chrome_100_percent.pak`
- `chrome_200_percent.pak`
- `locales/`

This aligns with Chromium's runtime lookup behavior on Linux.

### 2) Harden Linux CEF subprocess switches

File: `src/cef_runtime.cpp`

Ensure command-line switches include:

- `no-sandbox`
- `disable-setuid-sandbox`
- `no-zygote`

This prevents sandbox/zygote paths that were not appropriate for this runtime configuration.

## Verification

### Runtime

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets SPACE_BROWSER_CUBE_DEMO=1 ./build/space -m main
```

After fix: app starts normally (no ICU FD crash).

### Tests

- `make test` passes
- `make test-e2e` passes (after expected SDL3-related snapshot updates)
- CTest no longer forces `SPACE_SKIP_CEF=1` for `space_fnl_tests` or `test_dotenv_integration`; both now pass with default CEF startup enabled.

## Notes

- This incident is distinct from snapshot differences introduced by SDL3 migration.
- Snapshot mismatches were visual regressions/golden drift, not CEF startup failures.


## See also

- [[cef-in-world-browser]]
