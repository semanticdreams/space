# HUD Chrome Button-Owned Padding Design

## Context

The HUD chrome uniformity work made the status panel, control panel, side rails,
and Sandbox toolbar share a final cross-axis size. The status panel now looks
right, and the control/Sandbox icon sizes were corrected to match the rails.
However, the control panel and Sandbox toolbar still reach their height through a
different logic than the rails: their `Card` shell contributes outer `Padding`,
while the rails size directly from their button content.

The desired refinement is to make the control panel and Sandbox toolbar use the
same natural sizing logic as the rails. Their solid `Card` background should
remain, but the shell should not add cross-axis padding. The icon buttons should
own the padding that determines the toolbar height.

## Goals

- Remove outer/shell padding as a sizing contributor from the top control panel.
- Remove outer/shell padding as a sizing contributor from the Sandbox
  Flight/Move/Anchor toolbar.
- Preserve the solid background for both surfaces.
- Keep the final natural height matched to the side rail width.
- Express matching through button/icon metrics, not fixed container sizes.
- Preserve the current status panel sizing and behavior.

## Non-Goals

- No changes to rail appearance or rail metrics.
- No changes to status panel metrics.
- No fixed `Sized` wrappers, fixed toolbar heights, or HUD band changes.
- No global `Button` default changes.
- No Sandbox toolbar behavior changes beyond visual sizing.

## Design

Control/Sandbox single-row chrome should use button-owned padding:

- rail cross-axis size remains: rail icon scale `3.2` plus rail button horizontal
  padding `0.4 + 0.4`;
- control/Sandbox cross-axis size becomes: icon scale `3.2` plus button vertical
  padding `0.4 + 0.4`;
- control/Sandbox shell padding becomes zero or is removed from the wrapper so
  the `Card` provides background only.

In shared metrics terms, `single-row-button-padding` should become `[0.4 0.4]`
and the control/Sandbox shell padding should be represented separately from the
status shell padding. This avoids changing the status panel, whose height is
intentionally produced by text row padding.

Implementation should prefer explicit metric names over overloading the current
`single-row-shell-padding` for both status and button-owned chrome. The tests
should assert that control/Sandbox shell padding does not contribute to the
measured cross-axis size, so future changes cannot reintroduce the split-padding
logic by accident.

## Testing

Focused tests should cover:

- control panel natural height equals rail width;
- Sandbox toolbar natural height equals rail width;
- control/Sandbox use zero shell padding or a shell wrapper that does not affect
  measurement;
- status panel natural height remains equal to rail width;
- Sandbox toolbar behavior tests continue to pass.

Validation should follow the Space Fennel ladder: compile check, constraints,
focused HUD/Sandbox tests, and E2E snapshots if the visual goldens change.
