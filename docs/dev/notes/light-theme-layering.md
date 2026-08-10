# Light Theme Layering

The light theme uses existing theme tokens to create subtle Material-style tonal layering without introducing a public elevation or surface API.

## Token contract

The intended light-theme luminance order is:

1. `theme.chrome.rail-background` — rail surface, slightly darker/cooler than the graph background.
2. `theme.graph.background` — quiet cool off-white app/graph baseline.
3. `theme.chrome.panel-background` — panel chrome, slightly lighter than the app background.
4. `theme.card.background` — card, dialog, and toolbar surface, slightly lighter than panel chrome.
5. `theme.panel-border` — mostly opaque outline, visibly darker than panel and card surfaces.

Widgets should continue to consume these through existing resolvers and theme maps:
`resolve-chrome-background`, `resolve-card-colors`, `Card`, and existing HUD panel border handling.

## Non-goals

Do not add public `surface`, `elevation`, shadow, z-depth, or per-widget layering APIs for this behavior. If future work needs those concepts, it should introduce a separate design spec instead of overloading this note.
