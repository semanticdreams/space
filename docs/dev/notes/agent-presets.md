---
type: dev-note
tags:
  - note
---

# Agent Presets

## Overview

Space needs AI agents, exposed to opencode through MCP, whose tools and prompt context follow the user's current interaction context: scene manipulation, canvas drawing, graph navigation, and app-level operations.

The chosen design is a preset data layer that resolves context-aware capability bundles, then a small MCP sync layer exposes the resolved tool set to opencode. Higher-level agent strategy remains separate.

```
App context -> PresetManager -> PresetRegistry + ToolAdapters -> Managed MCP sync -> ToolRegistry -> opencode
                 live state       pure resolution     runtime tools       owned tool set
```

The preset layer is the implementation scope. Agent routing, model choice, prompt assembly strategy, and opencode session lifecycle are deferred.

## Goals

- **Context-aware MCP tools**: drawing tools are active in drawing mode, graph tools in graph mode, scene tools on the scene surface, and safe general tools where appropriate.
- **Explicit user overrides**: users can force presets `:on`, force them `:off`, or return them to `:auto` for the current session.
- **Risk-aware defaults**: presets that run shell commands, write files, delete data, or mutate broad app state are disabled by default unless the user or future agent layer explicitly enables them.
- **Clean ownership**: preset resolution never mutates MCP directly. MCP sync owns only the tools it registered and never unregisters unrelated tools.
- **Pure preset definitions**: presets describe capabilities and prompt fragments. Runtime closures live in tool adapters, not preset data.
- **Future agent compatibility**: the future agent layer can consume active presets, prompt fragments, tool metadata, and default risk policy without owning low-level context matching.

## Non-Goals

- Chat UI, agent runner, router agent, or opencode session orchestration.
- Model parameters, temperature, reasoning effort, or provider selection.
- Permanent preset editing UI. Overrides are session-only in v1.
- Per-tool user toggles. Presets are the v1 toggle granularity.
- Multiple implementations for the same MCP tool name. Duplicate resolved tool names are invalid in v1.

## Chosen Architecture

The system has four boundaries:

1. `PresetRegistry`: stores immutable preset definitions and performs pure resolution.
2. `PresetManager`: owns live context, overrides, cached resolved state, and change notifications.
3. `ToolAdapterRegistry`: maps stable capability IDs to runtime MCP tool definitions.
4. `PresetMcpSync`: synchronizes only manager-resolved tools into an MCP `ToolRegistry`.

This matches the existing repo split where MCP protocol, handler, registry, and HTTP transport are separate modules. It also keeps graph/view-style ownership clear: data descriptions do not close over runtime views or world objects.

## Data Model

### Preset Definition

Preset definitions are immutable after registration and contain no runtime closures.

```fennel
{:name "drawing-shape-tools"
 :group "drawing"
 :default-state :auto
 :risk :normal
 :contexts [{:surface :canvas :activity "drawing"}]
 :tool-ids ["drawing.set-tool"
            "drawing.insert-shape"
            "drawing.insert-line"
            "drawing.insert-stroke"]
 :system-prompt "The user is editing vector drawing content. Use drawing tools for shape and stroke operations."}
```

Fields:

| Field | Required | Meaning |
|-------|----------|---------|
| `:name` | yes | Unique preset ID. |
| `:group` | no | Flat grouping tag for UI/status. |
| `:default-state` | yes | `:auto` or `:off`. Dangerous presets must use `:off`. |
| `:risk` | yes | `:normal`, `:filesystem-read`, `:filesystem-write`, `:destructive`, or `:shell`. |
| `:contexts` | yes | OR-match rules for auto activation. |
| `:tool-ids` | yes | Capability IDs resolved by `ToolAdapterRegistry`. |
| `:system-prompt` | no | Raw prompt fragment consumed later by the agent prompt composer. |

### Context Snapshot

The manager stores a richer context than just surface/activity so tool exposure can follow the actual shell state.

```fennel
{:surface :canvas
 :activity "drawing"
 :canvas-visible? true
 :world-id "home"
 :selection-kind :drawing-object}
```

Required fields are `:surface` and `:canvas-visible?`. `:activity` is optional and nil when no activity is active. Other fields are optional facts supplied by app/runtime integrations. Context matchers ignore fields they do not mention.

### Context Matching

A context pattern matches when every field in the pattern matches the current context.

```fennel
{:surface :canvas :activity "drawing"}  ;; drawing activity only
{:surface :scene}                   ;; any scene context
{:surface :any}                     ;; all surfaces
{:activity :any}                    ;; any activity
{:activity :none}                   ;; no active activity
```

Rules:

- Missing fields in the pattern are wildcards.
- `:any` is an explicit wildcard value.
- Exact values otherwise compare with `=`.
- Use `:activity :none` to match only a nil current activity; a nil table field is indistinguishable from a missing wildcard field.

This avoids hard-coding "all four contexts" and keeps custom activities compatible with general presets.

### Override State

Overrides are session-only and keyed by preset name.

```fennel
{"drawing-shape-tools" {:state :auto}
 "graph-nav-tools" {:state :on}
 "scene-terrain-tools" {:state :off}}
```

Allowed states:

- `:auto`: use `:default-state` and context matching.
- `:on`: force-enable the preset.
- `:off`: force-disable the preset.

Resolution rejects unknown preset names and unknown states. Accessors return defensive copies; callers must use manager methods to change context or overrides so cache invalidation and MCP sync notifications stay correct.

## Tool Adapters

Presets reference tool IDs; adapters produce MCP tool definitions at sync time. This keeps preset data testable and prevents stale closures from capturing dead world/runtime objects.

```fennel
(fn ToolAdapterRegistry [opts]
  {:register (fn [self adapter] ...)
   :get (fn [self tool-id] ...)
   :resolve (fn [self tool-id app] ...)})
```

Adapter shape:

```fennel
{:id "drawing.set-tool"
 :mcp-name "space_drawing_set_tool"
 :description "Switch the active drawing tool."
 :inputSchema {:type "object"
               :properties {:tool {:type "string"}}
               :required ["tool"]}
 :make-run (fn [app]
             (fn [args]
               (local controller (assert app.drawing-controller
                                         "space_drawing_set_tool requires app.drawing-controller"))
               (controller:set-tool args.tool)))}
```

Adapter rules:

- All MCP-facing names must use the `space_` prefix because OpenCode-facing registries use `ToolRegistry {:namespace-prefix "space_"}`.
- `:make-run` must fetch canonical runtime objects from `app` at call time or fail loudly if unavailable.
- Adapters must not silently ignore missing state.
- Adapter IDs are internal and may be namespaced with dots. MCP names are external and must remain stable.

Existing `assets/lua/llm/tools/*` tools use the OpenAI tool shape (`:parameters`, `:call`) and unprefixed names. They should not be registered directly into MCP. Reusable logic can be extracted behind adapters, but MCP wrappers must provide `space_` names and `:inputSchema`/`:run`.

## PresetRegistry

`assets/lua/llm/presets/registry.fnl`

Owns only preset definitions and pure resolution.

```fennel
(fn PresetRegistry [opts]
  {:register (fn [self preset] ...)
   :unregister (fn [self name] ...)
   :get (fn [self name] ...)
   :list (fn [self] ...)
   :list-by-group (fn [self group] ...)
   :resolve (fn [self context overrides] ...)
   :status (fn [self] ...)
   :add-on-change (fn [self cb] ...)
   :remove-on-change (fn [self cb] ...)})
```

Resolution:

1. Validate `context` and `overrides`.
2. For each preset in registration order:
   - `override.state == :on` -> active, reason `:override`.
   - `override.state == :off` -> inactive.
   - otherwise active only when `preset.default-state == :auto` and any context pattern matches, reason `:context`.
   - `preset.default-state == :off` never auto-activates.
3. Collect active `:tool-ids` in order.
4. Reject duplicate tool IDs in the resolved list.
5. Return a deterministic result.

Resolved shape:

```fennel
{:active-presets [{:name "drawing-shape-tools"
                   :reason :context
                   :risk :normal}]
 :tool-ids ["drawing.set-tool" "drawing.insert-shape"]
 :prompt-fragments [{:preset "drawing-shape-tools"
                     :prompt "..."}]}
```

The registry does not know MCP and does not create `:run` closures.

## PresetManager

`assets/lua/llm/presets/init.fnl`

Owns current context, overrides, cached resolution, and notifications.

```fennel
(fn PresetManager [{:registry :tool-adapters :app :context :overrides}]
  {:register (fn [self preset] ...)
   :unregister (fn [self name] ...)
   :set-context (fn [self context] ...)
   :get-context (fn [self] ...)
   :set-override (fn [self name state] ...)
   :get-overrides (fn [self] ...)
   :resolve (fn [self] ...)
   :get-active-presets (fn [self] ...)
   :get-tool-defs (fn [self] ...)
   :get-prompt-fragments (fn [self] ...)
   :add-on-change (fn [self cb] ...)
   :remove-on-change (fn [self cb] ...)
   :status (fn [self] ...)})
```

`get-tool-defs` resolves tool IDs through `ToolAdapterRegistry` and returns full MCP tool definitions, including `:run`. It also attaches sync metadata used by `PresetMcpSync`:

```fennel
{:name "space_drawing_set_tool"
 :description "Switch the active drawing tool."
 :inputSchema {...}
 :run #<function>
 :managed-owner "agent-presets"
 :managed-source "drawing.set-tool"}
```

`on-change` fires only when the resolved preset names, tool IDs, prompt fragments, or override state changes. It should not fire when unrelated app state changes unless that state is included in the context snapshot.

`get-tool-defs` rejects duplicate MCP tool names after adapter resolution. Duplicate MCP names are implementation errors in v1 because name-only MCP calls cannot disambiguate multiple implementations.

## MCP Sync

`assets/lua/llm/presets/mcp-sync.fnl`

`PresetMcpSync` is the only module that mutates the MCP `ToolRegistry` for presets.

```fennel
(fn PresetMcpSync [{:manager :tool-registry :owner}]
  {:start (fn [self] ...)
   :sync (fn [self] ...)
   :stop (fn [self] ...)
   :status (fn [self] ...)})
```

Sync rules:

- Track a private `managed-tools` map of MCP tool name -> source tool ID.
- Register new managed tools.
- Re-register a managed tool when its source tool ID changes.
- Unregister only tools present in `managed-tools` that are no longer resolved.
- Never unregister or replace tools that were not registered by this sync object.
- If a resolved tool name already exists in `ToolRegistry` and is not owned by this sync object, fail loudly with an ownership error.

This avoids deleting manual tools such as `space_ping`, preserves unrelated MCP registrants, and handles active preset changes without stale closures.

## Built-In Presets

Built-ins live under `assets/lua/llm/presets/builtins/`. Each module exports `(register mgr)`.

### Drawing

Context: `{:surface :canvas :activity "drawing"}`

| Preset | Default | Risk | MCP Tools |
|--------|---------|------|-----------|
| `drawing-shape-tools` | `:auto` | `:normal` | `space_drawing_inspect`, `space_drawing_set_tool`, `space_drawing_insert_shape`, `space_drawing_insert_line`, `space_drawing_insert_stroke` |
| `drawing-layer-tools` | `:auto` | `:normal` | `space_drawing_add_layer`, `space_drawing_duplicate_layer`, `space_drawing_rename_layer`, `space_drawing_set_active_layer` |
| `drawing-layer-destructive-tools` | `:off` | `:destructive` | `space_drawing_delete_layer` |
| `drawing-color-tools` | `:auto` | `:normal` | `space_drawing_set_defaults`, `space_drawing_update_selection_style`, `space_drawing_sample_color` |
| `drawing-history-tools` | `:auto` | `:normal` | `space_drawing_undo`, `space_drawing_redo` |
| `drawing-selection-tools` | `:auto` | `:normal` | `space_drawing_select`, `space_drawing_transform_selection`, `space_drawing_clear_selection` |
| `drawing-selection-destructive-tools` | `:off` | `:destructive` | `space_drawing_delete_selected` |

### Graph

Context: `{:surface :canvas :activity "graph"}`

| Preset | Default | Risk | MCP Tools |
|--------|---------|------|-----------|
| `graph-node-tools` | `:auto` | `:normal` | `space_graph_add_node`, `space_graph_load_node` |
| `graph-node-map-tools` | `:auto` | `:destructive` | `space_graph_remove_nodes` |
| `graph-edge-tools` | `:auto` | `:normal` | `space_graph_add_edge` |
| `graph-nav-tools` | `:auto` | `:normal` | `space_graph_focus_node`, `space_graph_open_node`, `space_graph_search_nodes` |
| `graph-identity-tools` | `:auto` | `:normal` | `space_graph_create_identity` |
| `graph-state-tools` | `:off` | `:destructive` | `space_graph_get_state`, `space_graph_restore_state` |

### Scene

Context: `{:surface :scene}`

| Preset | Default | Risk | MCP Tools |
|--------|---------|------|-----------|
| `scene-object-tools` | `:auto` | `:normal` | `space_scene_add_cuboid`, `space_scene_add_physics_body`, `space_scene_select_object` |
| `scene-terrain-tools` | `:auto` | `:normal` | `space_scene_add_terrain`, `space_scene_raycast_terrain` |
| `scene-terrain-destructive-tools` | `:off` | `:destructive` | `space_scene_remove_terrain` |
| `scene-lighting-tools` | `:auto` | `:normal` | `space_scene_add_light`, `space_scene_set_light_state` |
| `scene-skybox-tools` | `:auto` | `:normal` | `space_scene_set_skybox`, `space_scene_set_background` |
| `scene-camera-tools` | `:auto` | `:normal` | `space_scene_set_camera`, `space_scene_reset_camera`, `space_scene_screen_ray` |
| `scene-state-tools` | `:off` | `:destructive` | `space_scene_get_state`, `space_scene_restore_state` |

### General

Context: `{:surface :any}`

| Preset | Default | Risk | MCP Tools |
|--------|---------|------|-----------|
| `general-theme-tools` | `:auto` | `:normal` | `space_app_set_theme` |
| `general-canvas-tools` | `:auto` | `:normal` | `space_app_set_canvas_visible`, `space_app_set_activity`, `space_app_switch_surface` |
| `general-world-tools` | `:off` | `:destructive` | `space_app_create_world`, `space_app_switch_world`, `space_app_delete_world` |
| `general-file-read-tools` | `:off` | `:filesystem-read` | `space_app_read_file`, `space_app_list_files` |
| `general-file-write-tools` | `:off` | `:filesystem-write` | `space_app_write_file` |
| `general-shell-tools` | `:off` | `:shell` | `space_app_run_bash` |

High-risk general tools are not auto-active. A user or future agent strategy must explicitly enable them with overrides.

## Integration Points

### Workspace Shell Context

`app.workspace-shell-changed` emits `payload.current` with `:interaction-surface`, `:activity`, and `:canvas-visible?`. The integration converts that payload to the preset context shape.

```fennel
(app.workspace-shell-changed:connect
  (fn [payload]
    (local current payload.current)
    (app.agent-presets:set-context
      {:surface current.interaction-surface
       :activity current.activity
       :canvas-visible? current.canvas-visible?})))
```

Activity-specific context enrichers can be added later by extending this context object before calling `set-context`.

### App Bootstrap

```fennel
(local ToolRegistry (require :mcp/tool-registry))
(local PresetRegistry (require :llm/presets/registry))
(local PresetManager (require :llm/presets/init))
(local ToolAdapterRegistry (require :llm/presets/tool-adapters))
(local PresetMcpSync (require :llm/presets/mcp-sync))
(local BuiltinDrawing (require :llm/presets/builtins/drawing))
(local BuiltinGraph (require :llm/presets/builtins/graph))
(local BuiltinScene (require :llm/presets/builtins/scene))
(local BuiltinGeneral (require :llm/presets/builtins/general))

(set app.mcp-tools (ToolRegistry {:namespace-prefix "space_"}))
(set app.agent-tool-adapters (ToolAdapterRegistry {:app app}))
(set app.agent-presets
     (PresetManager {:registry (PresetRegistry {})
                     :tool-adapters app.agent-tool-adapters
                     :app app
                      :context {:surface :scene
                                :activity nil
                                :canvas-visible? false}}))

(BuiltinDrawing.register app.agent-presets)
(BuiltinGraph.register app.agent-presets)
(BuiltinScene.register app.agent-presets)
(BuiltinGeneral.register app.agent-presets)

(set app.agent-preset-mcp-sync
     (PresetMcpSync {:manager app.agent-presets
                     :tool-registry app.mcp-tools
                     :owner "agent-presets"}))
(app.agent-preset-mcp-sync:start)
```

## Agent Layer Interface

The future agent layer consumes:

- `app.agent-presets:get-active-presets()` for active preset names, reasons, and risk metadata.
- `app.agent-presets:get-prompt-fragments()` for raw prompt fragments.
- `app.agent-presets:get-tool-defs()` for MCP tool definitions or local tool availability.
- `app.agent-presets:set-override(name, state)` to request temporary capability changes.

The agent layer owns:

- Prompt fragment ordering and template expansion.
- Model/provider/temperature/reasoning selection.
- Router/sub-agent strategy.
- opencode session lifecycle.

Template variables in prompt fragments are resolved by the future prompt composer, not at preset registration.

## Existing Code Preparation

- `assets/lua/tools/mcp-remote-server.fnl`: serve the app bootstrap-owned `app.mcp-tools` registry. Test/demo stubs such as `space_ping` belong in tests or dedicated examples, not as silent production fallbacks.
- `assets/lua/mcp/tool-registry.fnl`: add an ownership-aware helper or status API if `PresetMcpSync` needs to detect non-managed name collisions. At minimum, sync must track its own managed set and fail before replacing unknown names.
- `assets/lua/llm/tools/*`: do not register these directly into MCP. Extract shared file/shell logic only behind `space_` MCP adapters with explicit risk-disabled presets.
- `assets/lua/main.fnl`: wire `app.agent-presets`, `app.agent-tool-adapters`, and `app.agent-preset-mcp-sync` after MCP registry creation and before opencode-facing MCP server startup.
- `assets/lua/activities.fnl`: expose activity context enrichment when presets need selection/tool-target facts beyond shell state.
- `assets/lua/tests/fast.fnl`: add preset unit tests once modules land.

### Internal Unit Presets vs. External Unit MCP

The `space_unit_*` tools registered through `llm/presets/builtins/units.fnl`
(`space_unit_list`, `space_unit_inspect`, `space_unit_edit`, `space_unit_apply_patch`,
`space_unit_reload`, etc.) are **internal Space agent tools**. They expect the
full app runtime (`app.mcp-tools`, `app.unit-manager`, `app.code-dir`) and adapt
to context through the preset system.

External user-unit development uses the separate `llm/external-unit-mcp/*`
subsystem instead. The external MCP registry is loader-neutral, runs in a
headless engine with an isolated OpenCode config, and does not depend on the
app bootstrap's `app.mcp-tools` registry.

Do not add Space-specific user-unit behavior to global `~/.config/opencode`. The
external unit MCP bridge writes an isolated config and prints
`OPENCODE_XDG_CONFIG_HOME=<path>` as a label; external OpenCode sessions
consume it by setting `XDG_CONFIG_HOME` to the printed path.

## Tests

Add `assets/lua/tests/test-agent-presets.fnl`:

- validates preset schema and rejects duplicate preset names
- validates `:default-state`, `:risk`, context patterns, override states, and unknown override names
- resolves context matches, `:any` wildcards, missing-field wildcards, and nil activity matches
- confirms `:off` presets never auto-activate
- confirms force `:on` and force `:off`
- confirms prompt fragments are returned in registration order
- rejects duplicate resolved MCP tool names

Add `assets/lua/tests/test-agent-presets-mcp.fnl`:

- registers only resolved preset tools
- unregisters only previously managed tools
- preserves unrelated tools
- re-registers when source tool ID changes for the same MCP name
- fails on unmanaged name collision
- emits MCP `tools/list_changed` through existing `ToolRegistry` change callbacks

Extend live MCP coverage later only after offline tests cover sync ownership and risk-default behavior.

## Known Limitations

1. Overrides are session-only. Persistent preset preferences are future work and should use `JsonUtils.write-json!` for atomic writes.
2. Preset toggles are coarse. Per-tool user toggles are intentionally deferred.
3. Tool adapters can still fail at call time if the active world/runtime does not provide the required controller. This is intentional; missing required runtime state must surface as an MCP tool error.
4. There is still one active MCP SSE stream in the current transport. Presets do not change that transport-level limitation.

## Files

### New

- `assets/lua/llm/presets/registry.fnl`
- `assets/lua/llm/presets/init.fnl`
- `assets/lua/llm/presets/tool-adapters.fnl`
- `assets/lua/llm/presets/mcp-sync.fnl`
- `assets/lua/llm/presets/builtins/drawing.fnl`
- `assets/lua/llm/presets/builtins/graph.fnl`
- `assets/lua/llm/presets/builtins/scene.fnl`
- `assets/lua/llm/presets/builtins/general.fnl`
- `assets/lua/tests/test-agent-presets.fnl`
- `assets/lua/tests/test-agent-presets-mcp.fnl`

### Modified

- `assets/lua/main.fnl`
- `assets/lua/tools/mcp-remote-server.fnl`
- `assets/lua/mcp/tool-registry.fnl` if ownership inspection is needed
- `assets/lua/tests/fast.fnl`

## References

- [remote mcp](./remote-mcp)
- [external unit mcp](./external-unit-mcp)
- [drawing architecture](./drawing-architecture)
- [graph](./graph)
- [composable states](./composable-states)
- `assets/lua/activities.fnl`
- `assets/lua/mcp/tool-registry.fnl`
- `assets/lua/llm/tools/init.fnl`

## See also

- [Agent Tools](/dev/features/agent-tools), [Agent Runner System](/dev/features/agent-runner-system)
