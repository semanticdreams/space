# Heightfield Terrain Implementation Plan

This note turns the terrain architecture direction into a concrete first implementation plan.

It is intentionally narrower than [Terrain Architecture](/dev/notes/terrain-architecture). The goal here is to define the smallest useful `heightfield-terrain` that:

- fits the direct canonical-data model
- works with the current graph/world runtime architecture
- supports non-interactive terrain tools first
- leaves a clean path to interactive in-world tools later

## Current Constraints

The current system is built around whole-terrain records:

- world data can add, update, and remove terrain records
- scene runtime can add, replace, and remove terrain records in place
- `flat-terrain` and `perlin-terrain` are record-driven terrain kinds with dedicated graph editors

That is enough to bootstrap `heightfield-terrain`, but not enough yet for localized live editing. The first implementation should therefore split into:

1. `heightfield-terrain` data/runtime support
2. non-interactive form-driven tools that mutate the terrain
3. interactive world-space tools later

## First Persisted Schema

The first persisted schema should be explicit, JSON-friendly, and chunk-based from the start.

Suggested record shape:

```fennel
{:id "<uuid>"
 :kind "heightfield-terrain"
 :options
 {:position [0 0 0]
  :rotation [1 0 0 0]
  :opacity 1.0
  :physics true
  :sample-spacing [1 1]
  :chunk-samples [33 33]
  :default-height 0
  :material nil}
 :chunks
 [{:coord [0 0]
   :size [33 33]
   :heights [0 0 0 ...]}
  {:coord [1 0]
   :size [33 33]
   :heights [0 0 0 ...]}]}
```

Notes:

- `sample-spacing` means local X/Z spacing between height samples.
- `chunk-samples` means sample resolution per chunk, including border samples.
- `coord` is chunk-space integer coordinates, not world coordinates.
- `heights` is a row-major flat array.
- `default-height` is the value for missing chunks.
- `material` can stay minimal in the first pass; it only needs to reserve the field.

For the first pass, all chunks should use the same `chunk-samples` size. Do not add per-chunk variation yet.

## Deliberate Omissions

Avoid these in the first schema:

- stored tool history
- generator recipes
- per-chunk materials
- streaming metadata
- LOD data
- multiple physics representations
- sparse compression formats

The first schema should optimize for clarity, not storage efficiency.

## Runtime Representation

The runtime should derive from the record and expose chunk-local mutation.

Recommended runtime concepts:

- terrain metadata
- canonical chunk store
- render chunk cache
- collision chunk cache
- dirty chunk set

The runtime should not require rebuilding the whole terrain after every change.

## Minimum Runtime API

The first runtime/world API should be designed around localized edits.

Recommended operations:

- `create-heightfield-terrain(record)`
- `get-heightfield-terrain(world-id terrain-id)`
- `sample-height-local(terrain local-x local-z)`
- `sample-height-world(terrain world-x world-z)`
- `mutate-heightfield-chunks(world-id terrain-id mutation-fn)`
- `set-height-region(world-id terrain-id region value-fn)`
- `apply-flat-region(world-id terrain-id region opts)`
- `apply-perlin-region(world-id terrain-id region opts)`
- `apply-height-delta-brush(world-id terrain-id brush opts)`
- `smooth-region(world-id terrain-id region opts)`
- `rebuild-dirty-heightfield-chunks(world-id terrain-id)`

The most important one is `mutate-heightfield-chunks(...)`: one API that:

- loads or creates touched chunks
- applies the mutation
- marks touched chunks dirty
- syncs render/physics only for those chunks

That should become the core write path. Higher-level tools should be implemented in terms of it.

## Region Model

The system needs a simple region model before interactive brushes exist.

Recommended first region shapes:

- whole terrain
- axis-aligned local-space rectangle
- circular brush area

Do not add arbitrary polygon regions yet.

Suggested region representation:

```fennel
{:kind "rect"
 :center [x z]
 :size [sx sz]}
```

and

```fennel
{:kind "circle"
 :center [x z]
 :radius r}
```

Those are enough for:

- form-driven perlin/flat application
- initial brush tools

## First Tools

The first tool set should be intentionally small.

### Non-interactive first

These should work through the terrain node view with forms/buttons:

- initialize terrain to flat height
- apply perlin to whole terrain
- apply perlin to a rectangular region
- flatten a rectangular region to a chosen height

Why these first:

- they prove the direct-data model
- they exercise chunk mutation
- they do not require new world interaction systems
- they are still useful to users

### Interactive second

After the non-interactive tools are working:

- raise/lower brush
- smooth brush
- flatten brush

These require additional UI/runtime support and should come later.

## Required New UI Primitives

Interactive tools will need UI features the current graph forms do not provide.

Likely required primitives:

- tool activation state on the active world or terrain
- terrain/world ray hit query from cursor position
- world-space brush preview
- drag/hold input capture for active tools
- temporary overlay rendering for brush radius and target area
- throttled live updates while dragging

These should not be invented in the abstract. They should be built only as needed by the first real brush tool.

## Recommended Delivery Slices

The clean implementation order is:

### Slice 1: Data + runtime

- add `heightfield-terrain` record support
- add record normalization/defaults
- add runtime build path
- add chunk storage and dirty tracking
- add whole-terrain or rectangular region mutation API

No new interactive UI yet.

### Slice 2: Form-driven tools

- add `heightfield-terrain` graph node/editor
- add create flow in `terrains`
- add form controls for:
  - dimensions / sample spacing
  - flat initialize
  - perlin region apply
  - flatten region apply

This gives users useful terrain creation and adjustment without requiring new interaction systems.

### Slice 3: Query primitives

- world-space ray to terrain hit query
- local-space coordinate resolution
- terrain sample inspection helpers

This is the minimum needed before brush editing.

### Slice 4: First interactive brush

- active tool state
- world-space preview
- mouse drag application
- localized chunk mutation while dragging

Start with `raise/lower` or `flatten`, not a more complex tool.

### Slice 5: Additional brushes

- smooth
- perlin brush or stamp
- other region-local tools

Only add these after Slice 4 feels clean.

## Graph and UI Shape

The graph should stay terrain-centered.

Recommended first `heightfield-terrain` node view:

- terrain id
- terrain kind
- sample spacing
- chunk sample size
- chunk count summary
- material controls
- physics controls
- tool action panels

The tool action panels should be simple:

- `Initialize Flat`
- `Apply Perlin`
- `Flatten Region`

Those can all be form-driven first.

The graph does not need:

- separate tool nodes
- procedural history display
- separate chunk nodes

## Integration with Existing Terrain Kinds

There is no need to migrate `flat-terrain` and `perlin-terrain` immediately.

They can remain as existing simple terrain kinds while new work goes into `heightfield-terrain`.

Important rule:

- do not extend old terrain kinds with new live-edit features

That keeps the transition clean.

## Bullet Strategy

The first implementation should keep the Bullet decision narrow.

Required behavior:

- terrain collision updates only for dirty chunks
- terrain data stays independent of Bullet shape choice

Acceptable first options:

- one collision representation per chunk
- chunked triangle mesh if that is simpler to wire now
- Bullet heightfield shape only if it fits cleanly

Do not optimize for the perfect long-term Bullet representation before the editing path exists.

## Testing Plan

The first implementation needs tests at three levels.

### Record/schema tests

- normalize default `heightfield-terrain`
- reject invalid chunk sizes and malformed height arrays
- verify missing chunks read as `default-height`

### Runtime mutation tests

- mutating one region only dirties touched chunks
- perlin tool changes only targeted chunks
- flatten tool sets expected heights
- scene runtime rebuild stays localized

### Graph/world tests

- create `heightfield-terrain` from the terrains node
- apply flat/perlin tool actions from the terrain node
- verify world state changes and active scene stays in sync

Interactive brush tests can come later.

## Immediate Next Step

The next concrete step should be to define the exact `heightfield-terrain` record schema and default record/builder support in code.

That means:

1. add `heightfield-terrain` to terrain record normalization/defaults
2. define chunk storage helpers
3. build a minimal scene/runtime builder for heightfield chunks
4. expose one mutation API
5. then add the first form-driven terrain tool

That sequence keeps the implementation grounded and avoids building interactive UI before the terrain runtime can support it.
