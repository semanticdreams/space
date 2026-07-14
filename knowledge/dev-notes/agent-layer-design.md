---
type: dev-note
tags:
  - note
---

# Agent Layer Design

## Overview

The agent presets system (`knowledge/dev-notes/agent-presets.md`) exposes context-aware Space capabilities as MCP tools for opencode. This design covers the next layer: runtime agents that use those capabilities, LLM providers, local deterministic functions, and other agents to perform tasks for the user.

An agent is a runtime object built from a factory. It receives user input, a persisted session, and a turn context. It starts the work for that turn, registers cancellation with the runner, emits item updates through the context, and completes through a turn handle.

The runner owns session lifecycle, persistence, active-turn bookkeeping, and callback delivery. Agents own orchestration, provider choice, prompt composition, tool-loop logic, and provider-specific details.

## Design Goals

1. **Flexible**: An agent can use OpenCode, Codex, OpenAI, ZAI, deterministic functions, or other agents. Like LangGraph without the graph engine: the agent object owns its internal control flow.
2. **Persistent from day one**: Agent sessions are serializable JSON. The canonical history is an item stream, not lossy chat text. Display messages are projections from those items.
3. **Context-aware**: Agents receive app context, active presets, prompt fragments, and active tools. A single `SpaceAgent` can adapt between drawing, graph, scene, and app-level work.
4. **Risk-aware**: High-risk presets require explicit approval before the agent can enable or use them. The agent layer must not silently turn on shell, filesystem-write, or destructive capabilities.
5. **Minimal provider abstraction**: Agents import provider SDKs directly. Shared helpers are allowed where the repo already has a concrete boundary, but there is no generic provider framework in v1.
6. **Runtime factory pattern**: Agents are constructed at bootstrap by factory functions that close over dependencies (`app`, presets, provider clients, stores, policy objects), matching the rest of the Fennel codebase.

## Existing LLM Stack

| Provider | Module | Style | Tool execution | Turn shape |
|----------|--------|-------|----------------|------------|
| OpenCode SDK | `llm/providers/opencode.fnl` | Local CLI server, async HTTP callbacks | Server-side through MCP | `session.prompt` callback, optional `session.abort` |
| Codex SDK | `llm/providers/codex.fnl` | Local CLI subprocess, JSONL stdout | Server-side through Codex | `run-streamed` returns a pollable/cancellable handle |
| OpenAI API | `llm/providers/openai.fnl` | HTTP callbacks | Client-side loop in `llm/conversations/requests.fnl` | request id plus callbacks |
| ZAI API | `llm/providers/zai.fnl` | HTTP callbacks | Client-side loop in `llm/conversations/requests.fnl` | request id plus callbacks |

The repo already has three important boundaries:

- `llm/conversations/store.fnl`: persisted conversations, messages, tool calls, tool results, parent links, usage, model metadata, and graph adapters.
- `llm/conversations/requests.fnl`: OpenAI/ZAI request orchestration and client-side tool loops.
- `llm/presets/*` plus `mcp/tool-registry.fnl`: context-aware capability resolution and MCP-facing tool sync.

The agent layer should reuse these patterns without coupling agent sessions to the existing chat UI in v1.

## Architecture Decisions

### Provider abstraction layer

A uniform provider interface is deferred. OpenCode, Codex, OpenAI, and ZAI have different lifecycle, cancellation, streaming, and tool-loop behavior. A v1 abstraction would either leak or erase useful provider semantics.

Agents import providers directly. If 2-3 agents duplicate the same provider control flow, extract a helper then.

### Graph orchestration

Graph-based orchestration is deferred. The first useful layer is a small runner plus agent factories. Agents can use normal Fennel control flow internally. Reconsider a graph/state-machine runner only when real agents need durable multi-step checkpointing, parallel branches, or inspectable internal workflows.

### Agent-as-runtime-object

The chosen contract is:

```fennel
(agent:run input session ctx) ;; starts or drives a turn, returns nil
```

The agent does not return the final result directly. It reports through `ctx.turn` and callbacks because the actual providers are callback/handle based. The runner returns a `TurnHandle` to the caller immediately.

### Single SpaceAgent for v1

The initial drawing/scene/graph/app assistant should be one `SpaceAgent`. The preset layer already filters capabilities by context. Split into `DrawingAgent`, `SceneAgent`, or `CodeAgent` only when prompts, models, permissions, or provider flows genuinely diverge.

## Chosen Architecture

```text
AgentRegistry  <- built-in agents registered at app bootstrap
     |
AgentRunner    <- sessions, persistence, active turns, TurnHandle
     |
TurnContext    <- app, presets, tools, approvals, callbacks, turn controller
     |
Agent:run(input, session, ctx)
     |
     +-- imports providers directly
     +-- reads ctx.presets and ctx.tools
     +-- registers provider cancellation with ctx.turn:set-cancel
     +-- appends canonical items through ctx.turn:append-item
     +-- finishes through ctx.turn:finish or ctx.turn:fail

AgentOpencodeMcpBridge <- loopback MCP HTTP plus isolated OpenCode config
```

The runner knows how to cancel a turn because the agent registers the cancellation function. The runner still does not know whether the active backend is Codex, OpenCode, OpenAI, ZAI, or a deterministic function.

## Module Design

### `llm/agent/session.fnl`

Agent sessions are in-memory tables backed by JSON files under the user data directory.

```fennel
{:id "agt-ses-abc123"
 :agent-id "space-agent"
 :status :idle
 :items [{:id "itm-1"
          :type "message"
          :role "user"
          :content "draw a red circle"
          :created-at 1700000000}
         {:id "itm-2"
          :type "tool-call"
          :name "space_drawing_insert_shape"
          :arguments "{\"shape\":\"circle\",\"color\":\"#ff0000\"}"
          :call-id "call-1"
          :parent-id "itm-1"
          :created-at 1700000001}
         {:id "itm-3"
          :type "tool-result"
          :name "space_drawing_insert_shape"
          :output "{\"ok\":true}"
          :call-id "call-1"
          :parent-id "itm-2"
          :created-at 1700000001}
         {:id "itm-4"
          :type "message"
          :role "assistant"
          :content "Done."
          :parent-id "itm-3"
          :provider "opencode"
          :model "selected-model"
          :usage {:input-tokens 0 :output-tokens 0}
          :created-at 1700000002}]
 :data {}              ;; agent-owned serializable state
 :created-at 1700000000
 :updated-at 1700000002}
```

Canonical item types for v1:

- `message`: `:role`, `:content`, optional provider/model/usage.
- `tool-call`: `:name`, `:arguments`, `:call-id`, optional provider/source.
- `tool-result`: `:name`, `:output`, `:call-id`.
- `event`: structured provider or workflow event that is worth preserving.
- `error`: failed turn or provider failure.

This intentionally mirrors `llm/conversations/store.fnl` enough that graph nodes can later adapt it without migration loss. The session API should expose `append-item` rather than `append-message`; helper projections can derive chat-style messages for UI.

Persistence rules:

- Directory: `{app.user-data-dir}/agent-sessions/{session-id}.json`.
- Use `JsonUtils.write-json!` for atomic writes.
- Cache loaded sessions in memory and allow explicit `invalidate-cache`.
- `list-sessions()` reads metadata from files without eagerly loading full item history when possible.
- Save after user input is appended, after each persisted provider/tool item, and at turn completion.

Public API:

```fennel
{:create-session    ;; (agent-id data-dir) -> session
 :load-session      ;; (id data-dir) -> session or nil
 :save-session      ;; (session data-dir) -> session
 :delete-session    ;; (id data-dir)
 :list-sessions     ;; (data-dir) -> metadata list
 :append-item       ;; (session item) -> persisted item
 :update-session    ;; (session updates) -> session
 :invalidate-cache} ;; (id)
```

### `llm/agent/registry.fnl`

The registry maps stable agent IDs to factories.

```fennel
(AgentRegistry {:deps deps})
;; :register(id factory)
;; :get(id) -> agent or nil
;; :list() -> [{:id :name}]
;; :unregister(id)
```

Factories are called lazily on first `:get` and cached. They receive the registry deps, so agents can close over app services without global lookups.

### `llm/agent/turn.fnl`

`TurnHandle` is the public lifecycle object returned by `AgentRunner:run-turn`.

```fennel
{:id "turn-abc"
 :session-id "agt-ses-abc123"
 :status ;; :running, :completed, :failed, :cancelled
 :result ;; final summary or nil
 :error  ;; error message or nil
 :cancel      ;; () -> true
 :running?    ;; () -> bool
 :wait        ;; optional blocking helper for tests/CLI callers
 :on-complete ;; signal or callback registration helper
 :on-error}   ;; signal or callback registration helper
```

`TurnController` is passed to agents as `ctx.turn`.

```fennel
{:append-item  ;; persist item, emit on-item
 :update-item  ;; optional for streaming partials
 :set-cancel   ;; agent registers provider-specific cancellation fn
 :finish       ;; complete with result summary
 :fail         ;; fail with explicit error
 :cancelled?}  ;; agent/provider checks cooperative cancellation
```

The runner creates the handle/controller pair. Agents never mutate `active-turn` directly.

### `llm/agent/runner.fnl`

The runner owns session CRUD, active-turn bookkeeping, persistence, and callback delivery.

```fennel
(AgentRunner {:data-dir (fs.join-path app.user-data-dir "agent-sessions")
              :registry app.agent-registry
              :deps {:app app
                     :presets app.agent-presets
                     :tools app.agent-tool-surface
                     :approvals app.agent-approvals
                     :providers app.agent-providers}})
```

Public API:

```fennel
{:create-session
 :get-session
 :run-turn       ;; (session-id input callbacks) -> TurnHandle
 :cancel-turn    ;; (session-id) -> true
 :delete-session
 :list-sessions
 :flush
 :drop}
```

`run-turn` flow:

1. Load the session.
2. Resolve the agent.
3. If a turn is active for this session, cancel it before starting the new turn.
4. Append and persist the user message item.
5. Create a `TurnHandle` and `TurnController`.
6. Build the context: app, presets, tool surface, approvals, provider instances, callbacks, session ID, data dir, turn controller.
7. Call `agent:run input session ctx`.
8. Return the handle immediately.

Completion flow:

1. Agent or provider callback calls `ctx.turn:append-item` as durable output arrives.
2. Agent calls `ctx.turn:finish result` or `ctx.turn:fail err`.
3. Runner marks status, flushes session, clears the active turn, and fires callbacks.

Blocking callers use `handle:wait`; UI callers subscribe to callbacks/signals.

### `llm/agent/tool-surface.fnl`

The agent layer needs one tool surface that is derived from active presets and can serve all providers.

This is not a provider abstraction. It is a capability adapter over the preset layer.

```fennel
(AgentToolSurface {:presets app.agent-presets
                   :mcp-tools app.mcp-tools
                   :approvals app.agent-approvals})
;; :active-presets() -> preset metadata
;; :prompt-fragments() -> prompt fragments
;; :mcp-tools() -> MCP defs for OpenCode/Codex remote MCP
;; :openai-tools() -> OpenAI/ZAI function tool defs for client-side loops
;; :call(name args ctx) -> execute active local tool by external name
;; :require-risk(risk reason callbacks) -> approved? or explicit error
```

For OpenCode/Codex, tools are normally exposed through MCP sync. For OpenAI/ZAI, the same resolved preset tools are converted from MCP `:inputSchema`/`:run` into OpenAI-style `:parameters`/`:call` definitions. This keeps context filtering and risk policy identical across providers.

The existing `llm/tools/init.fnl` filesystem/shell tools are not registered directly. Reusable logic can be shared behind preset adapters, but all agent-visible tools must pass through the preset/risk layer.

### `llm/agent/mcp-sync.fnl`

Agent-facing MCP sync must use `AgentToolSurface`, not raw `PresetManager:get-tool-defs`.

```fennel
(AgentMcpSync {:surface app.agent-tool-surface
               :change-source app.agent-presets
               :tool-registry app.mcp-tools
               :owner "agent-tools"})
;; :start()
;; :sync()
;; :stop()
;; :status()
```

This is the MCP boundary used by provider-side tool callers such as OpenCode. It registers only `surface:mcp-tool-defs`, so approval and risk filtering are applied before tools become visible over MCP. The raw preset sync remains useful for preset-layer tests and non-agent diagnostics, but production agent MCP exposure should be through `AgentMcpSync`.

`change-source` is usually the preset manager; preset context changes trigger a resync. Approval policy changes can call `:sync` explicitly if a future UI lets users approve capabilities while a session is live.

### `llm/agent/opencode-mcp-bridge.fnl`

OpenCode needs a concrete MCP endpoint and config file before it can see Space
tools. The bridge owns both pieces so production, tests, and future live
debugging all use one setup path.

```fennel
(AgentOpencodeMcpBridge {:tools app.mcp-tools
                         :data-dir (fs.join-path app.user-data-dir "agent-opencode")})
;; :start()
;; :stop()
;; :opencode-env() -> {:XDG_CONFIG_HOME config-root}
;; :status() -> {:started? :host :port :url :config-root :config-path}
```

Rules:

- Bind only to loopback by default.
- Start the MCP HTTP server with `:force-sse true` so OpenCode uses the SSE transport.
- Write `{config-root}/opencode/opencode.json` through `JsonUtils.write-json!`.
- Fail loudly if the server cannot bind or if the config cannot be written.
- Give OpenCode only the bridge-owned `XDG_CONFIG_HOME`; do not rely on the user's normal OpenCode config.

### `llm/agent/approvals.fnl`

The approval layer centralizes risk decisions. V1 can be simple, but it must be explicit.

```fennel
(AgentApprovals {:policy {:normal :auto
                          :filesystem-read :ask
                          :filesystem-write :ask
                          :destructive :ask
                          :shell :ask}})
;; :check-risk(risk context) -> :approved, :denied, or :needs-approval
;; :request-risk(risk context callbacks) -> result
;; :record-decision(decision)
```

Rules:

- `:normal` may run automatically.
- `:filesystem-read`, `:filesystem-write`, `:destructive`, and `:shell` require user approval unless a user-controlled policy has already granted them.
- Agents may ask to enable a preset through `ctx.approvals`, but they must not call `PresetManager:set-override` for high-risk presets without approval.
- Denials are persisted as turn items so the user can inspect why a task stopped.

### `llm/agent/prompt-utils.fnl`

Prompt utilities are optional. They do not own provider behavior.

```fennel
{:render-template
 :format-context
 :format-presets
 :assemble-blocks
 :register-enricher
 :remove-enricher}
```

`format-context` runs registered enrichers:

```fennel
(PromptUtils.register-enricher
  :active-world
  (fn [ctx]
    (when ctx.app.world-manager
      "active world available")))
```

Enrichers live in `prompt-utils`, not on `AgentRunner`, so the runner API stays focused on lifecycle.

### `llm/agent/builtins/space-agent.fnl`

The initial agent uses OpenCode because the preset/MCP path is already built for it. Provider and model choice belong to the concrete agent configuration, not `AgentRunner`; the runner only supplies lifecycle, session, callback, and shared service context.

```fennel
(fn SpaceAgent [deps]
  (local model deps.model)
  (local self
    {:id "space-agent"
     :name "Space Agent"
     :run (fn [self input session ctx]
            (local PromptUtils (require :llm/agent/prompt-utils))
            (local context-block (PromptUtils.format-context ctx))
            (local preset-block (PromptUtils.format-presets ctx.presets))
            (local capability-guidance (table.concat
                                          (icollect [_ fragment (ipairs (ctx.tools:prompt-fragments))]
                                            fragment.prompt)
                                          "\n"))
            (local system-prompt
              (PromptUtils.assemble-blocks
                [{:name "Instructions"
                  :content "You are Space Agent. Help with drawing, graph, scene, and app tasks using only approved available tools."}
                 {:name "Context" :content context-block}
                 {:name "Available Capabilities" :content preset-block}
                 {:name "Capability Guidance" :content capability-guidance}]))
            ;; OpenCode session lifecycle, prompt body, concrete model choice,
            ;; callbacks, and cancellation
            ;; are owned here. The agent calls ctx.turn:set-cancel with session.abort
            ;; and reports output through ctx.turn:append-item / ctx.turn:finish.
            ;; After prompt success, it fetches OpenCode messages and persists
            ;; tool-call/tool-result audit items before the assistant message.
            )})
  self)

{:register
 (fn [registry deps]
   (registry:register "space-agent" (fn [_registry-deps] (SpaceAgent deps))))}
```

`SpaceAgent` stores the OpenCode session ID under `:opencode-session-id` in
`session.data` and validates it before reuse. If OpenCode rejects the stored
session ID, the agent clears it and creates a replacement.

## Context Object

Passed to agents on every turn:

```fennel
{:app app
 :presets app.agent-presets
 :tools app.agent-tool-surface
 :approvals app.agent-approvals
 :agents app.agent-registry
 :callbacks {:on-item fn :on-partial fn :on-finish fn :on-error fn}
 :turn turn-controller
 :session-id session.id
 :data-dir data-dir
 :providers app.agent-providers}
```

Required fields should be asserted by the runner when the context is built. Missing app services or missing tool surfaces should fail loudly.

## Integration with `main.fnl`

Bootstrap after `app.user-data-dir`, `app.agent-presets`, and `app.mcp-tools` exist:

```fennel
(local fs (require :fs))
(local AgentRegistry (require :llm/agent/registry))
(local AgentRunner (require :llm/agent/runner))
(local AgentToolSurface (require :llm/agent/tool-surface))
(local AgentApprovals (require :llm/agent/approvals))
(local AgentMcpSync (require :llm/agent/mcp-sync))
(local AgentOpencodeMcpBridge (require :llm/agent/opencode-mcp-bridge))
(local SpaceAgent (require :llm/agent/builtins/space-agent))
(local PromptUtils (require :llm/agent/prompt-utils))
(local OpencodeSdk (require :llm/providers/opencode))

(set app.agent-registry (AgentRegistry.AgentRegistry {:deps {:app app}}))
(set app.agent-approvals
     (AgentApprovals.AgentApprovals
       {:policy {:normal :auto
                 :filesystem-read :ask
                 :filesystem-write :ask
                 :destructive :ask
                 :shell :ask}}))
(set app.agent-tool-surface
     (AgentToolSurface.AgentToolSurface
       {:presets app.agent-presets
        :mcp-tools app.mcp-tools
        :approvals app.agent-approvals}))
(set app.agent-mcp-sync
     (AgentMcpSync.AgentMcpSync
       {:surface app.agent-tool-surface
        :change-source app.agent-presets
        :tool-registry app.mcp-tools
        :owner "agent-tools"}))
(app.agent-mcp-sync:start)
(set app.agent-opencode-mcp-bridge
     (AgentOpencodeMcpBridge.AgentOpencodeMcpBridge
       {:tools app.mcp-tools
        :data-dir (fs.join-path app.user-data-dir "agent-opencode")}))
(app.agent-opencode-mcp-bridge:start)
(set app.agent-providers {})
(tset app.agent-providers :opencode-factory
      (fn []
        (local provider
          (OpencodeSdk.Opencode
            {:opencode-path (or (os.getenv "OPENCODE_PATH") "opencode")
             :env (app.agent-opencode-mcp-bridge:opencode-env)}))
        (tset app.agent-providers :opencode provider)
        provider))

(SpaceAgent.register app.agent-registry
  {:app app
   :presets app.agent-presets
   :tools app.agent-tool-surface
   :approvals app.agent-approvals
   ;; Optional concrete model config owned by this agent, not by AgentRunner.
   ;; Example: {:providerID "opencode" :modelID "big-pickle"}
   :model app.space-agent-model
   :providers app.agent-providers})

(PromptUtils.register-enricher
  :active-world
  (fn [ctx]
    (when ctx.app.world-manager
      "active world available")))

(set app.agent-runner
     (AgentRunner.AgentRunner
       {:data-dir (fs.join-path app.user-data-dir "agent-sessions")
        :registry app.agent-registry
        :deps {:app app
               :presets app.agent-presets
               :tools app.agent-tool-surface
               :approvals app.agent-approvals
               :agents app.agent-registry
               :providers app.agent-providers}}))
```

Teardown in `app.drop`:

```fennel
(when app.agent-runner
  (app.agent-runner:drop)
  (set app.agent-runner nil))
(when app.agent-providers
  (local opencode app.agent-providers.opencode)
  (when (and opencode opencode.close)
    (opencode.close)))
(set app.agent-providers nil)
(when app.agent-opencode-mcp-bridge
  (app.agent-opencode-mcp-bridge:stop)
  (set app.agent-opencode-mcp-bridge nil))
(when app.agent-mcp-sync
  (app.agent-mcp-sync:stop)
  (set app.agent-mcp-sync nil))
(set app.agent-tool-surface nil)
(set app.agent-approvals nil)
(set app.agent-registry nil)
```

## Risk And Lifecycle Details

### OpenCode sessions

OpenCode has its own session IDs. Agent sessions are independent. `SpaceAgent`
stores the OpenCode session ID in `session.data.opencode-session-id`, validates
it before reuse, and creates a replacement if OpenCode no longer knows it.

OpenCode executes tools through the bridge-owned MCP server. After a successful
prompt, `SpaceAgent` fetches OpenCode session messages and persists any tool
parts as canonical `tool-call` and `tool-result` items before appending the
assistant message. If message fetching or audit persistence fails, the turn
fails explicitly rather than recording lossy assistant text.

### Codex streaming

Codex `run-streamed` already returns a handle with `poll`, `wait`, `cancel`, and `running?`. A Codex-backed agent should register `handle:cancel` through `ctx.turn:set-cancel`, poll from its own provider loop or a runtime update callback, and persist completed Codex items as agent session items.

### OpenAI/ZAI callbacks

OpenAI and ZAI requests use callback-based HTTP. Agents using them either call the existing `llm/conversations/requests.fnl` flow against an agent-session-compatible store adapter, or extract a focused helper after the first implementation proves the exact shape. The agent must register cancellation when the HTTP binding exposes a request id that can be cancelled.

### Tool execution divergence

OpenCode/Codex use server-side tools through MCP. OpenAI/ZAI need client-side function tools. `AgentToolSurface` is the shared source of active tool definitions and local `call` behavior, so all providers obey the same preset and approval rules.

### Active turn concurrency

There is at most one active turn per session. Starting a new turn cancels the previous turn through the registered cancel hook, marks the old turn `:cancelled`, persists an `error` or `event` item, and starts the new turn.

### Session file accumulation

Sessions are not deleted automatically in v1. The runner supports listing and deleting sessions. TTL/archive can be added after the UI has a real session browser.

## Future Extensions

### Agent routing / delegation

Agents can delegate by resolving another agent from `ctx.agents`. Delegation should create a child turn item in the parent session and use a separate session or explicit child-session ID for the delegated agent.

### Graph integration

Agent sessions can later surface as graph nodes (`LlmAgentSessionNode`, `LlmAgentItemNode`). The item stream is designed to preserve enough metadata for this without coupling v1 to graph views.

### Provider helper extraction

After multiple agents use the same backend pattern, extract focused helpers such as:

```fennel
(OpenCodeTurn.run {:client deps.opencode
                   :session session
                   :input input
                   :ctx ctx
                   :system-prompt system-prompt})
```

Do not introduce a generic `call-llm` interface until the repeated shape is proven by real agents.

## Implementation Order

| Step | Module | Rationale |
|------|--------|-----------|
| 1 | `llm/agent/session.fnl` | Durable item stream and JSON persistence |
| 2 | `llm/agent/turn.fnl` | TurnHandle/TurnController lifecycle contract |
| 3 | `llm/agent/registry.fnl` | Factory registration and lazy construction |
| 4 | `llm/agent/approvals.fnl` | Explicit high-risk capability policy |
| 5 | `llm/agent/tool-surface.fnl` | Preset-backed tools for MCP and client-side providers |
| 6 | `llm/agent/mcp-sync.fnl` | Agent-facing MCP sync through the approved tool surface |
| 7 | `llm/agent/opencode-mcp-bridge.fnl` | Loopback MCP server and isolated OpenCode config |
| 8 | `llm/agent/prompt-utils.fnl` | Prompt helpers and context enrichers |
| 9 | `llm/agent/runner.fnl` | Session CRUD, active turns, cancellation, callbacks |
| 10 | `llm/agent/builtins/space-agent.fnl` | First real agent using OpenCode/MCP |
| 11 | Wire into `main.fnl` | Bootstrap and teardown |
| 12 | Tests (`test-agent-layer.fnl`) | Session CRUD, turn lifecycle, cancellation, approvals, tool surface, MCP sync, bridge, SpaceAgent fixture |
| 13 | E2E/live tests | Full round-trip against opencode with MCP tools |

## Tests

Fast tests should cover:

- Session create/load/save/list/delete with atomic writes.
- Item append/update order and metadata preservation.
- `run-turn` returns a handle immediately.
- Completion, failure, and cancellation clear active turns and persist status.
- Agent-registered cancellation is invoked exactly once.
- Starting a second turn cancels the first.
- Tool surface exposes active preset tools as MCP and OpenAI/ZAI-compatible definitions.
- High-risk presets cannot be enabled or used without approval.
- Prompt enrichers are registered outside the runner.
- Prompt enricher failures name the failing enricher and fail explicitly.
- OpenCode bridge starts a loopback MCP server and writes the isolated config.
- `SpaceAgent` fixture records user, provider, tool-call, tool-result, and final message items.
- Cancel hook failures still mark the turn cancelled and surface the hook error.

### Online MCP Agent Test Strategy

The online end-to-end suite should live outside `tests.fast` and run through a dedicated entrypoint, for example `tests.test-agent-mcp-online:main` or a small script that invokes that module. It should not use gating environment flags such as `AGENT_MCP_LIVE_TESTS=1`; choosing this entrypoint is the opt-in. The module should keep its live settings in a single fixed constants table near the top:

```fennel
(local TEST_CONFIG
  {:opencode-path "opencode"
   :provider-id "opencode"
   :model-id "big-pickle"
   :root "/tmp/space/tests/agent-mcp-online"
   :mcp-host "127.0.0.1"
   :mcp-port 0
   :turn-timeout-ms 120000})
```

If the configured binary, credentials, provider, or model are unavailable, the test should fail loudly. It should not silently skip or choose a different model. That keeps regressions visible and avoids accidentally proving a different contract than the one the entrypoint is meant to validate. The fixed model should be passed into the concrete test agent registration, for example `SpaceAgent.register` with `:model {:providerID TEST_CONFIG.provider-id :modelID TEST_CONFIG.model-id}`; it should not be added to generic runner deps.

The suite should run in a fresh isolated root every time:

- Isolated app/user data directory under `/tmp/space/tests/agent-mcp-online`.
- Isolated OpenCode config directory generated from `TEST_CONFIG`.
- Local MCP HTTP server bound to loopback.
- Test-only `ToolRegistry` populated through `AgentMcpSync`, not raw `PresetMcpSync`.
- Test-only `SpaceAgent` registration with the fixed `TEST_CONFIG` model.
- Test-only agent session data directory.

The first online test should prove the core contract with a deterministic tool:

1. Register a normal-risk preset adapter for `space_agent_echo_token`.
2. Start `AgentMcpSync` against `AgentToolSurface`.
3. Configure OpenCode to use the local MCP endpoint.
4. Create an `AgentRunner` session for `space-agent`.
5. Prompt: "Use `space_agent_echo_token` exactly once with token `<marker>`. Then reply with exactly the tool output and no extra text."
6. Assert the tool call log contains exactly one call with the exact marker.
7. Assert the turn completes, the assistant response contains the marker, and the agent session has one user message plus one assistant message.
8. Invalidate the session cache and reload from disk while the isolated root still exists.
9. Assert `session.data.opencode-session-id` is persisted and the assistant item records the fixed model.

The second online test should prove sequencing without relying on creative model behavior:

1. Register `space_agent_get_nonce` returning a fixed nonce.
2. Register `space_agent_record_value` recording its argument and returning `recorded:<value>`.
3. Prompt: "Call `space_agent_get_nonce`, then call `space_agent_record_value` with the nonce you received. Reply exactly `done:<nonce>`."
4. Assert call order and exact recorded value.
5. Assert final text contains the fixed nonce.

The third online test should prove approval boundaries:

1. Register one normal-risk tool and one shell/destructive-risk tool.
2. Configure `AgentApprovals` so only `:normal` is approved.
3. Assert the MCP server `tools/list` output does not include the high-risk tool.
4. Prompt the agent to call the high-risk tool directly.
5. Assert no high-risk call is recorded and the turn either fails explicitly or responds that the tool is unavailable.

Assertions should prioritize deterministic local state over final prose. The hard checks are MCP call counts, exact tool arguments, persisted session state, turn status, and tool visibility. The final assistant text can be checked with a marker containment assertion except in the simplest echo case.

## References

- [[agent-presets]] - context-aware capability and MCP tool exposure
- [[remote-mcp]] - OpenCode MCP transport
- [[codex-sdk-fennel]] - Codex handle, streaming, and cancellation shape
- `assets/lua/llm/providers/opencode.fnl` - OpenCode SDK
- `assets/lua/llm/providers/codex.fnl` - Codex SDK
- `assets/lua/llm/conversations/requests.fnl` - existing OpenAI/ZAI tool-calling loop
- `assets/lua/llm/conversations/store.fnl` - existing persisted item model
- `assets/lua/llm/presets/init.fnl` - PresetManager interface

## See also

- [[agent-tools]], [[agent-runner-system]]
