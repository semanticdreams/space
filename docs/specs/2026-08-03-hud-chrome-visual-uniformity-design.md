# HUD Chrome Visual Uniformity Design

## Context

The HUD chrome has several related single-row surfaces: the left activity rail,
the right terminal/chat rail, the top control panel, the bottom status panel,
and the Sandbox activity toolbar for Flight/Move/Anchor modes. The side rails
currently have the desired visual density and cross-axis size. The Sandbox
toolbar does not visually match the rest of the chrome because it is a bare row
of buttons without a solid panel background, and the control/status/toolbars use
different content metrics from the rails.

The goal is to make these normal single-row HUD chrome surfaces feel uniform
without forcing fixed outer container sizes. Matching should come from the
children's natural measurements: icon scale, button padding, shell padding, and
card/panel composition.

Full panels, dialogs, expanded sidebars, agent/chat content, and other multi-row
or content-rich surfaces are out of scope. Those should continue to size to
their own content.

## Goals

- Preserve the left and right rails as the visual source of truth.
- Give the Sandbox toolbar a solid background consistent with the control and
  status panels.
- Make the normal single-row top control panel, bottom status panel, and Sandbox
  toolbar naturally measure to the same cross-axis size as the side rail width.
- Achieve sizing through shared child metrics, not fixed-size outer wrappers or
  HUD band constraints.
- Keep existing Sandbox toolbar behavior: labels, active variants, click
  handlers, state updates, and lifecycle disconnects.
- Keep changes localized to HUD chrome composition and tests.

## Non-Goals

- No redesign of theme color tokens.
- No global `Button` default changes that could affect dialogs or non-HUD UI.
- No fixed-size `Sized` wrappers or layout constraints around panels/toolbars.
- No HUD band allocation or dock topology changes.
- No expanded panel/dialog sizing changes.

## Recommended Approach

Introduce a small shared HUD chrome metrics module and apply those metrics at
the existing widget composition points.

The rails already use icon-only buttons with padding `[0.4 0.25]` and
`icon-style {:scale 3.2}`. Those values should become the canonical rail button
metrics. Single-row HUD panels and activity toolbars should use corresponding
button and shell metrics that cause their natural measured height to equal the
rail's natural measured width. The exact values should be validated by focused
measurement tests rather than by hard-coding container sizes.

The Sandbox toolbar should be wrapped in the same visual shell pattern used by
other HUD chrome: `Card` containing `Padding` containing the existing horizontal
`Flex` row. This gives it a solid background while preserving automatic sizing.
The toolbar should continue to expose/update its three buttons after wrapping,
either by capturing button references in the child builders or by carefully
traversing the new wrapper structure.

## Alternatives Considered

### Global button/theme defaults

Changing default button icon scale or padding would be mechanically simple, but
it is too broad. It would risk resizing unrelated buttons in dialogs, launchers,
wallet views, inputs, and other non-HUD contexts.

### Runtime rail measurement coupling

Another option is to measure the rail width and feed that value into top/bottom
toolbar sizing. This would produce equality, but it creates unnecessary runtime
coupling and effectively becomes a fixed cross-axis constraint. It also works
against the desired model where containers naturally size to their children.

### Local duplicated constants

Duplicating tuned values in each chrome file would be a small diff, but it would
make future visual tuning fragile. A tiny shared metrics module keeps the rule
explicit without introducing a larger theming redesign.

## Architecture

### Shared metrics

Create a Fennel module such as `hud-chrome-metrics.fnl` exporting constants for:

- rail button padding and icon style;
- single-row HUD button padding and icon style;
- panel/toolbar shell padding;
- any row spacing needed to keep existing visual rhythm.

The module should contain constants only unless implementation shows a helper is
needed. It should not depend on runtime layout state.

### Rails

Update the activity rail and extended sidebar rail to consume the shared rail
metrics while preserving their current natural size and appearance.

### Control and status panels

Update the control and status panel layouts to use shared shell padding. Update
control panel buttons, including the volume button if it uses its own button
construction path, so the panel row's natural height matches the rail width.

Status panel content should remain single-row text/command content. The matching
target applies to the normal collapsed/single-row surface, not arbitrary body
content.

### Sandbox toolbar

Wrap the existing toolbar row in `Card + Padding`, apply shared toolbar button
metrics, and preserve current state-driven updates. The root should have a
solid background through `Card`; no custom rectangle shell is needed unless the
existing card abstraction cannot satisfy tests.

### Lifecycle and layout constraints

The implementation must follow existing Fennel widget conventions:

- builders return build closures;
- composites own and drop their direct child widgets;
- required build context should assert rather than silently fall back;
- layout passes should write child transforms directly and mark only the
  shallowest appropriate layout dirty.

## Testing and Validation

Add focused tests that build representative HUD chrome widgets and compare
natural measurements with a small epsilon:

- rail natural width equals top control panel natural height for the normal
  single-row case;
- rail natural width equals bottom status panel natural height for the normal
  single-row case;
- rail natural width equals Sandbox toolbar natural height;
- Sandbox toolbar root has a solid panel/card background;
- existing Sandbox toolbar state, text, variant, click, update, and drop behavior
  remains intact.

Validation should follow the Space Fennel ladder:

1. `make fennel-check` or touched-file `tools.fennel-check` commands;
2. `make constraints`;
3. focused HUD/Sandbox toolbar Fennel tests;
4. broader `tests.fast:main` when the shared chrome metrics affect multiple HUD
   surfaces.

E2E snapshot updates are not required by the design unless implementation or
review finds that existing snapshot coverage must be refreshed for the visual
change.
