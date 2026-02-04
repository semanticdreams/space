# Render Architecture: Batching, Clips, and Model Transforms

This document describes how the renderer batching system worked historically, what we changed, why, and what we may optimize next.

Scope: immediate-mode style UI/scene renderers that write vertices into `VectorBuffer` and then issue OpenGL draws (triangles, text, images; meshes are discussed where relevant).

## Glossary

- **`VectorBuffer`**: C++ growable float buffer used as the shared vertex staging area for a renderer. Widgets allocate `VectorHandle`s into it and write vertex attributes (positions, colors, UVs, depth offsets, …).
- **`VectorHandle`**: `(index, size)` slice into a `VectorBuffer` (indices in floats, not bytes).
- **Clip region**: a layout-derived region that bounds visibility. We resolve it to a matrix via `assets/lua/clip-utils.fnl` and use it in shaders (`uClipMatrix`) to discard fragments outside the region.
- **Model matrix**: a per-object transform (layout node owned) applied in the vertex shader (`model`).

## Previous System (Per-handle draws + clip tracking)

### Data flow

1. Widgets allocate `VectorHandle`s from a `VectorBuffer` and write expanded vertices (already fully transformed into world space in many widgets).
2. Renderers upload the full buffer via `gl.bufferDataFromVectorBuffer(... GL_STREAM_DRAW)`.
3. Rendering was done with many `glDrawArrays` calls, typically one per handle.

### `ClipBatcher` (what it did)

The old `ClipBatcher` (`assets/lua/clip-batcher.fnl` before it was removed) was a small helper that:

- tracked `handle -> clip-region`,
- sorted tracked handles by `handle.index`,
- produced a `draws` list where each entry was **one handle**:
  - `start = handle.index / stride`
  - `count = handle.size / stride`
  - plus `clip` for the uniform update.

Crucially, it did **not** merge/coalese adjacent handles, and it did not batch by any state beyond clip. The triangle/text/image renderers therefore did roughly:

- set `uClipMatrix` per draw
- `glDrawArrays` per draw entry

### Limitations we felt

- **Driver/API overhead**: many calls into OpenGL (`glDrawArrays`) and many uniform updates (`uClipMatrix`), even when state was identical across adjacent handles.
- **Wasteful uploads**: every frame re-uploaded the whole `VectorBuffer` even if only a small slice changed.
- **No model transform batching**: triangles/text/images did not have a consistent per-object model transform concept (meshes did).

## What We Changed

### 1) Generalized batching: `DrawBatcher` (clip + model)

We replaced `ClipBatcher` with `DrawBatcher` (`assets/lua/draw-batcher.fnl`), which tracks:

- `handle -> (clip, model)`

and produces **draw batches** keyed by `(clip, model)` identity (Lua object identity). Each batch contains:

- `clip` (for `uClipMatrix`)
- `model` (for `model`)
- `firsts[]` and `counts[]` for `glMultiDrawArrays`

Important implication: “identical-by-value” clip/model objects do **not** automatically merge into the same batch unless they are the *same* object. If we need value-based merging, we should intern/canonicalize clip/model keys.

Inside a batch, we sort handles by index and **coalesce contiguous handles** into “runs”. Non-contiguous handles become separate `(first, count)` segments within the same batch.

### 2) Fewer draw calls: `glMultiDrawArrays`

Triangle/text/image renderers now draw each `(clip, model)` batch with:

- one clip uniform update
- one model uniform update
- one `glMultiDrawArrays(GL_TRIANGLES, firsts, counts)`

This preserves per-vertex data layout and avoids a large number of `glDrawArrays` calls.

### 3) Model matrices are now first-class for UI-style renderers

We added a `uniform mat4 model;` to:

- `assets/shaders/triangle.vert`
- `assets/shaders/msdf.vert`
- `assets/shaders/image.vert`

and the renderers now set `model` per draw-batch (defaulting to identity when a batch doesn’t provide one).

The build context API now accepts an optional model matrix when tracking handles:

- `track-triangle-handle(handle, clip, model)`
- `track-text-handle(font, handle, clip, model)`
- `track-image-handle(texture-batch, handle, clip, model)`

### 4) Incremental uploads: dirty-range tracking on `VectorBuffer`

We extended `VectorBuffer` (`src/vector_buffer.h`) to track a dirty float range:

- writes via Lua bindings (e.g. `set-glm-vec*`, `set-float`, `set-floats-from-bytes`, `set-floats-batch`) call `markDirty(...)`
- `deleteHandle`/zeroing also marks the relevant range dirty
- renderers upload:
  - full buffer once (or on size change / vector change)
  - then `glBufferSubData` for only the dirty subrange via `bufferSubDataFromVectorBuffer`

Triangle/text/image renderers share this “full upload then subupload” strategy.

Practical caveat: dirty-range subuploads help most when the same `VectorBuffer` stays bound and reused across frames. If a renderer frequently switches between different vectors (e.g. text per-font, images per-texture), we’ll still often do full uploads when the bound vector changes. If that becomes a bottleneck, the next lever is per-font/per-texture VBO caching or persistent mapping—not more batching logic.

## Trade-offs Discussed (and how the current design answers them)

### “Does order matter?”

If order has visible meaning (painter’s algorithm, depth test disabled, blending, etc.), naive “bucket by state” can reorder draws.

Current state:

- `DrawBatcher` groups by `(clip, model)` and then sorts batches by each batch’s minimum handle index (so batches are roughly in index order), but **interleaving across batches can still be reordered** when two states alternate.

Why we accepted that:

- Many UI elements are already depth-resolved via `depth_offset_index` and/or depth testing.
- You explicitly indicated order does not matter for the use case that motivated this change.

If we later need strict order, the correct fix is to emit **state runs in global handle-index order** (i.e. a sequence like: `[ (state A, segment1), (state B, segment1), (state A, segment2), … ]`) and multi-draw per run, rather than global bucketing by state.

### “Can we bucket by clip by construction to avoid sorting?”

We discussed trying to guarantee contiguity by allocating per-clip (or per-(clip,model)) so that handles for the same state are naturally adjacent. Downsides:

- harder allocation/free logic and increased fragmentation risk
- more `VectorBuffer`s or more complex sub-allocators
- extra buffer binds and uploads if we go “buffer per bucket”

Given the expected scale (≲100 clips, a few hundred models), the rebuild sort cost is usually acceptable, and we only rebuild when tracking changes.

### “If a region is zeroed it won’t be visible, so it’s ok to leave it”

Zeroing vertex data is not a reliable substitute for not drawing:

- it still costs vertex work and can create degenerate geometry that may still be visible depending on attributes (e.g. non-zero color, depth, UV sampling)
- it doesn’t avoid clip/model state work

In the current architecture, zeroing is just safety hygiene inside `VectorBuffer::deleteHandle`; correctness comes from **untracking** handles so they are not emitted into batches at all.

### “Would it be most efficient to have a buffer per clip region?”

We rejected “one VBO per clip” (or per `(clip, model)`) as the default because it trades one kind of overhead for another:

Pros:
- trivially stable batching and contiguity
- potentially less sorting

Cons:
- many GL buffer objects, binds, and lifetime management
- more frequent uploads (one per bucket) and harder dirty tracking across buckets
- increased CPU bookkeeping and memory fragmentation

The chosen approach (single shared VBO + bucketed multi-draw + dirty-range subuploads) is a better baseline for typical UI workloads.

## Alternatives Considered (and why we discarded them)

### Instanced rendering as the primary approach

Instancing helps when:

- you have a small set of base meshes (e.g. a unit quad)
- you render many instances with differing per-instance data (model matrix, color, UV rect, …)

Our triangle/text/image paths do not currently fit that shape:

- they upload **fully expanded vertices** into `VectorBuffer` (unique positions/UVs per-vertex)
- many primitives are not “the same mesh” repeated; they are already baked into unique triangles

Instancing would require a significant redesign:

- represent rectangles/glyph quads/images as instance records
- move more computation into the shader (vertex expansion from instance attributes)
- manage per-instance streams and capacity, plus additional dirty tracking

We *do* already use instancing where it naturally fits: the point renderer uses instanced quads. That remains the right pattern for repeated identical geometry.

### “Single draw with per-vertex clip/model IDs” (shader fetch from arrays)

Another path is to encode `clip_id` and `model_id` per vertex and do a single draw:

- upload all vertices once
- in shader, use IDs to index arrays of clip/model matrices (via UBO/SSBO/texture buffer)

Downsides:
- increases per-vertex attribute bandwidth (IDs per vertex)
- adds GPU-side indirection and storage limits/management complexity
- requires robust resource update logic for the matrix arrays

Given expected counts (few hundred models, <100 clips), this remains a viable *future* optimization if draw-call count becomes negligible and vertex bandwidth becomes dominant, but it’s not the simplest next step.

### Sorting everything by state every frame

We avoided unconditional per-frame sorting of draw segments because:

- handle tracking changes are already localized (dirty only when a widget’s clip/model changes or a handle is added/removed)
- rebuild cost is easier to pay on structural changes than every frame

## Why `glMultiDrawArrays` is a good starting point

- Minimal change to data representation: still one big vertex buffer, still `glDrawArrays` semantics.
- Fewer driver calls: one call per `(clip, model)` batch, not per handle.
- Works well with “contiguous range coalescing”: we can convert many handles into a few ranges.
- Pairs naturally with dirty-range uploads: buffer stays stable while draw segmentation changes.

## Future Optimizations (practical next steps)

These are ordered roughly from “smallest change” to “bigger architectural shift”.

### Note: if we reimplement rendering from scratch, prefer instancing for UI primitives

If we do a future “v2” renderer, instancing should likely be the default for UI-style primitives whose geometry is fundamentally many copies of a small base mesh:

- **Rectangles, images, glyphs** are all quads: instead of writing 6 expanded vertices per item, write **one instance record** (position/size, UV rect, tint, depth offset, `clip_id`, `model_id`) and draw a unit quad mesh instanced.
- Store clip/model matrices in a GPU-accessible array (UBO/SSBO/texture buffer) and index them by compact IDs in the instance data. This avoids splitting draws purely to change clip/model uniforms.
- To avoid splitting draws by texture (e.g. text per font, images per texture), prefer atlases/texture arrays (or other GPU-friendly binding strategies) where possible.

Instancing is **not** a blanket solution: arbitrary “triangle soup” that is not repeated meshes (today’s expanded triangle buffer) does not become cheaper just by adding instance attributes. For that kind of geometry, the more relevant tools are multi-draw/indirect draws, material/state bucketing, and/or a move to indexed meshes.

1. **Strict-order batching mode (if needed)**:
   - emit a global sequence of state runs in index order (no global state bucketing), still using `glMultiDrawArrays` for adjacent segments with the same state.

2. **Clip/model interning**:
   - if clip/model objects are frequently recreated, intern them so identity-based batching works reliably.

3. **Persistent-mapped buffers**:
   - use persistent mapping to reduce upload overhead further and avoid repeated `glBufferData`/`glBufferSubData` patterns.

4. **Per-renderer VBO caching policy**:
   - if certain vectors are frequently swapped (e.g. text per font), consider a VBO per font/texture *only for the hottest paths* while keeping the shared-VBO default elsewhere.

5. **ID-based single draw (UBO/SSBO indexed matrices)**:
   - move clip/model matrices into GPU arrays and reference them by compact IDs in vertex attributes.
   - best when draw-call count is already low and CPU/driver overhead is no longer the limiting factor.

6. **Instance-based UI primitives (quads/glyphs/images)**:
   - treat rectangles/glyphs/images as instances rather than expanded vertices.
   - potentially large win for vertex bandwidth and CPU writes, but requires redesign of vertex formats and a new instance buffer pipeline.

## Testing Notes

Current test coverage relevant to this architecture:

- draw batching correctness, including noncontiguous range splitting: `assets/lua/tests/test-renderers.fnl`
- dirty-range upload behavior for triangles (and smoke coverage via text/image render paths): `assets/lua/tests/test-renderers.fnl`

If we add strict-order batching or ID-based approaches, add tests that encode “interleaved states” and assert either:

- stable ordering is preserved, or
- ordering is explicitly documented as non-semantic for that renderer path.
