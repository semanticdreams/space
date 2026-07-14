---
type: bug
severity: low
status: open
parent-goal: "[[core-platform]]"
tags:
  - bug
  - layout
  - widget
created: 2026-07-14
---

# Mystery layout errors

## Reproduction

Intermittent layout computation errors during widget tree updates. Hard to reproduce deterministically; often manifests as incorrect child positioning after resize or theme change.

## Expected behavior

Widget layout passes produce correct positions and sizes deterministically.

## Actual behavior

Some widget trees produce incorrect child positions after resize or theme rebuilds. Errors are transient and difficult to isolate.

## Impact

Visual glitches in complex widget trees. Not data-loss or crash severity but degrades UI reliability.

## Related

- Goal: [[core-platform]]
- Depends on: [[layout-widget-engine]]
- See: [[dev-notes/mystery-layout-error]], [[dev-notes/resize-bugs]]
- See: [[bugs]]
