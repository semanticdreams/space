# Wlroots Integration Status

Date: February 6, 2026

Status: Paused. The wlroots compositor integration and Fennel bindings were removed after repeated failures in headless/Xvfb environments. The work is not currently active in the codebase.

## What Was Attempted

- Headless wlroots compositor embedded inside the Space process.
- Xwayland-based app launch (xterm) rendered into a wlroots scene output, surfaced as a texture in Space.
- Snapshot test to capture the xterm surface via the wlroots output texture.

## Problems Encountered

- DMA-BUF import consistently failed in headless/Xvfb runs with `EGL_BAD_MATCH` during `eglCreateImageKHR`, forcing a fallback path.
- Readback paths were unreliable: wlroots output textures remained `nil` or effectively black.
- `wlr_output` commit path was fragile in headless runs; earlier iterations hit `output->back_buffer == NULL` assertions.
- Xwayland socket binding collided with existing `X0..X2` sockets in the test environment, leading to unstable startup.
- Xwayland sometimes terminated mid-run, producing `Broken pipe` warnings and double-free crashes after test teardown.

## Why We Stopped

The integration blocked e2e snapshot testing and destabilized the app during CI-like headless runs. The amount of low-level plumbing required (context ownership, output buffering, renderer readback and Xwayland lifecycle) exceeded the remaining time budget for this phase.

## Next Steps (If We Revisit)

- Run against a real GPU session (non-Xvfb) to validate DMA-BUF import and renderer paths.
- Decide on a single authoritative render/commit model (wlroots output commit vs manual renderer begin/end) and document it.
- Implement a robust pixel readback strategy for headless environments.
- Isolate Xwayland lifecycle management from tests to avoid socket collisions and teardown crashes.

