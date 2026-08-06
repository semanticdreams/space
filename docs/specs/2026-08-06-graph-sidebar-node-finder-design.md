# Graph Sidebar Node Finder Design

## Context

Graph maps can contain nodes whose visual positions are outside the current view. When the map is sparse, or after removing visible nodes, it is hard to tell whether nodes still exist elsewhere in the graph view. The `start` node is also not automatically restored after a user removes it from an active map, which makes recovery unclear.

Current graph map doctrine remains in force: `GraphMap` owns map-local graph membership and interaction context over graph-addressable objects, while `GraphView` owns visual state such as layout, focus, selection, camera positioning, labels, and opened panels. Removing nodes from a map remains non-destructive.

## Goals

- Add a node finder/search to the graph map sidebar so users can discover nodes in the active map even when they are out of view.
- Let users single-click a finder result to select, focus, and center that node in the active graph view.
- Let users double-click a finder result to open the node panel/view after the same reveal behavior.
- Add an always-visible standalone `Add Start` button near the graph map selection UI.
- Keep `Add Start` independent from the finder; if `start` exists, it appears in the finder like any other node.
- Make `Add Start` idempotent: clicking it should add `start` if missing and reuse the existing map node if present.

## Non-Goals

- No destructive deletion changes.
- No automatic re-seeding of `start` after every removal.
- No special missing-`start` finder row or warning state.
- No zoom-to-fit, animated camera movement, minimap, or graph overview in this change.
- No arbitrary key autocomplete beyond nodes already present in the active map.
- No graph persistence format changes.

## Approaches Considered

### A. Minimal sidebar node list

Add a static list of active-map nodes and an `Add Start` button. This is simple, but it does not scale once maps contain enough nodes to make scanning difficult. It also does not reuse existing search/list widgets.

### B. Separate graph control panel

Put node search and recovery actions into the existing graph control launchable. This keeps the sidebar smaller, but it hides the recovery affordance away from graph map selection, which is where users are already looking when they are unsure what the active map contains.

### C. Sidebar-integrated finder with GraphView callbacks

Add a compact `Find Node` section to `GraphMapSidebar`, backed by active `GraphMap` membership, and route reveal/open actions through callback functions supplied by the graph activity. Add `Add Start` as a standalone sidebar action. This matches the requested placement, preserves graph/view boundaries, and keeps the user flow visible.

Chosen approach: **C**.

## User Experience

The graph map sidebar gains a compact map utility area below the map rows and near the existing selected count:

- `Add Start` button is always visible.
- `Find Node` label introduces a searchable list of nodes in the active map.
- Finder entries display the node label when available, otherwise the node key.
- Finder results are derived only from nodes currently present in the active `GraphMap`.
- Single-clicking a result selects that node, gives it focus, and centers the camera on its visual bounds while preserving current zoom/depth.
- Double-clicking a result opens the node panel/view. Existing click routing may emit the single-click reveal before the double-click open; that ordering is acceptable and should be documented in tests or developer notes.
- Switching maps rebuilds the finder for the newly active map.

`Add Start` calls the active map's `load-by-key` for `"start"`. If the node is absent, the key loader creates it; if the node already exists, `GraphMap:load-by-key` returns the existing node and no duplicate is added. The button does not select, center, or open `start` by itself; its behavior is limited to idempotent membership recovery.

## Architecture

### Sidebar responsibilities

`assets/lua/graph/map-sidebar.fnl` remains responsible for graph map sidebar composition. It should:

- Render the standalone `Add Start` button.
- Collect and sort active-map node entries from `active-map.nodes`.
- Build the finder using existing UI primitives, preferably `SearchView` plus custom row buttons.
- Rebuild finder contents on active-map node add/remove/replace signals and map switches.
- Receive optional `node-reveal-handler` and `node-open-handler` callbacks from its options.
- Avoid direct references to `app.graph-view`.

### Activity responsibilities

`assets/lua/graph-activity-unit.fnl` owns wiring between the sidebar and the active graph view. Its left-dock builder should pass callbacks that find the active `GraphView` and call public reveal/open methods. This keeps global runtime access at the activity boundary instead of embedding it in the sidebar widget.

### GraphView responsibilities

`assets/lua/graph/view/init.fnl` should expose public methods for sidebar-driven behavior:

- `reveal-node(node-or-key, opts)` resolves an existing active-map node, selects it, requests focus, and centers the camera on its visual bounds.
- `open-node(node-or-key, opts)` performs reveal behavior and opens the node view/panel.

GraphView should not create or load graph map nodes as part of reveal/open. It should assert clearly if asked to reveal a node that is not present in the active view, because silent no-ops would make the original UX problem harder to diagnose.

## Data Flow

1. Sidebar rebuild asks the manager for the active map.
2. Sidebar derives finder rows from `active-map.nodes`.
3. User clicks `Add Start`.
4. Sidebar calls `active-map:load-by-key "start"` and asserts that a node is returned.
5. User single-clicks a finder row.
6. Sidebar invokes `node-reveal-handler(node, event)`.
7. Graph activity routes the callback to `graph-view:reveal-node`.
8. User double-clicks a finder row.
9. Sidebar invokes `node-open-handler(node, event)`.
10. Graph activity routes the callback to `graph-view:open-node`.

## Error Handling

- Missing active map when invoking `Add Start` is an assertion failure.
- Missing or failed `start` key loader is an assertion failure that names the `start` load failure.
- Missing active graph view for reveal/open is an assertion failure in the activity callback.
- Missing node in the active GraphView is an assertion failure in GraphView reveal/open methods.
- The implementation must avoid silent fallbacks for missing context.

## Testing

Focused Fennel tests should cover:

- `Add Start` is visible in the graph map sidebar.
- Clicking `Add Start` adds `start` when absent.
- Clicking `Add Start` again does not duplicate `start`.
- Finder lists active-map nodes by label/key.
- Finder contents rebuild after node add/remove and map switch.
- Finder single-click invokes the reveal path for the selected node.
- Finder double-click invokes the open path for the selected node.
- GraphView reveal selects, focuses, and centers an existing node.
- GraphView open reveals and opens the node view.

Validation should use project-native Fennel checks and focused graph/sidebar tests, with broader graph fast tests when implementation touches shared GraphView APIs.

## Risks and Mitigations

- **Double-click ordering:** Existing button routing may emit single-click before double-click. Accept and test this as reveal-then-open behavior.
- **Boundary leakage:** Avoid `app.graph-view` inside the sidebar; keep runtime routing in `graph-activity-unit.fnl`.
- **Camera assumptions:** Centering should preserve current zoom/depth and use the best available visual bounds instead of resetting the whole view.
- **Large maps:** Start with the existing `SearchView`; defer virtualization or pagination refinements unless tests reveal unacceptable behavior.
