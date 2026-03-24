# Composable Input States

## Summary

The current state system is centered on `StateBase.make-state`, which gives each state a large bundle of inherited default behavior. That works for broad app modes like `:normal`, but it is a poor fit for modal editor states such as `:terrain-rect-pick` and `:terrain-paint`.

The core design problem is accidental inheritance:

- a state can receive input behavior it never explicitly asked for
- modal states must override handlers just to block unrelated behavior
- adding a new default input path can silently leak into existing states

The replacement should be a composable state system with zero implicit input behavior.

## Goals

- States start with no input behavior by default.
- A state gains behavior only by composing explicit components.
- Input routing strategy is pluggable rather than hardcoded in one base helper.
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

Reusable behavior should live in input components, not in one shared base state with broad defaults.

### 3. Dispatch is a strategy

The mechanism that delivers an event to components should itself be configurable.

### 4. Modal exclusivity should fall out of composition

A modal state should be exclusive because it only composes exclusive components, not because it inherits broad behavior and then blocks it.

## State Shape

A state is assembled from:

- metadata
- a list of input components
- a dispatch strategy

Example shape:

```fennel
{:name :terrain-rect-pick
 :components [PickDragSession EscapeCancel]
 :dispatch (Dispatch.first-handler-wins)}
```

Another state might use:

```fennel
{:name :normal
 :components [InputFields
              Clickables
              HoverTracking
              Movables
              Resizables
              SelectionBox
              CameraControls
              CameraUpdate]
 :dispatch (Dispatch.priority-chain)}
```

## Component Shape

A component exposes only the handlers it cares about:

```fennel
{:on-enter ...
 :on-leave ...
 :on-key-down ...
 :on-mouse-button-down ...
 :on-mouse-motion ...
 :on-mouse-wheel ...
 :on-updated ...}
```

Unspecified handlers mean “this component has no opinion.”

## Dispatch Strategies

The state builder should not hardcode one event-routing rule. It should accept a dispatch strategy object or function family.

Useful built-in strategies:

- `first-handler-wins`
  - components are called in order until one returns `true`
- `priority-chain`
  - like first-handler-wins, but with explicit phases or priorities
- `broadcast`
  - all components receive the event
- `capture-bubble`
  - useful for layered UI or nested scopes

This matters because some behaviors should compete, while others should co-exist.

## Recommended First Components

Initial reusable components should align with existing behavior seams:

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
- `TerrainRectPickSession`
- `TerrainPaintSession`

The important point is to separate camera wheel, camera motion, and camera per-frame update into different components so modal states can include none of them.

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
State.compose
  {:name :terrain-rect-pick
   :components [(TerrainRectPickSession)
                (EscapeCancel)]
   :dispatch (Dispatch.first-handler-wins)}
```

This state is exclusive because nothing camera-related or UI-routing-related is composed into it.

## Example: Terrain Paint

```fennel
State.compose
  {:name :terrain-paint
   :components [(TerrainPaintSession)
                (EscapeCancel)]
   :dispatch (Dispatch.first-handler-wins)}
```

Again, there is no need for explicit “reject wheel” or “block controls” logic if those components are absent.

## Example: Normal State

`normal` is the state that should explicitly assemble the shared app interaction model:

```fennel
State.compose
  {:name :normal
   :components [(InputDispatch)
                (MovableDispatch)
                (ResizableDispatch)
                (ClickableDispatch)
                (SelectionDispatch)
                (CameraMouseMotion)
                (CameraMouseWheel)
                (CameraUpdate)
                (HoverTracking)]
   :dispatch (Dispatch.priority-chain)}
```

This is a better fit for broad default behavior than forcing every state to inherit it.

## Migration Plan

### Phase 1: Introduce a new composer alongside `StateBase`

- Add a new state composer, for example `state-compose.fnl`
- Keep `StateBase.make-state` unchanged during initial adoption
- Implement a small set of dispatch strategies

### Phase 2: Extract modal session components

- Extract `TerrainRectPickSession`
- Extract `TerrainPaintSession`
- Move escape-cancel behavior into a small reusable component

### Phase 3: Migrate modal editor states first

Migrate these states first because they benefit most from zero-default behavior:

- `terrain-rect-pick`
- `terrain-paint`

These should become the proving ground for the new design.

### Phase 4: Extract shared default components

Split current broad default behavior into explicit reusable components:

- hover
- click routing
- move/resize routing
- camera wheel
- camera motion
- camera update

### Phase 5: Rebuild `normal` on composition

Once components are stable, rebuild `:normal` from explicit pieces and retire the broad inherited default model.

## Benefits

- No hidden input behavior in modal states
- Safer evolution when new input paths are added
- Better readability of state intent
- Reusable interaction pieces without broad inheritance
- Multiple dispatch semantics supported without special-casing modal states

## Risks

- More initial structure than a single base helper
- Requires clear component boundaries or it can become another implicit system
- Ordering between components must be explicit and tested

## Recommended Direction

Move toward zero-base composable states with pluggable dispatch strategy.

The key decision is not merely “opt-in” vs “opt-out.” The key decision is to stop encoding interaction policy inside one inherited state base.

States should declare:

- which behaviors they compose
- in what order
- under which dispatch strategy

That makes modal exclusivity, normal navigation, and future specialized modes all first-class cases of the same design.
