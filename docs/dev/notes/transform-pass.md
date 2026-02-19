# Transform/Cull Pass Plan

## Goals
- Make scroll/drag movement cheap by avoiding full layout work on every frame.
- Preserve correct clipping/culling when only transforms change.
- Keep existing widget composition semantics intact.
- Prepare renderers for future local‑space geometry + world transforms.

## Non‑Goals (for the first phase)
- No change to public widget APIs.
- No rework of text/rectangle/image renderers yet.
- No batching or uniform‑driven transforms in phase 1.

## Current Layout Pipeline (summary)
- `LayoutRoot:update` runs:
  - Measure pass (recomputes sizes)
  - Layout pass (writes world positions/rotations, clip visibility)
- Scroll/move currently marks layout‑dirty, forcing full layout.

## Proposed Pipeline
1) **Measure Pass** (unchanged)
   - Computes `layout.measure` for local sizes.
2) **Layout Pass** (local only)
   - Computes local sizes/offsets and stores them in new fields.
   - Avoids writing world position/rotation.
3) **Transform/Cull Pass** (new)
   - Walks tree in depth-first order (parent before children).
   - Composes world transforms: `world = parent.world × local`.
   - Calls `update-clip-region` to recompute `clip.bounds` from new world positions.
   - Updates `clip-visibility` via `compute-clip-visibility`.
   - Applies `parent-culled?` propagation.

## Data Model Changes
- Add `layout.local-position`, `layout.local-rotation`.
  - Initial values: `local-position = vec3(0)`, `local-rotation = quat(1,0,0,0)`.
- Keep `layout.size` as the single size field (no `local-size`; see Design Decisions).
- Keep existing `layout.position`, `layout.rotation`, `layout.size` as **world** values (size is both local and world).
- Add `layout.transform-dirty` flag + `transform-dirt` queue in `LayoutRoot`.

## Dirt Rules
- `mark-measure-dirty`: unchanged; still triggers layout + transform for subtree.
- `mark-layout-dirty`: triggers layout + transform for subtree.
- `mark-transform-dirty` (new): skips measure/layout, runs transform/cull only.

## Phase 1: Transform/Cull Pass Scaffolding

### 1.1 LayoutRoot
- Add `transform-dirt` queue (same bucket-queue structure as existing queues).
- Add `transform-timer` and stats counters.
- Update `update`:
  - Run measure pass (existing).
  - Run layout pass (existing).
  - Run transform pass on `transform-dirt` queue.
  - Ensure measure/layout enqueue transform for affected roots.

### 1.2 Layout
- Add `local-position`, `local-rotation` fields.
- Add `run-transformer` method (mirrors `run-measurer`/`run-layouter` pattern):
  ```fennel
  (fn run-transformer [self skip-dirt-clear?]
    (local root self.root)
    (when (and root root.transform-dirt (not skip-dirt-clear?))
      (root.transform-dirt:remove self))
    ;; Compose world from parent + local
    (local parent self.parent)
    (if parent
        (do
          (set self.position (+ parent.position (parent.rotation:rotate self.local-position)))
          (set self.rotation (* parent.rotation self.local-rotation)))
        (do
          (set self.position self.local-position)
          (set self.rotation self.local-rotation)))
    ;; Update clip bounds and visibility
    (when self.update-clip-region
      (self:update-clip-region))
    (local own-visibility (self:compute-clip-visibility))
    (local effective-visibility (if self.parent-culled? :culled own-visibility))
    (set self.clip-visibility effective-visibility)
    (if (= own-visibility :outside)
        (self:set-self-culled true)
        (self:set-self-culled false))
    ;; Recurse children
    (when self.children
      (each [_ child (ipairs self.children)]
        (child:run-transformer true))))
  ```
- Update setters:
  - `set-local-position` (new): marks `transform-dirty` only.
  - `set-local-rotation` (new): marks `transform-dirty` only.
  - `set-position` / `set-rotation`: continue to mark `layout-dirty` (world position changes imply layout invalidation).
- Update `run-layouter` to write `local-*` fields instead of world values directly.
  - **Note**: until Phase 4, leaf widgets that bake world-space vertex data must either:
    - continue to run their layouters after transform changes, or
    - opt out of transform composition with an `absolute?` flag.

### 1.3 Clip Region Handling
- `update-clip-region` in `scroll-area.fnl` currently reads `layout.position/rotation/size`.
- After transform pass refactor, these remain world values—no change needed to `update-clip-region` itself.
- **Key insight**: `update-clip-region` must be callable from the transform pass, not just from `run-layouter`. Add an optional `layout.update-clip-region` method that `ScrollArea` sets (e.g., `layout.update-clip-region = update-clip-region`), which `run-transformer` will invoke.

### 1.4 Defensive Assertions
- Add assertion in transform pass: if a node being transformed still has `layout-dirty` set, error immediately. This catches ordering bugs where transform runs before layout.
  ```fennel
  (when (and root root.layout-dirt (root.layout-dirt:contains self))
    (error (.. self.name " has stale layout-dirty during transform pass")))
  ```

### 1.5 Rooting/Reparenting
- Update `set-root` to enqueue `transform-dirty` for nodes that were `transform-dirty` before rooting.
- Ensure `remove-child`/`add-child` correctly recomputes transform dirt for subtree roots.

## Phase 2: Convert Container Layouters to Local Space
Update layouters to set:
- `child.local-position` (offset within parent)
- `child.local-rotation` (relative rotation)
- `child.size` (size computed from parent + measure—no `local-size` needed, see Design Decisions)

Target widgets (good candidates):
- `Stack`, `Flex`, `Grid`, `Padding`, `Sized`, `Aligned`, `Positioned`, `ListView`, `ScrollView`, `ScrollArea`, `Container`.

**Migration pattern** (example for `Stack`):
```fennel
;; Before
(set child.position self.position)
(set child.rotation self.rotation)
(set child.size self.size)

;; After
(set child.local-position (glm.vec3 0 0 0))  ; stack children share parent origin
(set child.local-rotation (glm.quat 1 0 0 0))
(set child.size self.size)  ; size stays as single field
```

## Phase 3: Scroll/Drag Wiring

### 3.1 ScrollArea
- `set-scroll-offset` should call `mark-transform-dirty` instead of `mark-layout-dirty`.
- Since scroll offset affects `child.local-position`, this is purely a transform change.

### 3.2 Movables
Current behavior (`movables.fnl` line 224):
```fennel
(drag.entry.target:set-position new-position)
```
This sets **world** position directly. Two options:

**Option A: Keep world position for movables**
- `set-position` continues to mark `layout-dirty`.
- Drag operations don't benefit from transform-only updates.
- Simpler, acceptable if drag doesn't need optimization.

**Option B: Convert movables to local space** (recommended for full optimization)
- Drag target stores offset relative to its parent.
- `set-local-position` marks `transform-dirty` only.
- Requires tracking parent's world position to compute local offset from world hit point.
- More complex, but unlocks cheap drag.

**Recommendation**: Start with Option A. If drag performance is a problem, implement Option B in a follow-up phase.
- **Alternative**: add `layout.absolute?` to skip transform composition for nodes that must stay in world space until movables are migrated.

### 3.3 Clip Visibility
- Ensure `run-transformer` invokes `update-clip-region` for scroll containers.
- Test that scrolling updates `clip-visibility` without triggering `layout-dirty`.

## Phase 4: Renderer Prep (future)
- Allow leaf widgets to emit local‑space geometry once.
- Renderers apply `world` transform via uniform or matrix stack.
- This unlocks "move without touching glyph buffers."

## Validation Steps

### Unit Tests
- Transform pass updates world position without rerunning layouter.
- Clip visibility updates on scroll without layout.
- `mark-transform-dirty` does not enqueue to measure or layout queues.
- Assertion fires if transform pass runs on a node with stale layout-dirty.

### Regression Tests
- Existing layout tests continue to pass.
- ScrollView tests still clamp offsets and update scrollbar.

### Performance Tests
- Scroll a `ScrollArea` for 100 frames; assert `layout-dirt` count is 0 for frames 2–100.
- Capture `layout-delta` timing before/after to measure improvement.
- Compare frame times for drag operations on movables.

## Risks / Open Questions

### Clip Regions
- `update-clip-region` in `scroll-area.fnl` reads world positions. After refactor, world values are populated by transform pass—ensure transform pass runs before any code that reads clip bounds.
- Document which clip-region updates happen in layout pass vs transform pass.

### Leaf Widgets
- Text/Rectangle/Image still write world-space vertex data in their layouters.
- Transform pass won't help them until Phase 4 (renderer prep).
- Acceptable: scroll/drag optimization benefits containers, not leaf geometry.

### Transform Pass Ordering
- Transform pass must run **after** layout pass to avoid stale locals.
- Add defensive assertion (see 1.4) to catch bugs.

### Parent Transform Chain
- When composing `world = parent.world × local`, if parent is culled, children still need world positions for correct clip testing.
- `parent-culled?` propagation is separate from world position composition—both must happen.

## Design Decisions

### No `local-size` field
**Decision**: Skip `local-size`, keep only `size` as a single field.

**Rationale**:
- Size doesn't compose hierarchically like position/rotation. A child's size is computed independently from its measure and parent's available space—it's not `parent.size × local-size`.
- Looking at layouters (`flex.fnl`, `stack.fnl`), they write `child.size` directly based on layout logic, not as an offset from parent.
- Position/rotation compose: `world = parent.world × local`. Size does not: `child.size = layouter_computed_value`.
- Adding `local-size` would create confusion about what it means and when to use it.

### Keep position + rotation, no transform matrix
**Decision**: Keep separate `position` + `rotation` fields (no combined matrix) for Phases 1–3. Consider adding a cached matrix in Phase 4.

**Rationale**:
- Current usage pattern: widgets read `layout.position` and `layout.rotation` separately. A matrix would require changing all call sites.
- Composition cost: `vec3 + quat.rotate(vec3)` is cheap. Full 4x4 matrix multiply adds complexity without significant benefit.
- No scale: the current system doesn't have scale—just position and rotation. A matrix would be overkill.
- Phase 4 option: when renderers start using transforms, compute `world-matrix` lazily on read, caching alongside position/rotation.

### World position via local-space conversion
**Decision**: Widgets that need to set absolute world position should convert to local space on set.

**Rationale**:
- `Positioned` already works this way—it stores an `offset` and composes with parent's world position.
- For movables (drag), compute `local = inverse(parent.rotation).rotate(world - parent.position)`.
- Alternative for fixed HUD elements: add a `layout.absolute?` flag where the transform pass skips composition. Only needed if there are HUD elements that must ignore parent transforms.

**Migration for `Positioned`** (already local-space):
```fennel
;; Current (writes world values via composition)
(set child.layout.position (+ self.position (self.rotation:rotate offset)))
(set child.layout.rotation (* self.rotation local-rotation))

;; After (writes local values, transform pass composes)
(set child.layout.local-position offset)
(set child.layout.local-rotation local-rotation)
```
