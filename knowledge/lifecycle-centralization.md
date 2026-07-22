---
type: tech-debt
impact: high
effort: large
status: resolved
tags:
  - tech-debt
  - lifecycle
  - centralization
created: 2026-07-14
updated: 2026-07-14
---

# Lifecycle ownership centralization

## Summary

The April 2026 push to replace implicit, signal-driven ownership with explicit, centralized lifecycle management. A prerequisite for hot-reload, canvas modes, and reliable teardown.

## What was done

1. **Centralized frame update** — single update entry point owns the full update pass (`2026-04-15`)
2. **Signal lifecycle hardening** — signals disconnect when owners drop; graph views explicitly cleaned up before rebuild (`2026-04-16`)
3. **Double-drop fix** — composite view children teardown clarified (`2026-04-16`)
4. **UnitManager** — explicit unit registry, SourceUnit, and runtime unit lifecycle (`2026-05-08`)
5. **Canvas mode centralization** — mode shell owns activate/deactivate lifecycle (`2026-04-30`)

## Results

- Eliminated the most common runtime crash class (stale callbacks after drop)
- Enabled hot-reload: units can be safely unloaded and reloaded
- Enabled canvas mode switching: modes activate/deactivate with clean transitions
- Enabled panel transfer: panels move between surfaces with transaction safety

## Related

- [[tech-debt-lifecycle-ownership]] — the bugs this fixed
- [[lifecycle-hardening-plan]] — the full plan and strategy options
- [[docs/dev/lifecycle-invariants]] — the finalized rules
- [[docs/dev/widget-ownership-and-teardown]] — teardown ownership model
- [[hot-reload-units]] — dependent on lifecycle safety
- [[canvas-mode-system]] — dependent on lifecycle safety

## See also

- Goal: [[core-platform]]
