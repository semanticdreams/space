# Sandbox Scene Activity Design

## Purpose

Make the 3D scene a retained HomeWorld surface rather than a source of always-on
default content. Add a **Sandbox** activity, shown in the activity switcher with
the Material icon `toys`, that exclusively owns the 3D workspace currently
present in every activity.

The current workspace includes terrain, persisted scene panels, physics objects
(including balls, light balls, cuboids, and demo-browser objects), containment,
lighting, skybox, background, scene actions, scene interactions, and incremental
panel hydration.

Graph, Drawing, Board, and any future activity must start with an empty scene
slot. They may deliberately create and retain their own unrelated 3D content in
their own scene slot later.

## Scope

This implements the scene activity-slot phase described in
`docs/dev/features/activities.md`. It includes scene ownership, rendering,
input, physics/environment activation, persisted-state migration, and focused
tests. It does not introduce a generic multi-activity compositor or replace the
existing retained surface model.

## Architecture

### Scene surface

`Scene` remains the retained 3D capability provider for the active HomeWorld. It
owns surface-level concerns only:

- camera, projection, viewport, and screen-ray helpers;
- rendering integration and active scene-slot selection;
- surface-level layout/build-context plumbing;
- the bridge to active renderer and physics services.

It must not own universal terrain, panels, lights, physics objects, environment
settings, or scene actions.

### Retained scene slots

Each activity has at most one retained scene slot, following the established
Canvas activity-slot pattern. A slot owns activity-specific retained 3D content:

- its render and layout root/build sources;
- scene panels and objects;
- terrain records;
- physics objects and containment configuration;
- light state, skybox state, and background state;
- scene-specific persistence, restore, and hydration state.

Only the active activity slot is exposed through Scene render, picking, pointer
target, and interaction APIs. Inactive slots remain retained but are neither
rendered nor interactive.

### Sandbox activity

Add the built-in `sandbox` activity with:

- label: `Sandbox`;
- icon: `toys`;
- a Scene preferred interaction surface;
- an activity-owned Sandbox scene slot;
- scene root actions and scene interaction behavior currently available by
  default.

Sandbox is the default activity for a newly created HomeWorld so first-run
behavior remains a 3D workspace. It is the only activity that initially creates
the current default terrain and hydrates the migrated legacy scene content.

Graph, Drawing, and Board activate empty scene slots in addition to their
existing Canvas slots. This is not a renderer visibility policy: no Sandbox
content is attached to, inherited by, or interactable from those slots.

## Activity lifecycle

On a scene-slot switch:

1. Deactivate the old slot: make its render and pointer sources unavailable,
   suspend/detach its physics participation, and clear its applied environment
   state.
2. Resolve or create the next retained slot.
3. Activate the next slot: expose its render/input sources and apply only that
   slot's physics, lights, skybox, and background to the singleton engine and
   renderer services.
4. Apply the active activity's hooks and preferred interaction surface.

Only one slot is active. Inactive slots must contribute no draw data, pointer or
keyboard input targets, physics simulation, lights, skybox, or background.

The Bullet world, `app.lights`, and renderer skybox/background remain engine
services, but their effective state is exclusively supplied by the active scene
slot. Activation must reset those services before applying the target slot, so
state cannot leak between activities.

## Persistence and migration

Scene content becomes canonical activity session state, conceptually:

```fennel
:activity {:active_id "sandbox"
           :sessions {"sandbox" {:scene {...}}
                      "graph" {:scene {...}}
                      "drawing" {:scene {...}}
                      "board" {:scene {...}}}}
```

The exact session envelope follows the existing activity-session persistence
mechanism, but all activity-owned scene data belongs under that activity's
session. The top-level legacy `scene` and `physics.containment` state is no
longer canonical.

At world load, a one-time, idempotent normalization migrates legacy persisted
data into the Sandbox session:

- `scene.panels`;
- `scene.terrains`;
- `scene.lights`;
- `scene.skybox`;
- `scene.background`;
- `physics.containment`.

The migration rewrites the world to its new canonical shape. Afterwards runtime
code writes and reads only activity-owned scene state; it keeps no compatibility
fallback to legacy keys.

## Error handling and invariants

- Missing required scene-slot bindings or activity session data fail loudly.
- Duplicate scene slots and attempts to activate an unknown activity fail
  loudly, consistent with the activity registry.
- Scene object restoration remains activity-scoped: an object restorer can only
  restore into the owning active/rehydrating slot.
- Slot activation is transactional enough that a failed target activation leaves
  no partially applied lights, environment state, input targets, or physics
  bodies from either slot.

## Acceptance criteria and tests

Focused automated coverage must prove:

- a new HomeWorld selects Sandbox and creates the current default 3D workspace;
- legacy world scene/physics state migrates once into Sandbox and persists in
  canonical activity-session state;
- Sandbox restores terrain, panels, objects, containment, lights, skybox, and
  background after reload;
- Graph, Drawing, and Board each activate an empty, non-interactive scene slot;
- inactive scene slots render no draw data, receive no interaction, simulate no
  physics, and apply no lights, skybox, or background;
- switches retain each slot and restore the same Sandbox content without normal
  drop/recreation;
- a future-style non-Sandbox slot can render its own content without receiving
  Sandbox content;
- existing scene, physics, rendering, activity-retention, and persistence tests
  are migrated or extended to the new ownership model.

## Non-goals

- A generic multi-slot scene compositor.
- Multiple simultaneously active activities or scene slots.
- Sharing Sandbox content with another activity.
- Long-term runtime aliases or legacy-state fallback reads.
