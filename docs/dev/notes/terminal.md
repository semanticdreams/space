Terminal widget implementation plan
===================================

Goal: build a Fennel terminal widget that renders libvterm output, handles input, and integrates with the existing layout/render systems.

Constraints
- Use the new C++ Terminal binding (rows/cols, dirty regions, cursor, title, bell, send_key/text/mouse, resize, update).
- Respect existing layout primitives and renderers; avoid re-dirtying layouts mid-pass.
- Favor monospace font and per-cell background + glyph rendering.

Current state (context for future work)
- Binding: C++ `Terminal` (PTY + libvterm) exposed via sol2; available via `(require :terminal)` and constructed with `terminal.Terminal(...)`.
- Scrollback/alt-screen: binding now stores scrollback with line/byte caps, exposes `get_scrollback_size/get_scrollback_line`, reports `is_alt_screen`, supports `set_scrollback_limit`, and allows `inject_output` for PTY-less tests.
- Widget: `assets/lua/terminal.fnl` builds a terminal entity with layout measurer/layouter, `update`/`drop`, options `rows/cols/cell-size/on-bell/on-title/focusable?/focus-name`, click-to-focus, focus-node creation, and pointer-target registration. Hooks `on_screen_updated/on_cursor_moved` to invalidate rendering, routes input while focused through `InputState` to `send_text/send_key/send_mouse`, and auto-subscribes `update` to `app.engine.events.updated` (disconnects on drop). Scrollback options now available: `scrollback-lines` (sets binding limit), `enable-alt-screen?` (default true), `follow-tail?` (default true), initial `scroll_offset`, and `on-scroll` callback. Scroll offsets are clamped to 0 in alt-screen and snap back to tail on input when following.
- Rendering: New `assets/lua/terminal-renderer.fnl` paints dirty cells into triangle/text buffers (background + glyph) with depth offsets and cursor overlay + blink timing. Uses dirty regions for partial redraws, full redraw on resize, and clears dirty regions post-paint.
- Tests: `assets/lua/tests/test-terminal-widget.fnl` (measure + resize + focus/input routing) and `assets/lua/tests/test-terminal-renderer.fnl` (dirty-region painting, cursor blink GL calls) included in `assets/lua/tests/fast.fnl` via `make test`/`./build/space -m tests.fast:main`.
- Behavior: Widget resizes terminal on layout size changes (using font-derived cell metrics unless overridden). Rendering and cursor visuals are in place; input plumbing is wired through focus + clickables and expects `ctx.clickables` to be present. When PTY creation fails, the binding exposes `is_pty_available`; the widget injects a placeholder banner, disables scrollback navigation, and continues rendering an empty grid so tests and UI stay stable.

Plan

1) Core widget skeleton ✅
- Added `assets/lua/terminal.fnl` builder that instantiates `Terminal`, exposes `update/drop`, supports `rows/cols/cell-size` options, and hooks bell/title callbacks.

2) Layout + sizing ✅
- Measurer reports `rows*cell_w`, `cols*cell_h` (defaults derived from theme font; can override via `cell-size`).
- Layouter converts pixel size→rows/cols (floor), calls `term:resize`, and writes layout size.
- Tests cover measure/resize (`assets/lua/tests/test-terminal-widget.fnl`).

3) Rendering pipeline ✅
- `assets/lua/terminal-renderer.fnl` iterates dirty regions, writes per-cell background quads + glyphs via existing buffers, honors `reverse`/`bold` (simulated), and clears dirty regions. Uses depth offsets and full redraw on resize/layout changes; wired via `on_screen_updated/on_cursor_moved`.

4) Cursor visuals ✅
- Renders a cursor overlay (block) with depth offset above glyphs, respects visibility, and blinks on a configurable period in Fennel.

Glyph styling ✅
- Bold/Italic: renderer swaps to theme-provided MSDF variants (regular/italic/bold/bold-italic) per cell, clears unused font buffers, and falls back to the regular font if a variant is missing.
- Underline: per-cell underline quad derived from font metrics/line height; rendered at `depth+1`, honors reverse/fg colors, and uses the layout transform.
- Tests: font-variant selection and underline geometry covered in `assets/lua/tests/test-terminal-renderer.fnl` alongside dirty-region behavior using the OpenGL mock.

5) Input plumbing ✅
- When widget focused, connect to `InputState` (same pattern as `assets/lua/input.fnl`) so `normal-state` handlers short-circuit to the active terminal and return `true` to stop propagation.
- Map SDL/Fennel events to the binding:
  - Printable text → `term:send_text`.
  - Special keys (arrows, home/end, page up/down, delete/backspace, tab, enter, function keys) → `term:send_key`.
  - Mouse events: convert screen coords to cell row/col via layout position/size; call `term:send_mouse` with button + pressed flag.
- On blur (focus lost), disconnect from `InputState` and let normal-state fall back; ignore input when unfocused.
- Implemented in `assets/lua/terminal.fnl` with focus listener + clickable registration; input dispatch routes text/keys/mouse to the binding. Tests cover focus connect/disconnect and event forwarding.

6) Update loop ✅
- Widget `update` calls `term:update` and is auto-connected to `app.engine.events.updated` so PTY output is pulled every frame; handler is dropped on widget `drop`.
- On `on-title-changed`, optionally propagate to window title; on `on-bell`, call supplied callback or play a sound. Currently only hooks the provided callbacks.

7) Tests
- Added `assets/lua/tests/test-terminal-widget.fnl` (measure + resize + focus/input dispatch + frame-update subscription).
- Added `assets/lua/tests/test-terminal-renderer.fnl` using the OpenGL mock to cover dirty-region repaint and cursor blink visibility.
- Input mapping covered by terminal widget test (focus, text/key/mouse send).

8) Configuration and docs ✅
- Documented `SPACE_TERMINAL_PROGRAM` default/override in README and below; the command is whitespace-split and defaults to `/bin/sh`.
- Sandboxed/PTY-less environments now render a placeholder message and leave scrollback controls disabled instead of crashing.

9) Misc
- How to best handle scrollback/alt-screen? (libvterm supports callbacks; we may need higher-level buffering.)
- Expose a palette map to avoid per-cell truecolor for performance.

Scrollback/alt-screen design
- Source of truth: keep history and alt-screen state in C++/libvterm; expose read-only APIs to Fennel to fetch lines by offset and query `in_alt_screen?`.
- Limits: configurable `scrollback-lines` (default 5k–10k) plus a byte cap (8–16 MB) enforced in the binding; let libvterm handle resize reflow.
- Alt-screen semantics: match traditional behavior—alt-screen has no scrollback; main scrollback is preserved but hidden while in alt-screen.
- Rendering: renderer paints the live screen; when `scroll_offset` > 0 (and not in alt-screen) it renders from history with that offset and freezes follow-tail until offset returns to 0.
- Input/navigation: wheel/PageUp/PageDown adjust `scroll_offset`; any typing or explicit follow-tail toggle snaps back to 0. Disable scrollback navigation in alt-screen. Optional `on-scroll` callback.
- APIs: widget options `scrollback-lines`, `enable-alt-screen?` (default true), `follow-tail?` (default true), `on-scroll`. Binding additions: history accessors, `is_alt_screen`, `get_scrollback_size`.
- Performance: introduce a palette map for scrollback rendering to reduce per-cell truecolor, and avoid re-dirtying layouts when only `scroll_offset` changes.
- Fallback: if PTY/libvterm unavailable, render empty grid with a status message and disable scrollback/alt-screen controls.

Configuration
- Runtime shell: defaults to `/bin/sh`; override with `SPACE_TERMINAL_PROGRAM` (split on whitespace) such as `SPACE_TERMINAL_PROGRAM="bash -l"`.
- Sandboxes: when PTY creation fails, the widget injects a placeholder banner into the terminal buffer and keeps scrollback navigation disabled while still rendering the grid.

Implementation plan
1) C++ binding ✅: scrollback storage/limits, alt-screen flag, accessors for current screen and history lines, `get_scrollback_size`, `set_scrollback_limit`, and `inject_output` for PTY-less tests.
2) Widget state/options ✅: add `scrollback-lines`, `enable-alt-screen?`, `follow-tail?`, `scroll_offset`, `on-scroll`; snap offset to 0 on input when follow-tail is true; block scrollback navigation in alt-screen.
3) Renderer ✅: support rendering with `scroll_offset` (history rows) while reusing existing dirty-region logic; add palette map for color lookup to reduce per-cell truecolor.
4) Input wiring ✅: map wheel/PageUp/PageDown/Shift+Wheel to offset adjustments; add follow-tail toggle; disable scrollback navigation in alt-screen; call `on-scroll` when offset changes.
5) Tests ✅: C++ unit tests for limits/history; Fennel tests for scrollback navigation, alt-screen blocking, renderer offset handling, and palette map behavior.
