---
type: dev-note
tags:
  - note
---

# Drawing Architecture

This note defines the first clean drawing system for `space`.

Raster follow-up work is documented separately in [[drawing-raster-implementation]].

Internally the system is called `drawing`. The user-facing canvas feature label can be `Draw`.

## Summary

The first drawing milestone should be:

- world-owned
- canvas-rendered
- graph-independent
- vector-only
- layer-based
- undoable from the start

Graph view and drawing can coexist visually in the same canvas, but only one canvas feature is interactive at a time.

## User Flow

### Canvas Feature Switching

Canvas interaction should have a second axis besides `scene` vs `canvas`.

- `scene` vs `canvas` remains the top-level interaction surface
- inside `canvas`, the active feature is either `graph` or `drawing`

When drawing is active:

- graph remains visible
- graph is not interactive
- drawing owns canvas interactions
- right-drag pan and wheel zoom still work

### HUD Layout

The HUD needs a dedicated left dock layer, separate from tiles and floating panels.

The intended order is:

- narrow canvas feature rail on the far left
- drawing sidebar immediately to its right when drawing is active

The drawing sidebar should contain:

- `Layers` section at the top
- `Tools` section below
- `Tool Defaults` section below that

This should not be implemented as a floating dialog. It is persistent feature chrome for the active world.

### Tool Behavior

The active drawing tool is persistent.

- entering drawing restores the last selected tool
- shape tools stay active until changed
- `Esc` cancels the active gesture only
- leaving drawing happens through the canvas feature rail, not through `Esc`

Initial tools:

- `Select`
- `Rectangle`
- `Ellipse`
- `Line`
- `Pen`
- `Brush`
- `Marker`
- `Eraser`

### Selection Rules

V1 selection is intentionally narrow.

- selection only works in the active layer
- click selects one object
- `Ctrl`+click toggles object membership
- click on empty space clears selection
- multi-select is supported
- marquee selection is deferred
- selected objects can be deleted
- selected objects cannot yet be moved, resized, or restyled

### Layer Rules

Layers are visible from day one.

V1 layer operations:

- add
- rename
- delete
- reorder
- activate

V1 does not include:

- hide
- lock
- grouping

If drawing is entered with no layers, the system auto-creates `Layer 1`.

Deleting a layer is immediate. Undo is the safety mechanism.

## Ownership And Persistence

The world owns drawing, not graph.

Recommended persisted shape:

```text
world
  canvas
    active_feature
  drawing
    document
    ui
```

`drawing.document` is persistent content.

`drawing.ui` is persistent editor state for that world.

This keeps the drawing content independent from transient controller/runtime objects while still restoring the user’s editing context after reload.

### Drawing Content vs UI State

Persist in `drawing.document`:

- layers
- vector objects
- object ids
- layer order

Persist in `drawing.ui`:

- active tool
- active layer
- tool defaults
- possibly selection, if restoring selection is desirable later

Do not store undo/redo stacks in world state.

## Document Model

The first document should support typed layers even though V1 only exposes vector layers.

### Document

```clojure
{:version 1
 :next-layer-id 1
 :next-object-id 1
 :layers [...]}
```

### Layer

```clojure
{:id "layer-1"
 :name "Layer 1"
 :kind "vector"
 :objects [...]}
```

### Common Object Fields

```clojure
{:id "object-1"
 :kind ...
 :style {...}}
```

### Rectangle

```clojure
{:id "object-1"
 :kind "rectangle"
 :x 10
 :y 20
 :w 80
 :h 50
 :style {...}}
```

### Ellipse

```clojure
{:id "object-2"
 :kind "ellipse"
 :x 10
 :y 20
 :w 80
 :h 50
 :style {...}}
```

### Line

```clojure
{:id "object-3"
 :kind "line"
 :x1 10
 :y1 20
 :x2 80
 :y2 120
 :style {...}}
```

### Stroke

```clojure
{:id "object-4"
 :kind "stroke"
 :preset "pen"
 :points [[10 20] [11 21] [13 24]]
 :style {...}}
```

`pen`, `brush`, and `marker` should share the same persistent stroke model.

They differ by:

- default style presets
- rendering semantics

They should not use three unrelated data models.

## Style Model

V1 style controls are creation defaults only.

They are not an inspector for selected objects.

Recommended default fields:

- stroke color
- fill color
- thickness
- opacity
- filled?
- outline?

Typical behavior:

- tool defaults are edited in the sidebar
- new objects copy those defaults at creation time
- later object styling changes will operate on object-local style

## Controller Model

Drawing needs a dedicated controller/runtime layer, not just raw document tables.

The controller should own:

- active?
- active layer id
- current tool
- current defaults
- current selection ids
- current hover target
- undo stack
- redo stack

It should also expose high-level operations:

- add object
- delete selected
- add layer
- rename layer
- delete layer
- reorder layer
- activate layer
- begin gesture
- cancel gesture
- undo
- redo

The controller is the main integration point for UI buttons, keybindings, and gesture states.

## Input And State Model

Global app states should not explode into drawing variants.

Keep:

- `normal`
- `leader`
- `camera`
- `fpc`

Add drawing-specific temporary capture only for active gestures.

Recommended pattern:

- a `drawing-gesture-manager`
- one `drawing-gesture-state`

This should mirror the existing terrain paint / rect-pick pattern:

- controller decides a gesture should begin
- gesture manager records previous state
- app enters the temporary drawing gesture state
- gesture consumes left-button drawing input
- gesture completion or cancel restores the previous state

The temporary gesture state should be used for:

- rectangle drag
- ellipse drag
- line drag
- freehand stroke
- eraser drag

It should not be used just because drawing is active.

## Selection And Hit Testing

Do not build V1 drawing selection on top of the current `ObjectSelector`.

`ObjectSelector` is box-oriented and expects a single projected position per selectable. That is the wrong primitive for shapes and strokes.

Drawing needs its own active-layer hit testing:

- rectangle / ellipse hit test
- line hit test with tolerance
- stroke hit test against sampled segments

Selection tolerance should be computed in canvas world units from `canvas.world-units-per-pixel`, so hit behavior stays stable across zoom levels.

Eraser should use the same hit-test machinery but collect touched objects continuously during the drag.

V1 eraser semantics:

- erase whole touched objects
- no partial stroke cutting yet

## Undo / Redo Model

Undo/redo must be designed in from the beginning.

It should be drawing-local, not shared with graph or other systems.

Use explicit commands with `apply` and `revert`.

Recommended command kinds:

- `add-object`
- `delete-objects`
- `add-layer`
- `rename-layer`
- `delete-layer`
- `reorder-layer`

Rules:

- one completed gesture = one history entry
- one layer operation = one history entry
- layer deletion must restore the layer, its contents, and its original order on undo
- active-layer changes are controller state, not history entries

Undo/redo stacks are runtime state only.

## Rendering Model

Drawing should render directly into the canvas build context.

This allows:

- graph and drawing to coexist visually
- drawing to share the existing canvas camera and projection
- no special offscreen drawing surface for V1 vector work

### Important Constraint

The current line renderer is not sufficient for thick drawing strokes.

V1 should not rely on plain GL lines for committed drawing geometry except possibly temporary debug previews.

Recommended render approach:

- rectangles and filled ellipses: quad / triangle geometry
- outlines: triangle ribbons or cached outline geometry
- lines: triangle ribbons
- strokes: triangle ribbons built from adjacent sampled points
- selection highlight: separate higher-depth overlay geometry
- live previews: same geometry path as committed objects when practical

This gives consistent thickness and makes future styling easier.

## Canvas Feature Gating

Canvas needs feature-specific pointer targets.

There are two problems to solve:

- graph and drawing both live on the canvas
- only the active canvas feature should be interactive

Recommended approach:

- keep the real canvas render target unchanged
- introduce feature-specific pointer targets that delegate `screen-pos-ray` to the canvas
- objects registered by graph use the graph target
- objects registered by drawing use the drawing target
- pointer enablement checks decide which target is currently interactive

This keeps visual coexistence while giving clean interaction exclusivity.

## Module Plan

Recommended new modules:

- `assets/lua/drawing/document.fnl`
- `assets/lua/drawing/defaults.fnl`
- `assets/lua/drawing/controller.fnl`
- `assets/lua/drawing/history.fnl`
- `assets/lua/drawing/commands.fnl`
- `assets/lua/drawing/hit-test.fnl`
- `assets/lua/drawing/render.fnl`
- `assets/lua/drawing/sidebar-view.fnl`
- `assets/lua/drawing/feature-rail-view.fnl`
- `assets/lua/drawing-gesture-state.fnl`
- `assets/lua/drawing-gesture-manager.fnl`

Likely integration changes:

- `assets/lua/home-world.fnl`
- `assets/lua/main.fnl`
- `assets/lua/hud-layout.fnl`
- `assets/lua/hud-control-panel-layout.fnl`

## Implementation Order

### Phase 1

- add drawing state defaults to world persistence
- add world runtime creation for drawing controller/runtime
- add canvas active feature state
- add left HUD dock support
- add feature rail with `Graph` and `Draw`

### Phase 2

- add drawing document model
- add layers UI
- add tool defaults UI
- persist active tool and defaults in world UI state

### Phase 3

- add drawing-local history
- add select and delete
- add active-layer-only hit testing
- add selection highlight

### Phase 4

- add rectangle, ellipse, and line creation with live preview
- add shift-constrained creation
- commit one history entry per completed gesture

### Phase 5

- add pen, brush, and marker as stroke presets over shared stroke objects
- add eraser drag that deletes whole touched objects

## Explicitly Deferred

These are out of scope for V1:

- raster layers
- hidden layers
- locked layers
- groups
- marquee selection
- move / resize editing
- selected-object style editing
- partial stroke erasing
- snapping
- graph integration of drawing content
- SVG import/export

## Core Decisions

These decisions are now fixed for the first implementation:

- use the internal name `drawing`
- drawing is world-owned
- one drawing document per world
- typed layers from the start, vector only in V1
- visible layers from day one
- selection only in the active layer
- creation defaults only, no selected-object style editing in V1
- graph and drawing coexist visually but only one is interactive
- undo/redo is drawing-local


## See also

- [[stylus-drawing-input]]
