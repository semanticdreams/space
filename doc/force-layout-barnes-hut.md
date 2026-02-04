# Force layout Barnes-Hut status

## Current state
- Barnes-Hut is already used for repulsive forces in `src/force_layout.cpp` during `ForceLayout::step`.
- The quadtree implementation lives in `src/force_layout_quad_tree.hpp` and is built every iteration from the current XY positions.
- The algorithm is 2D-only (uses `glm::dvec2` from each node's X/Y position); Z is ignored.
- The Barnes-Hut opening angle (`theta`) is currently hardcoded to `0.5` when calling `computeRepulsion`.

## If we revisit this later
- Decide whether the force layout should be 2D-only or full 3D. For 3D, replace the quadtree with an octree and update the Barnes-Hut traversal to use `glm::dvec3` positions.
- If we need configurable accuracy, plumb a `theta` parameter through `ForceLayout` and the Lua binding so it can be tuned from Fennel/Lua.
- Add a small regression/perf test for the repulsive-force step to avoid accidental removal of Barnes-Hut or unbounded O(n^2) regressions.
