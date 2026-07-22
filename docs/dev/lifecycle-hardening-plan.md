---
type: planning
tags:
  - plan
  - lifecycle
  - engineering
created: 2026-07-14
updated: 2026-07-14
---

# Lifecycle Hardening Plan

This note turns the recent lifecycle/debugging work into an explicit engineering plan.

It is intentionally broader than [Lifecycle Invariants](/dev/lifecycle-invariants) and
[Widget Ownership](/dev/widget-ownership-and-teardown)|Widget Ownership And Teardown.

Those documents define the rules.
This document focuses on:

- the bug classes we just dealt with
- the strategies that prevent them
- concrete options for tightening the rest of the codebase

## Why This Exists

The recent fixes were not isolated bugs. They were examples of a few recurring failure modes:

- stale callbacks after teardown
- ambiguous ownership of update loops
- confusion between layout teardown and widget teardown
- async completions mutating dropped UI
- incomplete post-drop contracts
- rebuild paths reusing stale ambient state

The goal is not to patch each case independently forever.
The goal is to make these bugs harder to write at all.

## Recent Bug Classes

### 1. Split update ownership

Example:

- `GraphView` was updated both through the app/word runtime flow and through a raw `app.engine.events.updated` subscription

Failure mode:

- one system drops the object
- the other system still has an in-flight callback path
- stale update work recreates state after teardown

Prevention:

- one update owner per runtime object
- raw engine frame signals only behind shared owner services

### 2. Layout teardown mistaken for widget teardown

Examples:

- `SearchView` was briefly using `self.layout:drop`
- `RipgrepView` manually dropped descendants that were already covered by recursive widget teardown

Failure mode:

- either child widgets survive because only layout state was removed
- or descendants are dropped twice because the owning composite widget also drops them

Prevention:

- treat `layout` as geometry bookkeeping, not widget lifetime
- drop the owning widget/composite, not just its layout
- document direct widget ownership explicitly in composites

### 3. Async completion after drop

Examples:

- `Input` external editor completion
- wallet RPC futures
- `RipgrepView` process completion

Failure mode:

- callback runs after UI has already dropped
- callback mutates dead widgets or touches dropped owned resources

Prevention:

- best: cancel or disconnect callback source in `drop`
- fallback: request/attempt generation invalidation
- final fallback: explicit `__dropped` guard only for truly external late completions

### 4. Incomplete post-drop contracts

Examples:

- double-drop was asserted, but some other public methods still operated after drop

Failure mode:

- code looks "strict" but still allows post-drop mutations through less obvious entry points

Prevention:

- review the full public API, not only `drop`
- decide whether each entry point should:
  - assert after drop
  - or quietly ignore a legitimate late external completion

### 5. Stale rebuild context

Example:

- theme rebuild reused a build context that still carried the old theme

Failure mode:

- rebuilt runtime objects are internally consistent but created from stale ambient dependencies

Prevention:

- inject mutable rebuild inputs explicitly
- avoid assuming shared context objects are already current

## Prevention Strategies

These are the main tools available in this codebase.

### 1. Centralize ownership

Use this when:

- an object updates every frame
- multiple subsystems can "reach" it
- teardown bugs come from hidden second owners

Preferred shape:

- one creator
- one updater
- one dropper

Examples already applied:

- `GraphView` moved under `HomeWorld:update`
- raw frame hooks moved behind `RuntimeTimers` / `RuntimeUpdates`

### 2. Prefer services over raw global signals

Use this when:

- code wants periodic work or every-frame work
- the real behavior is "I need ticking", not "I want to own the engine signal"

Preferred shape:

- `RuntimeTimers.Interval`
- `RuntimeTimers.Timeout`
- `RuntimeTimers.Debouncer`
- `RuntimeUpdates.FrameSubscription`

Benefits:

- one central raw signal subscription
- uniform teardown
- easier tests
- less per-widget signal wiring

### 3. Make post-drop behavior explicit

There are only two legitimate behaviors after drop:

- fail fast with an assertion
- return quietly because the callback is a late external completion

Do not leave ambiguous "maybe it still works" paths.

Good candidates for assertions:

- direct public API methods
- owned signal handlers
- internal update hooks
- owned timer callbacks

Good candidates for quiet ignore:

- process completion callbacks
- RPC futures with no cancellation support
- editor/file picker completions

### 4. Cancel or disconnect whenever possible

This is the cleanest fix for post-drop callbacks.

Examples:

- disconnect signal handler in `drop`
- cancel frame subscription in `drop`
- cancel process/future and suppress callback if the API supports it

Rule:

- if the source is owned and cancellable, prefer cancellation over guards

### 5. Use generation invalidation for non-cancellable async work

This is the clean fallback when cancellation is not available.

Shape:

1. increment request/attempt generation when starting work
2. increment again in `drop`
3. callback checks whether its generation is still current before touching state

This is what the wallet fixes now do.

Benefits:

- no post-drop UI mutation
- no stale callback touching dropped owned resources
- works even when the future API is weak

### 6. Tighten low-level contracts

Some lifecycle bugs disappear entirely if the primitive behavior is stricter.

Examples:

- `Signal.disconnect` suppressing later same-emit callbacks
- safe unwind in `Signal.emit`

Use this when:

- many objects need the same defensive pattern
- the real bug is the primitive, not every call site

### 7. Test misuse, not only success

Add regression tests for:

- double drop
- public API after drop
- late completion after drop
- dropped object no longer receiving periodic updates
- rebuild path receives current mutable state

These tests are high leverage because lifecycle regressions often reappear indirectly.

## Review Heuristics

During review, ask these questions:

- What owns creation, update, and drop?
- Is any raw engine signal used where a narrower owner already exists?
- Is this dropping a widget or only a layout?
- Are any descendants manually dropped and then also dropped through a composite parent?
- Can any async completion still fire after `drop`?
- If yes, can it be cancelled/disconnected?
- If not, is there a generation or dropped-state guard?
- Does every public mutator have an explicit post-drop policy?
- Does rebuild take current state explicitly instead of reading stale ambient context?

If any answer is unclear, the code is probably still lifecycle-fragile.

## Tightening Options

These are realistic next steps for the codebase, from narrowest to broadest.

### Option A: Targeted audit only

Scope:

- audit runtime objects with `drop`
- audit direct public mutators
- audit async callback sites

Work:

- add assertions to obvious public post-drop entry points
- add late-callback guards to non-cancellable async completions
- add missing regression tests

Benefits:

- low disruption
- good bug-finding yield
- easy to stage incrementally

Costs:

- repetitive
- depends on review discipline
- does not reduce boilerplate much

Best when:

- you want fast incremental hardening with low architectural churn

### Option B: Standardize async ownership helpers

Scope:

- future/process/RPC-backed UI flows

Work:

- introduce a small shared helper or pattern for drop-safe async completions
- likely concepts:
  - request generation tokens
  - invalidation handles
  - helper wrappers for guarded completion

Benefits:

- reduces hand-rolled late-callback logic
- makes reviews easier
- less chance of inconsistent guard behavior

Costs:

- small API design effort
- some migration work

Best when:

- async completions are the main remaining lifecycle pain point

### Option C: Strengthen future/process APIs themselves

Scope:

- wallet RPC futures
- other future-like or callback-based APIs

Work:

- add explicit cancellation/unsubscribe support
- optionally support suppressing callbacks after cancel
- document which APIs guarantee no late callback after cancel

Benefits:

- cleanest model
- shifts correctness into primitives instead of call sites
- reduces need for generation invalidation

Costs:

- medium design work
- may touch many call sites
- may require compatibility decisions

Best when:

- you want the architecture itself to forbid more of these bugs

### Option D: Repository-wide fail-fast pass

Scope:

- all `drop`-owning runtime objects and widgets

Work:

- enforce "public API after drop" assertions broadly
- normalize double-drop assertions
- add or tighten ownership docs module-by-module where needed

Benefits:

- strongest local correctness guarantees
- surfaces hidden lifecycle bugs quickly

Costs:

- high churn
- can produce a wave of newly exposed failures
- must be paired with ownership cleanup, not just assertions

Best when:

- you are willing to trade short-term breakage for a much stricter runtime contract

## Recommended Order

The most pragmatic sequence is:

1. Finish Option A for the highest-risk modules.
2. Do Option B for shared async guard patterns.
3. Then decide whether Option C is worth the API churn.
4. Only after ownership is clear should you do a broad Option D pass.

This order matters.
If you do a repository-wide assertion pass before ownership and async semantics are clear, you mostly convert hidden bugs into crashes without reducing the bug surface enough.

## High-Leverage Targets

If more tightening work resumes later, prioritize:

- non-cancellable async completion APIs
- UI flows that launch background work and then update widgets directly
- objects with `drop` plus several public mutators
- modules that still store child widget references and also manage complex teardown
- rebuild paths that depend on theme, target, world, or camera state

## Current Recommendation

If there is time for only one more tightening project, choose this:

- standardize drop-safe async completion handling for future/process-based UI flows

Why:

- raw frame ownership has already been improved substantially
- widget/layout ownership is now documented clearly
- the next likely lifecycle regressions are late async completions and incomplete public post-drop contracts

That is the highest-leverage remaining class after the recent fixes.

## See also

- [Developer Docs](/dev/)
