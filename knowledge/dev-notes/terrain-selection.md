---
type: dev-note
tags:
  - note
---

# Terrain Selection Notes

This note documents the current `heightfield-terrain` selection model, the reasoning behind it,
the bugs and design mistakes encountered while building it, and the cleanup still remaining.

It is intentionally more operational than [[terrain-architecture]].
The goal here is to preserve the implementation context that would otherwise be lost in commit history.

## Current Model

`heightfield-terrain` selection is now built around these rules:

- `heightfield-terrain` owns the persistent selection state and its surface overlay
- terrain tools reuse that shared selection instead of each tool owning a separate overlay
- selection is sample-based, not cell-based
- the overlay shows the affected cell footprint of the selected samples
- rect picking uses an explicit `:terrain-rect-pick` app state
- paint uses a parallel explicit `:terrain-paint` state

The clean split is:

- terrain runtime:
  - owns committed selection
  - owns transient preview selection
  - renders the selection overlay
- scene:
  - answers terrain hit queries
  - answers terrain drag target queries
- tool views / interaction state:
  - initiate picking
  - update preview
  - commit resolved targets back into forms and terrain selection

## Why Selection Is Terrain-Owned

We considered two designs:

1. tool-owned overlays
2. terrain-owned shared selection

The terrain-owned approach won because it provides:

- one source of truth for selection on a terrain
- one reusable visual for multiple tools
- persistent selection even if a tool closes
- support for typed form edits and live picking feeding the same terrain state

This does not mean terrain owns the interaction lifecycle.
It owns only reusable selection state and rendering.

The interaction lifecycle still belongs to explicit app states:

- `terrain-rect-pick-state`
- `terrain-paint-state`

## Why Selection Stayed Sample-Based

We considered changing the model to cell-based selection because it is visually more intuitive.

We kept sample-based selection because it matches the real data model:

- the canonical heightfield stores sample heights
- terrain tools mutate samples
- direct sample access is the more powerful and lower-complexity model

Cell-based selection would mainly improve UX.
It would not improve the canonical data model.
It would also introduce extra interpretation rules around how selected cells map to corner samples.

So the current design is:

- canonical model: samples
- visual overlay: affected cells around those samples

## Current Selection Query Semantics

The current intended rect selection semantics are:

- point hits are real terrain surface hits
- a rectangle target is derived from the terrain-local hit positions
- the selected samples are the samples crossed by the dragged terrain-local interval
- samples are not chosen by nearest-sample endpoint snapping anymore

The relevant query seam is:

- `HeightfieldTerrainQuery.target-between-hits(record, start-hit, end-hit)`

This currently computes the selected sample range from the terrain-local coordinate interval between
the two accepted hits.

That means:

- if the dragged interval crosses a sample position, that sample is selected
- if the dragged interval stays between samples, no sample is selected on that axis

This matches the “cross the sample to include it” model more closely than midpoint snapping.

## Overlay Semantics

We tried two overlay semantics:

1. direct selected sample region
2. affected cell footprint

The direct sample region gave a smaller visual region, but it stopped aligning with the visible grid
and created the false impression that samples were cells.

We reverted to the affected-cell footprint because it is more truthful for a sample-based terrain:

- the selected thing is still samples
- the surface that visibly responds is the surrounding cell footprint

So the current overlay intentionally shows more than a “single little patch” for a single sample.

## Persistent Selection vs Preview

Another important design correction:

- committed selection and transient preview are now separate state

This matters because:

- invalid typed drafts should not destroy committed selection
- cancelling live pick should not destroy committed selection
- preview should be able to come and go without changing what the terrain currently considers selected

Current runtime responsibilities:

- committed selection:
  - persistent until explicitly replaced or cleared
- preview selection:
  - transient, tool-driven, may be cleared on invalid draft or cancel

The overlay renders preview when present, otherwise committed selection.

## Theme Reactivity

The terrain selection overlay is theme-owned, not tool-owned.

That means the runtime must react when the active theme changes while a selection is visible.

This was originally missed.
The overlay now refreshes theme colors through the runtime update seam rather than only when the selection target changes.

## Major Problems Encountered

### 1. Hidden Override Input Routing

The first implementations tried to keep terrain interaction local to tool views via hidden selector/session overrides.

This repeatedly caused:

- normal selection winning instead of terrain picking
- button clicks arming interactions that then immediately died
- weak or misleading input ownership

The clean fix was to move terrain interactions onto explicit app states:

- `terrain-rect-pick`
- `terrain-paint`

That made interaction ownership visible both in code and in runtime behavior.

### 2. Render/Query Transform Mismatch

At one point:

- the terrain render runtime ignored persisted quaternion rotation
- the query path respected it

That meant visible terrain and queried terrain did not match.

This was a real bug and produced selection misses and displaced results.

The fix was to make runtime terrain rendering and terrain query use the same transform interpretation.

### 3. Scene Query vs Runtime Transform Mismatch

Another real bug:

- scene point hits used runtime-transformed terrain query records
- drag-region selection was temporarily using the raw persisted terrain record

That caused the selected region to be offset from the visible terrain.

This has been corrected so drag queries also use the runtime-transformed query record.

### 4. Slow and Wrong Screen-Space Sample Selection

One attempted implementation selected samples by:

- projecting every sample to screen space
- testing whether the projected sample lay inside the drag rectangle

This was a design mistake.

Problems:

- too slow for live drag
- selected by screen projection, not terrain-space drag geometry
- easy to disagree with the actually visible surface

This path has been removed.
Rect selection is back on the terrain-space hit seam.

### 5. Session Handoff / Drag Lifecycle Bugs

Several live bugs were caused by interaction lifecycle mistakes:

- arming a picker on button click, then consuming the same mouse-up as the first picker event
- dropping coalesced motion on mouse-up before flushing it
- requiring exact terrain hit on mouse-down and refusing to recover later in the drag

These were fixed incrementally.
The important lesson is:

- drag capture semantics must be explicit and tested at the real interaction seam

### 6. Tests That Covered the Wrong Seam

Repeatedly, tests passed while live behavior was broken.

The main reasons were:

- tests hit helper seams instead of the real hosted-tool path
- tests compared fast vs exact in a narrower context than the live interaction actually used
- some tests eventually became self-referential because the capture path delegated back into the same scene seam the test used as an oracle

This is now partially improved, but still not fully solved.

## Current Trade-Offs

### Sample-Based Selection vs Cell-Based Selection

Sample-based selection remains the cleaner canonical model because it matches stored data and preserves precision.

Cell-based selection would be easier to explain visually, but mostly improves UX rather than architecture.

The current compromise is:

- keep sample-based selection
- render the affected cell footprint

### Explicit App States vs Hidden Tool Sessions

Explicit app states are heavier than local widget logic, but they are much cleaner for global pointer interactions.

The current design chooses:

- explicit app states for terrain interactions
- terrain-owned reusable selection state

This split is correct.

### Exact Hit Path vs Fast Hit Path

The terrain point-hit path has had several fast/exact issues.
The current working path is the one that is covered and known to behave correctly with the current selection semantics.

The lesson here is:

- never switch live picking to a faster path unless the public seam has parity coverage strong enough to catch the exact regression we care about

## Current Review Findings

As of this note, the current selection path is functional but not yet perfect.

The main remaining design issues are:

1. `HeightfieldTargetCapture` still re-queries `scene:screen-drag-terrain-target(...)` from stored screen positions instead of deriving the target directly from the already accepted hits.

This is redundant and slightly weakens the seam. A cleaner design would use:

- point queries only to obtain accepted hits
- `TerrainQuery.target-between-hits(query-record, start-hit, end-hit)` to derive preview and final target

2. `scene:screen-drag-terrain-target(...)` still has weaker semantics than the live picker.

The live picker currently compensates for:

- pending-start drag promotion
- release with no final hit but a prior valid hit

That behavior is partly in `HeightfieldTargetCapture`, not wholly in the scene seam.

This should be unified.

3. Some interaction tests are still too coupled to shared implementation.

Tests that compare capture output to `scene:screen-drag-terrain-target(...)` are useful as plumbing checks,
but they are not strong enough as behavior oracles if capture itself relies on that same scene seam.

More fixed-fixture tests should sit at the public interaction seam.

## Recommended Cleanup Path

If work continues on terrain selection, the next clean steps should be:

1. Move rect-target derivation in `HeightfieldTargetCapture` to the already accepted hits instead of re-querying from screen positions.
2. Decide whether robust drag semantics belong in:
   - `scene:screen-drag-terrain-target(...)`, or
   - the capture object
   and make that ownership explicit instead of split.
3. Add one or two non-self-referential interaction regressions using fixed fixtures for:
   - promoted-start drag
   - release after the last valid hit
4. Only after that, revisit precision/performance tuning if manual testing still feels rough.

## Modules Involved

Core runtime/query:

- `assets/lua/heightfield-terrain.fnl`
- `assets/lua/heightfield-terrain-selection-overlay.fnl`
- `assets/lua/heightfield-terrain-query.fnl`
- `assets/lua/heightfield-terrain-grid.fnl`
- `assets/lua/scene.fnl`
- `assets/lua/terrain-query.fnl`

Interaction:

- `assets/lua/terrain-rect-pick-state.fnl`
- `assets/lua/terrain-paint-state.fnl`
- `assets/lua/graph/view/terrain-rect-pick-manager.fnl`
- `assets/lua/graph/view/terrain-paint-manager.fnl`
- `assets/lua/graph/view/heightfield-target-capture.fnl`
- `assets/lua/graph/view/heightfield-paint-capture.fnl`

Tool integration:

- `assets/lua/graph/view/heightfield-target-tool-view.fnl`
- `assets/lua/graph/terrain-editor-form-view.fnl`
- `assets/lua/graph/world-data.fnl`

Primary tests:

- `assets/lua/tests/test-terrain-query.fnl`
- `assets/lua/tests/test-demo-browser.fnl`
- `assets/lua/tests/test-graph-view.fnl`
- `assets/lua/tests/test-world-nodes.fnl`


## See also

- [[world-building]], [[terrain-heightfield-system]]
