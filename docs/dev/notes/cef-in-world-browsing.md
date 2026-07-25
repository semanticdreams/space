---
type: dev-note
tags:
  - note
---

# CEF In-World Browsing (Linux-First): Implementation Notes

## Summary

This document records the current CEF in-world browsing implementation for `space`, focused on Linux first, with a path to later Windows/macOS support.

The implementation now supports:

1. Downloaded/pinned CEF integration in CMake with no extra user flags for the default flow.
2. Production-style browser surfaces that can be mapped to arbitrary scene geometry (including cube faces).
3. Input routing from world-space ray hits to CEF mouse events.
4. Runtime diagnostics for surface health (paint/upload counters, texture info).
5. Deterministic visual smoke validation via snapshots/scripts.

Current build workflow remains exactly:

```bash
make cmake
make build
```

## Goals and Constraints

### Goals

1. Linux-first CEF integration that is stable enough for production hardening.
2. In-world browsing that is versatile: any mesh/face can host a web surface.
3. Keep build/run simple for developers: no extra CMake flags required in standard flow.
4. Structure platform code so Windows/macOS can be added without redesigning the Linux path.

### Explicit Non-Goals (for this phase)

1. Full multi-platform CEF support (Windows/macOS still TODO).
2. E2E snapshot test integrated in `assets/lua/tests/e2e.fnl` (not yet added).
3. Final UX/browser app shell features (tabs/history/devtools UI, etc.).

## High-Level Architecture

### Build/Packaging Layer

Primary files:

- `cmake/cef-defaults.cmake`
- `cmake/cef.cmake`
- `CMakeLists.txt`
- `apps/space/cef_subprocess_main.cpp`

Key design points:

1. CEF is configured via pinned `SPACE_CEF_VERSION`, `SPACE_CEF_URL`, and `SPACE_CEF_SHA256` defaults so standard `make cmake`/`make build` works without manual values.
2. Download/extract is handled by CMake with retries and SHA256 verification.
3. Platform-dispatch function (`space_setup_cef_for_target`) currently routes Linux through `space_setup_cef_for_target_linux`, with explicit TODO stubs for Windows/macOS.
4. Runtime assets (`libcef.so`, pak files, locales, etc.) are copied post-build.
5. A helper subprocess binary (`space_cef_helper`) exists for platform compatibility and future expansion.

### Runtime CEF Layer

Primary files:

- `src/cef_runtime.h`
- `src/cef_runtime.cpp`
- `apps/space/main.cpp`

Key design points:

1. `cef_runtime::maybe_execute_subprocess(argc, argv)` is called very early in process startup to correctly handle CEF subprocess roles.
2. `cef_runtime::initialize_browser_process(...)` initializes the browser process once.
3. Linux runtime sets CEF resource/locales/cache paths and Chromium switches for this environment:
   - `no-zygote`, `no-sandbox`, `disable-gpu`, `disable-gpu-compositing`, `enable-begin-frame-scheduling`, `disable-gpu-vsync`.
4. Engine loop calls `cef_runtime::do_message_loop_work()` every frame.
5. `SPACE_SKIP_CEF=1` bypasses CEF startup for utility modules (notably remote-control client processes).

### Browser Surface Layer

Primary files:

- `src/browser_system.h`
- `src/browser_system.cpp`
- `src/engine.cpp` (`app.engine.browser` binding)

Key design points:

1. `BrowserSystem` manages named windowless CEF surfaces.
2. Each surface creates a CEF browser + OpenGL texture (`Texture2D`) and updates via `OnPaint` → frame queue → `tick` upload.
3. Surface API exposed to Fennel through `app.engine.browser`:
   - `create-surface`, `destroy-surface`, `set-url`, `set-visible`, `set-focus`
   - `send-mouse-move`, `send-mouse-click`, `send-mouse-wheel`
   - `texture-name`, `texture-info`, `surface-stats`, `list-surfaces`
4. Diagnostics added for production debugging:
   - `paint-count`, `upload-count`, `last-upload-frame`, `texture-allocated`, dimensions, visibility.

### In-Scene Integration Layer

Primary files:

- `assets/lua/browser-cube-surface.fnl`
- `assets/lua/mesh-renderer.fnl`
- `assets/shaders/mesh.frag`
- `assets/lua/main.fnl`
- `assets/lua/app-projection.fnl`

Key design points:

1. `BrowserCubeSurface` creates six independent browser surfaces and maps them to cube faces.
2. Hit testing uses scene ray casting (`scene:screen-pos-ray`) and per-face intersection to convert mouse input to browser pixel coordinates.
3. Mesh batches for browser faces are unlit and force opaque compositing to avoid alpha artifacts (`forceOpaque`).
4. Default browser demo URL is now deterministic local smoke content (`data:` URL showing `CEF OK`) so validation does not depend on external network.
5. Projection was fixed to use viewport aspect (`app-projection`) rather than hardcoded invalid values.

### Capture/Verification Layer

Primary files:

- `scripts/capture_cef_surface.sh`
- `scripts/capture_cef_visible.sh`
- `assets/lua/render-capture.fnl`
- `src/lua_opengl.cpp`

Key design points:

1. `capture_cef_surface.sh` validates raw browser texture content via `glGetTexImage`.
2. `capture_cef_visible.sh` validates in-scene composition and now captures at `app.viewport` dimensions.
3. GL bindings were extended for diagnostics: `GL_FRONT`, `GL_BACK`, `glReadBuffer`, `glGetTexImage`.
4. Render capture path explicitly binds/readbacks from default framebuffer back buffer.

## Detailed Flow (End-to-End)

1. Build system downloads/extracts pinned CEF archive and links engine/helper targets.
2. App starts, early-calls `maybe_execute_subprocess`; subprocess roles exit immediately.
3. Browser process initializes CEF once.
4. Fennel creates browser surfaces with IDs, URLs, sizes, and max FPS.
5. CEF `OnPaint` emits BGRA-like buffer frames into a pending frame queue.
6. Engine `BrowserSystem::tick(frame_id)` uploads pending frames into GL textures.
7. Scene mesh renderer samples these textures on arbitrary geometry.
8. Input router computes ray→face hit and forwards mouse move/click/wheel to the corresponding CEF surface.

## Major Challenges Encountered and Resolutions

### 1) Black captures / apparent no-render

Observed:

1. Scene snapshots initially black.
2. Direct texture dump showed valid browser content.

Resolution:

1. Added diagnostics (`surface-stats`, `texture-info`) to prove paint/upload activity.
2. Fixed startup viewport initialization path in `main.fnl` so projection/render state can initialize correctly in this environment.

### 2) Distorted/garbled in-scene browser output

Observed:

1. Severe stretching/visual corruption in cube output despite valid texture data.

Root cause:

1. Default projection matrix used hardcoded invalid values (`fov/aspect` not viewport-derived).

Resolution:

1. `assets/lua/app-projection.fnl` now computes perspective with viewport-derived aspect and sane near/FOV values.

### 3) Alpha/compositing artifacts for browser faces

Observed:

1. Browser face readability degraded with transparency-like blending behavior.

Resolution:

1. Added `forceOpaque` path in mesh fragment shader.
2. Enabled it for browser cube batches.

### 4) Network-dependent verification instability

Observed:

1. `https://example.com` commonly returned Chromium network error page in this environment.

Resolution:

1. Default cube URL switched to deterministic local `data:` page (`CEF OK`).
2. Capture script supports optional URL override for real-world checks.

### 5) Sandboxed execution limitations for CEF/Xvfb

Observed:

1. AF_UNIX/socket/sandbox operations failed in restricted mode.

Resolution:

1. Run visual CEF/Xvfb capture flows outside sandbox when required.

## Assumptions

1. Linux runtime remains first-class target for CEF in current phase.
2. CEF binaries come from pinned URL + SHA256.
3. Remote-control endpoint is available when using capture scripts.
4. Snapshot/capture verification in CI or constrained dev environments may require Xvfb + unrestricted socket access.
5. Default smoke verification should not depend on external internet.

## Usage

### Build

```bash
make cmake
make build
```

### Run browser cube demo

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets SPACE_BROWSER_CUBE_DEMO=1 ./build/space -m main
```

### Capture visible in-scene browser output (deterministic)

```bash
scripts/capture_cef_visible.sh
```

Optional args:

1. Output path: `scripts/capture_cef_visible.sh /tmp/my-visible.png`
2. URL override: `scripts/capture_cef_visible.sh /tmp/my-visible.png "https://example.org"`

### Capture raw browser texture upload

```bash
scripts/capture_cef_surface.sh
```

## Operational Debugging Playbook

When browser output looks wrong:

1. Check surface activity:
   - Use `app.engine.browser.surface-stats(id)` and verify non-zero `paint-count` and `upload-count`.
2. Check texture allocation:
   - Use `app.engine.browser.texture-info(id)` and verify expected dimensions/channels.
3. Isolate composition vs upload:
   - If `capture_cef_surface.sh` image is correct but visible scene is wrong, issue is projection/compositing/scene-side.
4. Validate viewport/projection:
   - Verify `app.viewport` dimensions and projection math match runtime window size.
5. Use deterministic URL first:
   - Test with local `data:` smoke page before testing external sites.

## Known Gaps / Limitations

1. No integrated e2e snapshot test module yet for CEF browser cube in `assets/lua/tests/e2e.fnl`.
2. Windows/macOS CEF integration handlers are placeholders.
3. URL/network policy for production content loading (proxy/certs/security hardening) is not finalized in this note.
4. Browser input coverage is currently mouse-focused; keyboard/text IME details need explicit validation.

## Next Steps (Recommended)

1. Add e2e snapshot test:
   - New module: `assets/lua/tests/e2e/test-browser-cube-cef.fnl`.
   - Register in `assets/lua/tests/e2e.fnl`.
   - Use deterministic `data:` URL and assert snapshot stability.
2. Expand production hardening:
   - Explicit lifecycle/teardown tests for many create/destroy cycles.
   - Memory/VRAM observation under multiple high-resolution surfaces.
   - Input routing stress tests under rapid pointer motion/wheel bursts.
3. Platform extension prep:
   - Implement `space_setup_cef_for_target_windows` and `..._macos` without changing Lua/browser APIs.
   - Keep `BrowserSystem`/Fennel API unchanged so platform bring-up stays in CMake/runtime glue.
4. Add docs cross-links:
   - Link this note from the CEF build section of [Building space](/dev/building) and test docs once e2e coverage lands.

## File Inventory (Implementation Scope)

Primary touched/added files in this implementation:

1. `cmake/cef-defaults.cmake`
2. `cmake/cef.cmake`
3. `apps/space/main.cpp`
4. `apps/space/cef_subprocess_main.cpp`
5. `src/cef_runtime.h`
6. `src/cef_runtime.cpp`
7. `src/browser_system.h`
8. `src/browser_system.cpp`
9. `src/engine.cpp`
10. `assets/lua/browser-cube-surface.fnl`
11. `assets/lua/main.fnl`
12. `assets/lua/app-projection.fnl`
13. `assets/lua/mesh-renderer.fnl`
14. `assets/shaders/mesh.frag`
15. `assets/lua/render-capture.fnl`
16. `src/lua_opengl.cpp`
17. `scripts/capture_cef_surface.sh`
18. `scripts/capture_cef_visible.sh`

## Current Status

Linux-first CEF in-world browsing is implemented and functionally validated with deterministic smoke capture and texture-level diagnostics. The next high-value milestone is adding a formal e2e snapshot test module so this path is continuously regression-tested.

## See also

- [Core Platform](/dev/features/core-platform), [CEF In-World Browser](/dev/features/cef-in-world-browser)
