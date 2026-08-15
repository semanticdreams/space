---
type: feature
status: shipped
parent-goal: agent-tools
tags:
  - feature
  - agent
  - llm
  - mcp
created: 2026-07-14
updated: 2026-08-15
---

# Agent runner system

## Summary

Runtime agents that use LLM providers, local deterministic functions, and other agents to perform tasks. Sidebar chat sessions are now workflow-backed: each chat is one long-lived workflow run, and the runner API projects current session state from workflow events while preserving existing panel behavior.

## Motivation

LLM-based agents needed a runtime layer beyond the raw OpenAI conversation client. This system provides:
- Agent runner with workflow-backed session lifecycle, tool execution, and approval flow
- Preset system exposing context-aware capabilities (MCP tools) with risk badges
- Streaming replies from OpenCode and other providers
- Agent scope within reloadable units

## Design

- **Workflow-backed runner facade**: Preserves the sidebar runner API (`create-session`, `get-session`, `list-sessions`, `run-turn`, `cancel-turn`, `delete-session`, `flush`, `drop`) while storing current chats as workflow runs.
- **WorkflowStore**: Owns agent chat workflow definitions, long-lived runs, run steps, and event history.
- **Event projection**: Projects transcript, status, and session data from workflow events such as `:agent-session-created`, `:agent-status-changed`, and agent item events. Old JSON session files are not the current chat source of truth.
- **PresetRegistry**: Defines available capabilities as presets with three-state control (Auto/On/Off) and risk badges
- **MCP transport**: Remote OpenCode MCP transport for tool exposure across processes
- **Conversation-first supervisor**: Streaming with tee for parallel consumers
- **Approval**: Toggle-driven — preset toggle is user action; tool execution remains model action with approval checks

## Workflow-backed session flow

1. The sidebar calls `create-session`, which ensures the editable default agent workflow exists and starts a long-lived workflow run.
2. The workflow waits for `:agent-user-input`.
3. Each `run-turn` appends the user message as a workflow event, resumes the waiting step, and lets the provider-specific turn controller stream items/status back as more workflow events.
4. The sidebar and graph read the same projected workflow run/session state.
5. Legacy `agent-sessions/*.json` files are migrated only by the explicit `tools.agent-session-migrate` command, not during app startup.

## Tasks

- [x] Agent runner with session lifecycle
- [x] Preset system with MCP tool exposure
- [x] Risk-based approval model
- [x] OpenCode streaming integration
- [x] Remote MCP transport
- [x] Conversation-first supervisor
- [x] Workflow-backed sidebar sessions and explicit legacy migration

## Related

- Goal: [Agent Tools](/dev/features/agent-tools)
- See: [Workflow-backed agent sessions](/dev/features/workflow-backed-agent-sessions), [Workflows](/dev/features/workflows)
- See: [Agent Layer Design](/dev/notes/agent-layer-design), [Agent Presets](/dev/notes/agent-presets), [Remote Mcp](/dev/notes/remote-mcp)
- See: [Agent Preset Control Panel](/dev/agent-preset-control-panel)
