# Light Theme Visual Layering Design

## Problem

The light theme currently uses surfaces that are too close to white and too close to each other. Backgrounds, rails, toolbars, dialogs, panels, and cards can blend together, while the dark theme already reads with enough separation. The requested direction is subtle Material-style tonal layering, with borders clear enough to distinguish visual layers.

## Goals

- Improve visual separation in the light theme without redesigning the dark theme.
- Use a subtle tonal stack rather than heavy shadows or high-contrast chrome.
- Keep borders visible enough that panels, dialogs, rails, and cards do not disappear against adjacent surfaces.
- Fit existing Space Fennel UI architecture and theme-resolution patterns.

## Non-goals

- Do not introduce a general public `surface`, `elevation`, shadow, or per-widget z-depth color API.
- Do not rewrite widget layout, rendering depth, or ownership behavior.
- Do not change dark-theme color behavior except where tests compare existing resolver contracts.
- Do not perform broad snapshot churn unless current tests require refreshed evidence.

## Context

The current theme system already has the right narrow surfaces for this improvement:

- `assets/lua/light-theme.fnl` defines light-theme `graph`, `chrome`, `card`, `button`, and `panel-border` tokens.
- `assets/lua/widget-theme-utils.fnl` centralizes card and chrome background resolution.
- Rails and side panels commonly use `resolve-chrome-background` with `:rail` or `:panel`.
- Toolbars, dialogs, controls, and status panels commonly render through `Card`, which uses `theme.card.background`.
- HUD borders already use `theme.panel-border` when present.

Because existing widgets consume these tokens, a token calibration can improve the broad light-theme visual read without changing widget APIs.

## Considered approaches

### Approach A: Recalibrate existing light-theme tokens

Update the light theme's existing `graph.background`, `chrome.rail-background`, `chrome.panel-background`, `card.background`, and `panel-border` values to form a coherent tonal stack.

Trade-offs:
- Best fit for current architecture.
- Smallest implementation and review surface.
- Improves most existing panels, rails, dialogs, and cards through existing resolvers.
- Does not solve future needs for named elevation levels, but those needs are not required for this visual bug.

### Approach B: Add new `surface` or `elevation` theme tokens

Introduce semantic tokens such as app background, surface, surface-container, elevated surface, and outline.

Trade-offs:
- More Material-like vocabulary.
- Requires resolver and call-site migration decisions.
- Risks creating parallel token systems while existing `graph`, `chrome`, and `card` tokens remain active.
- Too large for the immediate visual correction.

### Approach C: Add widget-level borders or shadows

Add Card/dialog/panel APIs for outlines, shadows, or elevation rendering.

Trade-offs:
- Could produce explicit separation at each widget.
- Requires rendering behavior changes and per-widget visual decisions.
- Higher risk for layout, snapshots, and dark-theme regressions.
- Heavyweight for a problem that is primarily caused by light-theme token values.

## Recommended design

Use Approach A: recalibrate existing light-theme tokens to create a subtle Material-style tonal stack with clear outlines.

The intended ordering is:

1. Rail surface: slightly darker/cooler than the app or graph background.
2. App or graph background: quiet cool off-white baseline.
3. Chrome panel surface: slightly lighter than the background.
4. Card/dialog/toolbar surface: slightly lighter than panel surfaces.
5. Panel border: visibly darker than panel and card surfaces, mostly opaque, but not heavy black.

This preserves existing Fennel UI contracts: widgets continue to resolve colors through `widget-theme-utils`, `Card`, and the existing theme maps. The implementation should use semantic local names inside `light-theme.fnl` so the tonal intent is readable and maintainable.

## Components and data flow

- `LightTheme` produces calibrated `glm.vec4` color tokens.
- Chrome widgets request rail or panel backgrounds through `resolve-chrome-background`.
- Card-based widgets request card backgrounds through `resolve-card-colors` or `Card`.
- HUD and panel wrappers use `theme.panel-border` for visible outlines.
- Existing rendering objects continue to receive resolved flat colors; no new rendering primitive is required.

## Error handling and constraints

- Missing theme context should continue to assert or use existing explicit resolver behavior; this work must not add silent fallbacks.
- The public token shape must remain compatible with current widget consumers.
- Fennel code must follow project idioms: `local` bindings, factory functions, direct resolver use, and no constructor-style `.new` additions.

## Testing and validation

Focused tests should assert light-theme tonal invariants rather than exact screenshots:

- Rail luminance is lower than graph/background luminance.
- Panel luminance is higher than graph/background luminance.
- Card luminance is higher than panel luminance.
- Panel and card gaps are large enough to be visible but still subtle.
- `panel-border` exists, is mostly opaque, and is visibly darker than panel/card surfaces.

Validation should follow the Space Fennel ladder:

1. Compile check for touched Fennel files with `tools.fennel-check`.
2. `make constraints`.
3. Focused theme/widget Fennel tests.
4. Broader relevant UI/Fennel test suite if token changes affect many UI surfaces.
5. Manual visual smoke in light theme covering graph background, rails, panels, dialogs, and card-heavy views.

## Acceptance criteria

- In light theme, backgrounds, rails, panels, cards/toolbars, and dialogs read as distinct layers.
- Borders are clear enough to distinguish adjacent light surfaces without looking harsh.
- Dark theme remains visually and behaviorally unchanged.
- Existing theme resolver interfaces remain unchanged.
- Focused tests document and protect the light-theme tonal layering contract.
