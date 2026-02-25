# SDL3 Input Migration Notes

## Summary

The SDL3 input migration is complete for event correctness and runtime stability, including:

- Window-scoped text input control via `SDL_StartTextInput(window)` / `SDL_StopTextInput(window)`.
- Pixel-size viewport updates for HiDPI via `SDL_GetWindowSizeInPixels()` and `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED`.
- Float mouse position/relative motion propagation.
- Wheel direction normalization when `SDL_MOUSEWHEEL_FLIPPED` is set.
- Consistent gamepad timestamp units (milliseconds) for `InputState` updates.
- `SDL_EVENT_TEXT_EDITING` plumbing through engine events.

## IME Caveat (Current Behavior)

`SDL_EVENT_TEXT_EDITING` is now emitted as `app.engine.events.text-editing` and routed through state/input dispatch, but input widgets currently treat it as handled without rendering composition text.

This means:

- Final committed IME characters continue to work through `SDL_EVENT_TEXT_INPUT`.
- In-progress IME composition (pre-edit text/caret underline/candidate feedback) is not rendered in the input widget yet.

## Why This Is Acceptable For Now

- It avoids dropped or unknown events in SDL3.
- It keeps input state machines stable while preserving strict SDL3 semantics.
- It does not regress non-IME keyboard/text workflows.

## Follow-up For Full IME UX

Implement composition rendering in input widgets by consuming `text-editing` payload fields:

- `text` (composition string)
- `start` (cursor offset inside composition)
- `length` (selection length)

Suggested approach:

1. Store transient composition state on the input model/widget.
2. Render composition overlay separately from committed text.
3. Clear composition state on commit (`text-input`) and blur/disconnect.
4. Add dedicated tests for composition start/update/commit/cancel flows.
