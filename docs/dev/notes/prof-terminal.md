# Terminal Profiling Plan

## Context
- Terminal profiler (`assets/lua/prof-terminal.fnl`) shows ~33% in `TerminalRenderer.paint` and ~30% in font-state resolution/writes, driven by full-screen dirty regions when PTY floods output.
- Each cell walks all font states and rewrites background/glyph/underline buffers every frame; long outputs repeatedly mark the whole viewport dirty, stalling the main thread.

## Goals
- Reduce per-cell work during heavy output so the UI stays responsive.
- Keep correctness for scrollback, alt-screen, and cursor rendering.

## Plan
- **Short term**
  - Cache the resolved font state per cell and skip iterating `each-font-state` when only one applies; avoid per-cell table scans.
  - Skip buffer writes for unchanged cells within a region (track a hash or reuse vterm dirty rectangles to only touch modified cells).
  - Guard PTY drain-induced redraws with a max cells-per-frame or time budget; if exceeded, spread work across frames and keep input processing alive.
- **Medium term**
  - Rework `get_dirty_regions` consumption to batch by rows/columns and reuse `line-for-viewport` results instead of recomputing per cell.
  - Separate background and glyph passes so background-only changes (e.g., reverse) do not force glyph buffer rewrites.
  - Add a fast-path for “full redraw” that precomputes row slices and uses memcpy-like buffer fills instead of per-cell Fennel loops.
- **Validation**
  - Extend `assets/lua/prof-terminal.fnl` with a mode that simulates a log spammer (large scrollback) and measure frame time before/after.
  - Add a Lua test that drives `TerminalWidget` with synthetic dirty regions to assert we only touch changed cells and preserve scrollback/follow-tail behavior.
  - Manually run a long-output command (e.g., `yes | head -n 50000`) in-app to confirm no UI stall and cursor remains responsive.
