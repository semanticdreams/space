---
type: subsystem
tags:
  - subsystem
  - rendering
created: 2026-07-14
---

# Rendering system

OpenGL-based rendering pipeline: batched triangles and quads, SSBO-backed instanced rendering, model transforms, clips, depth management, FXAA, render capture, glTF async loading, and SDF font atlas generation.

## Key files

- `src/shader.h`, `src/texture.h`, `src/vector_buffer.h` — C++ GPU primitives
- `assets/lua/renderers.fnl`, `assets/lua/next-app/renderers.fnl` — widget and next-gen renderers
- `assets/lua/triangle-renderer.fnl`, `assets/lua/quad-renderer.fnl`, `assets/lua/text-renderer.fnl`

## Dependencies

- Depends on: [[core-platform]]
- Depended on by: [[layout-widget-engine]]

## Dev notes

- [[dev-notes/render-architecture]] — batching, clips, and model transforms
- [[dev-notes/transform-pass]] — transform pass pipeline
- [[dev-notes/depth-precision-long-distance]] — depth buffer precision
- [[dev-notes/gltf-async-embedded-texture-decode]] — async glTF loading
- [[dev-notes/render-capture]] — frame capture via glReadPixels
- [[dev-notes/xdg-icon-browser-and-svg-support]] — icon theming and SVG

## See also

- [[core-platform]]
- [[subsystems]]
