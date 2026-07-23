---
type: goal
status: active
tags:
  - goal
  - agent
  - llm
  - mcp
  - conversation
created: 2026-07-14
updated: 2026-07-14
---

# Agent-powered tools

## Summary

Use the existing LLM integration and conversation infrastructure to build useful agentic workflows. Expose saved conversations through the graph, support branch/fork workflows, connect conversations to related entities (tasks, code, notes), and expose Space capabilities as MCP tools with risk-gated approval models.

## Why

The LLM and agent infrastructure is already substantial (agent runner, preset system, multiple providers, MCP transport, conversation store). This goal is about making those pieces coherent and useful — connecting conversations to the graph, giving agents safe access to Space capabilities, and keeping LLM features subordinate to the entity model.

## Success criteria

- Saved conversations are exposed through the graph and linked to related entities
- Branch/fork conversation workflows work cleanly
- Agent presets expose useful Space capabilities with clear risk boundaries
- MCP tool integration stays provider-agnostic

## Features implementing this goal

- [Agent Runner System](/dev/features/agent-runner-system) — runtime agents with tool execution, presets, and approval flow

## Bugs

*(none yet)*

## Related

- [Subsystems](/dev/subsystems/) — Application Features (LLM & Conversations, Agent System, MCP Server)
- [Milestones](/dev/project/milestones/) (Milestone 5)
- [Project History](/dev/project/history) — Phase VI: Agent layer (May 2026)
- [Agent Layer Design](/dev/notes/agent-layer-design)
- [Agent Presets](/dev/notes/agent-presets)
