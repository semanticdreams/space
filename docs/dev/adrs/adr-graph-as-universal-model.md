---
type: adr
status: accepted
decision-date: 2026-02-18
tags:
  - adr
  - graph
  - architecture
  - modeling
supersedes:
superseded-by:
---

# Graph as universal model

## Context

Early in development, the project had separate concepts for entities (sqlite-backed knowledge objects), systems (engine subsystems), file references, world objects, and UI state. Each had its own API, lifecycle, and view wiring. The result was fragmentation: linking a notebook entry to a code file, or a terrain node to a conversation, required crossing subsystem boundaries with custom glue code.

## Decision

Make the graph the universal model: everything — state, code, system objects, files, world objects, notebook entries, terrains, lighting, and UI state — lives in the graph as nodes with typed properties and relationships.

The graph model itself stays pure (nodes, edges, signals) with views decoupled and pluggable via signals.

## Consequences

**Positive:**
- One uniform interface for inspection, linking, and navigation
- Notebooks, code directories, terrains, worlds, and lighting all use the same graph API
- Graph nodes stay view-agnostic — future interfaces (audio-first, VR, etc.) can sit on the same model
- Links between any two things (e.g., task → code, error → conversation) are natural graph edges

**Negative:**
- Everything must be modeled as a graph node, even things that don't naturally fit
- View logic is separate from node logic, requiring signal plumbing between them
- Performance: large graphs need LOD (multiple detail levels), incremental layout, and lazy loading

## Related

- [Graph Foundation](/dev/features/graph-foundation) — current goal to make the graph actually usable
- [Graph Browsing](/dev/features/graph-browsing) — feature for graph navigation/editing
- [Graph Identity](/dev/notes/graph-identity) — identity nodes for stable references
- [Graph Llm](/dev/notes/graph-llm) — graph + LLM integration
- [Composable States](/dev/adrs/adr-composable-states) — similar explicit-over-implicit philosophy
