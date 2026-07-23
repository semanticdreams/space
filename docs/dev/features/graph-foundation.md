---
type: goal
status: active
tags:
  - goal
  - graph
  - foundation
created: 2026-07-14
updated: 2026-07-14
---

# Usable graph foundation

## Summary

The graph provides a uniform interface to expose arbitrary objects — state, code, files, world objects, conversations — through one linked structure. This goal is specifically about making graph browsing, editing, and linking feel natural, fast, and useful. It is not about the systems exposed through the graph (those are separate goals).

## Why

If inspection, linking, filtering, and navigation are weak, expanding what the graph exposes will mostly create noise. We need a few strong universal interactions before building outward.

## Success criteria

- Graph browsing and editing feel natural and fast
- Users can link tasks, notes, code, errors, files, and conversations seamlessly
- Graph-backed objects are easy to inspect, edit, and navigate
- The graph model stays view-agnostic so future interfaces (e.g. audio-first) can sit on the same structure

## Features implementing this goal

- [Graph Browsing](/dev/features/graph-browsing) — graph navigation and editing UX
- [Graph Notebooks](/dev/features/graph-notebooks) — notebooks exposed through the graph with identity references

## Bugs

*(none yet)*

## ADRs underlying this goal

- [Graph as Universal Interface](/dev/adrs/adr-graph-as-universal-model) — why everything is exposed through the graph
- [Composable States](/dev/adrs/adr-composable-states) — input handling for graph interaction

## Related

- [Subsystems](/dev/subsystems/) — Graph system, Widget system, Application model
- [Project History](/dev/project/history) — how the graph evolved across project phases
- [Milestones](/dev/project/milestones/) (Milestone 1)
- Dev notes: [Graph](/dev/notes/graph), [Graph Identity](/dev/notes/graph-identity), [Graph Llm](/dev/notes/graph-llm), [Graph View As Widget](/dev/notes/graph-view-as-widget), [Graph Key Based Loaders](/dev/notes/graph-key-based-loaders), [Graph Vs Entities](/dev/notes/graph-vs-entities)
