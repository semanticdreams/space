# HUD Right-Rail Transparent Strip Fix Design

## Context

The HUD top toolbar is laid out in the center column while the extended right
rail is a sibling in the middle horizontal flex band. When the terminal/chat
panel expands, `HudExtendedSidebarView` currently measures itself as panel width
plus rail width. The parent flex therefore reserves a full panel-width strip for
the entire middle band, including the toolbar row. The expanded panel itself is
bottom-anchored below the toolbar reserve, leaving the reserved area above it
transparent and preventing the Sandbox toolbar from rendering there.

Prior spacing work already aligned the toolbar/control row and bottom-anchored
the right-rail panels below the toolbar reserve. This design is limited to
removing the remaining transparent strip caused by expanded measurement.

## Decision

Use the rail as the only in-flow width for `HudExtendedSidebarView`. In expanded
state the terminal/chat panel remains a child of the extended sidebar, but it is
laid out as a flyout projected to the left of the rail, below the toolbar
reserve. The parent HUD layout should reserve only the rail width in the middle
flex band whether the panel is collapsed or expanded.

Alternatives considered:

1. Move the HUD toolbar into the same right-dock column. This would couple
   independent toolbar and right-rail concerns and risks regressing recent
   toolbar spacing fixes.
2. Add a special case in `hud-layout` to subtract the panel width when the right
   dock is expanded. This would leak sidebar internals into the parent layout.
3. Measure the sidebar as rail-only and let the expanded panel project left.
   This matches the desired mental model, keeps the rail in flow, and preserves
   local ownership of panel placement in `HudExtendedSidebarView`.

The chosen approach is option 3.

## Components and Data Flow

- `assets/lua/hud-extended-sidebar-view.fnl`
  - Expanded measurement reports the measured rail width only.
  - Layout keeps the rail full-height at the right edge of the allocated sidebar
    root.
  - The active terminal/chat panel is positioned to the left of the rail and
    below the toolbar reserve, which may place it outside the sidebar root's
    measured bounds.
- `assets/lua/hud-layout.fnl`
  - No behavior change is intended. It should continue reserving the right dock
    by the dock child's natural measured width; after the sidebar measurement
    change this reservation is the rail width.
- Focused tests verify the sidebar contract directly and the HUD-layout
  integration behavior indirectly.

## Error Handling and Constraints

No new runtime fallback paths are introduced. Missing required context continues
to surface through existing assertions/errors. The fix must avoid legacy aliases
or compatibility shims and must not change behavior outside the transparent-strip
bug.

## Testing Strategy

Follow Space Fennel UI validation order:

1. Add/update focused Fennel tests before production changes.
2. Run touched-file `tools.fennel-check` for the sidebar and layout tests.
3. Run `make constraints`.
4. Run focused HUD extended sidebar and HUD layout Fennel tests.
5. Broaden only if the reviewer or validation evidence shows the changed surface
   requires it.

Acceptance criteria:

- Expanded `HudExtendedSidebarView` measured width equals rail width, not rail
  plus panel width.
- The expanded panel is laid out left of the rail and may project off the
  sidebar root while still honoring the toolbar reserve vertically.
- HUD layout's right-dock reservation consumes only actual rail width when the
  dock is expanded, preserving toolbar render space.
