---
type: dev-note
tags:
  - note
---

# Input line-wrapping and constrained measurement

## Overview

Changes to `Input` widget line-wrapping defaults and `Flex` constrained measurement behavior. Multiline inputs now line-wrap by default; no per-widget `:line-wrap? true` opt-in needed. Single-line inputs remain unwrapped. Flex layout allocates remaining axis space proportionally by flex weight, with fixed children measured first.

## Key changes (commit `b3f0f8a9`, 2026-07)

- **Multiline default**: `Input` widgets with `:multiline? true` now line-wrap by default. The `:line-wrap?` option still exists but defaults to true for multiline inputs.
- **Constrained measurement**: `Flex` allocates remaining axis space proportionally by flex weight. Fixed children (non-flex) are measured first; remaining space is distributed among flex children.
- **Wrapped caret auto-scroll**: Caret positioning uses visual-row mapping; scroll-on-type tracks visual rows during wrapping.
- **ListView auto-scroll viewport**: Uses constrained measurement for fill-width wrapping children. Viewport height corrects on width changes (e.g., window resize).
- **Chat message entries**: Use `:max-lines math.huge` so wrapped content is not line-capped.

## Affected modules

- `assets/lua/input.fnl` — Input widget, multiline and line-wrap defaults
- `assets/lua/flex.fnl` — Flex layout, constrained measurement
- `assets/lua/list-view.fnl` — ListView auto-scroll viewport
- `assets/lua/caret-state.fnl` — Visual-row caret positioning

## See also

- [Layout Widget Engine](/dev/features/layout-widget-engine)
