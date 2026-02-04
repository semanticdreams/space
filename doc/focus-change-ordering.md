# Focus Change Ordering Plan

## Summary
- Current focus notifications use a single `focus-changed` signal; listeners derive focus state by comparing against `FocusManager:get-focused-node`.
- Listener execution order is undefined, so blur handlers can run after focus handlers and clobber state (e.g. inputs toggling text/normal).
- Ordered blur → focus signals make focus transitions deterministic, so widgets can respond only to their own event without checking global focus state or other widgets.

## Planned Change
- Replace the single `focus-changed` signal with ordered notifications:
  - `focus-blur` (old node losing focus)
  - `focus-focus` (new node gaining focus)
- Blur must always fire before focus for the same transition.
- Remove the legacy `focus-changed` signal and update all listeners to the new API.

## Migration Notes
- Update widgets that listen to focus changes (`Input`, `Terminal`, any focus-aware UI) to subscribe to the ordered signals.
- Ensure state transitions triggered on focus are only performed in the focus handler; blur should only perform cleanup.
- Keep the two-phase contract consistent across scene and HUD focus scopes.
- Once ordered signals are in place, remove the interim guard logic added to `Input` that checks for another active input before forcing `:normal`.

## Follow-ups
- Add tests that assert blur fires before focus for a transition.
- Update any debug tooling or HUD status panels that show focus state.
