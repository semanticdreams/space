# Activity-Aware World Graph Exposure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build activity-aware graph exposure for world activity surfaces, starting with existing stale scene-backed world graph keys and a generic hierarchy for scene, HUD, canvas, and future surfaces.

**Architecture:** Graph remains a topology-only exposure layer. World root nodes expose world identity/actions and activity entry points; activity/surface nodes expose activity-owned state through keys that include `world-id` and `activity-id`; existing scene adapters move from implicit sandbox world keys to explicit activity scene keys. Old persisted graph topology keys are migrated to sandbox activity-aware keys during map hydration.

**Tech Stack:** Space Fennel, graph key loaders, graph node adapters, `WorldData`, `ActivitySceneState`, `GraphMapManager`, Fennel tests under `assets/lua/tests`.

## Global Constraints

- The graph is an exposure/adaptor layer, not the owner of domain objects.
- Graph core persists topology only.
- Owning systems persist domain data.
- Key loaders adapt owning stores/systems into graph node adapters.
- `GraphMap` owns interaction context over shared graph-addressable objects.
- Keys for activity-owned data must include both `world-id` and `activity-id`.
- Activity-aware exposure applies to all activity-owned surfaces: scene, HUD, canvas, and later surfaces.
- Initial implementation is incremental: scene-backed stale world keys first, plus generic HUD/canvas surface nodes only when session state exists.
- Do not move activity state into graph persistence.
- Do not reintroduce broad world-shared scene state.
- Do not redesign activity runtime lifecycle or scene slot activation beyond correct graph adapters.
- Missing optional surfaces are absent from graph exposure unless the activity owns meaningful surface state.
- Do not keep long-term legacy key loader aliases for stale world-level scene keys.
- Use Space Fennel validation only: `make fennel-check`, `make constraints`, then focused runtime tests. Do not use system `fennel` or `lua` as validation oracles.

---

## File Structure

- `assets/lua/graph/world-data.fnl`: activity/session/surface access boundary for graph node adapters. This file must stop treating sandbox as an implicit fallback for public scene APIs.
- `assets/lua/graph/key-loaders.fnl`: canonical key loader registry for activity-aware world, activity, surface, scene-category, and scene-detail nodes.
- `assets/lua/graph/nodes/world.fnl`: world root adapter. It should expose activities, not flattened scene/HUD/canvas categories.
- `assets/lua/graph/nodes/world-activities.fnl`: world-level activities collection adapter.
- `assets/lua/graph/nodes/world-activity.fnl`: one activity adapter under a world.
- `assets/lua/graph/nodes/activity-surfaces.fnl`: activity surface collection adapter.
- `assets/lua/graph/nodes/activity-surface.fnl`: generic scene/HUD/canvas surface adapter; scene surface can expand to existing scene category adapters.
- Existing scene category nodes: `background.fnl`, `skybox.fnl`, `lights.fnl`, `terrains.fnl`, `scene-panels.fnl`. These gain required `:activity-id` and activity-aware keys.
- Existing scene detail nodes/tools: `light-type.fnl`, `light.fnl`, `terrain.fnl`, `scene-panel.fnl`, terrain kind/tool/editor files. These gain required `:activity-id` and canonical `activity-*` detail keys.
- `assets/lua/graph/map-manager.fnl`: one-time canonicalization of persisted legacy keys and graph-view metadata before hydration/pruning.
- `docs/dev/notes/graph.md`, `docs/dev/graph-maps.md`, `docs/dev/features/activities.md`: canonical docs for graph doctrine, map migration, and activity-owned surface exposure.
- Tests: update focused tests in `assets/lua/tests/test-sandbox-scene-world-data.fnl`, `test-world-nodes.fnl`, `test-world-background-node.fnl`, `test-world-skybox-node.fnl`, `test-graph-loaders.fnl`, and `test-graph-map-manager.fnl`.

## Validation Commands

Use the narrowest relevant focused test command in each task after compile and constraints:

```bash
make fennel-check
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-sandbox-scene-world-data:main
```

Run `make build` first when `./build/space` is missing or stale. After the final implementation task, run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

---

### Task 1: Activity-Aware WorldData Access

**Files:**
- Modify: `assets/lua/graph/world-data.fnl`
- Test: `assets/lua/tests/test-sandbox-scene-world-data.fnl`

**Interfaces:**
- Consumes: `ActivitySceneState.scene-state(activity-state, id)`, `ActivitySceneState.ensure-session-scene!(activity-state, id, state-factory)`, `world-manager:get-world-entry(world-id)`.
- Produces:
  - `WorldData.resolve-activity-session(world-manager, world-id, activity-id) -> table|nil`
  - `WorldData.require-activity-session(world-manager, world-id, activity-id, context) -> table`
  - `WorldData.resolve-activity-surface-state(world-manager, world-id, activity-id, surface-key) -> table|nil`
  - `WorldData.require-activity-scene-state(world-manager, world-id, activity-id, context) -> table`
  - `WorldData.list-activities(world-manager, world-id) -> array<table>` where each item has `:id`, `:label`, and `:key`.
  - `WorldData.list-activity-surfaces(world-manager, world-id, activity-id) -> array<table>` where each item has `:surface-key`, `:label`, and `:key`.
  - Existing scene APIs take explicit `activity-id` immediately after `world-id`.

- [ ] **Step 1: Write failing tests for explicit non-sandbox scene access.** In `test-sandbox-scene-world-data.fnl`, create a fake world with `activity.sessions.sandbox.scene` and `activity.sessions.graph.scene`. Give each session distinct panels, terrains, lights, skybox, and background. Add assertions that `WorldData.list-scene-panels manager "test-world" "graph"`, `WorldData.list-terrains manager "test-world" "graph"`, and `WorldData.get-background manager "test-world" "graph"` read graph session data.
- [ ] **Step 2: Write failing mutation isolation tests.** In the same test file, call `WorldData.update-background manager "test-world" "graph" next-background`, `WorldData.update-terrain-record manager "test-world" "graph" "graph-terrain" updater`, and `WorldData.update-light-record manager "test-world" "graph" "point" "graph-light" updater`. Assert graph session state changes and sandbox session state remains byte-for-byte unchanged.
- [ ] **Step 3: Write failing missing activity tests.** Add a test named `activity scene access fails on missing requested activity`. Assert `(pcall WorldData.terrain-state-records manager "test-world" "missing-activity")` returns false and the error string contains `missing-activity`. Assert no helper returns sandbox data for the missing activity.
- [ ] **Step 4: Implement explicit activity helpers.** Add a local `require-activity-id` helper that asserts a non-empty string. Add exported helpers listed in the Interfaces section. `resolve-activity-surface-state` should support `"scene"`, `"hud"`, and `"canvas"` by looking at the requested session; it should not fabricate absent HUD/canvas state.
- [ ] **Step 5: Change public scene APIs to require `activity-id`.** Update all public scene functions in `world-data.fnl` so calls without an explicit activity id fail loudly instead of defaulting to sandbox. Keep sandbox-specific helpers only for migration/runtime refresh paths whose names clearly say sandbox.
- [ ] **Step 6: Preserve runtime sync invariants.** Runtime sync must update an active scene only when `scene.active-activity-slot-id` matches the requested `activity-id`. Sandbox retained-slot refresh must run only for `activity-id == "sandbox"`.
- [ ] **Step 7: Validate.** Run `make fennel-check`, `make constraints`, then the focused `tests.test-sandbox-scene-world-data:main` command from the validation section.
- [ ] **Step 8: Commit.** Commit with `feat(graph): add activity-aware world data access` after review passes.

---

### Task 2: World Activity and Surface Hierarchy Nodes

**Files:**
- Create: `assets/lua/graph/nodes/world-activities.fnl`
- Create: `assets/lua/graph/nodes/world-activity.fnl`
- Create: `assets/lua/graph/nodes/activity-surfaces.fnl`
- Create: `assets/lua/graph/nodes/activity-surface.fnl`
- Modify: `assets/lua/graph/nodes/world.fnl`
- Modify: `assets/lua/graph/key-loaders.fnl`
- Test: `assets/lua/tests/test-world-nodes.fnl`
- Test: `assets/lua/tests/test-graph-loaders.fnl`

**Interfaces:**
- Consumes: Task 1 `WorldData.list-activities` and `WorldData.list-activity-surfaces`.
- Produces:
  - `WorldActivitiesNode {:world-id string :world-manager table :key string?}`
  - `WorldActivityNode {:world-id string :activity-id string :world-manager table :key string?}`
  - `ActivitySurfacesNode {:world-id string :activity-id string :world-manager table :key string?}`
  - `ActivitySurfaceNode {:world-id string :activity-id string :surface-key string :world-manager table :key string?}`

- [ ] **Step 1: Write failing world hierarchy tests.** Update `test-world-nodes.fnl` so `WorldNode:emit-categories` returns only `{:key "activities" :label "activities"}`. Add tests that `WorldActivitiesNode` lists `sandbox`, `graph`, `drawing`, and `board` sessions when present; `WorldActivityNode` opens `activity-surfaces:<world-id>:<activity-id>`; and `ActivitySurfacesNode` lists `scene`, plus `hud`/`canvas` only when those session fields exist.
- [ ] **Step 2: Write failing key loader tests.** In `test-graph-loaders.fnl`, assert `world-activities:test-world`, `world-activity:test-world:sandbox`, `activity-surfaces:test-world:sandbox`, and `activity-scene:test-world:sandbox` load. Assert `activity-hud:test-world:sandbox` and `activity-canvas:test-world:sandbox` return nil unless `session.hud` or `session.canvas` exists.
- [ ] **Step 3: Implement `WorldActivitiesNode`.** Use key `world-activities:<world-id>`, label `activities`, a `changed` signal, `collect-items` backed by `WorldData.list-activities`, and an `add-activity-node` method that adds a `WorldActivityNode` through `self.graph:add-edge`.
- [ ] **Step 4: Implement `WorldActivityNode`.** Use key `world-activity:<world-id>:<activity-id>`, label `<activity-id> activity`, and an `Open Surfaces` action that creates/loads `activity-surfaces:<world-id>:<activity-id>` in the current graph.
- [ ] **Step 5: Implement `ActivitySurfacesNode`.** Use key `activity-surfaces:<world-id>:<activity-id>`, label `surfaces`, `collect-items` backed by `WorldData.list-activity-surfaces`, and an `add-surface-node` method that opens `activity-scene`, `activity-hud`, or `activity-canvas` keys.
- [ ] **Step 6: Implement `ActivitySurfaceNode`.** For `surface-key == "scene"`, expose categories for `activity-scene-panels`, `activity-terrains`, `activity-skybox`, `activity-background`, and `activity-lights`. For `"hud"` and `"canvas"`, expose summary nodes with labels only and no editing actions until meaningful child adapters exist.
- [ ] **Step 7: Update `WorldNode`.** Remove direct scene/HUD category imports and category creation. Import `WorldActivitiesNode`, emit only the activities category, and create `WorldActivitiesNode` from `add-category-node`.
- [ ] **Step 8: Register hierarchy loaders.** In `key-loaders.fnl`, add loaders for `world-activities`, `world-activity`, `activity-surfaces`, `activity-scene`, `activity-hud`, and `activity-canvas`. Each loader must resolve the requested world/activity/surface via `WorldData` before constructing nodes.
- [ ] **Step 9: Validate.** Run `make fennel-check`, `make constraints`, `tests.test-world-nodes:main`, and `tests.test-graph-loaders:main` with the environment shown in the validation section.
- [ ] **Step 10: Commit.** Commit with `feat(graph): expose world activities and surfaces` after review passes.

---

### Task 3: Activity-Aware Scene Category Adapters

**Files:**
- Modify: `assets/lua/graph/nodes/background.fnl`
- Modify: `assets/lua/graph/nodes/skybox.fnl`
- Modify: `assets/lua/graph/nodes/lights.fnl`
- Modify: `assets/lua/graph/nodes/terrains.fnl`
- Modify: `assets/lua/graph/nodes/scene-panels.fnl`
- Modify: `assets/lua/graph/key-loaders.fnl`
- Test: `assets/lua/tests/test-world-nodes.fnl`
- Test: `assets/lua/tests/test-world-background-node.fnl`
- Test: `assets/lua/tests/test-world-skybox-node.fnl`
- Test: `assets/lua/tests/test-graph-loaders.fnl`

**Interfaces:**
- Consumes: Task 1 WorldData APIs with explicit `activity-id`; Task 2 `ActivitySurfaceNode` scene categories.
- Produces activity-aware category constructors that require `:activity-id`: `BackgroundNode`, `SkyboxNode`, `LightsNode`, `TerrainsNode`, `ScenePanelsNode`.

- [ ] **Step 1: Write failing category key tests.** Update tests to expect `activity-background:<world-id>:sandbox`, `activity-skybox:<world-id>:sandbox`, `activity-lights:<world-id>:sandbox`, `activity-terrains:<world-id>:sandbox`, and `activity-scene-panels:<world-id>:sandbox` instead of world-level keys. Add loader assertions for each key.
- [ ] **Step 2: Write failing non-sandbox isolation tests.** Create sandbox and graph sessions with different terrain/background/skybox/light/panel data. Instantiate category nodes with `:activity-id "graph"` and assert they expose only graph session data; instantiate with `:activity-id "sandbox"` and assert they expose only sandbox data.
- [ ] **Step 3: Update category constructors.** Require `options.activity-id`, set `node.activity-id`, default keys to canonical `activity-*` category keys, and pass `activity-id` to every WorldData read/write.
- [ ] **Step 4: Update category child keys.** `TerrainsNode` should create `activity-terrain:<world-id>:<activity-id>:<terrain-id>`. `LightsNode` should create `activity-light-type:<world-id>:<activity-id>:<type-key>`. `ScenePanelsNode` should create `activity-scene-panel:<world-id>:<activity-id>:<panel-index>`.
- [ ] **Step 5: Register activity category loaders.** Add loaders for `activity-background`, `activity-skybox`, `activity-lights`, `activity-terrains`, and `activity-scene-panels`. Remove direct world-level loaders for `background`, `skybox`, `lights`, `terrains`, and `scene-panels` after migration support exists in `map-manager.fnl` task planning.
- [ ] **Step 6: Update existing tests that construct category nodes.** Pass `:activity-id "sandbox"` where tests still inspect sandbox behavior.
- [ ] **Step 7: Validate.** Run `make fennel-check`, `make constraints`, `tests.test-world-nodes:main`, `tests.test-world-background-node:main`, `tests.test-world-skybox-node:main`, and `tests.test-graph-loaders:main`.
- [ ] **Step 8: Commit.** Commit with `feat(graph): make scene category nodes activity-aware` after review passes.

---

### Task 4: Activity-Aware Scene Detail Adapters

**Files:**
- Modify: `assets/lua/graph/nodes/light-type.fnl`
- Modify: `assets/lua/graph/nodes/light.fnl`
- Modify: `assets/lua/graph/nodes/terrain.fnl`
- Modify: `assets/lua/graph/nodes/scene-panel.fnl`
- Modify: `assets/lua/graph/nodes/flat-terrain.fnl`
- Modify: `assets/lua/graph/nodes/perlin-terrain.fnl`
- Modify: `assets/lua/graph/nodes/heightfield-terrain.fnl`
- Modify: `assets/lua/graph/nodes/heightfield-resize-tool.fnl`
- Modify: `assets/lua/graph/nodes/heightfield-adjust-tool.fnl`
- Modify: `assets/lua/graph/nodes/heightfield-perlin-tool.fnl`
- Modify: `assets/lua/graph/nodes/heightfield-flat-tool.fnl`
- Modify: `assets/lua/graph/terrain-editors.fnl`
- Modify: `assets/lua/graph/terrain-tools.fnl`
- Modify: `assets/lua/graph/key-loaders.fnl`
- Modify: `assets/lua/llm/presets/builtins/scene.fnl`
- Test: `assets/lua/tests/test-world-nodes.fnl`
- Test: `assets/lua/tests/test-sandbox-scene-world-data.fnl`
- Test: `assets/lua/tests/test-graph-loaders.fnl`

**Interfaces:**
- Consumes: Task 3 activity-aware scene category child keys.
- Produces canonical detail keys:
  - `activity-light-type:<world-id>:<activity-id>:<type-key>`
  - `activity-light:<world-id>:<activity-id>:<type-key>:<light-id>`
  - `activity-terrain:<world-id>:<activity-id>:<terrain-id>`
  - `activity-terrain-editor:<world-id>:<activity-id>:<terrain-id>`
  - `activity-terrain-tool:<world-id>:<activity-id>:<terrain-id>:<tool-id>`
  - `activity-scene-panel:<world-id>:<activity-id>:<panel-index>`

- [ ] **Step 1: Write failing detail key tests.** Update tests to expect the canonical detail keys listed above. Add loader assertions for each scheme and missing-world assertions for each scheme.
- [ ] **Step 2: Write failing detail mutation isolation tests.** Create sandbox and graph scene sessions with distinct terrains/lights. Mutate graph terrain and graph light through the activity-aware detail nodes and assert sandbox terrain/light records are unchanged.
- [ ] **Step 3: Update detail constructors.** Require `options.activity-id`, set `node.activity-id`, default keys to canonical `activity-*` schemes, and pass `activity-id` into all WorldData reads/writes.
- [ ] **Step 4: Update terrain editor/tool factories.** `TerrainEditors.create-editor-node` and `TerrainTools.create-tool-node` should accept and propagate `:activity-id`. Generated editor/tool keys must include world id, activity id, terrain id, and tool id where applicable.
- [ ] **Step 5: Update detail loader parsing.** Parse `world-id` and `activity-id` before object identifiers. Validate the requested activity scene state exists before constructing nodes. Remove world-level loaders for `light-type`, `light`, `terrain`, `terrain-editor`, `terrain-tool`, and `scene-panel` after Task 5 covers persisted-key migration.
- [ ] **Step 6: Update LLM scene preset calls.** In `assets/lua/llm/presets/builtins/scene.fnl`, pass explicit `"sandbox"` to WorldData scene mutation calls because those tools currently operate on the durable sandbox scene.
- [ ] **Step 7: Validate.** Run `make fennel-check`, `make constraints`, `tests.test-world-nodes:main`, `tests.test-sandbox-scene-world-data:main`, and `tests.test-graph-loaders:main`.
- [ ] **Step 8: Commit.** Commit with `feat(graph): make scene detail nodes activity-aware` after review passes.

---

### Task 5: Legacy Graph Topology Key Migration

**Files:**
- Modify: `assets/lua/graph/map-manager.fnl`
- Test: `assets/lua/tests/test-graph-map-manager.fnl`

**Interfaces:**
- Consumes: canonical activity-aware key loaders from Tasks 2-4.
- Produces local helper behavior in `map-manager.fnl`: `canonicalize-legacy-activity-key(key) -> canonical-key, migrated?`, applied to map state and graph-view metadata before hydration/pruning.

- [ ] **Step 1: Write failing category migration tests.** In `test-graph-map-manager.fnl`, add a persisted map with nodes `background:w1`, `skybox:w1`, `lights:w1`, `terrains:w1`, and `scene-panels:w1`. Register only canonical activity-aware loaders. Assert hydrated/captured node keys contain `activity-background:w1:sandbox`, `activity-skybox:w1:sandbox`, `activity-lights:w1:sandbox`, `activity-terrains:w1:sandbox`, and `activity-scene-panels:w1:sandbox`, with old keys absent.
- [ ] **Step 2: Write failing detail migration tests.** Add persisted nodes `light-type:w1:point`, `light:w1:point:p1`, `terrain:w1:t1`, `terrain-editor:w1:t1`, `terrain-tool:w1:t1:resize-terrain`, and `scene-panel:w1:2`. Assert they migrate to `activity-light-type:w1:sandbox:point`, `activity-light:w1:sandbox:point:p1`, `activity-terrain:w1:sandbox:t1`, `activity-terrain-editor:w1:sandbox:t1`, `activity-terrain-tool:w1:sandbox:t1:resize-terrain`, and `activity-scene-panel:w1:sandbox:2`.
- [ ] **Step 3: Write failing edge and metadata migration tests.** Persist an edge from `terrains:w1` to `terrain:w1:t1`. Persist metadata entries in positions, presentations, sizes, `panels[].node-key`, and `extra_panels[].node-key`. Assert all references are rewritten to canonical keys before pruning and persistence.
- [ ] **Step 4: Implement deterministic canonicalization.** Add a local parser that maps only known legacy key shapes to sandbox activity-aware keys. Unknown malformed keys return the original key and `false` so normal pruning behavior handles them.
- [ ] **Step 5: Apply migration before hydration.** Canonicalize nodes and edges before `GraphMap:restore-state`. Deduplicate canonical nodes and drop self-duplicate edges caused by migration.
- [ ] **Step 6: Apply metadata migration before metadata pruning.** Rewrite dictionary keys in positions, presentations, and sizes. Rewrite `node-key` fields in panel metadata. Persist rewritten metadata with `json-utils` only when migration/pruning changed data.
- [ ] **Step 7: Validate.** Run `make fennel-check`, `make constraints`, then `tests.test-graph-map-manager:main`.
- [ ] **Step 8: Commit.** Commit with `feat(graph): migrate legacy world scene graph keys` after review passes.

---

### Task 6: Documentation and Final Validation

**Files:**
- Modify: `docs/dev/notes/graph.md`
- Modify: `docs/dev/graph-maps.md`
- Modify: `docs/dev/features/activities.md`

**Interfaces:**
- Consumes: implemented activity-aware key hierarchy and migration behavior from Tasks 1-5.
- Produces canonical developer documentation for graph doctrine, activity-owned surface exposure, and legacy key migration.

- [ ] **Step 1: Update graph doctrine note.** Replace stale wording that says world/terrain/light data comes from `world.state.scene.*`. Document that activity-owned scene/HUD/canvas state is exposed through keys containing both `world-id` and `activity-id`, and key loaders adapt `world.state.activity.sessions.<activity-id>` state into graph node adapters.
- [ ] **Step 2: Update graph maps documentation.** Add a persistence/migration subsection explaining one-time legacy key migration to sandbox activity-aware keys. Include the five category mappings and note deterministically parseable scene detail descendant mappings.
- [ ] **Step 3: Update activities documentation.** Replace the old speculative shared-scene split with the implemented rule: activity sessions own surface-specific state; graph exposure should point to the owning activity surface rather than flattening scene/HUD/canvas state onto the world root.
- [ ] **Step 4: Validate docs and focused behavior.** Run `rg "world.state.scene|background:<world-id>|activity-background|activity-surfaces" docs/dev/notes/graph.md docs/dev/graph-maps.md docs/dev/features/activities.md`, then run `make fennel-check`, `make constraints`, `tests.test-world-nodes:main`, `tests.test-graph-loaders:main`, `tests.test-graph-map-manager:main`, and `tests.test-sandbox-scene-world-data:main`.
- [ ] **Step 5: Run complete relevant local suite.** Run `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test` because graph key loading, persisted map hydration, and shared activity scene adapter behavior changed.
- [ ] **Step 6: Commit.** Commit with `docs(graph): document activity-aware world exposure` after review passes.
- [ ] **Step 7: Final gate.** Confirm `git status --porcelain` is clean, focused validation passed, and `make test` passed. PR CI remains the full integration gate before ready-to-merge claims.
