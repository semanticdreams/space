# Render Capture

Render capture provides runtime image capture from the renderer for debugging and diagnostics.
It is separate from the E2E snapshot system (`assets/lua/snapshots.fnl`) which is test-focused.

## Current API (Final Frame Only)

Module: `assets/lua/render-capture.fnl`

```
(local RenderCapture (require :render-capture))
(RenderCapture.capture {:mode "final"
                        :path "/tmp/space/capture.png"
                        :width 1280
                        :height 720})
```

Notes:
- `:mode` defaults to `"final"` and is the only supported mode right now.
- `:width`/`:height` default to `app.viewport` if not provided.
- `:path` is optional; when omitted, capture returns the raw bytes.
- Use remote control to request captures in a live app and then inspect the PNG.
- If you need a frame to render after making changes, queue the capture with `app.next-frame`.

Remote control example (capture on the next frame):

```
./build/space -m tools.remote-control-client:main -- \
  --endpoint ipc:///tmp/space-rc.sock \
  -c "(do (local RenderCapture (require :render-capture))
           (app.next-frame (fn []
             (RenderCapture.capture {:mode \"final\"
                                     :path \"/tmp/space/tests/rc-capture.png\"}))))"
```

## Planned Modes (Design Outline)

The API is intended to expand without changing call sites:

```
{:mode "final"}                      ; read back the final framebuffer (current)
{:mode "scene"}                      ; scene-only capture
{:mode "hud"}                        ; HUD-only capture
{:mode "view" :camera {...}}         ; custom camera transform
{:mode "widget" :target <id>}        ; single widget capture
```

Implementation expectations:
- `scene`/`hud` will render to an offscreen framebuffer and read back that texture.
- `view` will render to an offscreen framebuffer using a temporary camera.
- `widget` will require isolating a widget draw list or computing bounds + readback.
- Unsupported modes should error loudly (`render-capture mode unsupported`).

## Testing

- Fast tests use mock OpenGL via `assets/lua/mock-opengl.fnl` to validate readback and PNG write logic.
- E2E tests compare a render-capture PNG against a snapshot generated through the xvfb runner.
