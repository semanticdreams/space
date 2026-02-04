# Sub Apps

Sub apps are offscreen-rendered mini apps that keep their own renderers, state, and update logic, then get composited into the main scene as textured quads. They are useful for embedding self-contained visuals inside dialogs or panels without mixing their draw calls into the main scene buffers.

## Architecture Overview
- `sub-app` owns its own render targets and rendering state.
- `sub-app-view` owns layout, sizing, and wiring a sub app into the main renderers.
- `renderers` is responsible for prerendering all sub apps and then compositing their quads into the main scene.

## Key Modules
- `assets/lua/sub-app.fnl`
  - Creates an offscreen framebuffer (FBO) with a color texture and depth buffer.
  - Owns a local `TriangleRenderer` and `VectorBuffer` instances.
  - Renders content into its FBO in `:prerender`.
  - Renders the final textured quad using `ImageRenderer` in `:render`.
- `assets/lua/sub-app-view.fnl`
  - Creates the sub app and registers it with `app.renderers`.
  - Converts layout size in world units to pixel size using `units-per-pixel`.
  - Updates the quad geometry based on layout position/rotation/size.
- `assets/lua/renderers.fnl`
  - `:prerender-sub-apps` runs before main scene rendering.
  - `:draw-sub-apps` draws the textured quads after scene content and before the HUD.
  - `:add-sub-app` / `:remove-sub-app` manage the list.

## Size Matching (Sharpness)
The sub app’s FBO size is recomputed from its layout size in world units:

```
pixel_width  = layout.size.x / units_per_pixel
pixel_height = layout.size.y / units_per_pixel
```

This ensures the offscreen texture matches the on-screen size, keeping the output sharp. The FBO is only recreated when the computed pixel size changes.

## Demo Wiring
- Button: `sub-app-one` in `assets/lua/hud-control-panel.fnl`.
- Opens a dialog with a `SubAppView` named `sub-world-one`.
- The demo sub app uses `raw-gradient-triangle.fnl` to render a gradient triangle.

## E2E Snapshot
- Test: `assets/lua/tests/e2e/test-sub-app.fnl`
- Snapshot: `assets/lua/tests/data/snapshots/sub-app-dialog.png`

To update:
```
SPACE_SNAPSHOT_UPDATE=sub-app-dialog SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e
```
