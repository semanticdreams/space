# Right Sidebar Rail Visual Alignment Design

Date: 2026-07-25

## Summary

The rightmost HUD sidebar rail, used for toggling panels such as Terminal and Space Agent, should visually match the left activity sidebar. Today the right rail uses smaller icons and different vertical padding, and its width is fixed independently from the size needed by its buttons. This makes the buttons look wider than their icons, non-square, and inconsistent with the left activity rail.

The design is to make the right rail button-driven and naturally measured, like the left rail. The right rail buttons will use the same icon scale, padding, variant behavior, vertical flex layout, and zero spacing as the left activity buttons. The HUD layout will stop imposing a fixed right dock width.

## Goals

- Make right sidebar rail buttons look like the left activity rail buttons.
- Remove fixed right rail width sizing; the rail should size from its button contents.
- Preserve existing right sidebar behavior for selecting, toggling, collapsing, focus clearing, panel caching, and panel updates.
- Preserve the existing expanded panel width and position the panel directly left of the rail.

## Non-Goals

- Do not change left activity dock behavior.
- Do not make the expanded Terminal/Space Agent panel naturally measured or resizable.
- Do not introduce a shared dock button abstraction in this change.
- Do not change sidebar entry registration, persistence, focus semantics, or panel lifecycle semantics.

## Current Behavior

The left activity dock constructs icon buttons in `assets/lua/activity-dock-view.fnl` with:

- `:padding [0.4 0.25]`
- `:icon-style {:scale 3.2}`
- `:variant :primary` when active and `:secondary` otherwise
- a vertical `Flex` rail using `:xalign :stretch` and `:spacing 0`

The right extended sidebar constructs icon buttons in `assets/lua/hud-extended-sidebar-view.fnl` with smaller styling:

- `:padding [0.4 0.2]`
- `:icon-style {:scale 2.4}`
- a fixed rail width of `6`

The HUD layout also wraps the right dock in a fixed-width `Sized` container, using `right-dock-width` or a default width. Production wiring in `assets/lua/main.fnl` currently sets `right-dock-width` to `6`.

## Proposed Design

### Right rail button styling

Update the right rail buttons in `hud-extended-sidebar-view.fnl` to match the left activity rail buttons:

- `:padding [0.4 0.25]`
- `:icon-style {:scale 3.2}`
- keep `:focusable? false`
- keep the existing button names and focus names
- keep the existing click behavior through `sidebar:entry-clicked`
- keep the existing active/inactive variant selection

This makes Terminal and Space Agent rail buttons visually consistent with activity selection buttons.

### Natural rail measurement

Remove the fixed `rail-width` constant from `hud-extended-sidebar-view.fnl`. The sidebar root layout should measure its rail by measuring `rail-entity.layout` and reading the rail's measured width.

Collapsed measurement:

- root width equals the measured rail width

Expanded measurement:

- root width equals `panel-width + measured rail width`

The existing `panel-width 38` remains unchanged.

### Right-edge anchoring

The right sidebar should remain visually anchored at the right edge of its allocated HUD area. During layout:

- compute the rail width from the rail entity measurement
- compute the allocated root width from the layout size, falling back to the measured root width when needed
- position the rail at the right edge of the allocated root area
- position the active panel immediately to the left of the rail

This preserves the existing visual relationship where the expanded panel opens leftward from the right rail.

### HUD layout contract

Update `hud-layout.fnl` so the right dock is inserted as a natural `FlexChild`, matching the left dock. Remove the fixed-width `Sized` wrapper and remove the default right dock width constant.

Update production wiring in `main.fnl` to stop setting `hud-opts.right-dock-width`. The right dock builder remains `HudExtendedSidebarView app.extended-sidebar`.

## Testing Plan

Add or update focused tests for:

- `hud-layout.fnl`: right dock uses its natural measured width instead of a fixed width.
- `hud-extended-sidebar-view.fnl`: collapsed width equals measured rail width.
- `hud-extended-sidebar-view.fnl`: expanded width equals `panel-width + measured rail width`.
- `hud-extended-sidebar-view.fnl`: expanded layout positions the active panel immediately left of the rail.

Validation commands:

```sh
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hud-layout:main
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hud-extended-sidebar:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.fast:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

## Acceptance Criteria

- Right sidebar rail buttons visually match the left activity rail buttons.
- Right sidebar rail width comes from measured button contents, not a fixed constant.
- The expanded panel remains directly left of the rail.
- Existing right sidebar toggle/select/collapse behavior is unchanged.
- Existing left activity dock behavior is unchanged.
