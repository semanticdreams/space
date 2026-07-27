---
name: humpback-graph-doctrine
description: Use when editing Humpback graph nodes, graph maps, graph views, graph persistence, graph topology, graph key loaders, or graph terminology.
---

# Humpback Graph Doctrine

## Use When

Editing Humpback graph nodes, graph maps, graph views, graph persistence, graph topology, graph key loaders, or graph terminology.

## Canonical References

- `docs/dev/notes/graph.md`
- `docs/dev/graph-maps.md`

## Required Doctrine

- The graph is an exposure/adaptor layer, not the owner of domain objects.
- Graph core persists topology only.
- Owning systems persist domain data.
- Key loaders adapt owning stores/systems into graph node adapters.
- `GraphMap` owns interaction context over shared graph-addressable objects.

## Terminology

- Avoid forbidden terminology by using the canonical terms from `docs/dev/notes/graph.md`.
