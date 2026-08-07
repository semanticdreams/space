# Graph UX Polish Design

## Context

The graph sidebar node finder works, but follow-up use exposed four issues:

1. Long node labels in the `Find Node` list expand the graph sidebar instead of truncating within the available panel width.
2. The finder query input stays at its intrinsic width when the active map has no finder rows, instead of filling the sidebar content width.
3. The graph canvas background is black; graph mode should use theme-based neutral greys, and the visual hierarchy between graph canvas, side rails, and panels should be distinguishable but harmonious.
4. Pressing the graph sidebar `New` map button can crash with `map-2.0` because restored `next_map_id` values may retain decimal formatting and map ids intentionally reject dots.

The confirmed crash root cause is that `GraphMapManager.ensure-int` accepts integral numeric values but returns the original value. When a restored value is represented as `2.0`, the sidebar stringifies it into `map-2.0`, and `safe-map-id?` correctly rejects the dot.

## Goals

- Keep the graph sidebar width fixed and stable as maps/nodes with long labels are added.
- Truncate long graph sidebar map row and node finder labels with an ellipsis for display.
- Preserve full labels for search source data and test/debug observability where useful.
- Make the finder input fill the fixed sidebar content width even when the finder list is empty.
- Replace black graph activity background with a theme-based neutral grey.
- Add a simple theme hierarchy for graph canvas, side rails, and panels so backgrounds are related but visually distinct.
- Fix `New` graph map creation when restored `next_map_id` is represented as an integral float such as `2.0`.

## Non-Goals

- No global `Text` or `Button` overflow/truncation engine.
- No user-configurable graph sidebar width.
- No changes to graph topology or map persistence semantics beyond normalizing restored integer ids.
- No relaxing of `safe-map-id?`; map ids remain dot-free for metadata path safety.
- No broad theme redesign or pixel-perfect color tuning.

## Approaches Considered

### A. Local sidebar-only fixes

Clamp the graph sidebar width and truncate finder labels only in `graph/map-sidebar.fnl`, while separately normalizing `next_map_id`. This is low risk but leaves the background hierarchy duplicated and inconsistent across dock/sidebar surfaces.

### B. General constrained text overflow

Teach `Text` or `Button` to truncate dynamically from layout constraints. This is architecturally attractive but too broad for the current polish pass; many widgets could change behavior at once.

### C. Focused graph polish with shared theme chrome tokens

Fix graph sidebar width/truncation locally, normalize map ids at the manager boundary, and introduce small shared theme chrome tokens for graph background, rails, and panels. Existing sidebar/dock surfaces can use the same resolver without changing every widget’s text behavior.

Chosen approach: **C**.

## User Experience

- The graph sidebar keeps a stable fixed width.
- Long map names and node finder rows render with `...` rather than expanding the sidebar.
- Searching still uses the full node labels, not only the truncated display labels.
- The finder input stretches across the sidebar content area even when the active map has no node rows.
- Pressing `New` creates `map-2`, `map-3`, etc. and never formats ids as `map-2.0`.
- Graph mode uses a neutral theme background instead of black:
  - graph canvas: base grey surface;
  - side rails/tool rails: distinct rail grey;
  - panels/sidebars: slightly elevated panel/card grey.

The exact colors should be conservative and theme-specific. Dark theme should use related charcoal greys; light theme should use related pale greys. The goal is reasonable hierarchy, not final art direction.

## Architecture

### Graph map id creation

`GraphMapManager` remains the source of truth for safe map state. Restored `next_map_id` values should be normalized at the manager boundary so `manager.next-map-id` is always integer-like. The sidebar can still build ids from the manager value, but it should format them with integer formatting rather than raw `tostring`.

`safe-map-id?` remains strict. The fix is not to allow dots; the fix is to avoid creating dotted ids.

### Sidebar sizing and truncation

`GraphMapSidebar` should own its visual width. It should measure and lay out to a fixed width and stretch its vertical content to that width. Map row and node finder button text should use bounded, display-only truncation via the existing graph ellipsis helper. Logical node labels remain available in finder item data for sorting/searching.

This avoids a global widget overflow behavior change and keeps risk limited to graph sidebar polish.

### Finder input width

The current input width problem comes from intrinsic measurement: an empty `ListView` contributes no width, and the input has its own minimum width. Once the sidebar supplies a fixed width and the content flex stretches on the x axis, `SearchView` can stretch its input/list composition to the available sidebar content width even with zero items.

### Theme backgrounds

Themes should expose a small chrome/background hierarchy:

- `theme.graph.background` for graph activity canvas background.
- `theme.chrome.rail-background` for tool/side rails.
- `theme.chrome.panel-background` for panels/sidebar bodies.

`widget-theme-utils` should provide a resolver for panel/rail backgrounds with safe fallbacks to existing `theme.card.background` behavior. Existing dock/sidebar code should prefer the resolver over duplicated color math.

Graph activity should apply `theme.graph.background` to the graph activity scene/slot background at activation time. If the active theme lacks the token, use a non-black grey fallback.

## Error Handling

- Invalid map ids still fail fast through `assert-safe-map-id`.
- Missing required graph sidebar context remains an assertion failure.
- Missing theme tokens use explicit neutral grey fallbacks; graph activity should not silently fall back to black.

## Testing

Focused tests should cover:

- `GraphMapManager` normalizes restored `next_map_id = 2.0` to an integer-like value.
- Graph sidebar `New` with restored `next_map_id = 2.0` creates/switches to `map-2` without crashing.
- Graph sidebar width stays fixed with a very long node label.
- Long finder row and map row labels display with ellipsis.
- Finder input lays out to the fixed sidebar content width when there are no node rows.
- Theme background resolver returns theme chrome rail/panel colors and safe fallbacks.
- Graph activity applies a theme graph background instead of black.

Validation should run project-native Fennel compile checks, constraints, focused graph/theme tests, and a broader suite because theme/chrome/activity changes can affect adjacent UI surfaces.

## Risks and Mitigations

- **Over-broad theme impact:** Keep new theme tokens small and route existing surfaces through a resolver with existing fallback behavior.
- **Approximate truncation:** Character-count truncation is acceptable for this pass; dynamic pixel-perfect truncation is out of scope.
- **Layout regressions:** Cover fixed width and empty finder input layout with focused sidebar tests.
- **Persistence compatibility:** Normalize integer-like `next_map_id` values without changing map ids or persistence structure.
