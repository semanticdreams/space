---
type: adr
status: accepted
decision-date: 2026-03-07
tags:
  - adr
  - rendering
  - gpu
  - performance
supersedes:
superseded-by:
---

# SSBO + quad pipeline for UI rendering

## Context

UI rectangles and text were rendered through multiple code paths: rectangles used one shader/pipeline, text used another (MSDF), images used a third. Each path had its own buffer management, draw calls, and state tracking. This fragmented the renderer and made batch optimizations difficult.

## Decision

Unify all 2D UI rendering (rectangles, text, images) onto a single SSBO-backed instanced quad pipeline. All primitives are instances of a single quad geometry, with per-instance data (position, size, color, texture coordinates, clip rects) packed into SSBOs. Text is handled as instanced glyphs within the same pipeline.

Commit: `refactor(ui): unify ui rectangles/text on SSBO+quad pipeline` (2026-03-07)

## Consequences

**Positive:**
- Single draw-call path for all UI — massive reduction in draw calls
- Instanced rendering with minimal CPU overhead
- Consistent clip rect handling across all primitives
- Easier to add new UI primitive types (just add instance data)

**Negative:**
- All primitives must fit the quad + instance data model
- Custom rendering (e.g., non-rectangular primitives) needs separate paths
- SSBO requires GL 4.3+ (acceptable for the target platforms)

## Related

- Goal: [[core-platform]] — this pipeline renders all core platform UI
- Feature: [[layout-widget-engine]] — the layout system rendered by this pipeline
- [[dev-notes/render-architecture]] — detailed rendering architecture
- [[dev-notes/transform-pass]] — transform pass details
