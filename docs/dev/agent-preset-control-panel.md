# Agent Preset Control Panel

## Purpose

Space Agent can currently act only through presets resolved from the current interaction context. That works for
local context-sensitive assistance, but it blocks legitimate cross-context work. For example, the user may be on
the drawing canvas and still want Space Agent to inspect graph nodes, manage scene objects, or run a file search.

The preset control panel exposes the preset system directly in the Agent panel so the user can choose which
capabilities Space Agent has right now.

This is not a replacement for tool approvals. Preset selection is a user action and can be trusted. Tool execution
is a model action and still needs approval policy enforcement for risky operations.

## Existing Model

The agent layer is split into three responsibilities:

- Agents own turn orchestration. `AgentRunner` loads a session, resolves `session.agent-id`, builds the run context,
  and calls `agent.run`.
- Presets own capability selection. `PresetRegistry` resolves active presets from context and overrides.
- Tool surfaces own executable tool exposure. `AgentToolSurface` converts resolved preset tool IDs into tool
  definitions and applies approval policy before execution.

Current preset shape:

```fennel
{:name "drawing-shape-tools"
 :group "drawing"
 :default-state :auto
 :risk :normal
 :contexts [{:surface :canvas :mode "drawing"}]
 :tool-ids ["drawing.inspect" "drawing.set-tool"]
 :system-prompt "Use drawing tools for shape and stroke operations."}
```

Current override states:

- `:auto`: context decides.
- `:on`: preset is active regardless of context.
- `:off`: preset is inactive regardless of context.

These semantics are already implemented in `PresetRegistry.resolve` and `PresetManager.set-override`.

## Trust Boundary

The panel must preserve this distinction:

- User-selected preset override: trusted control-plane state.
- Model-selected tool call: untrusted action request.

Therefore:

- Toggling a preset does not require confirmation.
- Toggling a preset does not auto-run any tool.
- Risk labels are visible, but never block preset toggles.
- Existing approval behavior remains for tool calls chosen by the model.

Example:

1. User pins `general-shell-tools` to `on`.
2. Space Agent now sees shell capability.
3. Model decides to call `space_app_run_bash`.
4. Approval policy still handles that tool execution because the action was chosen by the model.

## User Experience

Add a `Presets` area to the Agent panel.

The user should be able to:

- See all registered presets, including inactive context-mismatched presets.
- See which presets are active.
- See why each active preset is active: context or override.
- Pin any preset `on`.
- Force any preset `off`.
- Return any preset to `auto`.
- See risk level and tool count before changing state.
- Reset all overrides.

No confirmation dialogs or warnings are shown when changing states.

## Layout

Recommended panel structure:

1. Agent selector.
2. Status row.
3. Agent tabs:
   - `Sessions`
   - `Presets`
4. Transcript.
5. Pending approval row.
6. Input row.

Tabs avoid shrinking the transcript while still making presets easy to find.

Initial implementation can use a simpler inline section above sessions if adding tabs is more work than justified.
The controller/view model should be independent of the final layout so the UI can move later.

## Preset Row

Each preset row contains:

- Name.
- Group.
- Three-state segmented control: `Auto`, `On`, `Off`.
- Active badge: `active`, `inactive`, or `pinned`.
- Risk badge.
- Tool count.
- Optional expanded tool ID list.

State labels:

- `auto active`: no override, context matched.
- `auto inactive`: no override, context did not match.
- `pinned on`: override `:on`, active because of user.
- `forced off`: override `:off`, inactive because of user.

Risk display:

- `normal`: neutral.
- `filesystem-read`: info.
- `filesystem-write`: warning.
- `destructive`: danger.
- `shell`: danger.

Risk is informational only in this panel.

## Controller View Model

`AgentPanelController` should receive `:presets`.

```fennel
(AgentPanelController {:runner opts.runner
                       :registry opts.registry
                       :approvals opts.approvals
                       :presets opts.presets})
```

Extend controller state:

```fennel
{:preset-rows []
 :preset-groups []
 :expanded-preset-groups {}
 :expanded-presets {}}
```

Computed row shape:

```fennel
{:name preset.name
 :group (or preset.group "other")
 :risk preset.risk
 :default-state preset.default-state
 :contexts preset.contexts
 :tool-ids preset.tool-ids
 :tool-count (# preset.tool-ids)
 :override-state (or override.state :auto)
 :active? active?
 :active-reason active.reason}
```

Controller methods:

```fennel
:load-presets
:set-preset-override
:reset-preset-overrides
:toggle-preset-expanded
:toggle-preset-group-expanded
:is-preset-expanded?
:is-preset-group-expanded?
```

`load-presets`:

1. Read all presets from `presets.registry:list`.
2. Read active presets from `presets:get-active-presets`.
3. Read overrides from `presets:get-overrides`.
4. Build rows grouped by `group`.
5. Sort groups by name.
6. Sort rows by name inside each group.
7. Store rows in controller state.
8. Emit controller change signal.

`set-preset-override`:

```fennel
(fn set-preset-override [self name state]
  (presets:set-override name state)
  (self:load-presets))
```

`reset-preset-overrides`:

```fennel
(each [name _override (pairs (presets:get-overrides))]
  (presets:set-override name :auto))
```

The reset operation should not unregister presets or modify context.

## Change Propagation

`AgentPanelController` should subscribe to `presets:add-on-change` during `init`.

On preset change:

- Recompute preset rows.
- Refresh active state and override labels.
- Let existing MCP sync/tool surface listeners update active tool definitions.

On `drop`:

- Remove preset change listener.
- Clear controller state.

The preset manager already emits changes only when the effective signature changes. The panel can still call
`load-presets` after direct user changes so UI state remains immediate even when a state change does not alter
effective active tools.

## Persistence

Initial implementation should use in-memory overrides only, matching current `PresetManager` behavior.

Do not add persistence in the same change unless required by product work. Persistence needs a separate decision:

- App-global overrides.
- Per-agent overrides.
- Per-session overrides.
- Per-world overrides.

Recommended later default: app-global overrides saved atomically with `JsonUtils.write-json!`. The user is controlling
Space Agent's capability surface, so app-global behavior is easiest to understand.

## Prompt and Tool Effects

When a preset becomes active:

- Its tool IDs resolve through `PresetManager:get-tool-defs`.
- Its prompt fragment appears in `AgentToolSurface:prompt-fragments`.
- Space Agent includes active preset names in `Available Capabilities`.
- Space Agent includes preset guidance in `Capability Guidance`.

No additional Space Agent changes are required for basic preset control.

## Approval Effects

Preset toggles must not call `approvals`.

Approvals remain only at model-action time:

- `AgentToolSurface:call` checks active tool.
- `run-with-approval` requests risk approval for tool arguments.
- `space_agent_request_tool_approval` remains available for the model to request approval before risky calls.

This keeps the policy coherent: user can grant capability exposure, but model cannot silently execute risky actions.

## Failure Behavior

The UI should fail loudly for invalid state.

- Unknown preset name: surface the `PresetManager:set-override` error.
- Invalid override state: surface the error.
- Missing `opts.presets`: assert in `AgentPanel` and `AgentPanelController`.
- Missing preset registry access: assert when building rows.

Do not silently hide broken presets. A broken capability surface is a product bug, not a user preference.

## Implementation Plan

### 1. Controller Support

Update `assets/lua/llm/agent/ui/controller.fnl`.

Add required `opts.presets`.

Add state fields:

```fennel
:preset-rows []
:preset-groups []
:expanded-preset-groups {}
:expanded-presets {}
```

Add listener lifecycle:

```fennel
(var preset-change-listener nil)
```

In `init`, connect:

```fennel
(set preset-change-listener
     (presets:add-on-change
       (fn []
         (self:load-presets))))
```

In `drop`, disconnect with `presets:remove-on-change`.

Add methods listed above and include them in the returned controller table.

### 2. Preset List Widget

Add `assets/lua/llm/agent/ui/preset-list.fnl`.

Pattern after `session-list.fnl`:

- Use `ListView`.
- Header: `Presets` plus reset button.
- Rows grouped by `group`.
- Row click can expand/collapse details.
- `Auto`, `On`, `Off` buttons call `controller:set-preset-override`.
- Expanded row shows contexts and tool IDs.

Controls:

- Use icon buttons where appropriate.
- Use text buttons for `Auto`, `On`, `Off` because they are state labels, not generic icon actions.
- Keep rows compact.

### 3. Panel Integration

Update `assets/lua/llm/agent/ui/panel.fnl`.

Requirements:

- Assert `opts.presets`.
- Pass `:presets` into `AgentPanelController`.
- Build `AgentPresetList`.
- Include preset widget in layout.

First pass layout:

```fennel
(local preset-list (AgentPresetList controller))
(local preset-list-widget (preset-list ctx))

(local sections [(FlexChild (fn [_ctx] agent-row-padded))
                 (FlexChild (fn [_ctx] status-row-padded))
                 (FlexChild (fn [_ctx] preset-list-widget) 0)
                 (FlexChild (fn [_ctx] session-list-widget) 0)
                 (FlexChild (fn [_ctx] transcript-widget) 1)
                 ...])
```

If height becomes cramped, add tabs in a follow-up instead of overfitting the first patch.

Refresh path:

```fennel
(preset-list-widget:refresh)
```

Drop path:

```fennel
(preset-list-widget:drop)
```

### 4. App Wiring

Find current `AgentPanel` construction site and pass the existing `PresetManager` instance as `:presets`.

Do not create another preset manager for the panel. The panel must control the same manager used by:

- Agent runner context.
- Agent tool surface.
- MCP sync.

### 5. Tests

Add or extend Fennel tests.

Controller tests:

- Controller requires `:presets`.
- `load-presets` includes inactive presets.
- Context-active preset row reports `active? true` and `active-reason :context`.
- `set-preset-override name :on` activates context-mismatched preset.
- `set-preset-override name :off` deactivates context-matched preset.
- `set-preset-override name :auto` returns to context behavior.
- `reset-preset-overrides` returns all overrides to `:auto`.
- Preset manager change listener refreshes rows.
- `drop` removes preset listener.

Preset list widget tests:

- Build with dummy context.
- Refresh after controller state changes.
- Toggle buttons call controller override method.
- Expanded details show tool IDs.

Integration tests:

- Pin graph preset on while context is drawing.
- Verify graph tool IDs resolve through `PresetManager:get-tool-ids`.
- Verify `AgentToolSurface:mcp-tool-defs` includes graph tools.
- Verify risky tool still goes through approval when called.

Recommended direct test command:

```sh
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

## Non-Goals

This design does not:

- Add a router agent.
- Add sub-agent orchestration.
- Persist preset overrides.
- Remove tool approvals.
- Add per-session capability profiles.
- Add model-driven preset selection.

Those are separate features.

## Open Questions

- Should overrides eventually be app-global, per-agent, per-session, or per-world?
- Should the UI show raw tool IDs by default or only when expanded?
- Should risky presets sort to the bottom of each group?
- Should there be a one-click `All graph`, `All scene`, `All drawing` group state control?

The initial implementation can defer these and keep the contract small: every preset gets `Auto`, `On`, and `Off`.


## See also

- [[../../knowledge/home|Knowledge Base]]
