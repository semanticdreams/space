---
type: dev-note
tags:
  - note
---

# Raster Drawing Implementation

This note extends [drawing architecture](./drawing-architecture).

That earlier note defined the first clean vector drawing system and explicitly deferred raster layers. This note records the agreed follow-up design for mixed vector and raster drawing in the same document, including the decisions that are now fixed and the features that remain deferred.

## Summary

Raster drawing will be added as a second `drawing` layer backend, not as a special case inside the current vector object path.

The key architectural choice is:

- one drawing document per world
- mixed vector and raster layers in the same document
- `layer.kind` is the backend seam
- vector layers keep object-based storage
- raster layers use sparse tiled pixel storage in document space
- CPU-owned raster data is authoritative
- GPU textures are cached render/upload resources
- raster pixels persist as sidecar PNG tiles, not inline world JSON

This is the clean path for undo, pressure, fill, eyedropper, marquee selection, move, and future layer features.

## Fixed Decisions

These decisions are now fixed for the raster implementation.

- Vector and raster layers must coexist in the same drawing document.
- Switching the active layer auto-switches to the last tool used for that layer kind.
- Tool names should fit user intent. Shared names are fine when behavior maps naturally across layer kinds.
- Raster layers get raster versions of `rectangle`, `ellipse`, and `line`.
- Raster erasing means writing transparency, not painting with a background color.
- Stylus pressure affects brush size and flow. These mappings should be individually toggleable in brush settings.
- Eyedropper samples the composited document under the cursor by default, not only the active layer.
- Fill starts as contiguous flood fill with tolerance.
- Raster selection starts with rectangular marquee selection.
- Raster transform starts with move. Scale and rotate are deferred.
- Moving a raster selection uses a floating raster fragment until commit.
- Raster selection and edit operations target the active layer only.
- The proper implementation is CPU-owned pixels plus dirty-tile GPU uploads, not a GPU-only source-of-truth path.
- Raster layer persistence uses sidecar tiled files.
- Layer visibility, lock, opacity, and blend modes are deferred and must remain documented as follow-up work.

## Current Seams In The Code

The current drawing system already has the right top-level seam, but the rest of the stack is still vector-only.

- `assets/lua/drawing/document.fnl` already persists `layer.kind`, but only allocates vector layers today.
- `assets/lua/drawing/controller.fnl` is object-centric end to end: previews, selection, add/delete, eraser, and history commands all work in terms of vector objects.
- `assets/lua/drawing/input.fnl` and `assets/lua/drawing/hit-test.fnl` assume object hit testing.
- `assets/lua/drawing/render.fnl` rebuilds vector triangle geometry from `layer.objects`.
- `assets/lua/build-context.fnl` already exposes image batch support, which is the obvious render seam for raster tiles.
- `src/texture.h` already supports `allocate`, `update_full`, and `update_sub_rect`, but `src/lua_textures.cpp` does not expose the partial update path needed for proper raster editing.
- `assets/lua/home-world.fnl` currently snapshots drawing state inline into the world state, which is correct for vector metadata but incorrect for raw raster pixels.

Do not jam raster into the existing object-only controller branches. Split behavior by backend at the layer-kind seam.

## Document Model

The document remains world-owned and document-space based.

Raster does **not** introduce a required fixed canvas size in the first implementation.

Instead:

- vector content remains world-space geometry
- raster layers are sparse tiled images in document space
- only touched raster tiles exist
- empty space is represented by missing tiles

This avoids a premature finite-canvas model and keeps mixed vector/raster worlds practical.

### Persistent Document Shape

The document version should advance when raster metadata lands.

Recommended direction:

```clojure
{:version 2
 :next-layer-id 1
 :next-object-id 1
 :layers [...]}
```

Vector layers continue to look like:

```clojure
{:id "layer-1"
 :name "Layer 1"
 :kind "vector"
 :objects [...]}
```

Raster layers should persist metadata, not inline pixels:

```clojure
{:id "layer-2"
 :name "Paint 1"
 :kind "raster"
 :storage {:scheme "png-tile-v1"
           :tile-size 256
           :channels 4
           :base-path "drawing/raster/layer-2"}}
```

Notes:

- `tile-size` is fixed per layer for v1.
- Raster tiles are stored as RGBA8 PNGs.
- Raster tile bounds can be derived from filenames or a lightweight manifest if needed later.
- Raster selection and floating-selection state are runtime state, not persistent document state.

## UI State Model

The current single `active_tool` and single defaults table are not sufficient once layer kinds auto-switch tools.

The persisted editor UI state should move toward:

```clojure
{:active_layer_id "layer-2"
 :active_tool_by_kind {:vector "select"
                       :raster "brush"}
 :defaults_by_kind {:vector {...}
                    :raster {...}}}
```

Guidance:

- the visible active tool is derived from the active layer kind
- switching layers restores the last-used tool for that kind
- vector defaults remain vector style defaults
- raster defaults become brush/fill/settings defaults

Do not persist:

- undo/redo stacks
- active raster marquee contents
- floating raster fragments

Selection persistence should stay off for raster work. It is too stateful and too easy to restore incorrectly.

## Backend Split

The clean design is a shared drawing controller with backend-specific layer operations.

Recommended responsibility split:

- shared controller owns document, active layer, history, high-level commands, and UI state
- vector backend owns vector preview, hit test, object commands, and vector render contribution
- raster backend owns tile storage, brush engine, raster hit/select/fill/move logic, and raster render contribution

The shared controller should dispatch backend-sensitive operations through the active layer kind:

- begin gesture
- update gesture
- preview
- commit
- cancel
- hit test
- selection behavior
- delete behavior
- render contribution

This can be implemented as explicit backend tables or modules rather than large `if` ladders spread across the controller.

## Raster Storage And Persistence

Raster storage is sidecar-file based.

World persistence should continue to store drawing metadata in `world.state.drawing`, but raster pixels themselves must live in world-owned sidecar files.

Recommended sidecar layout:

```text
<world-dir>/
  world.json
  drawing/
    raster/
      layer-2/
        0_0.png
        0_1.png
        -1_0.png
```

Rules:

- one PNG per tile
- filename encodes tile coordinates
- missing tile means fully transparent tile
- save only dirty or live tiles
- delete cleared tiles rather than writing blank tiles

Implementation notes:

- use `JsonUtils.write-json!` for manifest-like JSON writes
- use temp-file then rename semantics for tile PNG writes
- do not inline pixel blobs into `world.state.drawing`

The engine already exposes PNG read/write helpers through `image-io`; use those instead of inventing a second image persistence path.

## Raster Runtime Model

Raster data is authoritative on the CPU.

Each active raster layer needs:

- a tile map keyed by tile coordinate
- CPU pixel buffers per loaded tile
- dirty rect tracking per tile
- GPU texture cache per visible tile
- optional preview/floating-selection surfaces

The chosen model is:

- CPU buffers answer editing questions
- history stores CPU patch data
- fill reads CPU pixels
- eyedropper reads composited CPU-visible pixels or a render-aligned sample path
- GPU textures exist to draw the current CPU state efficiently

This is the "proper solution" for this codebase. A GPU-only painting path would immediately fight undo, persistence, fill, selection, and tooling.

## Raster Rendering

Raster rendering should use the existing image-batch path instead of the vector triangle buffer.

Per visible raster tile:

- ensure a texture exists
- allocate it once at tile size
- upload only dirty regions
- submit one textured quad into the image batch
- cull tiles outside the current canvas view

Required engine work:

- expose `Texture2D.allocate` to Lua if missing at the usable module surface
- expose `Texture2D.update_full`
- expose `Texture2D.update_sub_rect`
- keep failures loud if texture allocation or upload fails

The raster renderer should not rebuild full-layer textures on every change.

## Tool Model

Shared tool names are acceptable when the user intent matches.

Recommended raster tool set for the initial raster milestone:

- `select`
- `marquee`
- `move`
- `eyedropper`
- `fill`
- `pen`
- `brush`
- `marker`
- `eraser`
- `rectangle`
- `ellipse`
- `line`

Rules:

- `pen`, `brush`, and `marker` are presets over one raster brush engine
- `eraser` writes alpha to zero
- shape tools stamp pixels on commit in the first implementation
- shape tools should still provide live previews while dragging
- `fill` is contiguous flood fill over CPU pixels with tolerance
- because raster layers are sparse and unbounded, filling fully transparent space is bounded to the layer's known persisted-or-loaded tile extent in v1
- `move` operates on the active floating selection when one exists

## Raster Selection And Move

Raster selection is not object selection.

The first raster selection implementation should be:

- rectangular marquee only
- active layer only
- one floating raster fragment at a time

Recommended move flow:

1. marquee selects pixels from the active raster layer
2. beginning a move lifts the selected pixels into a floating fragment
3. the source region becomes transparent in the working layer buffer
4. preview renders the floating fragment at its current offset
5. commit writes the fragment back into destination tiles
6. one move commit creates one history command

Scale and rotate are intentionally deferred until the floating-selection path is stable.

## History Model

Raster history remains drawing-local and command-based.

Recommended command granularity:

- one completed brush stroke = one history entry
- one completed shape stamp = one history entry
- one fill = one history entry
- one move commit = one history entry

Raster commands should store tile patches, not whole-layer snapshots.

Recommended patch shape:

- affected tile ids
- before bytes for each dirty rect or tile span
- after bytes for each dirty rect or tile span

Start with whole-tile before/after patches if that unblocks implementation cleanly. Move to sub-rect patches once the path is correct and tested.

## Implementation Order

### Phase 1: Architecture And Engine Surface

- update the drawing document/UI model for per-kind tools/defaults
- introduce explicit vector/raster backend seams in the controller and render path
- expose texture allocation and partial update APIs to Lua
- add a raster implementation note link in docs

### Phase 2: Tile Storage And Persistence

- add raster layer allocation and normalization
- add sidecar tile load/save paths
- add runtime tile maps and dirty tracking
- add world save/load integration for raster sidecar assets

### Phase 3: Raster Render Path

- render visible raster tiles through image batches
- upload dirty tile regions only
- keep vector and raster layers composited in layer order

### Phase 4: Paint Core

- add raster brush engine
- add `pen`, `brush`, `marker`, and `eraser`
- add pressure mapping for size and flow
- add raster `rectangle`, `ellipse`, and `line` with live preview and commit stamping

### Phase 5: Pixel Tools

- add contiguous flood fill with tolerance
- add composited eyedropper sampling

### Phase 6: Selection And Move

- add rectangular marquee selection
- add floating raster fragment support
- add move-only transform and commit path

### Phase 7: Test And Harden

- add fast tests for document normalization and backend dispatch
- add raster persistence tests for save/load tile correctness
- add e2e coverage for paint, erase, fill, marquee, move, and mixed vector+raster render order
- profile dirty upload and brush interaction paths

## Current Implementation Status

Implemented now:

- mixed vector and raster layers in one document
- per-kind tool memory with auto-switch on active-layer change
- sparse tiled raster CPU storage with sidecar PNG persistence
- raster render compositing through image batches
- raster `pen`, `brush`, `marker`, and `eraser`
- raster `rectangle`, `ellipse`, and `line`
- raster `fill` with bounded transparent-region behavior on sparse layers
- composited eyedropper sampling across drawing layers
- raster marquee selection
- raster floating-fragment move
- fast test coverage for persistence, render upload, fill, eyedropper, marquee, and move
- e2e coverage for mixed vector/raster drawing, fill, eyedropper, marquee, move, and raster image-batch rendering

Still deferred:

- move-scale and move-rotate transforms
- layer visibility, lock, opacity, and blend modes
- lasso / wand selection
- import/export workflows
- additional e2e coverage for save/reopen raster sidecars and keyboard delete/undo over raster selections
- dirty-sub-rect texture uploads instead of current whole-tile updates

## Review Follow-ups

These are optional cleanup/performance improvements, not required for the initial raster wrap-up:

- split the controller's vector and raster gesture/commit branches into backend modules once the v1 behavior stops moving
- replace whole-tile history patches with dirty sub-rect patches after the tile path is stable
- use `Texture2D.update_sub_rect` from the raster renderer when dirty-region tracking lands
- add an e2e save/reopen workflow around raster sidecar persistence

## Explicitly Deferred

These features are intentionally out of scope for the initial raster milestone and must stay documented as deferred work:

- layer visibility toggles
- layer lock toggles
- layer opacity controls
- layer blend modes
- lasso selection
- wand / color-range selection
- raster selection scale
- raster selection rotate
- cross-layer raster selection/edit
- image import/export workflows
- non-rectangular raster shape editing after commit
- smudge
- blur / sharpen
- adjustment layers
- raster/vector boolean interactions

These are real follow-up features, not accidental omissions. The implementation should leave room for them without polluting v1 with half-finished abstractions.

## Notes For Implementers

- Keep `layer.kind` as the single top-level dispatch seam.
- Do not represent raster marks as fake vector objects.
- Do not persist floating-selection data into the world state.
- Do not hide raster failures behind fallbacks. Missing sidecar data or failed texture upload should fail loudly.
- Keep raster editing authoritative on CPU buffers, then upload dirty regions to the GPU.
- Preserve mixed layer ordering semantics so vector and raster interleave by document order.


## See also

- [Stylus Drawing Input](/dev/features/stylus-drawing-input)
