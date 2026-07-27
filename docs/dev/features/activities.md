# Space Activities Architecture

## Purpose

This document specifies the migration from canvas-specific modes to HomeWorld activities.

The current `canvas-modes` system started as a way to switch behavior inside the canvas, but it now controls much more than canvas rendering. It installs input handlers, root actions, selection actions, HUD dock content, command hints, context enrichment, update hooks, and active graph/drawing/board runtime objects.

That makes `canvas mode` the wrong abstraction. The next architecture should model these workflows as world-provided activities.

The design goal is a clean migration, not a compatibility layer.

Acceptance requirements:

- Existing graph, drawing, and board canvas modes are migrated into HomeWorld activities.
- Existing persisted data is migrated into the new activity and surface state layout.
- Existing runtime APIs and tests are migrated to activity terminology.
- No long-term compatibility aliases, fallbacks, duplicate old/new fields, or shim APIs are introduced.
- The final runtime should not keep `canvas-mode` concepts as first-class names.
- Activity switches must be instantaneous in normal use.
- Activities are world-specific. HomeWorld provides activities; another world may provide different activities or no activity system at all.

## Terminology

### World

A world owns durable world state and decides what runtime model it exposes.

HomeWorld exposes activities. Other worlds may expose different activity sets or no activity concept.

Activities live inside the currently active world. An activity can trigger a world switch as part of its own behavior, such as a portal widget, but activity identity is not app-global.

### Activity

An activity is a top-level user workflow inside a world.

Examples:

- `graph`
- `drawing`
- `board`
- future `world-edit`
- future `terminal-workbench`
- future combined workflows that compose graph, drawing, and board concepts internally

An activity owns workflow-specific runtime state, input behavior, actions, and surface content.

An activity may use any subset of available surfaces. It may use scene only, canvas only, HUD only, scene plus canvas, all surfaces, or no visible surface beyond global shell UI.

### Surface

A surface is a retained render/input capability provider owned by the world runtime.

HomeWorld surfaces currently include:

- `scene`
- `canvas`
- `hud`

Surfaces provide building blocks, not workflow semantics.

Examples of surface responsibilities:

- Build contexts and render buffers.
- Projection and screen-ray helpers.
- Layout roots.
- Focus scope integration.
- Pointer target identity.
- Panel mounting primitives.
- Surface-specific services such as scene camera, canvas camera, object selector, and render helpers.

A surface must not know about graph, drawing, board, or other activity-specific concepts.

### Activity Surface Slot

An activity surface slot is a retained per-activity content boundary inside a surface.

Each activity can have at most one slot per surface.

Examples:

- graph activity canvas slot
- drawing activity canvas slot
- board activity canvas slot
- future world-edit scene slot

If a future activity wants to combine graph and drawing, it composes those concepts inside its own activity slots. The surface does not compose multiple activity slots for it.

The slot exists to provide isolation:

- Inactive activity draw data must not render.
- Inactive activity interaction targets must not receive input.
- Activity content can be retained without leaking into active surfaces.
- Switching activities can be instantaneous because content is hidden/deactivated, not rebuilt.

### Activity Host

The activity host is a HomeWorld runtime component that owns activity registration, active activity switching, retained activity sessions, and activity lifecycle coordination.

Responsibilities:

- Register HomeWorld activity specs.
- Track active activity id.
- Retain activity sessions.
- Activate/deactivate activities.
- Coordinate activity surface slots.
- Apply active activity input/action/update hooks.
- Apply active activity HUD contributions.
- Persist active activity id and activity-owned state.

### Surface Host

The surface host is a HomeWorld runtime component, or a coherent set of APIs on the existing surfaces, that manages activity surface slots.

Responsibilities:

- Create a surface slot for an activity.
- Return existing retained slots.
- Activate the active activity's slot for each surface.
- Deactivate inactive slots.
- Ensure surfaces expose only active slot draw data.
- Ensure input routing rejects inactive slots.

The first implementation does not need a broad generic compositor. It only needs one active slot per surface.

## Current Seams

### Canvas Modes Are Already App Behavior Controllers

`assets/lua/canvas-modes.fnl` owns the current registry and active mode lifecycle.

Current mode hooks include:

- `app.canvas-mode-root-actions`
- `app.canvas-mode-selection-actions`
- `app.canvas-mode-left-dock-builder`
- `app.canvas-mode-command-hints-provider`
- `app.canvas-mode-delete-selection`
- `app.canvas-mode-activate-focused`
- `app.canvas-mode-drawing-enabled?`
- `app.canvas-mode-context-enricher`
- `app.canvas-mode-input-handlers`
- `app.canvas-mode-target-enabled?`
- `app.canvas-mode-update`

These hooks are not canvas-only. They affect input routing, context menus, command hints, per-frame updates, HUD composition, and selected runtime objects.

### Rendering Uses Retained Global Surfaces

`assets/lua/renderers.fnl` currently renders in fixed order:

- scene
- canvas
- HUD

The renderer already tolerates missing scene/canvas/HUD by skipping nil targets, but it assumes the global `app.scene`, `app.canvas`, and `app.hud` are the mounted render targets.

This design keeps that order and keeps retained HomeWorld surfaces. Activities do not replace `app.scene` or `app.canvas`; they provide the active content slots that those surfaces expose.

### Build Context Is The Major Isolation Seam

`assets/lua/build-context.fnl` owns vectors, batches, text sources, quad sources, image batches, mesh batches, focus data, and pointer target references.

Current canvas activity content shares one canvas build context. That prevents safe retained inactive activities because inactive graph/drawing/board draw data would continue to exist in the shared buffers.

Activity surface slots must therefore provide slot-local build contexts or equivalent isolated draw sources.

### Scene Is Currently Monolithic

`assets/lua/scene.fnl` currently has one attached root entity through `self.entity` and methods like `build-default`, `attach-entity`, `capture-state`, and `restore-state` are shaped around that one root.

Scene also owns or exposes world-level concepts:

- terrain records
- lights
- skybox
- background
- scene panels
- physics bodies
- scene object registration

For activities, scene should remain a retained surface, but it needs per-activity scene slots so wildly different scene content can be retained and switched instantly.

World-level scene state can remain world-level. Activity-owned scene content should live in activity slots and activity session state.

### Canvas Is Closer But Still Shared

`assets/lua/canvas.fnl` already uses `FloatLayer` for floating panels and provides projection, screen-ray, layout, and panel persistence helpers.

Current graph/drawing/board content is not isolated by activity:

- Graph view writes directly to the canvas build context vectors and registries.
- Drawing render writes directly to the canvas build context vectors and image batches.
- Board view creates a `FloatLayer`, but attaches it directly to `canvas.layout-root` and uses the shared canvas context.

Canvas needs activity surface slots before graph/drawing/board can be retained safely.

### HUD Already Matches The Model Best

HUD is already a retained shell with contributions:

- control panel content
- status panel content
- left dock
- right dock
- overlays
- floating/tiled panels

The activity switcher should be system-owned by HomeWorld, not activity-owned. Activities can contribute adjacent HUD content but cannot replace the activity switcher itself.

### Input Routing Is Surface-Oriented

Input currently routes through active interaction surface and pointer target checks.

Important current fields:

- `app.preferred-interaction-surface`
- `app.active-interaction-surface`
- `app.scene-interactive?`
- `app.canvas-interactive?`
- `app.canvas-visible?`
- `app.active-pointer-controls`
- `app.pointer-target-enabled?`

Activity migration should keep the surface-oriented input model, but route through active activity slots and renamed activity hooks.

## Target Runtime Shape

HomeWorld runtime should contain retained shared services and retained surfaces:

```fennel
{:camera camera
 :canvas-camera canvas-camera
 :scene scene
 :canvas canvas
 :activity-host activity-host
 :active-activity-id nil
 :activity-sessions {}
 :graph graph
 :graph-map-manager graph-map-manager
 :drawing-controller drawing-controller
 :world-dir world.dir}
```

The app globals remain mounted surface aliases for the active world:

```fennel
app.scene
app.canvas
app.hud
app.active-activity-id
app.active-interaction-surface
```

Activity-specific globals should be minimized. Where app-level references are still useful for existing code, use activity-oriented names, not canvas-mode names.

Examples:

```fennel
app.activity-root-actions
app.activity-selection-actions
app.activity-command-hints-provider
app.activity-context-enricher
app.activity-input-handlers
app.activity-target-enabled?
app.activity-delete-selection
app.activity-activate-focused
app.activity-update
```

No old `app.canvas-mode-*` fields should remain in the final migrated code.

## Activity Spec

An activity spec should be a registered table:

```fennel
{:id "graph"
 :label "Graph"
 :icon "account_tree"
 :show-in-switcher? true
 :activate activate-graph-activity!
 :deactivate deactivate-graph-activity!
 :snapshot snapshot-graph-activity!
 :restore restore-graph-activity!}
```

Required fields:

- `:id`
- `:activate`

Switcher-visible activities also require:

- `:label`
- `:icon`
- `:button-name` or a replacement canonical UI id

Optional fields:

- `:deactivate`
- `:snapshot`
- `:restore`
- `:show-in-switcher?`

Activity ids are world-local. The id `graph` in HomeWorld does not imply another world has a graph activity.

## Activity Context

Activation receives an activity context that stages hooks and cleanup.

The current `canvas-modes` activation staging pattern is good and should be preserved with activity names.

Context API:

```fennel
ctx:defer-cleanup!
ctx:clear-runtime-hooks!

ctx:set-root-actions!
ctx:set-selection-actions!
ctx:set-command-hints-provider!
ctx:set-delete-selection!
ctx:set-activate-focused!
ctx:set-context-enricher!
ctx:set-input-handlers!
ctx:set-target-enabled!
ctx:set-update!

ctx:set-preferred-interaction-surface!
ctx:set-surface-state!

ctx:set-hud-left-dock-builder!
ctx:set-hud-control-panel-body!
ctx:set-hud-status-panel-body!
ctx:set-hud-overlay!
```

The context should expose surface slot helpers:

```fennel
ctx:scene-slot
ctx:canvas-slot
ctx:hud
```

Or explicit methods:

```fennel
ctx:ensure-surface-slot! :scene
ctx:ensure-surface-slot! :canvas
```

Activity code should build its content into its own slot contexts rather than directly into `app.scene.build-context` or `app.canvas.build-context`.

## Activity Surface Slots

Each surface slot provides an isolated activity content boundary.

Minimal slot shape:

```fennel
{:activity-id "graph"
 :surface :canvas
 :ctx build-context
 :layout-root layout-root
 :root nil
 :visible? false
 :interactive? false
 :update update
 :activate activate
 :deactivate deactivate
 :drop drop}
```

Slot responsibilities:

- Own slot-local render buffers or batch sources.
- Own slot-local layout root or a retained root under the surface layout.
- Provide pointer target identity where needed.
- Allow activity content to be retained while inactive.
- Hide inactive draw data from surface draw APIs.
- Disable inactive input targets.

Slot APIs should be narrow:

```fennel
(surface:ensure-activity-slot "graph")
(surface:activity-slot "graph")
(surface:activate-activity-slot "graph")
(surface:deactivate-activity-slot "graph")
(surface:drop-activity-slot "graph")
```

Each surface should expose only the active slot's draw data from render target methods such as:

- `get-triangle-vector`
- `get-triangle-batches`
- `get-line-vector`
- `get-point-vector`
- `get-image-batches`
- `get-quad-draw-list`
- `get-text-ssbo-draw-list`
- `get-mesh-batches`
- `get-instanced-color-mesh-batches`

The first implementation should support one active slot per surface. Multi-slot composition should not be built until a real activity needs it.

## Surface Policies

Activities can request surface state:

```fennel
{:scene {:visible? true
         :interactive? false}
 :canvas {:visible? true
          :interactive? true}
 :hud {:visible? true
       :interactive? true}
 :preferred-interaction-surface :canvas}
```

Surface state controls visibility and interaction. It does not control renderer order in the first migration.

Initial renderer order remains:

- scene
- canvas
- HUD

Visibility gates can be explicit:

```fennel
app.scene-visible?
app.canvas-visible?
app.hud-visible?
```

If `hud-visible?` is not needed immediately, HUD can remain always visible. Scene and canvas should still have explicit activity-controlled visibility because activities may not use them.

## Activity Switching

Activity switching must be instantaneous.

That implies retained activity sessions by default.

Switch sequence:

1. Snapshot current active activity session.
2. Deactivate current activity hooks and surface slots.
3. Keep activity session objects alive.
4. Resolve or create the next activity session.
5. Activate next activity surface slots.
6. Apply next activity hooks.
7. Apply next activity HUD contributions.
8. Apply preferred interaction surface and surface visibility/interactivity.
9. Persist active activity id into HomeWorld state.
10. Emit workspace shell changed signal.

Deactivation must not drop retained activity content unless the world is dropping, hot reload requires it, or the activity explicitly destroys its own session.

This requires replacing the current graph/board/drawing pattern where deactivation drops the view.

New lifecycle distinction:

- `deactivate`: hide and unregister live interactions, retain session.
- `drop`: destroy session and release resources.

Existing `drop` behavior stays as final cleanup, not normal activity switch behavior.

## Graph Activity

Current graph mode creates `GraphView` directly against `runtime.canvas.build-context` and drops the graph view on deactivate.

Target graph activity behavior:

- Ensure graph canvas slot.
- Create `GraphView` once per retained activity session.
- Build graph view against graph canvas slot context.
- Retain graph view on activity switch.
- Deactivate graph slot and unregister graph interactions while inactive.
- Reactivate graph slot and interactions on switch back.
- Continue to expose graph map sidebar through activity HUD contribution.

Graph activity should own graph-specific canvas content. It may also request scene content later, such as graph node cubes, through its scene slot or explicit scene panel APIs.

Graph map manager and graph core remain HomeWorld shared services.

## Drawing Activity

Current drawing mode enables drawing input and uses a shared `DrawingRender` created by canvas runtime.

Target drawing activity behavior:

- Ensure drawing canvas slot.
- Create or retain drawing render in the drawing activity session.
- Build drawing render against drawing canvas slot context.
- Install drawing input handlers only while active.
- Expose drawing sidebar through activity HUD contribution.
- Retain drawing controller as HomeWorld shared state unless a future activity needs an independent drawing document.

The drawing controller can remain world-owned because drawing data is durable HomeWorld state. The drawing activity owns the active drawing presentation and workflow controls.

## Board Activity

Current board mode creates `Board` and `BoardView`, then drops them on deactivate.

Target board activity behavior:

- Ensure board canvas slot.
- Create or restore board session once.
- Build board view against board canvas slot context.
- Retain board view and board state on activity switch.
- Deactivate board slot and unregister board interactions while inactive.
- Drop only on world drop, hot reload, or explicit cleanup.

Board state should move out of canvas-mode-specific runtime fields and into board activity session or world durable state as appropriate.

## Scene Activity Slots

Scene activity slots are needed for activities that want wildly different 3D scene content or no scene content.

The first graph/drawing/board migration may not need complex scene content, but the architecture should make scene slots real, not theoretical.

Scene shared state should remain separate:

- lights
- skybox
- background
- shared terrains, if they are considered HomeWorld world state

Activity-owned scene slot state should include activity-specific roots and panels.

Potential state split:

```fennel
:scene {:shared {:lights ...
                 :skybox ...
                 :background ...
                 :terrains ...}
        :activity-slots {"graph" {...}
                         "drawing" {...}}}
```

If terrain/world editing is an activity, terrain presentation and editing widgets may belong to that activity while terrain records remain world data.

## HUD Contributions

HomeWorld owns the activity switcher.

Activities may contribute:

- left dock body beside the switcher
- control panel body
- status panel body
- overlays
- command hints

Activities may not replace the activity switcher.

Rename current `CanvasModeDockView` to an activity-oriented system-owned view, such as:

- `activity-dock-view.fnl`
- `activity-switcher-view.fnl`

Recommended name: `activity-dock-view.fnl`, because it contains both switcher rail and active activity dock body.

## Persistence

Current HomeWorld default state includes:

```fennel
:canvas {:camera {:position [0 0 100]}
         :scale_factor 1.0
         :active_mode nil
         :preferred_interaction_surface "scene"
         :panels []}
```

Target state should move active workflow data out of canvas:

```fennel
:activity {:active_id nil
           :preferred_interaction_surface "scene"
           :sessions {}}

:canvas {:camera {:position [0 0 100]}
         :scale_factor 1.0
         :panels []}
```

Scene, canvas, and HUD keep surface-specific state. Activities keep workflow state.

Possible complete HomeWorld state shape:

```fennel
{:camera {:position [0 0 30]
          :rotation [1 0 0 0]}

 :activity {:active_id "graph"
            :preferred_interaction_surface "canvas"
            :sessions {"graph" {...}
                       "drawing" {...}
                       "board" {...}}}

 :scene {:shared {:panels []
                  :terrains []
                  :lights ...
                  :skybox ...
                  :background ...}
         :slots {}}

 :canvas {:camera {:position [0 0 100]}
          :scale_factor 1.0
          :panels []
          :slots {}}

 :hud {:panels []}

 :drawing ...
 :graph ...
 :board ...
 :physics ...}
```

The exact session payloads should be defined by each activity.

Migration requirement:

- Existing persisted `canvas.active_mode` is migrated into `activity.active_id`.
- Existing persisted `canvas.preferred_interaction_surface` is migrated into `activity.preferred_interaction_surface`.
- Existing canvas camera, scale factor, and panels stay under `canvas`.
- Existing graph, drawing, board, scene, HUD, and physics data are preserved under their new canonical owners.
- After migration, code writes only the new shape.
- No runtime fallback should keep reading old fields after the migration is complete.

Migration can be implemented as a one-time load-time state normalization that rewrites world state to the new canonical layout immediately. That normalization is not a compatibility layer; it is data migration.

## API Renames

Direct migration from old names to new names:

| Old | New |
| --- | --- |
| `canvas-modes.fnl` | `activities.fnl` |
| `CanvasModes` | `Activities` or `ActivityRegistry` |
| `canvas-mode-dock-view.fnl` | `activity-dock-view.fnl` |
| `graph-canvas-mode-unit.fnl` | `graph-activity-unit.fnl` |
| `drawing-canvas-mode-unit.fnl` | `drawing-activity-unit.fnl` |
| `board-canvas-mode-unit.fnl` | `board-activity-unit.fnl` |
| `app.canvas-mode-registry` | `app.activity-registry` or world activity host state |
| `app.active-canvas-mode` | `app.active-activity-id` |
| `app.set-active-canvas-mode` | `app.set-active-activity` |
| `app.canvas-modes-changed` | `app.activities-changed` |
| `app.canvas-shell-changed` | `app.workspace-shell-changed` |
| `app.canvas-mode-root-actions` | `app.activity-root-actions` |
| `app.canvas-mode-selection-actions` | `app.activity-selection-actions` |
| `app.canvas-mode-left-dock-builder` | `app.activity-left-dock-builder` or staged HUD contribution |
| `app.canvas-mode-command-hints-provider` | `app.activity-command-hints-provider` |
| `app.canvas-mode-delete-selection` | `app.activity-delete-selection` |
| `app.canvas-mode-activate-focused` | `app.activity-activate-focused` |
| `app.canvas-mode-context-enricher` | `app.activity-context-enricher` |
| `app.canvas-mode-input-handlers` | `app.activity-input-handlers` |
| `app.canvas-mode-target-enabled?` | `app.activity-target-enabled?` |
| `app.canvas-mode-update` | `app.activity-update` |
| `canvas.active_mode` | `activity.active_id` |

No old aliases should remain after the migration branch is complete.

## Agent Preset Context

Current presets use contexts like:

```fennel
{:surface :canvas :activity "drawing"}
```

Target context:

```fennel
{:surface :canvas
 :activity "drawing"
 :canvas-visible? true
 :scene-visible? true}
```

Preset registry matching should use `:activity`, not `:mode`, for HomeWorld activity-specific tools.

General app tools should rename:

- `app.set-canvas-mode` -> `app.set-activity`
- `space_app_set_canvas_mode` -> `space_app_set_activity`

Tool descriptions should refer to activities and surfaces separately.

## Context Menus And Actions

Current root context menus pass `:surface` and `:canvas-mode`.

Target context should pass:

```fennel
{:surface :canvas
 :activity "graph"
 :targets {:scene app.scene
           :canvas app.canvas
           :hud app.hud}
 :scene {...}
 :graph {...}
 :drawing {...}}
```

Activity context enrichment should run when the context activity matches the active activity.

It should not activate inactive activities or borrow actions from inactive activities.

## Hot Reload And Units

Current built-in canvas mode units are enumerated in `main`.

Target built-in activity units should be enumerated or registered as HomeWorld activity units:

- `graph-activity`
- `drawing-activity`
- `board-activity`

Unit lifecycle remains:

- load
- unload
- snapshot
- restore

Activity unit reload must preserve active activity state and retained sessions when possible.

Because acceptance criteria reject compatibility shims, unit names and exports should be renamed directly.

Example exports:

```fennel
:graph-activity-owned-paths
:load-graph-activity!
:unload-graph-activity!
:snapshot-graph-activity!
:restore-graph-activity!
```

## Testing Strategy

Tests must be migrated from canvas mode language to activity language.

Required coverage:

- Activity registry rejects duplicate ids.
- Unknown activity activation fails loudly.
- Active activity id persists per HomeWorld.
- Switching HomeWorld activity restores last active activity after reload.
- Switching graph -> drawing -> graph does not recreate graph view in normal operation.
- Inactive graph canvas slot does not render graph draw data.
- Inactive drawing canvas slot does not render drawing draw data.
- Inactive board canvas slot does not render board draw data.
- Inactive activity clickables, hoverables, movables, and resizables do not receive input.
- Active activity context menu actions are exposed.
- Inactive activity context menu actions are not exposed.
- Agent preset context resolves by `:activity`.
- Existing world JSON fixtures migrate to the new state shape and are rewritten canonically.
- No tests refer to `canvas-mode` names after migration.

E2E coverage:

- Boot into persisted graph activity.
- Switch to drawing via activity dock.
- Switch back to graph instantly with graph view state retained.
- Board activity remains separate and switchable.
- Canvas visibility and preferred interaction surface follow activity policy.

## Implementation Phases

Current implementation status:

- Phases 1, 2, 3, and 4 are implemented for HomeWorld graph, drawing, board, and sandbox activities.
- Graph, drawing, and board render into isolated canvas activity slots.
- Sandbox activity owns the former default 3D workspace via an isolated Scene activity slot.
- Normal activity switches retain graph, drawing, board, and sandbox sessions instead of dropping presentation objects.
- Scene slots are retained per-activity and active-slot isolated; canonical persisted state is activity-session scene state.
- Remaining work is focused on HUD contribution formalization, broader agent preset context migration, and preserving old terminology only in explicitly legacy/historical docs.

### Phase 1: Activity Naming And State Shape (Complete)

Introduce activity modules and state shape.

Work items:

- Add `activities.fnl` based on current `canvas-modes.fnl`, but with activity names only.
- Rename app globals and functions to activity names.
- Replace `canvas-shell-state` with `workspace-shell-state`.
- Replace `canvas-shell-changed` with `workspace-shell-changed`.
- Move `canvas.active_mode` and `canvas.preferred_interaction_surface` into `activity` state.
- Update HomeWorld state normalization to rewrite old persisted state into new canonical state.
- Remove old field usage after migration.

Phase exit criteria:

- Runtime uses activity terminology.
- No live code depends on `canvas-mode` names.
- Persisted state writes `activity.active_id`.

### Phase 2: Canvas Activity Surface Slots (Complete)

Add isolated per-activity canvas slots.

Work items:

- Add canvas slot creation and activation APIs.
- Give each canvas slot a slot-local build context.
- Make canvas render methods expose active slot draw data.
- Route pointer target enablement through active slot state.
- Port graph activity canvas content to graph canvas slot.
- Port drawing activity render to drawing canvas slot.
- Port board view to board canvas slot.

Phase exit criteria:

- Graph, drawing, and board can be retained without inactive draw leakage.
- Activity switch no longer drops graph/drawing/board presentation objects in normal operation.

### Phase 3: Activity Host Retention (Complete)

Make activity sessions retained by default.

Work items:

- Add HomeWorld activity host.
- Store sessions by activity id.
- Distinguish deactivate from drop.
- Make activity switch hide/deactivate slots, not destroy sessions.
- Persist active activity id.
- Snapshot/restore session state where needed.

Phase exit criteria:

- Switching is instantaneous in normal cases.
- Activity sessions survive activity switching.
- World drop and hot reload still clean up correctly.

### Phase 4: Scene Activity Surface Slots (Complete)

Add equivalent scene slots.

Work items:

- Add scene slot creation and activation APIs.
- Move default world scene content into a canonical scene slot or shared root plus active slot boundary.
- Ensure scene render methods expose active slot draw data plus explicitly shared world draw data.
- Decide which scene state is shared and which is activity-owned.
- Migrate scene panel persistence if activity-owned scene panels are introduced.
- Add the Sandbox activity (id `sandbox`, label `Sandbox`, icon `toys`) as the sole owner of the former default 3D workspace.
- Make Sandbox the default activity for a new HomeWorld.

Phase exit criteria:

- An activity can request no scene content without destroying the scene surface.
- An activity can request a distinct retained scene root.
- Scene switching does not rebuild the scene surface.
- Sandbox owns the former default 3D workspace: scene slots are retained per-activity and active-slot isolated; canonical persisted state lives under `activity.sessions.<activity-id>.scene`.
- Legacy top-level `scene.*` and `physics.containment` are migrated once at load, removed from canonical state, and never read as runtime fallback.
- Graph, Drawing, and Board activate empty Scene slots and must not inherit Sandbox state.
- Inactive slots remain retained; ordinary activity switching does not drop or recreate them.
- Only the active slot supplies render data, picking targets, scene interaction, physics simulation, lights, skybox, and background.

### Phase 5: HUD Contributions And Activity Dock

Migrate HUD mode dock to activity dock.

Work items:

- Rename `CanvasModeDockView` to activity-oriented name.
- Keep activity switcher system-owned by HomeWorld.
- Apply activity HUD contributions from activity host.
- Update drawing and graph sidebars to listen to workspace/activity shell changes.

Phase exit criteria:

- Activity switcher works for graph/drawing/board.
- Active activity dock body updates without canvas-mode names.

### Phase 6: Presets, Tools, Tests, Docs

Complete external-facing migration.

Work items:

- Rename agent tools and preset contexts.
- Update docs.
- Update tests and E2E snapshots.
- Remove old modules and old file names.
- Run full test suite.

Phase exit criteria:

- No `canvas-mode` references remain except historical docs or migration tests if intentionally retained.
- No compatibility aliases remain.
- Full tests pass.

## Non-Goals For First Migration

- Generic multi-layer compositor.
- Activity-owned replacement of `app.scene` or `app.canvas` surface objects.
- Cross-world global activity registry.
- Backward-compatible old API aliases.
- Silent fallback from missing activity or missing surface slot.
- Support for multiple active activities at once.

## Design Invariants

- Activities are world-local.
- HomeWorld activities are retained by default.
- Activity switch is not a drop/recreate operation.
- A surface is a capability provider, not a workflow owner.
- An activity owns its content inside a surface slot.
- Each activity has at most one slot per surface.
- Future combined workflows compose internally inside an activity, not by asking surfaces to compose unrelated activity slots.
- The activity switcher is system-owned and cannot be replaced by an activity.
- Persisted state has one canonical shape after migration.
- Missing required activity data or bindings fail loudly.
- No compatibility shim is kept after migration.

## Acceptance Criteria

The migration is complete only when all of the following are true:

- Graph, drawing, and board are implemented as HomeWorld activities.
- `canvas-modes.fnl` and canvas-mode unit modules are removed or fully renamed.
- App runtime fields use activity names, not canvas-mode names.
- HomeWorld state stores active activity under `activity.active_id`.
- Existing persisted world data migrates to the new canonical layout.
- New writes do not emit `canvas.active_mode` or `canvas.preferred_interaction_surface`.
- Activity switches retain sessions and do not recreate graph/drawing/board presentations in normal operation.
- Inactive activity content does not render.
- Inactive activity content does not receive pointer or keyboard input.
- Agent presets use `:activity`, not `:mode`, for activity-specific capability resolution.
- Context menus use `:activity`, not `:canvas-mode`.
- HUD activity dock is system-owned and activity contributions cannot replace it.
- Tests and docs are updated to new terminology.
- No fallback aliases such as `set-active-canvas-mode` remain.
- No long-term compatibility reads from old persisted fields remain after migration normalization.
- Full test suite passes.

## Open Implementation Decisions

These are implementation choices, not unresolved architecture questions.

1. Module name for the system-owned activity dock: `activity-dock-view.fnl` is recommended.
2. Whether `ActivityHost` and `SurfaceHost` are separate modules or one HomeWorld activity subsystem initially.
3. Exact scene state split between shared scene state and activity-owned scene slot state.
4. Whether HUD needs a formal activity slot or remains contribution-based. Initial recommendation: keep HUD contribution-based.
5. Whether scene visibility should be introduced immediately as `app.scene-visible?` or only after scene slots exist. Initial recommendation: introduce explicit visibility with activity surface state.
