# Terrain Architecture

This note defines the clean terrain model for `space`.

The intended user is an end user editing terrain live while using the world, not only a designer in a separate authoring mode.

## Design Decision

The terrain system should have:

- terrain objects as the persistent things in the world
- terrain tools as actions that mutate those objects
- terrain runtimes as derived render/physics state

The first real terrain object kind should be `heightfield-terrain`.

`flat-terrain` and `perlin-terrain` should not remain as terrain object kinds in the long-term design. They are terrain tools for `heightfield-terrain`, not peer terrain objects.

## Core Model

Worlds contain multiple terrain objects.

Each terrain object is single-kind forever.

Examples of future terrain kinds:

- `heightfield-terrain`
- later `voxel-terrain`
- later `sdf-terrain`
- later `mesh-terrain`

Each terrain object has three responsibilities:

### 1. Terrain Object

Persistent world data.

Responsibilities:

- id
- name
- kind
- transform
- appearance settings
- physics settings
- terrain-domain configuration
- canonical terrain data

### 2. Canonical Terrain Data

Editable source of truth.

Examples:

- heightfield sample grid
- voxel field
- signed-distance field
- mesh patch data

For the first implementation, canonical data is chunked heightfield data in terrain-local space.

### 3. Terrain Runtime

Derived runtime state.

Responsibilities:

- render mesh chunks
- collision chunks
- picking / raycast helpers
- dirty-chunk tracking

Runtime is disposable. It is never authoritative.

## Canonical State

The terrain system should persist final terrain data, not tool history.

That means:

- `flat`, `perlin`, `raise`, `smooth`, and future tools modify terrain data directly
- the world persists only the resulting terrain
- if the user wants different perlin parameters later, they run the perlin tool again on the target region

This matches the live in-context editing model and avoids unnecessary complexity around recipes, operator stacks, baking, or history replay.

## Terrain Objects vs Tools

Terrain objects answer:

- what terrain exists in the world?
- where is it?
- what kind is it?
- what are its physical/render properties?

Tools answer:

- how does the user change this terrain right now?

Examples of `heightfield-terrain` tools:

- `Initialize Flat`
- `Apply Perlin`
- later `Raise`
- later `Lower`
- later `Smooth`
- later `Flatten`
- later `Stamp Heightmap`

Tools are not persistent model objects. They are UI/actions that mutate canonical terrain data.

## Graph Model

The graph should present terrain objects, not terrain history.

Recommended shape:

- `Terrains`
- `Terrain`

That is enough for the first clean implementation.

The generic `Terrain` node should be generic.

Its label should be:

- terrain name if present
- otherwise `terrain`

It should not use terrain kind as the node label.

The generic terrain node view should show:

- name
- kind
- transform summary
- terrain-domain summary
- appearance summary
- physics summary
- available tools list

`kind` is metadata in the view, not the node label.

## Terrain Editors

Terrain properties and terrain tools are different concepts and should have different UIs.

### Terrain Properties Editor

Each terrain kind can have one kind-specific terrain-properties editor.

For `heightfield-terrain`, this editor should own:

- name
- position
- rotation
- sample spacing
- chunk/sample configuration
- appearance settings
- physics settings

This editor changes terrain object properties.

It should not embed terrain tools like perlin or flatten.

### Terrain Tools List

The generic terrain node view should show a searchable list of tools applicable to the terrain kind.

For `heightfield-terrain`, the first list should include:

- `Initialize Flat`
- `Apply Perlin`

Later:

- `Raise`
- `Lower`
- `Smooth`
- `Flatten`

Clicking a tool should open that tool's own dedicated view or node.

That keeps the terrain-properties editor clean and allows many tools without turning one view into a dumping ground.

## Tool UI Semantics

Terrain property editing and tool application should not share exactly the same button behavior.

### Property Editors

For terrain properties:

- `Apply` should require valid input
- `Apply` should be enabled only when the form is dirty

### Tools

For terrain tools:

- `Apply` should require valid input
- `Apply` should stay enabled even if the params are unchanged
- repeated apply with unchanged params is valid

This matters especially for tools like perlin, where a user may want to re-run the tool repeatedly without changing the form.

## Tool Target Model

All terrain tools should operate on an explicit target.

The first clean target modes are:

- whole terrain
- rectangle

Later:

- brush

Suggested target representation:

```fennel
{:mode :whole}
```

and

```fennel
{:mode :rect
 :x0 local-x0
 :z0 local-z0
 :x1 local-x1
 :z1 local-z1}
```

This is enough for:

- whole-terrain initialization
- whole-terrain perlin generation
- rectangular perlin application
- rectangular flatten

For the first pass, rectangle selection can be form-driven by numeric inputs. A friendlier interactive selection mechanism can come later.

## Interactive Editing Primitives

Manual live editing still needs shared infrastructure.

Required primitives:

- world ray hit to terrain-local coordinates
- region preview overlay
- brush cursor preview
- pointer drag lifecycle
- localized dirty-chunk update path

These primitives should be built only after rectangular form-based tools exist and the terrain mutation path is stable.

## Heightfield First

`heightfield-terrain` is the right first terrain kind because it supports:

- procedural generation like flat/perlin
- direct local edits
- simple chunking
- practical Bullet integration

Canonical heightfield data should be:

- chunk-based
- sparse-capable
- terrain-local
- independent of Bullet representation

## Bullet Integration

Bullet should sit behind the terrain runtime, not inside the terrain object model.

Rules:

- terrain data is authoritative
- render/physics are derived
- only dirty chunks rebuild

For `heightfield-terrain`, collision can use whichever runtime representation is simplest, as long as:

- it is chunk-local
- it does not force terrain data to mirror Bullet data structures

## Non-Goals

Avoid these in the clean design:

- old `flat-terrain` / `perlin-terrain` object kinds as part of the new path
- persistent operator lists
- persisted tool history
- bake-first authoring workflows
- terrain kind in the generic terrain node label
- embedding many tool forms into the terrain-properties editor
- special fallback compatibility structures in the new model

## Clean Direction

The clean direction from here is:

1. `heightfield-terrain` becomes the only active terrain path for new work.
2. The generic terrain node stays generic.
3. A dedicated heightfield properties editor handles terrain object settings.
4. Terrain tools are listed separately and opened separately.
5. Tools operate on explicit targets.
6. Form-driven rectangular targeting comes before interactive selection.
7. Interactive brush primitives come after the rectangular tool path is clean.
