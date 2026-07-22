---
type: feature
status: shipped
parent-goal: core-platform
tags:
  - agent
  - workflow
  - opencode
  - python
created: 2026-07-14
---

# OpenCode agent workflow

## Summary

Python-based workflow orchestrator (`scripts/agent`) that coordinates multi-role OpenCode agent sessions through a structured pipeline: supervisor routing, exploration, plan drafting, human approval, implementation, review, adjudication, and fix cycles. 2500+ lines with 90+ offline workflow tests and online integration tests exercising real model calls.

## Motivation

The in-app Agent Runner handles runtime agent execution within Space. This Python orchestrator handles the offline development workflow — using OpenCode to plan and implement code changes, then reviewing and fixing them before committing. It is a development-time tool, not a runtime feature.

## Design

- **Conversation-first supervisor** (`scripts/agent.py`): A state machine that routes each user message through a supervisor model, classifying intent and dispatching to specialist agents.
- **Seven specialist agents** (`.opencode/agents/supervisor,explorer,planner,implementer,fixer,reviewer,adjudicator.md`): Each has a model, temperature, and permission assignment tailored to its role.
- **Agent configuration** (`agent.toml`): Model selection, validation commands, review/fix budgets, notification settings.
- **Workflow stages**: Explore → Plan (with human approval) → Implement → Review → Adjudicate → Fix (loop) → Human Accept.
- **Safety gates**: Clean-tree requirement before starting, model-limit recovery with auto-wait, checkpoint commits for workflow artifacts, paused states for `blocked_validation`, `blocked_model_limit`, `blocked_review_budget`.
- **Tee streaming**: OpenCode subprocess stdout streamed to terminal for live feedback.
- **Resumable state machine**: Interrupted workflows can be resumed, with checkpointed plan files and workflow artifacts.

## Tasks

- [x] Supervisor state machine with role routing
- [x] Seven specialist agent role definitions
- [x] Agent configuration (model, budgets, validation)
- [x] Conversation-first supervisor loop
- [x] Tee streaming of subprocess output
- [x] Safety gates (clean-tree, model-limit, review-budget)
- [x] Resumable workflow with checkpoint commits
- [x] 90+ offline workflow unit tests
- [x] Online integration tests with real model calls

## Related

- Goal: [Core Platform](/dev/features/core-platform)
- See: [Agent Runner System](/dev/features/agent-runner-system) — the in-app agent runtime this tool supports
- See: [Opencode Agent Workflow](/dev/opencode-agent-workflow) — full design document
- See: [Agent Layer Design](/dev/notes/agent-layer-design)
