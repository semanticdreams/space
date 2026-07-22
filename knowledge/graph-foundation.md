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

- [[graph-browsing]] — graph navigation and editing UX
- [[graph-notebooks]] — graph-backed notebooks with identity references

## Bugs

*(none yet)*

## ADRs underlying this goal

- [[adr-graph-as-universal-model]] — why everything is a graph node
- [[adr-composable-states]] — input handling for graph interaction

## Related

- [[subsystems]] — Graph system, Widget system, Application model
- [[history]] — how the graph evolved across project phases
- [[milestones]] (Milestone 1)
- Dev notes: [[dev-notes/graph]], [[dev-notes/graph-identity]], [[dev-notes/graph-llm]], [[dev-notes/graph-view-as-widget]], [[dev-notes/graph-key-based-loaders]], [[dev-notes/graph-vs-entities]]
