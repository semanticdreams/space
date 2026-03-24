# Heightfield Terrain Implementation Plan

This note turns the terrain architecture into a concrete implementation order.

The goal is to move to the clean model:

- one real terrain object path for new work: `heightfield-terrain`
- one generic terrain object in the graph
- one terrain-properties editor for `heightfield-terrain`
- separate terrain tools
- form-based region targeting first
- interactive selection and brushes later

## Immediate Corrections

Before building more tools, the graph model should be corrected.

Required corrections:

1. The generic terrain node must stop using terrain kind as its label.
2. The `heightfield-terrain` editor must become a terrain-properties editor only.
3. `Initialize Flat` and `Apply Perlin` must move out of the terrain-properties editor and become terrain tools.
4. Old `flat-terrain` and `perlin-terrain` terrain-object integration should be removed from the new path.

Those are structural fixes, not optional cleanup.

## Target Runtime and Data Model

The canonical terrain record should remain final chunked heightfield data.

Suggested persistent shape:

```fennel
{:id "<uuid>"
 :name "terrain"
 :kind "heightfield-terrain"
 :transform
 {:position [0 0 0]
  :rotation [1 0 0 0]}
 :appearance
 {:opacity 1.0
  :material nil}
 :physics
 {:enabled true}
 :domain
 {:sample-spacing [1 1]
  :chunk-samples [33 33]
  :default-height 0}
 :chunks
 [{:coord [0 0]
   :heights [0 0 0 ...]}]}
```

Notes:

- `name` belongs on the terrain object, not inferred from kind.
- `transform`, `appearance`, `physics`, and `domain` should become explicit sections instead of a catch-all options blob.
- `coord` should allow negative terrain-local chunk coordinates.
- the canonical model stays chunk-based and final-data-based

The current code does not need to reach this exact schema in one jump, but all new work should move toward it.

## Graph Structure

The graph should be terrain-centered and simple.

Recommended shape:

- `Terrains`
- `Terrain`
- `Terrain Properties`
- `Terrain Tool`

Meaning:

- `Terrain` is the generic object node
- `Terrain Properties` is the kind-specific object editor
- `Terrain Tool` is an invoked tool UI for one terrain

The `Terrain` node view should show:

- name
- kind
- summary of transform/domain/appearance/physics
- searchable list of tools available for the terrain kind

The `Terrain` node should not directly embed tool forms.

## Heightfield Terrain Properties Editor

`heightfield-terrain` needs a dedicated properties editor node/view.

It should own only object properties:

- name
- position
- rotation
- sample spacing
- chunk sample size
- appearance settings
- physics settings

Not tool actions.

This editor should behave like a normal record editor:

- validate
- enable `Apply` only when dirty
- update active scene terrain in place

## Tool Registry

Add a dedicated tool registry for terrain kinds.

For `heightfield-terrain`, initial tool list:

- `Initialize Flat`
- `Apply Perlin`

Later:

- `Flatten Region`
- `Raise`
- `Lower`
- `Smooth`

The terrain view should use this registry to populate a searchable list of tools.

Clicking one tool should open that tool’s dedicated node/view.

## Tool Nodes and Views

Each tool should own:

- its params
- its target mode
- its validation
- its apply behavior

The tool node is not a terrain object. It is a UI/action node scoped to one terrain.

First tool nodes:

- `heightfield-flat-tool`
- `heightfield-perlin-tool`

Each node should reference:

- world id
- terrain id
- tool name

## Tool Button Semantics

Tool UIs should not behave like record editors.

For tool nodes:

- `Apply` is enabled whenever the tool is valid
- it remains enabled after apply
- it may keep the last-used params in local view state

That gives the correct behavior for tools like perlin, where repeated apply with the same params is useful.

## Target Region Model

All terrain tools should take a target.

First supported target modes:

- `whole`
- `rect`

Suggested representation:

```fennel
{:mode :whole}
```

and

```fennel
{:mode :rect
 :x0 0
 :z0 0
 :x1 128
 :z1 128}
```

Interpretation:

- local terrain-space coordinates
- axis-aligned rectangle
- normalized by the tool validation layer before apply

This region model should be shared across heightfield tools.

## First Tool Forms

For now, region selection should be form-driven.

That means:

- whole-terrain toggle or selector
- rectangle coordinate inputs

Example perlin tool form:

- target mode
- rectangle bounds if `:rect`
- seed
- `n1div`
- `n2div`
- `n3div`
- `n1scale`
- `n2scale`
- `n3scale`
- `zroot`
- `zpower`
- `Apply`

Example flat tool form:

- target mode
- rectangle bounds if `:rect`
- target height
- `Apply`

This is enough to prove the target model and the data mutation path before building friendlier selection UI.

## Shared Data Mutation API

Terrain data helpers should move to explicit target-aware APIs.

Recommended first write surface:

- `apply-flat!(record target params)`
- `apply-perlin!(record target params)`

Lower-level support:

- iterate samples in target region
- ensure touched chunks exist
- mutate touched samples
- return touched chunk coordinates

Scene/runtime sync should then rebuild only affected chunks.

Even if chunk-local rebuild is not fully implemented yet, the API should already report touched chunks so the runtime can evolve cleanly.

## Interactive Selection Later

After form-based rectangle tools exist and feel stable, add selection primitives:

- terrain hit query from cursor
- rectangular drag preview in world space
- brush cursor preview
- drag lifecycle

Those primitives should feed the same target model:

- drag rectangle produces `{:mode :rect ...}`
- brush stroke later produces `{:mode :brush ...}`

Do not build a separate parallel targeting system.

## Delivery Order

Recommended order from here:

### Slice 1: Graph cleanup

- generic terrain node label becomes generic again
- generic terrain node view shows tool list, not embedded tool forms
- add dedicated `heightfield-terrain` properties editor
- remove old `flat-terrain` / `perlin-terrain` terrain-object integration from the active terrain path

### Slice 2: Tool registry and tool nodes

- add terrain tool registry
- add searchable tools list for `heightfield-terrain`
- add dedicated flat tool node/view
- add dedicated perlin tool node/view
- keep tool apply re-clickable

### Slice 3: Region-aware data APIs

- target model
- flat whole/rect apply
- perlin whole/rect apply
- validation and tests

### Slice 4: Heightfield properties coverage

- name
- transform
- domain settings
- appearance
- physics

### Slice 5: Interactive selection primitives

- world hit query
- rectangle selection preview
- brush preview

### Slice 6: First interactive edit tool

- `Raise/Lower` or `Flatten`

## Tests Needed

New tests should cover:

### Graph semantics

- generic terrain node label stays generic
- terrain view lists tools
- tool click opens dedicated tool node

### Tool semantics

- tool apply stays enabled when valid after apply
- tool keeps last-used params locally
- tool validate/apply paths work for both `:whole` and `:rect`

### Data semantics

- rectangular target only changes intended samples
- untouched chunks remain unchanged
- negative chunk coordinates still work

### Properties editor semantics

- terrain properties are editable independently of tools
- active scene terrain updates in place

## What Not To Do

Do not continue with:

- tool forms inside the heightfield terrain editor
- treating old `flat-terrain` / `perlin-terrain` object kinds as part of the new path
- whole-terrain-only tool APIs as the long-term surface
- building brush UI before target-aware form tools exist

## Next Concrete Step

The next implementation step should be:

1. fix the generic terrain node label and semantics
2. split the current `heightfield-terrain` editor into:
   - terrain-properties editor
   - dedicated flat/perlin tool nodes
3. add the shared whole/rect target form model

That is the smallest clean step that aligns the code with the intended terrain design.
