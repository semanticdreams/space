---
type: adr
status: accepted
decision-date: 2026-03-25
tags:
  - adr
  - architecture
  - state
  - composition
supersedes:
superseded-by:
---

# Composable state architecture over inheritance

## Context

Input and UI state handling was originally built on a class hierarchy — a `StateBase` class providing defaults, with subclasses overriding specific behaviors like keyboard focus, mouse hover, touch handling, and scroll routing. This created:
- Fragile overrides — subclasses needed deep knowledge of parent class internals
- Hard-to-compose behaviors — mixing keyboard + gamepad + touch required multi-level inheritance
- Implicit defaults in the base class that were easy to accidentally inherit

## Decision

Replace the inheritance-based state system with composable states: small, focused state objects that are assembled declaratively without inheritance. Three commits executed this:
1. `feat(lua): define final composable state architecture` (2026-03-25)
2. `refactor(lua): replace state base with composable states`
3. `refactor(lua): remove implicit state defaults`

The new model: each input concern (keyboard, mouse, touch, scroll, gamepad) is a standalone composable module. Widgets compose only the states they need, with no inherited defaults.

## Consequences

**Positive:**
- Explicit state composition — you can see exactly which input paths a widget handles
- No implicit inherited behavior to track down
- Easier to add new input modalities without touching existing states
- Cleaner test isolation (test one state at a time)

**Negative:**
- Boilerplate per widget — each widget explicitly wires its states
- Migration pain — the StateBase-to-composable transition required rewiring every interactive widget
- Route subscription trimming (`fix(lua): harden state wiring and trim route subscriptions`, 2026-03-25) was needed post-migration

## Related

- Goal: [Core Platform](/dev/features/core-platform) — composable states are a core platform input primitive
- Goal: [Graph Foundation](/dev/features/graph-foundation) — graph interaction relies on composable input states
- [Graph as Universal Interface](/dev/adrs/adr-graph-as-universal-model) — similar philosophy of explicit over implicit
- [Lifecycle Centralization](/dev/lifecycle-centralization) — companion decision on ownership
