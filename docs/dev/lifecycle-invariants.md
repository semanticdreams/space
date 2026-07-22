# Lifecycle Invariants

This note documents the runtime ownership and lifecycle rules that prevent stale-callback, use-after-drop, and rebuild-state bugs.

For widget subtree teardown specifically, see [Widget Ownership And Teardown](/dev/widget-ownership-and-teardown).
For prevention strategies and next-step options, see [Lifecycle Hardening Plan](/dev/lifecycle-hardening-plan).

## Why This Exists

Runtime bugs in `space` often come from one of four failures:

- an object has more than one update owner
- an object stays subscribed after its owner considers it dropped
- rebuild code reuses stale ambient state instead of injecting current state explicitly
- teardown is treated as a soft suggestion instead of a terminal boundary

These failures are especially expensive because they often look harmless until timing changes expose them.

## Core Rules

### 1. Every runtime object has one owner

For each long-lived object, be able to answer all three questions unambiguously:

- who creates it
- who updates it
- who drops it

If different layers answer different questions, the design is wrong.

Example:

- `GraphView` belongs to `HomeWorld`
- `HomeWorld` creates it in runtime setup
- `HomeWorld:update` drives `graph-view:update`
- `HomeWorld` teardown drops it

`app` may keep a reference to the active object for convenience, but that does not make `app` the owner.

### 2. `drop` is terminal

After `drop`, public methods and owned callback entry points should usually assert immediately.

Do not silently ignore post-drop calls in normal owned runtime flow. Silent behavior converts lifecycle bugs into corrupted state and delayed failures.

The main exception is truly external late completion:

- process callbacks
- RPC futures
- editor/file chooser completions
- similar async work that may already be in flight and is not fully suppressible by construction

Those paths should usually return quietly after confirming the target object is already dropped, unless the async source itself is supposed to be owned and cancelled strictly enough that a late callback would indicate a real bug.

Good:

```fennel
(fn assert-not-dropped [context]
  (assert (not dropped?)
          (string.format "GraphView %s called after drop" context)))
```

### 3. Global frame signals are the exception

`app.engine.events.updated` is a low-level primitive. Most objects should not subscribe to it directly.

Prefer:

- world-owned updates for world runtime objects
- widget/layout-owned updates for widget trees
- domain signals for model changes

Direct subscriptions to global frame signals require a specific reason and a clear owner responsible for disconnecting them.

### 4. Signal semantics must match lifecycle expectations

If `disconnect` happens during an `emit`, later callbacks from that same `emit` should not still fire. Otherwise a dropped object can still receive stale callbacks during teardown.

The current `Signal` contract is:

- `disconnect` suppresses later same-emit callbacks
- `clear` suppresses remaining same-emit callbacks
- `connect` during emit only affects future emits
- failing handlers must still unwind internal emit bookkeeping correctly

Low-level contracts like this remove entire classes of downstream defensive patches.

### 5. Rebuild paths must inject current state explicitly

Rebuild code should not assume that reused build context is already current.

If rebuild depends on theme, active world, camera, selection, or other mutable app state, inject that state deliberately as part of the rebuild.

## Assertions: Where They Pay Off

Assertions are useful when they defend a real invariant, not when they paper over a design that still allows the bad path by construction.

Use assertions at:

- lifecycle boundaries: create, activate, deactivate, drop
- public mutation entry points: reject use after drop
- owned signal/callback entry points: reject callbacks into dropped objects
- required build/update context boundaries: fail if critical dependencies are missing
- restore/persistence boundaries: fail on structurally invalid state

Avoid relying on assertions alone when ownership is still ambiguous. Fix ownership first.

## Case Study: Theme Switch Graph Labels

### Symptom

After a theme switch, old graph node labels remained visible and new labels were added on top.

### Root Cause

This was not a label teardown bug. It was a lifecycle and ownership bug.

- theme change dropped the old `GraphView`
- `GraphView` was also directly subscribed to `app.engine.events.updated`
- the same engine update emission continued and invoked the old view's queued callback once more
- the dropped view still had enough internal state to recreate labels

There was a second bug in the same area:

- graph-view rebuild reused a build context whose theme had not been updated yet
- the rebuilt view could therefore use stale theme state

### Fix

The final fix was architectural, not just defensive:

- `GraphView` no longer subscribes directly to raw engine frame updates
- `HomeWorld:update` owns `graph-view:update`
- `Signal` semantics were tightened so disconnecting during emit suppresses later same-emit callbacks
- `GraphView` now asserts on use after drop
- theme rebuild explicitly injects the active theme into the build context before recreating the view

### Lessons

- a guard may be the correct temporary correctness fix, but it should trigger an ownership review
- split update ownership is a design smell
- stale ambient context is as dangerous as stale callbacks
- once the architecture is corrected, assertions become valid and useful

## Review Checklist

When adding or reviewing a runtime object, check these points:

- Is there exactly one owner?
- Is frame/update ownership explicit?
- Are all signal subscriptions owned and disconnected by the same owner?
- Does `drop` make further use fail fast?
- Does rebuild explicitly inject all mutable state it depends on?
- Are there tests for misuse, not just normal operation?

If any answer is unclear, the object is probably under-specified.
