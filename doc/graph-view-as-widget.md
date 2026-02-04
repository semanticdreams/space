# GraphView as a Layout Widget (Feasibility + Implementation Plan)

## Summary

Goal: refactor `GraphView` so it can be composed like a normal widget (i.e., it has a `layout` node and can be placed in other layouts such as `Flex`/`Stack`), while preserving its current rendering (points + edges + labels) and interactions.

Key requirements:
- `GraphView` must expose a `layout` node so parent widgets can size/position it.
- ForceLayout bounds must be derived from the size assigned by the parent (not hard-coded).
- Node positions must be relative to the widget’s layout node (position + rotation), not global coordinates.
- The “main” graph view should be wrapped in a dialog widget (so the dialog is draggable/resizable like other panels).
- Interaction change:
  - **Alt + Left Drag** moves the *dialog/panel* (unchanged vs other dialogs).
  - **Left Drag (no Alt)** moves individual graph nodes (points) inside the graph.

This is feasible, but it touches several subsystems at once: coordinate spaces, persistence, and input routing.

## Current State (what exists today)

From `assets/lua/graph/view/init.fnl` and related modules (see `doc/graph.md`):
- `GraphView` is an object (not a widget) that owns:
  - `ForceLayout` (`layout`)
  - `LayeredPoint` instances for nodes (via `ctx.points`)
  - edge rendering (triangle line batches)
  - labels (`graph/view/labels`)
  - selection + focus management
  - drag targets via `GraphViewMovables` registering with `app.movables`
  - persistence (`graph/view/persistence`)
- ForceLayout bounds are currently set explicitly during graph view construction, not based on any widget size.
- Node positions are treated as world coordinates; the graph has no layout node that would let a parent place/rotate it.
- Dragging points currently uses `app.movables`, which is only engaged by `state-base` when **Alt** is held.
- Dialog/panel movement is also powered by `app.movables` (Alt + Left) via HUD/Scene panel wrappers.

Implication: today we can’t reliably embed multiple graph views into independent “rectangles” because there’s no per-instance transform/bounds derived from a parent layout region.

## Proposed Design

### 1) Single `GraphView` widget + `GraphViewDialog` wrapper

No split between “core” and “widget shell”.

- **`GraphView`** becomes a normal widget module (still the canonical owner of view-only concerns):
  - exposes a `layout` node (`Layout` from `layout.fnl`)
  - owns ForceLayout, points, labels, selection, node dialogs, and persistence
  - derives ForceLayout bounds from the size assigned by the parent
  - maintains a graph-local coordinate system with origin at **bottom-left** (like other widgets)
- **`GraphViewDialog`** is just composition:
  - wraps `GraphView` in `DefaultDialog` (so the whole graph can be floated, moved, and resized)

This keeps a single “GraphView” concept for callers while enabling layout composition via `GraphView.layout`.

Naming note:
- Today `GraphView.layout` is the ForceLayout instance. As part of this refactor, reserve `GraphView.layout` for the widget layout node.
- Rename the ForceLayout field to `GraphView.force-layout` (or similar) to avoid confusion and to match other widget conventions.

### 2) Define two coordinate spaces and make them explicit

Define:
- **Graph-local space**: ForceLayout positions live here. Origin is the widget’s bottom-left corner.
- **World space**: `LayeredPoint.position`, edge endpoints, and label placement live here (renderers + intersection operate on world space today).

Mapping should use the widget layout node’s transform:
- Let `Lpos = graph_view.layout.position`
- Let `Lrot = graph_view.layout.rotation`
- For a local point `p_local`:
  - `p_world = Lpos + Lrot:rotate(p_local)`
- Inverse mapping used for persistence and dragging:
  - `p_local = (Lrot:inverse):rotate(p_world - Lpos)`

Important: keep the mapping centralized (one helper module) to avoid subtly inconsistent transforms across edges/labels/persistence.

Suggested helper:
- `assets/lua/graph/view/transform.fnl`
  - `local->world(layout, vec3)`
  - `world->local(layout, vec3)`

### 3) Bounds derived from widget size

ForceLayout bounds should be set from the widget’s assigned size (in its local space).

For a widget rectangle that starts at local origin and extends positive:
- `bounds_min_local = (0, 0, 0)`
- `bounds_max_local = (layout.size.x, layout.size.y, 0)`

Then:
- `graph_view.force-layout:set-bounds(bounds_min_local, bounds_max_local)`
- Leave `auto-center-within-bounds` enabled so center is computed as `(size.x/2, size.y/2)` automatically.

When `layout.size` changes:
- Update bounds.
- Do **not** automatically restart the force layout (resizing should not trigger a re-run).

### 4) Rendering changes (minimal)

Keep the current render pipeline:
- Points: still `LayeredPoint` via `ctx.points`, stored in world space.
- Edges: still triangle lines (`graph-edge-batch` / `graph/view/edge`), using world endpoints.
- Labels: still `Text` spans placed in world space.

Main change:
- Whenever ForceLayout produces a position (`p_local`), write the corresponding world position to the point:
  - `point:set-position(p_world)`

This implies updating:
- `graph/view/layout.fnl` refresh logic to apply the transform before calling `set-point-position`.
- Any code path that “sets node position” (dragging, persistence, explicit node opts) must set ForceLayout in local space and then refresh the point world position.

### 5) Persistence stores shared, graph-local positions

Persistence remains shared (single store) and keyed only by node key, but positions stored on disk are **graph-local** positions.

- Path stays as-is (`graph/view/persistence.fnl` currently uses a shared `graph-view/metadata.json`).
- Store local positions `[x y z]` where origin is the widget’s bottom-left.
- It is acceptable for saved positions to “fluctuate” when multiple graph views with overlapping node keys are open simultaneously.
- No migration logic is required.

### 6) Input / drag behavior changes

#### Requirement
- Alt + Left drag should move the dialog/panel (existing behavior).
- Left drag (no Alt) should move nodes within the graph.

#### Constraints in current input pipeline
- `state-base` only forwards to `app.movables` on Alt + Left.
- `GraphViewMovables` registers each point with `app.movables` today.

#### GraphView-local drag controller (preferred)

Do not use `app.movables` for point dragging.

Plan:
- Keep dialog/panel dragging as-is: Alt + Left engages `app.movables` and moves the dialog wrapper (existing HUD/Scene behavior).
- Implement point dragging inside `GraphView` itself with its own drag state + hit testing.

Efficiency requirement (“only hit-test points if GraphView was hit”):
- First hit-test the `GraphView.layout` bounds (cheap AABB/OBB ray-box intersection via `Layout:intersect`).
- Only if that hits, do a second-stage hit-test against the graph’s point handles to choose a node to drag.

Routing strategy (minimal global changes, GraphView-owned logic):
- Add a small global router that only knows how to delegate to registered graph views, e.g.:
  - `app.graph_view_router` (new module, created once during bootstrap)
  - API: `register(view)`, `unregister(view)`, `on-mouse-button-down`, `on-mouse-motion`, `on-mouse-button-up`, `drag-active?`
- Modify `state-base` to consult this router for **left button** events when Alt is *not* held:
  - On mouse down: router may “arm” a potential drag, but do not consume the event (keep clickables/double-click behavior as-is).
  - On mouse motion/up: forward to router when it has an active drag.

Drag start threshold + clicks:
- Implement a drag threshold (same concept as `Movables`: don’t start dragging until pointer moved far enough).
- Do not add special “click suppression” logic; keep click/double-click behavior as-is (i.e., whatever `Clickables` does based on its pointer threshold).

Dragging constraints:
- Dragged positions must be clamped to widget bounds in **local** space so the user cannot drag points outside:
  - clamp local x to `[0, layout.size.x]`
  - clamp local y to `[0, layout.size.y]`
  - z remains 0 (or preserved if needed)
- After updating the ForceLayout local position, update the rendered world position via the layout transform.
- Dragging a point must **not** trigger a force-layout run/restart (`ForceLayout:start`); it only updates the dragged node’s position.

Suggested code reuse:
- Extract the ray-plane intersection helpers from `assets/lua/movables.fnl` into a small math module (no dependency on `Movables`), so GraphView can compute drag world positions without duplicating geometry code.

### 7) Dialog wrapping

Once `GraphView` is a widget, define:
- `GraphViewDialog` = `DefaultDialog` whose `:child` is `GraphView`.
- This makes it trivially movable/resizable via existing HUD/Scene panel wrappers.

`GraphViewControlView` should continue to target a specific graph view instance via `:graph-view` (already supported), not rely on `app.graph-view` if multiple instances exist.

## Detailed Implementation Plan

### Phase 1 — Make `GraphView` a widget (layout node + transforms)
1. Update `assets/lua/graph/view/init.fnl` so the returned object includes a real `layout` (`Layout` from `layout.fnl`) owned by the graph view, and rename the ForceLayout field from `layout` to `force-layout`.
2. Add `assets/lua/graph/view/transform.fnl` with local↔world helpers based on `GraphView.layout.position/rotation`.
3. Change all node positioning flows to treat ForceLayout positions as **local**:
   - When `GraphView.force-layout` updates a node to `p_local`, write `point.position = local->world(layout, p_local)`.
   - When code asks for a node’s position for persistence or APIs, return local unless explicitly requesting world.
4. Ensure `GraphView.drop` drops all owned render objects and disconnects signals (same as today, but now includes `layout:drop`).

Exit criteria:
- Existing graph tests pass.
- GraphView can be embedded in a parent layout tree (it has a `layout` node).

### Phase 2 — Bounds derived from size (no auto re-run)
1. Remove hard-coded `ForceLayout:set-bounds` defaults from graph view initialization.
2. In `GraphView.layout` layouter (or in the widget’s update path):
   - set `GraphView.force-layout` bounds to `[0,0] -> [layout.size.x, layout.size.y]` in local space
   - do not call `ForceLayout:start` on resize
3. Clamp node drag updates (see Phase 4) to the same bounds so user cannot move points outside.

Exit criteria:
- ForceLayout bounds track parent-assigned size.
- Resizing the widget does not restart the layout.

### Phase 3 — `GraphViewDialog` wrapper
1. Add `assets/lua/graph-view-dialog.fnl` composing:
   - `DefaultDialog` with `:child` set to `GraphView`.
2. Update existing “open graph” entry points (HUD control panel) to create a dialog wrapper instead of a global singleton view.
3. Ensure `GraphViewControlView` can target a specific graph view instance (accept `:graph-view`), but keep `app.graph-view` wired to the “main” GraphView for minimal disruption.

Exit criteria:
- GraphView can be used both as a widget and as a dialog (canonical UX stays dialog).
- Existing user workflows remain stable (see “Minimal disruption” below).

### Phase 4 — GraphView-owned point dragging (no `app.movables`)
1. Implement per-GraphView drag state:
   - `drag = {node, start_pointer, started?, start_local, plane, ...}`
   - drag threshold before “started?”
2. Add a small router (global delegator) that only forwards events to graph views:
   - register/unregister graph views (likely on build/drop)
   - on left mouse down (no Alt): choose topmost GraphView under pointer using `GraphView.layout:intersect`
   - only then perform point hit-test inside that GraphView to select a node
3. While dragging:
   - compute new world hit point (ray-plane intersection)
   - convert to local via `world->local(layout, p_world)`
   - clamp to `[0..size]` and write into ForceLayout
   - update point world position
   - do not call `ForceLayout:start` as part of dragging
4. Do not add special click suppression; keep click/double-click independent.

Exit criteria:
- No-Alt dragging moves points, clamped inside bounds.
- Alt dragging still moves the dialog (existing `app.movables` behavior).
- Point dragging only hit-tests points after GraphView bounds is hit.

### Phase 5 — Persistence stores shared local positions
1. Update `assets/lua/graph/view/persistence.fnl` to store **local** positions (shared store, keyed by node key).
2. Update load/save boundaries:
   - load: local → world when instantiating points
   - save: world → local when capturing positions
3. Do not add migration logic; accept that values may fluctuate across multiple views.

Exit criteria:
- Local positions persist and re-load correctly for a single view.
- Multiple concurrent views are allowed to “fight” over saved positions.

## Testing Strategy

Minimum:
- `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`

Add/extend unit tests:
- Transform roundtrip correctness.
- Bounds update behavior when parent resizes widget.
- Drag behavior with/without Alt (no special click suppression).
- Shared local-space persistence (local saved positions).

Optional but recommended:
- Add an E2E snapshot under `assets/lua/tests/e2e/` that places two `GraphView` instances side-by-side in a `Flex` row with different sizes to visually confirm separation.

## Minimal Disruption / Compatibility Checklist

The goal is that introducing `GraphViewDialog` does not “break the app” or change how users interact with graph views beyond the intentional changes (being inside a dialog + point dragging without Alt).

Treat these as “must keep working” features, and add covering tests where practical:

- **Graph lifecycle**: GraphView still attaches to a graph, listens to add/remove/replace edge/node signals, and cleans up correctly on `drop`.
- **Rendering**: edges still emit triangles; points still update positions; labels still update and reposition.
- **Selection + focus**: clicking points still focuses; selection borders/focus borders remain correct (existing tests should continue to cover this).
- **Node views**: double click still opens node views; Alt+double-click expansion still works.
- **Graph control panel**: `GraphViewControlView` continues to operate (continuous mode, start/stop, center_force Apply) against the active GraphView instance.
  - To minimize disruption, keep `app.graph-view` pointing at the “main” GraphView instance created by `GraphViewDialog` so legacy call sites and defaults keep working.
  - `GraphViewControlView` should still accept an explicit `:graph-view` for future multi-graph layouts.
- **Dialog behavior**: Alt+left dragging the dialog continues to work via existing HUD/Scene panel movables.
- **Resizing**: resizing the dialog/widget updates ForceLayout bounds but does not restart force layout; points remain clamped within bounds.

Suggested covering tests to add (if missing):
- `tests.test-graph-view-dialog`: builds `GraphViewDialog`, verifies it yields a widget with a `layout` node and an internal GraphView reference, and that `drop` releases resources.
- Extend `tests.test-graph-view-control-view`: ensure it works when given a graph-view instance coming from `GraphViewDialog` (not only a mock).
- Extend `tests.test-graph-view`: verify that changing the GraphView layout transform offsets/rotates rendered world positions consistently (a small transform test around a known local position).

## Risks / Gotchas

- **Click vs drag thresholds**: without explicit suppression, small drags can still register as clicks (and large drags may not count as clicks), depending on `Clickables` thresholds.
- **Persistence semantics**: switching to local-space in a shared store means layouts can “jump” when multiple views with overlapping keys are open; this is accepted by design.
- **Label ownership/clipping**: labels are not children of the widget layout; they may render “outside” during transitions. ForceLayout bounds + drag clamping should keep them inside, and explicit clipping isn’t required.
- **Rotation pivot**: layout rotation rotates around `layout.position` (local origin). If “rotate around center” becomes required, the transform helper must incorporate a pivot `(size * 0.5)`.
- **Multi-instance globals**: anything relying on `app.graph-view` must be audited to avoid singleton assumptions.

## Decisions / Constraints

- Local coordinate origin is bottom-left (local bounds `[0..size]`).
- Resizing updates bounds but does not trigger `ForceLayout:start`.
- No explicit clipping required; ForceLayout bounds + drag clamping keep points within the widget.
