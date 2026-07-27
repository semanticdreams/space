---
name: space-fennel-ui
description: Use when editing or designing Space Fennel widgets, layout, rendering adapters, interaction widgets, widget lifecycle, or widget tests.
---

# Space Fennel UI

## Use When

Editing or designing Space Fennel widgets, layout, rendering adapters, interaction widgets, widget lifecycle, or widget tests.

## Canonical References

- `docs/dev/fennel/style.md`
- `docs/dev/lifecycle-invariants.md`
- `docs/dev/widget-ownership-and-teardown.md`

## Required Reminders

- Widget constructors return build closures.
- Builders receive renderer/build context and instantiate children with that context.
- Widgets own explicit `Layout` objects.
- Composite widgets own and drop their direct child widgets.
- Directly write child layout transforms during layout passes instead of calling dirtying setters.
- Mark the shallowest appropriate layout dirty.
- Assert on missing required context instead of silently falling back.
- Prefer project Fennel idioms: `local` over `let`, multi-branch `if`, factory functions over `.new`.

## Avoid

- Silent fallbacks for missing context or required data.
- Calling dirtying setters during layout passes instead of writing transforms directly.
- Using `let` or `.new` constructors when project idioms prefer `local` and factory functions.
