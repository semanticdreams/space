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
updated: 2026-07-14
---

# Agent runner system

## Summary

Runtime agents that use LLM providers, local deterministic functions, and other agents to perform tasks. Built on the agent presets system which exposes Space capabilities as MCP tools, with risk-based approval models and session management.

## Motivation

LLM-based agents needed a runtime layer beyond the raw OpenAI conversation client. This system provides:
- Agent runner with session lifecycle, tool execution, and approval flow
- Preset system exposing context-aware capabilities (MCP tools) with risk badges
- Streaming replies from OpenCode and other providers
- Agent scope within reloadable units

## Design

- **AgentRunner**: Owns agent sessions, manages tool execution and approval
- **PresetRegistry**: Defines available capabilities as presets with three-state control (Auto/On/Off) and risk badges
- **MCP transport**: Remote OpenCode MCP transport for tool exposure across processes
- **Conversation-first supervisor**: Streaming with tee for parallel consumers
- **Approval**: Toggle-driven — preset toggle is user action; tool execution remains model action with approval checks

## Tasks

- [x] Agent runner with session lifecycle
- [x] Preset system with MCP tool exposure
- [x] Risk-based approval model
- [x] OpenCode streaming integration
- [x] Remote MCP transport
- [x] Conversation-first supervisor

## Related

- Goal: [Agent Tools](/dev/features/agent-tools)
- See: [Agent Layer Design](/dev/notes/agent-layer-design), [Agent Presets](/dev/notes/agent-presets), [Remote Mcp](/dev/notes/remote-mcp)
- See: [Agent Preset Control Panel](/dev/agent-preset-control-panel)
