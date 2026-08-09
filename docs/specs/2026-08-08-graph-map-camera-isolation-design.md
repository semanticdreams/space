# Graph Map Camera Isolation Design

## Context

Graph and Board are canvas-backed activities. Moving the camera in one activity must not affect the other, yet user behavior shows camera state can leak between activities. Separately, Graph currently has only one activity-level camera keyed as `"graph"`, so every graph map shares a single graph camera. Users expect each graph map to remember its own view.

Existing architecture already supports per-activity canvas slots and cameras. `Board` uses the `"board"` activity camera, and `Graph` uses the `"graph"` activity camera. Graph map switching already captures per-map graph view state, but not camera state.

## Goals

- Preserve strict Board-vs-Graph camera isolation: moving Board must not move Graph, and moving Graph must not move Board.
- Give each graph map its own camera transform.
- Persist per-graph-map camera state across world/app reload.
- Save the active graph map camera before graph map switches, graph activity deactivation, world save/session snapshot, and graph view teardown paths that can otherwise lose the latest camera transform.
- Restore the target graph map camera when switching to or reloading that map.
- For a graph map with no persisted camera state, initialize camera position predictably:
  - if a first/start node point is already present, center it as if the user selected/clicked it from the node list;
  - if the camera exists before the first node point is added, start from the identity/default camera and center the first added node point once;
  - do not auto-center successive nodes after the first automatic centering.
- Cover the behavior with focused activity, graph map, graph view persistence, and camera-state tests.

## Non-Goals

- No camera state in graph core topology. `Graph` persists topology only.
- No camera state on individual graph nodes or backing domain stores.
- No Board-specific redesign beyond adding regression coverage that Board and Graph do not share cameras.
- No simultaneous multi-map rendering or multiple visible Graph maps.
- No graph map duplication camera semantics beyond the new-map default policy.
- No broad `CanvasControls` rewrite unless evidence shows stable camera transform restoration cannot preserve control correctness.

## Root Cause Summary

Read-only investigation found:

- Canvas activity cameras are keyed by activity id in `runtime.activity-cameras.canvas[activity-id]`.
- Graph activation obtains one camera with `ensure-activity-canvas-camera! runtime "graph"` and installs it into the graph canvas slot.
- Board activation obtains a separate `"board"` camera in the intended path.
- Graph map switching captures per-map graph view state keyed by map id, but camera state is captured only as a single Graph activity `canvas-camera`.
- Therefore every graph map shares the same live graph activity camera and persisted graph activity camera state.

The activity-sharing symptom should be covered with an explicit Board/Graph regression. If the regression exposes aliasing or stale control bindings, the fix should address that path directly rather than masking it with graph-map camera persistence.

## Chosen Approach

Use **per-graph-map persisted camera metadata with stable graph slot camera objects**.

The graph canvas slot continues to own the live `Camera` object and controls. Graph activity restores map-specific transforms onto that stable object when the active graph map changes. This avoids stale `CanvasControls` bindings while keeping graph map navigation state independent.

Persisted camera state belongs with graph-map interaction/view metadata, not graph topology or domain data. The existing graph view persistence metadata file is the natural boundary because it already stores per-map view state such as positions, presentations, sizes, and panels.

## Architecture

### Activity camera isolation

Board and Graph must use distinct activity camera entries and distinct canvas slots. Tests should verify object identity and transform independence across Board→Graph→Board switching.

If controls are reused, they must remain bound to the correct activity camera. The preferred implementation keeps one stable live camera per activity slot and restores transforms into that camera rather than swapping camera objects behind controls.

### Per-graph-map camera persistence

Graph view persistence should expose camera accessors:

- read optional saved camera state for the map;
- write the current captured camera state for the map;
- preserve existing metadata keys.

Use the same camera serialization semantics as existing activity camera state. Malformed persisted camera data should fail loudly with an explicit error.

### Map switching data flow

When the active graph map is about to change:

1. capture the current graph slot camera transform;
2. write it to the current map's persistence metadata;
3. capture/drop the current graph view as existing map-switch code already does.

When the target graph map becomes active:

1. activate/rebuild the graph view for the target map;
2. if that map has persisted camera state, restore it into the live graph slot camera;
3. otherwise apply the one-shot initial centering policy.

### New-map initial centering policy

For maps with no saved camera:

- If the first/start node point exists at activation time, center that point using the same semantics as graph node reveal/list selection.
- If no point exists yet, leave the camera at the identity/default camera and register a one-shot pending initial center. The first added node point consumes the pending center and recenters the camera once.
- After the first automatic center, do not recenter later nodes automatically.

This policy gives new maps a useful starting view without fighting user navigation as content grows.

### Persistence timing

Camera state must be captured before any operation that can lose the live graph view/camera context:

- graph map switch;
- graph activity snapshot/deactivation;
- graph view drop/teardown paths used by theme changes and activity changes;
- world save/session capture.

## Error Handling

- Missing required graph activity runtime, graph map manager, graph map, graph view persistence, or graph slot camera should fail loudly.
- Malformed persisted camera state should fail with an explicit message naming the map/camera field.
- Absence of camera state for a map is not an error; it triggers the default/one-shot initial centering policy.

## Testing

Focused tests should cover:

- Board and Graph activity cameras are separate objects and moving one does not mutate the other.
- Graph map A and graph map B maintain independent camera transforms during map switching.
- Per-map camera state persists to map metadata and survives reload/session restore.
- A graph map with an existing first/start node and no saved camera centers that node on activation.
- A graph map whose camera exists before first node insertion starts at identity/default, then centers the first added node once and does not recenter later nodes.
- Malformed persisted camera state fails loudly.

Validation should run Space-native Fennel compile checks, constraints, focused camera/activity/graph map tests, and a broader suite because activity switching and persistence affect shared runtime behavior.

## Risks and Mitigations

- **Stale controls after camera restore:** restore transforms into the stable graph slot camera rather than replacing the object unless evidence requires a broader controls fix.
- **Overwriting map camera too late:** capture camera before map-switch teardown and during snapshot/deactivation.
- **Graph doctrine violation:** keep camera in map interaction/view metadata, not graph topology or node/domain stores.
- **Annoying auto-centering:** make initial centering one-shot only for maps without saved camera state.
