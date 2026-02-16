# Graph Layout Profiling Plan

Goal: reduce graph node movement cost during force layout and drag by avoiding unnecessary label work and coalescing point updates.

Scope
- Graph view layout/update: `assets/lua/graph/view/init.fnl`, `assets/lua/graph/view/layout.fnl`
- Labels: `assets/lua/graph/view/labels.fnl`
- Layered points: `assets/lua/layered-point.fnl`, `assets/lua/points.fnl`
- Movables glue: `assets/lua/graph/view/movables.fnl`

Plan
1) Stop rebuilding labels every tick during drag.
   - Add drag start/end hooks from `GraphViewMovables` to `GraphView`.
   - During drag, skip label updates and refreshes; on drag end, refresh labels once for moved nodes.

2) Coalesce point updates for layered points.
   - Update `LayeredPoint.set-position-values` to avoid `glm.vec3` allocation and call per-layer `set-position-values` directly.
   - Add a fast path to `LayeredPoint.set-position`/`apply-position` to reuse the new per-component update.
   - Ensure `GraphView.set-point-position` uses the per-component path to reduce Lua->C++ overhead.

3) Keep force-layout behavior unchanged.
   - Do not reduce update frequency or iteration count.

Validation
- Re-run `make prof target=graph-layout args="--skip-images"` and compare flamegraph hotspots.
- Spot-check drag updates for label correctness (labels snap to new position after drag end).
