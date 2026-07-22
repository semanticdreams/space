# Widget Ownership And Teardown

This note documents the actual teardown model used by the Fennel widget system.

It exists because it is easy to confuse three different things:

- layout relationships
- widget composition
- lifecycle ownership

Those are related, but they are not the same.

## Short Version

- `Layout` is for measurement, placement, clipping, and dirt tracking.
- `Layout.drop` does not drop widgets.
- A composite widget owns its direct child widgets.
- Teardown is recursive because each widget drops its own direct children.
- Do not manually drop descendants that are already covered by dropping an owning composite widget.

## What `Layout.drop` Actually Does

`Layout.drop` in `assets/lua/layout.fnl` only:

- clears child layout links
- removes the layout from root dirt queues

It does not:

- call `drop` on child widgets
- recursively destroy a widget subtree

So this is wrong:

```fennel
(self.layout:drop) ; assumes widget subtree is gone
```

unless the widget intentionally owns only a bare layout and no child widgets.

## The Real Ownership Model

The widget system uses direct ownership plus recursive teardown.

That means:

1. A composite widget constructs some child widgets.
2. That composite widget keeps responsibility for dropping those direct children.
3. Its `drop` method usually does:
   - `self.layout:drop`
   - `child-a:drop`
   - `child-b:drop`
4. If a child is itself composite, its own `drop` continues the recursion.

So the system is not based on "layout tree owns widget tree".

It is based on:

- each widget owns its direct children
- recursive `drop` walks the widget tree

## Examples From Core Widgets

This pattern is explicit in many core composites:

- `assets/lua/padding.fnl`
- `assets/lua/sized.fnl`
- `assets/lua/aligned.fnl`
- `assets/lua/flex.fnl`
- `assets/lua/stack.fnl`
- `assets/lua/container.fnl`

Representative shape:

```fennel
(fn drop [self]
  (self.layout:drop)
  (child:drop))
```

Or for multiple children:

```fennel
(fn drop [self]
  (self.layout:drop)
  (each [_ child (ipairs children)]
    (child:drop)))
```

That is the canonical pattern in this codebase.

## What Counts As Ownership

Holding a reference is not enough to imply ownership.

These are different:

- "I need a reference so I can update text, connect a signal, or inspect state."
- "I am responsible for dropping this object."

In UI code, a composite often keeps references to descendants for behavior:

- inputs
- buttons
- list views
- labels
- focus nodes

But if one of those descendants is already a direct child of a composite widget that will be dropped, then the outer object usually should not drop it separately.

The outer object still owns:

- listeners it connected
- async jobs or timers it started
- signals it created
- raw engine objects with no composite widget owner above them

The outer object does not also automatically own widget descendants independently of the composite that already owns them directly.

## Case Study: `RipgrepView`

`RipgrepView` in `assets/lua/ripgrep-view.fnl` builds:

- `path-input`
- `query-input`
- `search-button`
- `status-text`
- `results-list`
- `query-row` as a `Flex`
- `root` as a `Flex`

The important ownership relationships are:

- `root` directly owns:
  - `path-input`
  - `query-row`
  - `status-text`
  - `results-list`
- `query-row` directly owns:
  - `query-input`
  - `search-button`

So when `root:drop` runs:

1. `root` drops its direct children.
2. Dropping `query-row` then drops `query-input` and `search-button`.

That means this old pattern was wrong:

```fennel
(results-list:drop)
(status-text:drop)
(query-row:drop)
(search-button:drop)
(query-input:drop)
(path-input:drop)
(root:drop)
```

because it drops descendants manually and then drops the composite that will recursively drop them again.

The correct `RipgrepView.drop` shape is:

- cancel the outstanding search it owns
- disconnect the listeners it owns
- drop `root`

No separate child widget drops are needed there.

## Case Study: `SearchView`

`SearchView` builds:

- `input`
- `list-view`
- `flex` as the composite root

The correct ownership rule is:

- `flex` owns `input`
- `flex` owns `list-view`

So `SearchView.drop` must drop the owning widget:

```fennel
(self.root:drop)
```

not merely:

```fennel
(self.layout:drop)
```

Dropping only the layout removes layout wiring but leaves widget teardown undone.

This distinction matters because `Input` and `ListView` do real teardown work:

- signal disconnection
- unregistering from click/hover systems
- focus cleanup
- child widget teardown

## Practical Rules

When writing a composite widget or view:

### 1. Identify the direct widget children

Ask:

- which widgets did this object construct directly?
- which of those are already owned by a composite child?

Only direct children belong in this object's widget teardown logic.

### 2. Drop the owning composite, not the descendants

If you have:

- `root` as a `Flex`, `Stack`, `Container`, `Dialog`, etc.

and all UI children live under that composite, prefer:

```fennel
(root:drop)
```

over manually dropping individual descendants.

### 3. Do not confuse `layout` with widget lifetime

If a value is `something.layout`, that is not the widget object.

Dropping the layout is only sufficient when the thing you built is actually just a bare layout wrapper with no separate widget subtree responsibilities.

### 4. Separately clean up non-widget resources

Even when a composite widget owns the subtree, the outer object may still need to clean up:

- signal listeners
- runtime timer handles
- async search/process handles
- subscriptions
- external resources

That cleanup belongs beside the composite widget drop.

### 5. Assert on double drop where the contract is terminal

If the object is meant to be dropped exactly once, assert on second drop.

That makes ownership mistakes obvious instead of silently tolerated.

## Review Questions

When reviewing teardown code, ask:

- Is this code dropping a widget or only a layout?
- Which object is the direct owner of each child widget?
- Is any descendant being dropped both manually and through a composite parent?
- Are non-widget resources being cleaned up separately from widget teardown?
- Should this object assert on double drop?

## Common Failure Modes

### Dropping descendants and then the composite parent

Symptom:

- double-drop assertions start firing after lifecycle tightening

Cause:

- the parent widget already recursively drops those descendants

### Dropping only `layout`

Symptom:

- layout disappears, but listeners, focus nodes, registrations, or child widgets remain alive

Cause:

- layout teardown was mistaken for widget teardown

### Treating stored references as separate ownership

Symptom:

- a view manually drops buttons/inputs/list widgets it only referenced for behavior

Cause:

- references were mistaken for ownership responsibilities

## Relationship To Lifecycle Invariants

This note complements [Lifecycle Invariants](/dev/lifecycle-invariants).

That document covers:

- single ownership of long-lived runtime objects
- update ownership
- signal semantics
- fail-fast use-after-drop rules

This document is narrower:

- widget subtree ownership
- the difference between widget teardown and layout teardown
- how recursive `drop` is supposed to work in composed UI code

Use both documents together when reviewing UI lifecycle code.


## See also

- [[../../knowledge/home|Knowledge Base]]
