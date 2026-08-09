# Graph Activity Theme and Panel UX Design

## Context

Recent graph activity polish improved several layout surfaces, but four UX issues remain visible in normal graph map use:

1. Graph edges do not visually respond to theme changes. In dark mode, default edges remain effectively black/dark and are difficult to see.
2. Inline compact panels created by double-clicking graph points are now bounded, but full node-view panels opened by focusing a point and pressing Enter can be added to the graph map with unbounded size.
3. The graph-map management sidebar can disappear after a theme change and returns only after switching to another activity and back. Graph activity should always own this sidebar while active.
4. Inline compact panels should show the node's truncated label in their titlebar/header, matching the useful title context available in full panels.

The graph remains an adaptor layer over graph-addressable domain objects. These fixes should stay in graph view, widget presentation, activity dock lifecycle, and theme-resolution boundaries rather than changing graph topology or domain persistence.

## Goals

- Make default graph edge rendering use the active theme's graph edge color in both light and dark modes.
- Preserve explicit per-edge colors when callers intentionally set them.
- Ensure focused-Enter full node-view panels use the same bounded default sizing policy as inline compact panels unless an existing persisted panel size is being restored.
- Guarantee that graph activity restores and displays its graph-map management sidebar after theme changes without requiring an activity switch.
- Display a truncated node label in the compact inline panel header/titlebar.
- Cover the behavior with focused Fennel tests and project-native Fennel validation.

## Non-Goals

- No changes to graph node, edge, or map persistence format except normal use of existing persisted panel size data.
- No global dialog, `Text`, or panel sizing overhaul.
- No global theme system redesign beyond correcting graph edge theme resolution and activity dock rebuild behavior.
- No changes to graph map ownership or node-view domain adapters.
- No pixel-perfect dynamic title truncation engine; existing character-count ellipsis behavior is sufficient for this pass.

## Approaches Considered

### A. View-owned UX fixes plus shell rebuild repair

Keep each fix in the layer that owns the visible behavior: graph edge rendering resolves theme defaults at render/layout time; graph node-view opening supplies bounded default sizes; graph activity/theme lifecycle explicitly rebuilds or refreshes the activity dock after graph reactivation; compact card presentation adds the truncated title text.

This is the chosen approach. It fits the current graph doctrine and UI lifecycle boundaries while keeping the behavioral surface narrow.

### B. In-place theme mutation APIs

Add direct `apply-theme` methods to graph views, edge widgets, and sidebars so existing widgets mutate themselves on theme change rather than being rebuilt.

This risks stale callbacks and partial theme application because theme changes already use explicit rebuild/teardown paths. It also makes widget ownership less obvious.

### C. Generalize panel bounds and titles globally

Move bounded sizing and title truncation into shared dialog or float-panel utilities so every panel gets similar behavior.

This may be useful later, but it is too broad for the current defects and could alter unrelated panel behavior.

## User Experience

- Switching between light and dark themes keeps graph edges visible. Default edges follow `theme.graph.edge-color`; intentionally colored edges retain their explicit colors.
- Double-click inline expansion and focused Enter panel opening both produce bounded, usable graph node panels. The focused Enter default should match the inline expanded panel's default/min/max sizing policy when no persisted size exists.
- If a user is in graph activity and changes theme, the graph-map sidebar remains present or is immediately rebuilt as part of the same theme transition. There should be no state where graph activity is active but its required sidebar is absent.
- Compact inline panels show a short title using the node label when available and the node key as fallback. Long labels are truncated with an ellipsis in the compact header.

## Architecture

### Theme-responsive default edges

`GraphEdge` should not make theme fallback impossible by stamping every edge with an indistinguishable hardcoded default color. The rendering/layout layer should be able to tell the difference between an explicitly colored edge and an edge using the theme default.

The preferred contract is:

- `edge.color` means an explicit color override.
- missing/nil `edge.color` means use the current graph view theme edge color.
- `GraphView`/layout code resolves the active theme edge color from `ctx.theme.graph.edge-color` with a safe visible fallback.

This keeps theme-specific colors out of persisted graph topology and avoids mutating graph edges during theme changes.

### Bounded focused-Enter panels

The node-view open path used by keyboard activation should provide bounded default placement data when creating a new canvas panel. If existing map-local panel metadata includes a size, restoration should continue to honor that persisted size. Otherwise, the default placement should include the same size/min/max policy used for inline expanded graph cards.

The graph view node-view boundary is the right place to do this because it already adapts graph node activation into target-panel creation and knows whether it is restoring or opening a new view.

### Graph sidebar lifecycle across theme changes

Graph activity owns a left-dock builder for graph-map management. Theme switching may deactivate and reactivate graph activity while suppressing transient activity events. The final state must still notify or refresh the activity dock view after the graph activity's left-dock builder has been restored.

The design invariant is: when graph activity is active, the activity dock can always derive and display the graph-map management sidebar from the active activity's dock builder. If theme transition suppression skips the rebuild signal, the theme/action lifecycle must explicitly trigger the appropriate dock rebuild after reactivation.

This should not be fixed by making the sidebar globally persistent or by hiding errors. Missing required graph sidebar context remains an assertion failure.

### Compact inline titlebar label

Inline expanded card presentation should include a title text element in the header before spacer/action buttons. The title should use `node.label` when present, otherwise `node.key`, and display a truncated value with the existing graph ellipsis helper.

The full untruncated label remains available in node data and search/finder logic; truncation is display-only.

## Error Handling

- Missing required graph view, node-view, or sidebar context should continue to fail loudly through assertions rather than silent no-ops.
- If a theme lacks `graph.edge-color`, rendering should use an explicit visible fallback rather than black.
- Invalid persisted panel metadata should not prevent opening a bounded default panel; existing validation behavior should be preserved where present.

## Testing

Focused tests should cover:

- Default graph edges use the active theme edge color and differ between light/dark theme contexts.
- Explicit per-edge colors override the theme edge color.
- Focused Enter node-view panel creation passes bounded default size metadata matching the inline expanded panel policy when no persisted size exists.
- Restored node-view panels continue to honor persisted panel size metadata.
- Applying a theme while graph activity is active leaves the graph-map sidebar builder/dock present after the transition.
- Compact inline expanded cards include a truncated node label in the header, with node key fallback.

Validation should use project-native Fennel checks: touched-file `tools.fennel-check` or `make fennel-check`, `make constraints`, focused graph view/node-view/sidebar/main-event tests, and broader validation if activity/theme lifecycle changes affect shared shell behavior.

## Risks and Mitigations

- **Theme regression for explicitly colored edges:** Add tests for explicit color override and only use theme fallback when `edge.color` is nil/missing.
- **Over-broad panel sizing changes:** Apply bounded defaults in the graph node-view open path rather than globally in float panels.
- **Dock lifecycle masking a deeper design bug:** Test the invariant after theme application instead of only testing that no crash occurs. The fix should restore the activity dock rebuild path, not merely recreate a sidebar ad hoc.
- **Approximate compact title truncation:** Reuse existing character-count ellipsis logic and keep pixel-perfect truncation out of scope.
