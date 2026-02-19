# Scroll Profiling: Large Input List Drag

## Scenario
- 100 multiline inputs, each with 100 lines of random text.
- Scroll from top to bottom over 120 frames (slow drag).
- Creation/layout done once before profiling; profiler captures scrolling only.
- Renderer uploads (GL bufferData) are not executed; CPU-side VectorBuffer writes are included.

## Profiler Output Summary
Top stacks (abridged):
- `assets/lua/layout.fnl:update:457` (LayoutRoot update loop)
- `assets/lua/bucket-queue.fnl:iterate:35` (layout queue walk)
- `assets/lua/list-view.fnl:114` (ListView layouter: per-child positioning)
- `assets/lua/layout.fnl:layouter:241` (layout traversal)
- `assets/lua/input.fnl:383` (Input layouter)
- `assets/lua/text.fnl:55` (Text glyph layout + VectorBuffer writes)

Interpretation: scrolling dirties layout, which re-lays out the list and each input widget every frame. The heaviest cost comes from ListView iterating all children and Input/Text layouters updating geometry.

## Current Glyph Optimization (post-profile)
- `assets/lua/text.fnl` now caches glyph metadata and avoids per-glyph table allocations during layout.
- This reduces CPU overhead when text content is unchanged, but it does not remove the per-vertex position writes that happen on every layout pass.
- Advances are computed per layout from the current `TextStyle.scale` (scale is not part of the cache). This keeps label LOD scaling correct today; if/when we move to a transform-only pass, we may want a scale-aware cache key.

## Recent Profiler Runs
### Baseline (pre-glyph-cache)
- Total samples: ~601M
- `text.fnl` layouter: ~3.4%
- `input.fnl` layouter: ~5.2%

### After glyph cache + allocation-free vertex emission
- Total samples: ~484M
- `text.fnl` layouter: ~2.8%
- `input.fnl` layouter: ~4.6%

### After scale-safe cache fix (current)
- Total samples: ~449M
- `text.fnl` layouter: ~2.8%
- `input.fnl` layouter: ~4.6%

## Key Hotspots
### 1) LayoutRoot pass cost
- Location: `assets/lua/layout.fnl:update:457`
- Cause: every scroll tick enqueues layout work across a large subtree.
- Effect: repeated per-frame layout of all list items.

### 2) ListView layout of every child
- Location: `assets/lua/list-view.fnl:114` (layout-children loop)
- Cause: scroll offset marks layout-dirty at scroll container, then ListView layouter recomputes position/size for all items.
- Effect: O(N) layout work for N = 100, even though only a small visible subset changes.

### 3) Input layout and text geometry
- Locations:
  - `assets/lua/input.fnl:383` (Input layouter)
  - `assets/lua/text.fnl:55` (Text layouter)
- Cause: Input layouter drives child layouts and Text layouter rewrites glyph quads to VectorBuffers.
- Effect: expensive per-item CPU work that repeats on every scroll tick.

### 4) Layout bookkeeping overhead
- Locations:
  - `assets/lua/layout.fnl:116` (clip/visibility bookkeeping)
  - `assets/lua/layout.fnl:layouter:241` (tree traversal)
- Cause: clip visibility checks and traversal across a large subtree on each scroll.

## Suggested Optimizations
### A) Split layout vs. transform/cull passes (unified for scroll + drag)
Goal: keep culling correct while avoiding full layout and glyph rebuilds on movement.
- Approach:
  - Layout pass computes local sizes/positions only when content/size changes.
  - Transform/cull pass composes parent transforms, updates world bounds, and recomputes clip visibility.
  - Scroll and Movables update only parent transforms and trigger transform/cull pass.
- Expected impact:
  - Scroll/drag becomes O(N) *cheap* (transform + bounds), instead of O(N) *expensive* (full layout + glyph rebuilds).
  - Culling stays correct because clip visibility is recomputed.
Implementation notes:
- Add a `transform-dirty` queue in `LayoutRoot`.
- Store `local-position/rotation/size` separate from `world` values.
- Renderers consume world transforms via a per-batch uniform or a lightweight matrix stack.

### B) Virtualize list items
Goal: reduce list size that participates in layout and text updates.
- Approach: keep widgets only for visible rows + small overscan buffer.
- Implementation idea:
  - `VirtualListView` that reuses widget instances as scroll index changes.
  - Adjust content height without instantiating off-screen inputs.
- Expected impact: reduces layout + text costs by visible count, not total count.

### C) Skip Input/Text work on pure scroll
Goal: avoid per-frame glyph rebuild when content and viewport are unchanged.
- Approach:
  - In `Input` layouter, only run `apply-viewport` and `refresh-virtual-text` when viewport size or model content changes.
  - In `Text` layouter, reuse existing geometry and update transform/clip only; avoid rewrites of all glyph vertices.
- Expected impact: reduces VectorBuffer writes and layout work per item.

### D) Cache measure results
Goal: avoid running measurers when sizes are stable.
- Approach:
  - Cache child measurements in ListView; only re-measure on text/model change.
- Expected impact: reduces measure-dirt propagation and downstream layout.

### E) Aggressive culling for off-screen children
Goal: early-out of layout work for items outside clip.
- Approach:
  - Ensure ScrollArea clip visibility is evaluated before children; set `parent-culled?` so child layouters can early return.
- Expected impact: lower layout time for large off-screen sets.

## Notes on Measurer During Scroll
The scroll path (`ScrollView:set-scroll-offset -> ScrollArea:set-scroll-offset`) marks layout-dirty only. Measurers run during scroll only if:
- viewport/scrollbar visibility changes and marks measure-dirty, or
- content changes (e.g., text updates) mark measure-dirty.

## Next Experiments
- Re-run profiler after (A) to confirm ListView layout cost drops.
- Add a run including renderer uploads to quantify GL bufferData costs if needed.
