PNG snapshot goldens live in this directory.

Update snapshots by setting `SPACE_SNAPSHOT_UPDATE` to a comma-separated list of names (e.g. `SPACE_SNAPSHOT_UPDATE=combo-box,scroll-view`).

Current e2e outputs:
- `button.png`: isolated widget-only render.
- `button-hover.png`: hover state triggered by hoverables/intersectables.
- `image.png`: image widget rendering `assets/pics/test.png`.
- `hud-button.png`: stable HUD-only render.
- `scroll-view.png`: scroll view mid-scroll with clipped items and scrollbar.
- `scroll-view-top.png`: scroll view after simulated wheel events return to top.
- `list-view.png`: list view default scroll position inside a constrained viewport.
- `scene-button.png`: stable scene-only render.
- `scene-hud-button.png`: combined scene + HUD render.

When adding or updating tests, view the PNGs directly to confirm the visuals match the intended scenario.
