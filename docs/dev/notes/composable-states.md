---
type: dev-note
tags:
  - note
---

# Composable Input States

## Summary

The current state system is centered on `StateBase.make-state`, which gives each state a large bundle of inherited default behavior. That works for broad app modes like `:normal`, but it is a poor fit for modal editor states such as `:terrain-rect-pick` and `:terrain-paint`.

The core design problem is accidental inheritance:

- a state can receive input behavior it never explicitly asked for
- modal states must override handlers just to block unrelated behavior
- adding a new default input path can silently leak into existing states

The replacement should be a composable state system with zero implicit input behavior.

## Implementation Status

This design is now implemented.

The legacy `StateBase` layer has been removed. The runtime is now centered on:

- `assets/lua/state.fnl`
- `assets/lua/state-routes.fnl`
- `assets/lua/state-runtime.fnl`
- `assets/lua/state-handlers/*.fnl`

Production states such as `normal`, `terrain-rect-pick`, `terrain-paint`, `leader`, `camera`, `fpc`, `text`, `insert`, `quit`, `car`, and `tetris` now build on `State` directly.

There is no shared default route bundle. Each state now declares its own `:routes`, `:enter`, and `:leave` lists explicitly, reusing only opt-in handler tables from focused modules under `state-handlers/`.

The existing outer state-manager contract remains in place: runtime states still expose methods such as `on-enter`, `on-leave`, `on-key-down`, and `on-mouse-motion`. That compatibility surface is now produced by the new composer rather than inherited from `StateBase`.

## Goals

- States start with no input behavior by default.
- A state gains behavior only by composing explicit handlers.
- Input routing is declared per event rather than hardcoded in one base helper.
- Modal states do not need special blocking logic to stay exclusive.
- Shared behaviors like hover tracking, click dispatch, and camera controls remain reusable.

## Non-Goals

- This note does not propose a full app-wide input rewrite in one change.
- This note does not require replacing all existing states immediately.
- This note does not define exact naming for every helper module.

## Problems With the Current Design

### Inherited defaults are too broad

`StateBase.make-state` currently wires in default behavior for:

- clickables
- hoverables
- movables
- resizables
- first-person controls
- mouse wheel dispatch
- per-frame updates

That means a state is not just defining its own behavior. It is also inheriting a policy bundle.

### Modal states are forced into opt-out behavior

States like `:terrain-rect-pick` are conceptually exclusive. While active, they should own the relevant input surface. In the current model they instead inherit general behavior and must override individual handlers to prevent leaks.

This is fragile because:

- forgetting one override causes mixed behavior
- future default handlers can create new leaks
- the exclusivity contract is not visible in the state definition

### Dispatch policy is hardcoded

Today event routing is embedded in the default handlers. For example, mouse motion and mouse wheel already have baked-in assumptions about ordering and fallback.

That prevents using different strategies for different states, such as:

- first-handler-wins
- broadcast
- prioritized chains
- capture vs bubble phases
- modal guards

## Design Principles

### 1. Zero-base states

A state starts with no behavior. If it should react to mouse wheel, update hover, or drive camera controls, those behaviors must be explicitly composed in.

### 2. Composition over inheritance

Reusable behavior should live in explicit handlers, not in one shared base state with broad defaults.

### 3. Dispatch is a strategy

The mechanism that delivers an event to handlers should itself be configurable.

### 4. Modal exclusivity should fall out of composition

A modal state should be exclusive because it only composes exclusive handlers, not because it inherits broad behavior and then blocks it.

## State Shape

A state is assembled from:

- metadata
- a routing table keyed by event name
- optional enter/leave handler lists

The important architectural constraint is that this is the final shape, not a wrapper over `StateBase.make-state`. The new system may preserve the current external state-manager interface for compatibility, but the new core should not inherit old default-policy concepts.

Example shape:

```fennel
(State
  {:name :terrain-rect-pick
   :routes
   {:key-down (FirstHandlerWins [EscapeCancel TerrainRectPick])
    :mouse-button-down (FirstHandlerWins [TerrainRectPick])
    :mouse-motion (FirstHandlerWins [TerrainRectPick])
    :mouse-button-up (FirstHandlerWins [TerrainRectPick])
    :updated (Broadcast [TerrainRectPick])}
   :enter [TerrainRectPick]
   :leave [TerrainRectPick]})
```

Another state might use:

```fennel
(State
  {:name :normal
   :routes
   {:key-down (FirstHandlerWins [InputDispatch FocusDispatch])
    :key-up (FirstHandlerWins [InputDispatch])
    :mouse-button-down (FirstHandlerWins [InputDispatch
                                          ResizableDispatch
                                          ClickableDispatch
                                          MovableDispatch
                                          SelectionDispatch
                                          CameraMouseButtons])
    :mouse-button-up (FirstHandlerWins [InputDispatch
                                        ResizableDispatch
                                        ClickableDispatch
                                        MovableDispatch
                                        SelectionDispatch
                                        CameraMouseButtons])
    :mouse-motion (FirstHandlerWins [InputDispatch
                                     MovableDispatch
                                     ResizableDispatch
                                     SelectionDispatch
                                     CameraMouseMotion
                                     HoverTracking])
    :mouse-wheel (FirstHandlerWins [InputDispatch
                                    HoveredWheelDispatch
                                    CameraMouseWheel])
    :updated (Broadcast [CameraUpdate HoverUpdate])}
   :enter [HoverTracking]
   :leave [HoverTracking]})
```

## Handler Shape

A handler module exposes only the event functions it cares about:

```fennel
{:enter ...
 :leave ...
 :key-down ...
 :mouse-button-down ...
 :mouse-motion ...
 :mouse-wheel ...
 :updated ...}
```

Unspecified handlers mean “this handler has no opinion.”

The routing table is the primary declaration of state behavior. A handler may appear in multiple event routes. That repetition is intentional because it keeps event ownership and ordering visible in the state definition.

## Final Runtime API

The implementation should target a small final runtime API:

- `State`
  - composes a state definition into a runtime state object
- `FirstHandlerWins`
  - tries handlers in order until one handles the event
- `Broadcast`
  - invokes all handlers for an event
- `Chain`
  - runs handlers in order, keeping sequencing visible for side-effectful routing such as pointer dispatch

Example target module boundaries:

- `state.fnl`
  - owns `State`
- `state-routes.fnl`
  - owns route combinators such as `FirstHandlerWins` and `Broadcast`
- `state-handlers/*.fnl`
  - own reusable handler tables grouped by concern such as hover, focus, pointer routing, gamepad, and camera update

The runtime may expose compatibility fields like `on-key-down` and `on-mouse-motion` so the existing state manager can keep working during migration, but those are an outer integration seam only. They must be produced by the new composer rather than defining the new architecture.

## Handler Contract

Handlers should be plain tables of event functions plus optional lifecycle functions. They should not inherit from a base state and should not receive hidden default behavior.

Recommended handler function shape:

```fennel
{:enter (fn [ctx] ...)
 :leave (fn [ctx] ...)
 :key-down (fn [ctx payload] ...)
 :mouse-button-down (fn [ctx payload] ...)
 :mouse-motion (fn [ctx payload] ...)
 :updated (fn [ctx delta] ...)}
```

Return convention:

- `true`
  - this handler handled the event
- `false` or `nil`
  - this handler did not handle the event

Handlers may mutate their own internal state or app/runtime state. The design goal is explicit composition, not artificial purity.

## Runtime Context

Handlers should receive an explicit runtime context rather than depending on hidden ambient behavior from `StateBase`.

Minimum expected context:

```fennel
{:app app
 :state runtime-state
 :set-state (fn [name] ...)
 :active-input (fn [] ...)
 :connect-input (fn [input] ...)
 :disconnect-input (fn [input] ...)}
```

This context is where generic helpers should live. For example, active-input lookup or state switching can be provided through `ctx` rather than reimplemented in every handler module.

Route combinators may extend `ctx` with event-local helpers when needed. The current runtime uses event-local context fields for chained routing, such as “has this event already been consumed within this route?”

## Composer Responsibilities

The composer should own:

- state-local runtime context construction
- engine event subscription and unsubscription
- enter/leave lifecycle dispatch
- route lookup per event
- production of compatibility methods such as `on-key-down`, `on-updated`, and `on-enter`

The implemented composer also treats `on-enter` and `on-leave` as idempotent. Entering the same runtime state twice does not duplicate signal subscriptions, and leaving a state that is already inactive is a no-op.

The composer should not:

- inject default handlers
- encode the old `normal` behavior implicitly
- require handler modules to follow `StateBase` naming or structure internally

## Dispatch Strategies

The state builder should not hardcode one event-routing rule. Each event route should accept a strategy combinator.

Useful built-in strategies:

- `FirstHandlerWins`
  - handlers are called in order until one returns `true`
- `Broadcast`
  - all handlers receive the event
- `PriorityChain`
  - like first-handler-wins, but with explicit phases or priorities
- `CaptureBubble`
  - useful for layered UI or nested scopes

This matters because some behaviors should compete, while others should co-exist, and different events often need different routing semantics.

For the initial implementation, `FirstHandlerWins`, `Broadcast`, and `Chain` are sufficient. Additional strategies should be added only when a concrete state needs them.

## Recommended First Handlers

Initial reusable handlers should align with existing behavior seams:

- `HoverTracking`
- `ClickableDispatch`
- `MovableDispatch`
- `ResizableDispatch`
- `SelectionDispatch`
- `CameraMouseButtons`
- `CameraMouseMotion`
- `CameraMouseWheel`
- `CameraUpdate`
- `EscapeCancel`
- `TerrainRectPick`
- `TerrainPaint`

The important point is to separate camera wheel, camera motion, and camera per-frame update into different handlers so modal states can include none of them.

## Example: Terrain Rect Pick

Current conceptual intent:

- left mouse down begins drag
- mouse motion updates drag
- left mouse up resolves drag
- escape cancels
- no camera motion
- no camera wheel
- no unrelated clickable dispatch

Under a composable system:

```fennel
(State
  {:name :terrain-rect-pick
   :routes
   {:key-down (FirstHandlerWins [EscapeCancel TerrainRectPick])
    :mouse-button-down (FirstHandlerWins [TerrainRectPick])
    :mouse-motion (FirstHandlerWins [TerrainRectPick])
    :mouse-button-up (FirstHandlerWins [TerrainRectPick])
    :updated (Broadcast [TerrainRectPick])}
   :enter [TerrainRectPick]
   :leave [TerrainRectPick]})
```

This state is exclusive because nothing camera-related or UI-routing-related appears in its routes.

## Example: Terrain Paint

```fennel
(State
  {:name :terrain-paint
   :routes
   {:key-down (FirstHandlerWins [EscapeCancel TerrainPaint])
    :mouse-button-down (FirstHandlerWins [TerrainPaint])
    :mouse-motion (FirstHandlerWins [TerrainPaint])
    :mouse-button-up (FirstHandlerWins [TerrainPaint])
    :updated (Broadcast [TerrainPaint])}
   :enter [TerrainPaint]
   :leave [TerrainPaint]})
```

Again, there is no need for explicit “reject wheel” or “block controls” logic if those handlers are absent.

## Example: Normal State

`normal` is the state that should explicitly assemble the shared app interaction model:

```fennel
(State
  {:name :normal
   :routes
   {:key-down (FirstHandlerWins [NormalCommands
                                 InputKeyDownDispatch
                                 FocusTabKeyDown
                                 FocusDirectionKeyDown
                                 ActiveInputKeyBlock])
    :key-up (FirstHandlerWins [InputKeyUpDispatch
                               ActiveInputKeyBlock])
    :mouse-button-down (Chain [InputMouseButtonDownDispatch
                               ResizableMouseButtonDown
                               ClickableMouseButtonDown
                               MovableMouseButtonDown
                               SelectionMouseButtonDown
                               CameraMouseButtonDown])
    :mouse-button-up (Chain [InputMouseButtonUpDispatch
                             ResizableMouseButtonUp
                             ClickableMouseButtonUp
                             MovableMouseButtonUp
                             SelectionMouseButtonUp
                             CameraMouseButtonUp
                             HoverAfterMouseButtonUp])
    :mouse-motion (Chain [InputMouseMotionDispatch
                          MovableMouseMotion
                          ResizableMouseMotion
                          CameraDragMouseMotion
                          SelectionMouseMotion
                          CameraMouseMotion
                          HoverMouseMotion])
    :mouse-wheel (FirstHandlerWins [InputDispatch
                                    HoveredWheelDispatch
                                    CameraMouseWheel])
    :updated (Chain [CameraUpdated HoverUpdated])}
   :enter [HoverLifecycle]
   :leave [HoverLifecycle]})
```

This keeps the full interaction policy visible in the state itself instead of hiding it behind a premerged default bundle.

## Migration Plan

### Phase 1: Implement the final core

- Add the new state composer in a dedicated module such as `state.fnl`
- Add route combinators in a dedicated module such as `state-routes.fnl`
- Define the explicit runtime context passed to handlers
- Keep compatibility only at the outer boundary by having `State` return fields like `on-key-down` and `on-leave`

This phase should not reuse `StateBase.make-state` internally.

### Phase 2: Extract modal session handlers

- Extract `TerrainRectPick`
- Extract `TerrainPaint`
- Move escape-cancel behavior into a small reusable handler

### Phase 3: Prove the design on modal editor states

Migrate these states first because they benefit most from zero-default behavior:

- `terrain-rect-pick`
- `terrain-paint`

These should become the proving ground for the new design.

### Phase 4: Extract shared default handlers

Split current broad default behavior into explicit reusable handlers:

- hover
- click routing
- move/resize routing
- camera wheel
- camera motion
- camera update

### Phase 5: Rebuild `normal` from explicit routes

Once handlers are stable, rebuild `:normal` from explicit pieces and retire the broad inherited default model.

### Phase 6: Migrate the remaining specialized states

Migrate the remaining states directly into the new model:

- `leader`
- `camera`
- `fpc`
- `insert`
- `text`
- any other state-specific modules

These ports should preserve current behavior, but they should be expressed in the final handler/route model rather than translated through `StateBase`.

### Phase 7: Remove `StateBase`

- Delete `StateBase.make-state`
- Move any remaining generic helpers into the new runtime modules or dedicated reusable handlers
- Reject any fallback path that silently restores inherited default behavior

This phase is complete. `StateBase` has been deleted rather than left as a compatibility shim.

## Implementation Notes

The final implementation did not follow the migration plan literally in every detail. A few practical decisions mattered:

- `normal` was rebuilt using explicit route composition plus a reusable default route/config layer instead of recreating an implicit base-state policy bundle.
- Shared behavior was split into two levels:
  - route combinators in `state-routes.fnl`
  - reusable default behavior and runtime helpers in `state-defaults.fnl`, `state-default-config.fnl`, and `state-runtime.fnl`
- Compatibility was preserved only at the edge where `states.fnl` expects state objects with `on-*` methods.
- Tests that previously depended on `StateBase` helpers were migrated to use `State`, `state-runtime`, or explicit default config directly.

## Problems Encountered

Several migration issues showed up during implementation and test cleanup.

### Duplicate signal subscriptions

The biggest issue was duplicated engine-signal subscriptions during tests.

Some tests manually called `state.on-enter` after also activating the state through `states.set-state`, which already calls `on-enter`. Under the new system that produced duplicated signal handlers and repeated input delivery.

The fix was:

- make `State.on-enter` and `State.on-leave` idempotent
- stop manually double-entering states in affected tests where possible

This was an important hardening step for the new runtime, not just a test workaround.

### Test reset leaked state transitions

The original test cleanup path sometimes called `InputState.release-active-input`. That function can transition from `:text` or `:insert` back to `:normal`. In the test environment that could re-enter a state while signals were being reset, leaving unexpected listeners attached.

The fix was:

- add an explicit reset path for input runtime state that does not perform state transitions
- have the shared test runner reset composable-state runtime state directly

This clarified an architectural distinction that matters going forward:

- runtime reset for tests
- user-facing input release during actual app execution

These are not the same operation and should not share one API.

### Suite-level event contamination

One terminal widget test was stable in isolation but failed under the full `tests.fast` order. The cause was leaked or unexpected engine-signal state from earlier tests in the same process.

The fix was to isolate that test with a fresh temporary engine-events table for the duration of the case. That keeps the focus-routing assertion about terminal behavior rather than making it sensitive to unrelated suite history.

### Parser cleanup during migration

One migrated state (`tetris-state`) hit a Fennel parse issue after the routing rewrite because the nested input logic had become too structurally dense.

The fix was to pull the key handling into a helper function and flatten the state route definition. This reinforced a useful implementation rule:

- if migrating a handler makes nesting awkward, factor the logic out rather than forcing the route declaration to carry it

## Testing Notes

The final migration was validated with the full test suite:

- `make test`

That run passed with:

- `space_fnl_tests`
  - `Executed 1222 Lua tests`
- all C++/integration CTest targets
- `100% tests passed, 0 tests failed out of 8`

## Benefits

- No hidden input behavior in modal states
- Safer evolution when new input paths are added
- Better readability of state intent
- Reusable interaction pieces without broad inheritance
- Multiple dispatch semantics supported without special-casing modal states

## Risks

- More initial structure than a single base helper
- Requires clear handler boundaries or it can become another implicit system
- Ordering between handlers must be explicit and tested

## Recommended Direction

Move toward zero-base composable states with explicit per-event routes.

The key decision is not merely “opt-in” vs “opt-out.” The key decision is to stop encoding interaction policy inside one inherited state base.

Implementation should be guided by the final architecture, not by the structure of the current state system. Existing behavior is the migration spec. The current internals are not.

States should declare:

- which handlers run for each event
- in what order
- under which routing strategy

Compatibility is acceptable only at the outer boundary where the state manager expects methods like `on-enter` and `on-key-down`. It is not acceptable to rebuild the new core as a thin wrapper around `StateBase`.

That makes modal exclusivity, normal navigation, and future specialized modes all first-class cases of the same design.

## See also

- [Input](/dev/subsystems/input), [Composable States](/dev/adrs/adr-composable-states)
