# HUD Control Button Spacing Design

## Context

The HUD chrome is now height-aligned across the Sandbox toolbar, control panel,
and rail first-row buttons. The next visual polish is to make the visible
control panel groups look more uniform by removing horizontal gaps between their
buttons.

The visible control panel surface consists of the main icon-button cluster and
the world selector buttons. The older/default layout path can also accept status
or body builders, but this change targets the visible button groups, not text
content or unrelated panels.

## Desired Behavior

- The control panel icon buttons sit directly adjacent to each other, with no
  Flex spacing inserted between buttons.
- The world selector buttons sit directly adjacent to each other, including the
  add-world button.
- Button-owned padding remains unchanged, so each button keeps its current size,
  touch target, icon/text padding, and rail-height alignment.
- HUD shell padding, rail metrics, status panel metrics, toolbar metrics, and
  global `Button`/`Flex` defaults remain unchanged.

## Design Direction

Use a HUD-scoped spacing adjustment rather than changing global widget defaults:

1. Set the HUD control row spacing metric to zero for the icon-button cluster.
2. Pass zero tab spacing when constructing the HUD world selector.
3. Add focused tests that measure row widths against the sum of child widths,
   proving no inter-button spacing is present.

This keeps the change local to the HUD chrome and avoids changing unrelated UI
rows that still intentionally use spacing.

## Components

- `hud-chrome-metrics.fnl`: owns the control-row spacing metric.
- `hud-control-panel-layout.fnl`: consumes the metric for the control row.
- `world-tabs-widget.fnl`: already supports caller-provided `:tab-spacing`.
- `main.fnl`: constructs the HUD world selector and can pass the HUD-specific
  zero spacing value.
- Focused Fennel tests should cover both the icon-button cluster and world tab
  row measurement.

## Testing

- Compile-check touched Fennel files with `tools.fennel-check`.
- Run constraints after compile check.
- Run focused control panel and world-tabs tests.
- Run HUD chrome/layout related tests if the changed files affect shared HUD
  surfaces.
- Run broader fast tests for regression coverage.
- Run E2E only if a snapshot-covered HUD view changes and goldens need refresh.

## Non-Goals

- Do not change global `Button`, `Flex`, or `WorldTabsWidget` defaults.
- Do not change button padding or heights.
- Do not change right/left rail metrics, toolbar height, HUD band allocation, or
  right-rail panel overlay positioning.
- Do not remove spacing from unrelated dialogs, lists, forms, or graph views.

## Self-Review

- No placeholders or TBDs remain.
- Scope is limited to HUD button-group spacing.
- The design preserves the button-owned sizing model and avoids global defaults.
- The world selector requirement is explicit and separate from legacy status
  text paths.
