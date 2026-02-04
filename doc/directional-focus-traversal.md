# Directional Focus Traversal

This document describes how directional focus traversal works in Space’s UI, how it is implemented in Fennel, and the trade-offs behind the current design.

## Goals

- Allow spatial focus traversal using arrow keys / vim keys.
- Prefer the “next” focus target in the chosen direction, rather than cycling order.
- Respect view boundaries so focus does not jump between unrelated scopes (HUD vs scene vs graph).
- Avoid focusing invisible or clipped items, while still allowing scroll views to be navigated.
- Keep the traversal logic centralized and reusable across widgets, graph points, and future focusable objects.

## Concepts

- **Focus node**: A focusable entity (widget, graph point, etc.) created via `FocusManager`.
- **Scope**: A focus subtree that can be marked as a traversal boundary.
- **Directional traversal boundary**: A scope that restricts directional traversal to its subtree.
- **Bounds**: Position + size for a focus node. Used to compute spatial relationships.
- **Frustum**: A 2D/3D directional cone (implemented as an angular frustum) used to score candidates.
- **Clip visibility**: Layout-level visibility classification (`inside`, `partial`, `outside`, `culled`).
- **Scroll controller**: Scroll view object attached to scroll layouts to allow auto-scrolling into view.

## High-level behavior

1. When a directional input arrives (e.g. Up), `FocusManager:focus-direction` is called.
2. The manager determines the direction axes based on camera orientation and the direction.
3. It resolves the directional traversal boundary for the currently focused node.
4. It gathers all focusables in that scope.
5. It filters out non-traversable nodes and invisible targets.
6. It scores candidates using a frustum intersection heuristic.
7. It selects the best candidate (lowest score, tie-breaker by required distance).
8. If the focused node is inside a scroll view and the target is in the same view, it calls `ensure-visible` to scroll.

## Implementation (Fennel)

Main implementation lives in:

- `assets/lua/focus.fnl`

Key pieces:

- `resolve-node-bounds`: obtains bounds from a node’s layout or custom bounds.
- `resolve-direction-axes`: resolves a direction and a perpendicular basis, using camera orientation when present.
- `frustum-intersection-score`: computes the “cost” to intersect a candidate with the directional frustum.
- `pick-directional-candidate`: iterates candidates and selects the best-scoring one.
- `find-directional-target`: ties everything together and chooses a target.

### Direction axes

Directional input can be:

- A symbolic direction (`:left`, `:right`, `:up`, `:down`), mapped to camera right/up.
- A vector (world direction), normalized and used directly.

The perpendicular axes are derived via cross products, using camera up/forward when available.

### Frustum scoring

Instead of pure center-to-center distance, traversal uses an angular frustum based on the focused node’s bounds. For each candidate we:

- Project the source and candidate bounds onto the forward axis.
- Project onto the perpendicular axes.
- Compute the gap between the bounds in perpendicular space.
- Compute the minimum forward distance required for a frustum to reach the candidate.

The score is `forward + required`, which favors nearer targets but penalizes large perpendicular offsets.

### Tiebreaker

If two candidates have the same score, we prefer the one that requires less perpendicular spread (smaller `required`).

### Scope boundaries

Focus scopes can be marked as directional traversal boundaries. Traversal will only consider targets within the same boundary scope as the focused node, preventing surprising jumps between HUD, scene, and graph contexts.

### Visibility filtering

Directional traversal filters by layout visibility:

- `:outside` or `:culled` are never eligible.
- `:partial` is eligible.

This avoids focusing fully clipped items while keeping traversal simple.

### Scroll view interactions

If focus is already inside a scroll view, traversal allows partially visible items in that scroll view (so arrowing can scroll through the list). When a target in the same scroll view is chosen, `scroll-controller:ensure-visible` is invoked to scroll it into view.

If focus is outside a scroll view, partially visible items in that scroll view are still eligible, allowing traversal to enter lists without special-case clipping rules.

## Trade-offs and rationale

- **Center-based navigation is unstable**: It caused “random” traversal when items are near each other. The frustum scoring is more consistent.
- **Strict `:inside` filtering is too harsh**: It skipped scroll lists entirely if items were clipped horizontally. Allowing partial targets keeps traversal predictable with simpler rules.
- **Traversal boundaries reduce surprise**: Without them, focus can jump between HUD and scene objects in unintuitive ways.
- **Centralized logic**: By keeping the traversal logic in `focus.fnl`, multiple widget types (graph points, list items, buttons, future focusables) can share the behavior without duplicating math.

## Issues encountered

- **Scroll view skip**: Directional traversal skipped the Top Stories dialog even when items were visible. Root cause was horizontal clipping causing `:partial` visibility. The fix was to allow partial targets for directional traversal.
- **Visibility vs scrolling**: We needed to prevent directional focus from selecting fully clipped items, but still allow scrolling within a scroll view once focus is inside it.
- **Frustum selection balance**: The algorithm had to balance perpendicular offsets vs forward distance to feel natural.

## Tests

Directional traversal behaviors are covered in:

- `assets/lua/tests/test-focus.fnl`
- `assets/lua/tests/test-scroll-view.fnl`

Key test cases:

- Uses frustum scoring and camera orientation.
- Ignores culled nodes.
- Stays within traversal boundary.
- Scrolls within a scroll view when focused inside.
- Accepts partial candidates when entering a scroll view.

## Future improvements

- Consider exposing a debug view for directional candidate scoring.
- Consider making frustum angle configurable per scope or per focusable type.
