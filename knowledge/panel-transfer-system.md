---
type: feature
status: shipped
parent-goal: "[[core-platform]]"
tags:
  - feature
  - panel
  - ui
  - transfer
created: 2026-07-14
updated: 2026-07-14
---

# Panel transfer system

## Summary

Protocol for moving panels between HUD, Scene, Canvas, and Board surfaces with transaction semantics and rollback. Panels maintain their wrapper state across transfers, and the system ensures cleanup on failed transfers.

## Motivation

Panels (scene panels, dialogs, tool windows) needed to move between different surfaces — from the HUD dock to the 3D world, from the canvas to a board. Previously this required ad-hoc recreation of panel state. The transfer system makes this a first-class operation.

## Design

- **Receiver registry**: Each surface (HUD, Scene, Canvas, Board) registers as a panel receiver
- **Transfer builder**: Constructs the transfer operation with source, target, and panel state
- **Transaction semantics**: Transfer succeeds atomically or rolls back completely
- **Persistence**: Transferred panels skip persistence during transfer to avoid half-written state
- **Legacy migration**: Pre-transfer panels are migrated to the new system on app start

## Tasks

- [x] Receiver registry with surface registration
- [x] Transfer builder protocol
- [x] Transactional transfer with rollback
- [x] Panel persistence skip during transfer
- [x] Legacy panel migration path

## Related

- Goal: [[core-platform]]
- Used by: [[canvas-mode-system]] — canvas modes register as panel receivers
