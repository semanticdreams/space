---
type: subsystem
tags:
  - subsystem
  - input
created: 2026-07-14
---

# Input system

Keyboard, mouse, gamepad, touch, and stylus input handling. Composable state architecture for per-widget input routing, directional focus traversal, focus ordering, and SDL3 event pipeline.

## Key files

- `src/input_state.h`, `src/input_keyboard_state.h`, `src/input_mouse_state.h`, `src/input_gamepad_state.h`
- `assets/lua/state-handlers/` — focus, hover, pointer, camera, gamepad, touch, pen handlers
- `assets/lua/input-state-router.fnl`, `assets/lua/touch-router.fnl`

## Dependencies

- Depends on: [[core-platform]]
- Depended on by: [[layout-widget-engine]], [[canvas-mode-system]]

## Dev notes

- [[dev-notes/composable-states]] — composable state architecture over inheritance
- [[dev-notes/directional-focus-traversal]] — focus movement between widgets
- [[dev-notes/focus-change-ordering]] — focus event ordering
- [[dev-notes/sdl3-input-migration]] — SDL2 to SDL3 migration
- [[dev-notes/selection]] — selection model

## See also

- [[core-platform]]
- [[adr-composable-states]]
- [[subsystems]]
