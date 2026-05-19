# Agent HUD Panel Design

## Overview

This note defines the initial user-facing agent UI. The panel is a global right
HUD sidebar that is always visible. It combines a session/task list with a
chat-style agent console and a compact, inspectable tool audit stream.

The implementation should prefer existing reusable widgets and general-purpose
layout primitives. Add shared widgets only when the behavior is not specific to
agents and will be useful elsewhere.

Related docs:

- `docs/dev/notes/agent-layer-design.md` - agent runner, sessions, approvals, OpenCode bridge.
- `docs/dev/notes/agent-presets.md` - context-aware capability and risk model.
- `docs/dev/widget-ownership-and-teardown.md` - widget ownership and drop rules.

## Product Decisions

The initial UI decisions are fixed:

- The panel is global and lives in the HUD on the right side.
- The panel is always visible for v1; there is no hide/collapse control.
- The active agent can change.
- The top portion shows a session/task list.
- The lower portion shows the active session console.
- Users type plain text. Context attachment is expressed in natural language.
- Tool calls are compact rows, expandable to show arguments and output.
- Approval prompts appear inline in the panel and block the turn.
- All tools may be exposed, but high-risk tools still require explicit approval.
- Initial actions are basic: send, stop, retry, copy, and show JSON.
- The visual style should be a dense operations panel, not a marketing-style assistant.

## Existing Reusable Pieces

Use these before adding new widgets:

| Need | Existing module | Notes |
|------|-----------------|-------|
| Vertical and horizontal layout | `flex.fnl`, `stack.fnl`, `padding.fnl`, `sized.fnl`, `aligned.fnl` | Main composition primitives. |
| Text | `text.fnl`, `text-style.fnl` | Use theme colors and compact scales. |
| Click actions | `button.fnl` | Supports icons, labels, variants, focus, hover, and click routing. |
| Agent selector | `combo-box.fnl` | Good enough for v1 active-agent selection. |
| Session/task list | `list-view.fnl` | Use custom row builders; avoid custom list layout. |
| Scrollable transcript | `scroll-view.fnl` | Wrap the message stream; use `scrollbar-policy :as-needed`. |
| Input | `input.fnl` | Use multiline mode with bounded line count. |
| Section surfaces | `card.fnl`, `rectangle.fnl`, `padding.fnl` | Use sparingly; avoid nested cards. |
| HUD placement | `hud-layout.fnl`, `hud.fnl` | Extend the dock model rather than adding absolute-position UI. |
| Persistence helpers | `json-utils.fnl` | Agent sessions already use atomic writes. |

Do not create an agent-only copy of `ListView`, `ScrollView`, or `Input`.
If one of these needs a small capability, extend the shared widget with tests.

## Layout

The right sidebar should be a HUD dock sibling to the existing middle/tiles
area. `hud-layout.fnl` currently supports `left-dock-builder`; generalize this
to side docks rather than hard-coding an agent panel into HUD layout.

Recommended reusable layout change:

```fennel
(HudLayout.make-hud-builder
  {:left-dock-builder ...
   :right-dock-builder ...})
```

The middle band becomes:

```text
left dock | main middle stack | right dock
```

The right dock should receive a stable width from HUD logical units. It should
not resize based on session names, tool names, or message text.

Initial sizing:

- Desktop: right dock width around 26-32 logical HUD units.
- Minimum: clamp to a compact width that still fits icon buttons and status text.
- Height: fill the middle band between the existing control panel and status panel.
- Depth: use the same dock depth layer pattern as the left dock; transcript rows
  should use child depth offsets instead of fighting with the dock background.

## Panel Wireframe

```text
┌───────────────────────────────────┐
│ Agent        [Space Agent       ▾] │
│ Status       running · big-pickle  │
├───────────────────────────────────┤
│ Sessions                          │
│ ┌ current task row              ┐ │
│ ├ older task row                ┤ │
│ └ + New session                 ┘ │
├───────────────────────────────────┤
│ Conversation                      │
│ user: draw a red circle           │
│ assistant: Done.                  │
│ ▸ tool space_draw_shape     ok    │
│   args/output when expanded       │
│ error: provider failed...         │
├───────────────────────────────────┤
│ Approval Needed                   │
│ shell · space_run_command         │
│ [Deny] [Approve once]             │
├───────────────────────────────────┤
│ [plain text input.............]    │
│ [Send] [Stop] [Retry] [JSON]      │
└───────────────────────────────────┘
```

The exact typography should be compact:

- Small section labels.
- Single-line session rows with ellipsis/truncation when needed.
- Messages wrapped inside transcript width.
- Tool rows use monospace only for tool names/JSON snippets, not for all text.

## Module Shape

Add an agent UI namespace under `assets/lua/llm/agent/ui/`:

```text
assets/lua/llm/agent/ui/
  panel.fnl              ; top-level right dock widget
  controller.fnl         ; bridges AgentRunner/session events into view model
  session-list.fnl       ; composes ListView with session row builder
  transcript.fnl         ; renders session item stream
  item-row.fnl           ; message/tool/error/approval row dispatcher
  approval-row.fnl       ; inline approval prompt row
```

Keep `panel.fnl` as composition. It should not contain low-level rendering
rules for every row type. The controller owns state and runner interactions;
widgets render state and emit user intents.

Recommended public constructor:

```fennel
(AgentPanel.AgentPanel
  {:runner app.agent-runner
   :registry app.agent-registry
   :approvals app.agent-approvals
   :providers app.agent-providers})
```

`AgentPanel` should assert these dependencies. Do not silently hide the panel
or no-op if the agent layer is missing.

## Shared Widgets To Add

Add shared widgets only if existing widgets cannot cleanly cover the behavior.
These should live outside `llm/agent/ui/`.

### `disclosure-row.fnl`

Reusable expandable row:

```fennel
(DisclosureRow
  {:summary summary-widget-builder
   :details details-widget-builder
   :expanded? false
   :on-toggle fn})
```

Use cases:

- Agent tool-call/tool-result rows.
- Debug panels.
- Future tree/list inspectors.

Behavior:

- Owns summary and details widgets directly.
- Shows details only when expanded.
- Uses an icon button with `expand_more` / `chevron_right` if available.
- Maintains stable row width; expansion affects height only.
- Emits toggle events without owning external state unless no external state is supplied.

### `status-badge.fnl`

Small reusable label for status/risk:

```fennel
(StatusBadge {:text "running" :tone :info})
```

Tones:

- `:neutral`
- `:info`
- `:success`
- `:warning`
- `:danger`

Use cases:

- Agent status.
- Tool result status.
- Approval risk.
- Future wallet/network/status views.

### `json-inspector-row.fnl` or `key-value-list.fnl`

Only add this if raw JSON display becomes too awkward with `Text` and
`ScrollView`. Prefer a generic key/value display over an agent-specific JSON
viewer.

Initial v1 can use a scrollable text block with `json.dumps` output, so this is
not required for the first slice.

## Avoid New Specialized Widgets

Do not add these as new low-level widgets:

- `AgentSessionListWidget` if it is only `ListView` plus a row builder.
- `AgentMessageBubble` if it is only padding, text, and a status badge.
- `AgentToolAccordion` if `DisclosureRow` can represent it.
- `AgentInputBox` if `Input` plus buttons is enough.

Agent-specific modules can compose reusable widgets, but they should not
duplicate generic behavior.

## View Model

The controller should maintain a small view model derived from agent sessions:

```fennel
{:agents [{:id "space-agent" :name "Space Agent"}]
 :active-agent-id "space-agent"
 :sessions [{:id "agt-ses-..." :agent-id "space-agent" :title "Draw..."
             :status :idle :updated-at 1700000000}]
 :active-session-id "agt-ses-..."
 :items [...]
 :active-turn {:id "turn-..." :status :running}
 :expanded-items {"itm-tool-call" true}
 :pending-approval nil
 :last-error nil}
```

The controller should be the only part of the UI that calls:

- `AgentRunner:create-session`
- `AgentRunner:list-sessions`
- `AgentRunner:get-session`
- `AgentRunner:run-turn`
- `AgentRunner:cancel-turn`

Widgets emit intents:

- `:select-agent`
- `:new-session`
- `:select-session`
- `:send`
- `:stop`
- `:retry`
- `:copy`
- `:show-json`
- `:toggle-expanded`
- `:approve`
- `:deny`

This keeps the UI testable and prevents runner calls from scattering across row
widgets.

## Data Mapping

Agent sessions are canonical item streams. The transcript should render item
types directly:

| Item type | Row |
|-----------|-----|
| `message` + `role :user` | User message row |
| `message` + `role :assistant` | Assistant message row |
| `tool-call` | Compact disclosure row: tool name + arguments |
| `tool-result` | Prefer pairing with matching tool call; otherwise standalone result row |
| `error` | Error row with danger tone |
| `event` | Low-emphasis event row |

Tool call/result pairing:

- Pair by `call-id`.
- If both exist, show one disclosure row:
  - summary: tool name, status, short output/error preview.
  - details: arguments, output, provider, timestamps.
- If result is missing while a turn is running, show `running`.
- If `is-error` is true, use danger tone.

Do not parse or mutate session files in UI code. Use `AgentRunner:get-session`
and the in-memory item tables.

## Session / Task List

The session list is a compact task list for the active agent:

- Current session at top.
- Recent sessions below, sorted by `updated-at` descending.
- Row content:
  - title derived from first user message or session id fallback.
  - status badge: idle/running/error.
  - short timestamp.
- `+ New session` button below or above the list.

Use `ListView` with a custom row builder. Do not write a custom scrolling list.

Initial behavior:

- On first render, if there are no sessions for the selected agent, create one.
- Selecting a different agent switches the session list to that agent.
- New session uses the selected agent.
- Deleting sessions can wait until after the first UI slice unless it is needed
  for test cleanup.

## Conversation Console

The console is:

- A `ScrollView` containing a vertical `Flex` of transcript rows.
- A bottom input row using `Input` and buttons.
- A small status strip with provider/model/turn status.

Initial input rules:

- Plain text only.
- `Enter` sends for single-line mode.
- If multiline is enabled, use `Ctrl+Enter` to submit and keep `Enter` for
  newline, matching existing input behavior where possible.
- Disable send while a turn is running; show `Stop`.
- Keep `Retry` enabled only when the latest user input exists and no turn is
  running.

The transcript should auto-scroll to bottom when a new item is appended, unless
the user has manually scrolled away from the bottom. If current `ScrollView`
does not expose this behavior cleanly, add a small shared option to `ScrollView`
instead of agent-specific scroll code.

## Approvals

All tools can be visible, but high-risk tools must still require explicit
approval before execution.

The current approval module is synchronous and policy-based. To support user
approval UI, extend it toward pending decisions without breaking the existing
fast path:

```fennel
{:id "apr-..."
 :risk :shell
 :reason "space_shell requested by Space Agent"
 :tool "space_shell"
 :session-id "agt-ses-..."
 :turn-id "turn-..."
 :status :pending}
```

Recommended `AgentApprovals` API extension:

```fennel
:pending() -> list
:approve(id decision)
:deny(id decision)
:add-on-change(fn)
:remove-on-change(token)
```

For v1:

- Normal-risk tools auto-approve.
- Ask-policy tools create a pending approval and block the tool/turn.
- The panel renders the pending approval inline above the input.
- `Approve once` resumes the pending action.
- `Deny` fails or unblocks the turn with an explicit denial item.

If resuming blocked tool execution is too large for the first UI slice, the
first implementation may deny by default and require the user to retry after
approval policy changes. That is less ergonomic but still safe. The target UX is
blocking/resume.

## Basic Actions

### Stop

Calls `AgentRunner:cancel-turn active-session-id`.

Display:

- Stop button only while running.
- Turn status changes to `cancelled`.
- Error/cancel item remains visible in transcript.

### Retry

Initial retry behavior:

- Find the latest user message in the active session.
- Submit its content as a new turn in the same session.
- Do not delete or rewrite previous items.

This creates an auditable retry trail.

### Copy

Use `gl.clipboard-set` on:

- assistant message content,
- user message content,
- tool JSON/details,
- error text.

### Show JSON

For v1, show raw item JSON in an expandable details area or a simple modal-like
overlay using existing HUD overlay/dialog patterns. Prefer reusable
`DisclosureRow` details first; add a generic JSON inspector only if needed.

## HUD Integration

Implementation should not manually place the agent panel with absolute
positions. Extend `HudLayout.make-hud-builder` to accept `right-dock-builder`.

Suggested integration:

```fennel
(HudLayout.make-hud-builder
  {:right-dock-builder
   (fn [ctx]
     ((AgentPanel.AgentPanel {:runner app.agent-runner
                              :registry app.agent-registry
                              :approvals app.agent-approvals
                              :providers app.agent-providers})
      ctx))})
```

The panel builder must require the same `ctx` services as its child widgets:

- `clickables`
- `hoverables`
- `focus`
- `menu-manager` if context menus are used
- `system-cursors` if hover cursor changes are needed

Do not guard missing `clickables` or `hoverables`; assert through the widgets
that require them.

## State And Update Flow

Avoid frame-by-frame polling if possible. Prefer direct signals/callbacks.

Initial practical flow:

1. `AgentPanelController` loads agents and sessions on build.
2. Session list refreshes after create/delete/select.
3. `run-turn` callbacks append items and update status.
4. Approval changes emit a controller refresh.
5. UI calls `layout:mark-measure-dirty` on affected shared root when list/item
   counts change.

Only use `app.engine.events.updated` if no direct callback exists. The agent
runner already emits turn callbacks; lean on those.

## Ownership And Teardown

Follow `docs/dev/widget-ownership-and-teardown.md`.

Rules:

- `AgentPanel` owns its top-level composite root and controller.
- Row widgets own only their direct child widgets.
- Do not manually drop descendants already owned by a `Flex`, `Stack`,
  `ListView`, or `ScrollView`.
- The controller owns runner callback handles/listeners it registers.
- `AgentPanel:drop` drops the root widget and disconnects controller listeners.

Expected shape:

```fennel
(fn drop [self]
  (self.controller:drop)
  (self.root:drop))
```

## Visual Design

The panel should be quiet and dense:

- Use theme panel/background colors.
- Avoid large cards; use full-width bands and row separators.
- Use icons for common actions where existing Material icon names are available:
  - `send`
  - `stop`
  - `refresh`
  - `content_copy`
  - `data_object` or equivalent JSON/details icon
  - `expand_more`
  - `chevron_right`
- Validate icon names against `assets/material-design-icons/icons.txt`.
- Keep labels short and stable.
- Prefer fixed row heights for session rows and compact tool rows.
- Message rows may grow vertically with wrapped text.

Color/tone guidance:

- `running`: info tone.
- `completed`/tool ok: success tone.
- `needs approval`: warning tone.
- `failed`/tool error: danger tone.
- `idle`: neutral tone.

## Testing Plan

Fast tests:

- Controller creates a first session when none exist.
- Controller lists sessions for the active agent.
- Sending text calls `AgentRunner:run-turn`.
- Stop calls `AgentRunner:cancel-turn`.
- Retry resubmits the latest user message.
- Transcript maps message/tool/error items to expected row descriptors.
- Tool call/result pairing by `call-id`.
- Disclosure row toggles details and preserves stable width.
- Approval row emits approve/deny intents.
- HUD layout right dock reserves width and leaves middle stack usable.
- Drop disconnects controller callbacks and drops root once.

E2E snapshot tests:

- Right agent panel visible by default.
- Empty state with new session button.
- Transcript with user, assistant, compact tool row.
- Expanded tool row.
- Pending approval row.
- Running state with stop button.

Live/manual tests:

- Run `tests.test-agent-mcp-online:main`.
- Start app and submit a normal-risk prompt.
- Verify tool calls appear in compact rows.
- Verify high-risk prompt creates approval UI before execution.
- Verify stop cancels an active OpenCode turn.

## Implementation Phases

### Phase 1 - Reusable Layout Support

- Generalize `hud-layout.fnl` from `left-dock-builder` to left and right dock builders.
- Add tests for right dock measurement/placement.
- Add `DisclosureRow` and `StatusBadge` shared widgets if existing widgets are insufficient.

### Phase 2 - Passive Agent Panel

- Add `llm/agent/ui/panel.fnl`, `controller.fnl`, `session-list.fnl`, and `transcript.fnl`.
- Render static/session-derived state without sending turns.
- Use `ListView`, `ScrollView`, `Input`, `Button`, `ComboBox`, `Flex`, and `Text`.

### Phase 3 - Runner Integration

- Wire new session, select session, send, stop, retry.
- Update transcript through runner callbacks.
- Keep all runner calls in the controller.

### Phase 4 - Tool Audit UX

- Render paired tool calls/results as compact `DisclosureRow`s.
- Add copy and show JSON actions.
- Add fast tests for pairing, failed results, and expansion state.

### Phase 5 - Approval UX

- Extend `AgentApprovals` for pending decisions.
- Render inline approval rows.
- Wire approve once and deny.
- Add tests for approval state transitions.

### Phase 6 - Snapshot And Live Validation

- Add E2E snapshots for the panel states.
- Run fast suite and live OpenCode MCP suite.

## Open Questions

These are not blockers for the first implementation, but should be settled
before broad exposure:

- Should panel width be user-resizable later, or fixed by HUD settings?
- Should session deletion be in v1 or delayed?
- Should approval decisions persist across app restarts, or only live in memory?
- Should `Approve once` apply to one tool call, one turn, or one session?
- Should the transcript show provider/model per message or only in the status strip?

## Definition Of Done For V1

- The right HUD agent panel is visible by default.
- The user can create/select a session and send plain text to the selected agent.
- Running, completed, failed, and cancelled states are visible.
- Tool calls/results are visible as compact expandable rows.
- High-risk tools can be exposed but require inline approval.
- Stop and retry work.
- The UI uses reusable widgets and shared primitives; no duplicate custom list,
  scroll, input, or accordion logic.
- Fast tests and HUD snapshot tests cover the main states.
