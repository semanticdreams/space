---
type: bug
severity: medium
status: open
parent-goal: "[[core-platform]]"
tags:
  - bug
  - lifecycle
  - async
created: 2026-07-14
---

# Stale async callbacks after widget teardown

## Reproduction

Async completions (RPC futures, process output, editor/file-picker results) fired callbacks that mutated dropped widgets. Notable examples in wallet RPC, editor completion, and RipgrepView process output.

## Expected behavior

After a widget is dropped, no async callbacks should mutate its state.

## Actual behavior

Some async workflows lack cancellation or generation invalidation, so callbacks run after the owning widget is destroyed, producing use-after-drop errors.

## Impact

Runtime crashes in async-heavy UI flows. The most common crash class during development before the April 2026 lifecycle hardening.

## Fix progress

Partially resolved by lifecycle hardening (April 2026): centralized update ownership, signal disconnect on drop, generation invalidation for wallet futures. Remaining exposure exists in non-cancellable process-based completions and external editor callbacks.

## Related

- Goal: [[core-platform]]
- See: [[lifecycle-hardening-plan]], [[tech-debt-lifecycle-ownership]]
- See: [[docs/dev/lifecycle-invariants]]
- See: [[bugs]]
