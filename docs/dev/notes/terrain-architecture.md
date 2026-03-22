# Terrain Architecture

This note proposes the long-term terrain structure for `space`.

The immediate goal is to move beyond top-level `flat-terrain` and `perlin-terrain` objects without throwing away the useful ideas behind them. The design should support:

- multiple terrain objects per world
- live in-context terrain editing during gameplay
- procedural generation and local sculpting
- clean Bullet integration
- future terrain backends such as heightfields, voxels, and SDFs
- eventual chunking and streaming for very large or effectively infinite worlds

The intended users for terrain editing are end users in the live world, not only developers or designers. They should be able to generate terrain, adjust it while playing, and keep going without switching into a separate authoring workflow.

## Design Decision

The first real top-level terrain object should be `heightfield-terrain`.

`flat-terrain` and `perlin-terrain` should not be the long-term canonical terrain objects. They are better understood as terrain tools or terrain actions that write into a `heightfield-terrain`.

This gives a simpler separation:

- terrain kind answers "what kind of terrain is this?"
- terrain tools answer "how does the user change the terrain right now?"
- runtime adapters answer "how is it rendered and simulated?"

This is the right model for live end-user editing because the world only needs to keep the final terrain state. It does not need to remember how that state was produced.

## Top-Level Model

Worlds contain multiple terrain objects.

Each terrain object is single-kind forever. A world can mix multiple terrain kinds, but one terrain object should never internally switch between heightfield and voxel or hold multiple domain kinds at once.

Recommended top-level kinds:

- `heightfield-terrain`
- later `voxel-terrain`
- later `sdf-terrain`
- later `mesh-terrain`

## Core Parts

Each terrain object should have three distinct parts of responsibility.

### 1. Terrain

Persistent authored object stored in world data.

Suggested responsibilities:

- terrain id, name, kind
- transform / placement
- terrain-specific configuration such as chunk size and resolution
- material assignments
- physics options
- canonical terrain data
- persistence metadata

This is the authoritative representation, not the render mesh and not the Bullet shape.

### 2. Canonical Terrain Data

The editable geometry data stored inside a terrain.

Examples:

- heightfield: sampled height grid in local XZ
- voxel: sparse voxel field
- SDF: signed-distance volume
- mesh: explicit patch or triangle domain

For the first implementation, the canonical data is chunked heightfield data.

### 3. Terrain Runtime

Derived runtime representation used by rendering, selection, raycasts, and physics.

Examples:

- render mesh chunks
- normals/tangents
- Bullet collision chunks
- dirty-region rebuild tracking

The runtime is disposable and rebuildable. It should never be the canonical source of truth.

## Heightfield First

Heightfield is the right first canonical terrain kind.

Why:

- it directly supports flat/perlin-style generation
- it directly supports raise/lower/smooth sculpting
- it has simple spatial semantics
- it has straightforward chunking
- it is practical for Bullet
- it does not block future voxel or SDF terrain kinds

The canonical heightfield representation should be chunked sample data in terrain-local coordinates.

Suggested structure:

- `heightfield-terrain`
- chunk grid or sparse chunk map
- per-chunk sample arrays

## Canonical Data Model

The canonical editable source of truth should be final heightfield chunk data, not an operator list and not brush replay history.

That means:

- tools such as `flat`, `perlin`, `raise`, `lower`, `smooth`, and `flatten` act directly on the terrain data
- the world persists only the resulting terrain state
- changing a generator later means running that generator tool again on some region

This is simpler than persisting a history or a procedural recipe, and it matches the intended user experience much better.

Example:

- a user generates a perlin area
- a user smooths part of it
- a user later wants a different perlin shape in one section
- the user applies the perlin tool again to that section

There is no need to preserve the original perlin parameters unless a future feature explicitly wants history or recipes.

## Tools, Not Operators

The terrain system should distinguish between canonical data and the tools that modify it.

Examples of terrain tools:

- `flat`
- `perlin`
- `raise`
- `lower`
- `smooth`
- `flatten`
- later `heightmap-stamp`
- later `erosion`

These should be treated as editing actions, not as persistent model objects.

Some tools are broad generators:

- `flat`
- `perlin`
- `heightmap-stamp`

Some tools are local interactive brushes:

- `raise`
- `lower`
- `smooth`
- `flatten`

That distinction matters for the UI, but not for persistence. Persistence only needs the resulting terrain data.

## Why Not Persist Tool History?

Persisting tools or tool history would add complexity without enough value for the current goal.

Costs of persisting tools/history:

- more complex persistence format
- more complex runtime evaluation model
- more complicated graph UI
- harder reasoning about how local edits interact with old generators
- pressure to expose reorder, bake, or recipe concepts to users

Benefits of persisting tools/history:

- procedural re-editability
- recipe-style terrain reuse
- richer undo/inspection possibilities

Those are real benefits, but they are not required for the first terrain system and they make live end-user editing less simple. If they become important later, they can be added as optional non-canonical metadata or separate recipe assets.

## Live Editing Constraint

Terrain editing should be designed as an in-game activity, not only an offline authoring workflow.

That implies:

- edits must apply immediately in the active world
- rendering and physics updates must be localized
- gameplay systems should not need to rebuild unrelated scene state
- users should not be forced to understand bake, recipes, or asset-pipeline concepts
- the same terrain object should support generation, inspection, and direct adjustment

This strongly favors direct canonical data editing over an operator-history model.

## Bullet Integration

Bullet should be integrated through terrain-kind-specific runtime adapters, not through the authored model directly.

Recommended boundaries:

- terrain is authoritative
- terrain runtime derives collision representation
- Bullet data is rebuilt only for dirty chunks

For heightfields, there are two viable runtime options:

- Bullet heightfield shape if the bindings and behavior are suitable
- chunked static triangle mesh collision otherwise

The architectural rule should be:

- terrain data must not depend on a specific Bullet shape type

That keeps the terrain model clean and leaves room for a different collision strategy per backend.

## Graph Structure

The graph should present terrain objects, not terrain construction history.

Recommended high-level graph shape:

- `Terrains`
- `Terrain`
- `Materials`
- `Physics`

The graph does not need to expose tools as separate nodes in the first pass.

For `heightfield-terrain`, the terrain node view can show:

- terrain kind
- terrain dimensions / resolution
- material settings
- physics settings
- controls for applying terrain tools

If the user invokes a tool such as perlin or smooth, that action mutates the terrain data directly.

## Clean First Implementation

The clean first implementation is:

1. Introduce a new top-level `heightfield-terrain` kind.
2. Define its persisted schema clearly.
3. Store final canonical heightfield chunk data.
4. Implement terrain tools that mutate that data directly.
5. Add chunk-based runtime invalidation and rebuild boundaries.
6. Keep Bullet integration behind a heightfield runtime adapter.

There is no need to design migration or persistent operator/history machinery right now.

## Runtime and Invalidation

The terrain runtime should be chunk-based from the start, even if initial worlds are small.

Required concepts:

- chunk identity in terrain-local space
- dirty chunk tracking
- render rebuild by chunk
- collision rebuild by chunk
- local-space sampling and ray queries

When a tool changes terrain:

- identify touched chunks
- mutate canonical terrain data for those chunks
- rebuild only the changed render/physics chunks

This structure is what will scale later to bigger worlds.

## Forward Compatibility

The design should be explicitly ready for larger worlds and other terrain domains, but those should remain future work.

### Large or Infinite Worlds

Not needed immediately, but the architecture should already assume:

- chunk-local authored data
- sparse chunk storage
- chunk identity separate from loaded runtime state
- runtime streaming is possible later

Do not design around one monolithic terrain mesh.

### Future Terrain Kinds

The backend contract should be designed so new terrain kinds plug in at the terrain-kind boundary, not by modifying the heightfield model.

Each terrain kind should provide:

- terrain schema
- canonical geometry data
- editing tools
- runtime mesh builder
- physics adapter
- spatial query helpers

That is the main protection against future refactors when voxel or SDF terrain arrives.

### Optional Future History or Recipes

If terrain history or reusable procedural recipes become valuable later, they should be added as optional secondary data, not as the canonical terrain format.

Examples:

- a non-canonical "recipe" attached to a terrain
- reusable generator presets
- undo/redo history

The terrain should still be fully represented by its final canonical data even if those features exist.

## Non-Goals for the First Pass

Avoid these in the first implementation:

- persistent operator lists
- brush stroke history as canonical state
- arbitrary operator graph reordering
- multi-kind terrain objects
- full terrain streaming
- solving voxel/SDF runtime details now
- exposing bake as a required user workflow
- exposing tools as separate graph nodes in the first pass

## Summary

The clean design is:

- worlds contain multiple terrain objects
- each terrain object has one canonical terrain kind
- `heightfield-terrain` is the first real terrain object
- canonical state is final heightfield chunk data
- `flat`, `perlin`, and sculpting actions are tools that mutate that data directly
- runtime render and Bullet data are derived chunked representations
- the architecture leaves room for voxel/SDF terrain kinds later without changing the top-level graph model

This gives a practical path forward now while staying simple and avoiding unnecessary history machinery.
