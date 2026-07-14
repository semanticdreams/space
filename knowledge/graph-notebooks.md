---
type: feature
status: shipped
parent-goal: "[[graph-foundation]]"
tags:
  - feature
  - graph
  - notebooks
  - knowledge
created: 2026-07-14
updated: 2026-07-14
---

# Graph notebooks

## Summary

Graph-backed notebooks with identity references, inline previews, and auto-wrap text. Notebooks are a core knowledge management primitive — they let users write structured notes with live links to graph entities.

## Motivation

Users need a way to create and edit structured text content that is intimately connected to the graph. Notebooks serve as the primary user-authored content surface, linking to code, tasks, errors, conversations, and other graph objects.

## Design

- **Notebook nodes**: Each notebook is a graph node with typed content (text, images, links)
- **Notebook pages**: Optional nested structure for organizing content (inspired by gtoolkit's notebook model)
- **Identity references**: Inline links to graph entities using identity nodes for stable references
- **Auto-wrap**: Text reflows within the layout constraint
- **Inline previews**: Linked entities show preview content inline

## Tasks

- [x] Notebook graph node type
- [x] Identity reference system
- [x] Inline previews of linked entities
- [x] Auto-wrap text layout

## Related

- Goal: [[graph-foundation]]
- ADR: [[adr-graph-as-universal-model]]
- See: [[dev-notes/graph-identity]], [[dev-notes/graph-key-based-loaders]]
