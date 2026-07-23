---
type: adr
status: accepted
decision-date: 2026-02-18
amended-date: 2026-07-23
tags:
  - adr
  - graph
  - architecture
  - modeling
supersedes:
superseded-by:
---

# Graph as universal interface / exposure layer

## Context

Early in development, the project had separate concepts for entities (sqlite-backed knowledge objects), systems (engine subsystems), file references, world objects, and UI state. Each had its own API, lifecycle, and view wiring. The result was fragmentation: linking a notebook entry to a code file, or a terrain node to a conversation, required crossing subsystem boundaries with custom glue code.

## Decision

Make the graph the universal interface: everything — state, code, system objects, files, world objects, notebook entries, terrains, lighting, and UI state — is exposed through the graph as nodes with typed properties and relationships.

**The graph is an exposure/adaptor layer, not an owning store.** Domain objects live wherever they naturally belong: entity data in entity stores, world/terrain/light state in world scene state, LLM conversations in the LLM store, filesystem nodes on the actual filesystem. The graph creates lightweight adapter nodes that project these objects into a uniform navigable topology. Graph core persists only topology (which node keys and edge connections exist); owning systems persist the actual object data.

The graph model itself stays pure (nodes, edges, signals) with views decoupled and pluggable via signals.

## Consequences

**Positive:**
- One uniform interface for inspection, linking, and navigation of any domain object
- Notebooks, code directories, terrains, worlds, and lighting all use the same graph API for exposure
- Graph node adapters stay view-agnostic — future interfaces (audio-first, VR, etc.) can sit on the same exposure layer
- Links between any two things (e.g., task → code, error → conversation) are natural graph edges
- Owning systems remain the source of truth for their data; graph does not duplicate or hijack storage

**Negative:**
- Every domain object that wants graph visibility must register a key loader and node adapter, even things that don't naturally fit as graph nodes
- View logic is separate from node logic, requiring signal plumbing between them
- Performance: large graphs need LOD (multiple detail levels), incremental layout, and lazy loading
- Terminology discipline is required: "graph-exposed object", not "graph-backed object"; "graph topology state", not "full graph state backup"

## Related

- [Graph Foundation](/dev/features/graph-foundation) — current goal to make the graph actually usable
- [Graph Browsing](/dev/features/graph-browsing) — feature for graph navigation/editing
- [Graph Identity](/dev/notes/graph-identity) — identity nodes for stable references
- [Graph Llm](/dev/notes/graph-llm) — graph + LLM integration
- [Composable States](/dev/adrs/adr-composable-states) — similar explicit-over-implicit philosophy
- [Graph Architecture Doctrine](/dev/notes/graph) — canonical terminology and ownership rules
