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

- Depends on: [Core Platform](/dev/features/core-platform)
- Depended on by: [Layout Widget Engine](/dev/features/layout-widget-engine), [Canvas Mode System](/dev/features/canvas-mode-system)

## Dev notes

- [Composable States](/dev/notes/composable-states) — composable state architecture over inheritance
- [Directional Focus Traversal](/dev/notes/directional-focus-traversal) — focus movement between widgets
- [Focus Change Ordering](/dev/notes/focus-change-ordering) — focus event ordering
- [Sdl3 Input Migration](/dev/notes/sdl3-input-migration) — SDL2 to SDL3 migration
- [Selection](/dev/notes/selection) — selection model

## See also

- [Core Platform](/dev/features/core-platform)
- [Composable States](/dev/adrs/adr-composable-states)
- [Subsystems](/dev/subsystems/)
