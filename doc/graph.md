# Graph Core Refactors

Now that `assets/lua/graph/core.fnl` is a pure model, `assets/lua/graph/view.fnl` owns all visual + interactive systems while keeping node views pluggable via signals.

## Extracted
- Graph model: `graph/core` owns nodes/edges, add/remove/replace, and emits signals (`node-added`, `node-removed`, `node-replaced`, `edge-added`, `edge-removed`).
- Graph view: `graph/view` (`GraphView`) owns ForceLayout, points, labels, selection, movables, persistence, and node dialogs. It listens to graph signals and can be dropped/recreated without touching the graph model.
- Persistence: `graph/view/persistence` handles metadata load/save and scheduled writes.
- Labels and LOD: `graph/view/labels` (`GraphViewLabels`) manages label creation, LOD switching, camera-distance debounce, positioning, and cleanup.
- Selection: `graph/view/selection` (`GraphViewSelection`) owns selector wiring, selected-node bookkeeping, pruning, and signals.
- Node view wiring: `graph/view/node-views` (`GraphViewNodeViews`) builds/drops node dialogs or HUD embeds.
- Movables: `graph/view/movables` (`GraphViewMovables`) builds drag targets, registers/unregisters with `app.movables`, forwards position updates, and schedules persistence on drag end.
- Layout and edges: `graph/view/layout` (`GraphViewLayout`) wraps `ForceLayout`, line updates, node positioning, and rebuilds.
- View registry: `graph/view/registry` (`GraphViewRegistry`) centralizes view-only bookkeeping (indices, node/point maps, edge map), replacement, and deduping.
- Utils split: `graph/core/utils` holds core-only helpers (glm vec coercion). `graph/view/utils` adds view helpers (label text truncation/wrapping) and re-exports the core glm helpers.

## Label and LOD handling
- Core now forwards node→point maps to `graph/view/labels` to build spans and reposition them based on camera distance; tune LOD thresholds and label styling there instead of in core.
- Benefits: keeps HUD text concerns and camera logic out of core; makes it easier to tune LOD thresholds separately.

## Selection and node views
- Selection is owned by `graph/view` + `graph/view/selection`; update behavior there when changing selector policies or selection logging.
- Node dialogs are handled by `graph/view/node-views`; tweak dialog builders or HUD embedding there without touching the graph model.
- Graph nodes **do not track view instances**. Nodes expose a plain `:view` constructor (e.g. `:view HackerNewsStoryView`) and emit state via signals (`rows-changed`, `items-changed`, `targets-changed`, etc.). Views subscribe to those signals (or call node methods like `fetch`, `open-entry`, `add-target`) and stay UI-only so multiple views can hang off the same node.

## What stays in core
- Graph model: adding/removing/replacing nodes/edges, triggering nodes, and lifecycle (`drop`).
- No visual state: layout, labels, selection, movables, points, or persistence belong in `graph/view`.
