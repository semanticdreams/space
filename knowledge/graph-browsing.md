---
type: feature
status: planned
parent-goal: "[[graph-foundation]]"
tags:
  - feature
  - graph
  - ui
created: 2026-07-14
updated: 2026-07-14
---

# Graph browsing & editing

## Summary

Refine the graph browsing and editing experience so users can navigate, manipulate, and understand their graph-backed objects fluently.

## Motivation

Currently graph-backed objects exist but navigating between them, inspecting their contents, and editing relationships is not yet smooth. This is central to making the graph the primary interface for everything.

## Design

- Improve the graph view widget for smoother navigation
- Add keyboard-driven browsing (search, jump, expand/collapse)
- Make node property inspection fast with inline editing
- Support drag-to-link between graph objects
- Keep interaction model consistent with rest of space UI

## Tasks

- [ ] Audit current graph browsing pain points
- [ ] Design improved navigation keybindings
- [ ] Implement keyboard-driven focus/selection in graph view
- [ ] Add inline property editing for graph nodes
- [ ] Implement drag-to-link between graph-backed objects
- [ ] Test with realistic-sized graphs

## Related

- Goal: [[graph-foundation]]
- Depends on: [[canvas-mode-system]] — graph-surface mode is a canvas mode
- ADRs: [[adr-graph-as-universal-model]], [[adr-composable-states]]
- See: [[dev-notes/graph-identity]], [[dev-notes/graph-view-as-widget]], [[dev-notes/graph-vs-entities]]
