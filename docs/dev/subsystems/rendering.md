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

- Depends on: [Core Platform](/dev/features/core-platform)
- Depended on by: [Layout Widget Engine](/dev/features/layout-widget-engine)

## Dev notes

- [Render Architecture](/dev/notes/render-architecture) — batching, clips, and model transforms
- [Transform Pass](/dev/notes/transform-pass) — transform pass pipeline
- [Depth Precision Long Distance](/dev/notes/depth-precision-long-distance) — depth buffer precision
- [Gltf Async Embedded Texture Decode](/dev/notes/gltf-async-embedded-texture-decode) — async glTF loading
- [Render Capture](/dev/notes/render-capture) — frame capture via glReadPixels
- [Xdg Icon Browser And Svg Support](/dev/notes/xdg-icon-browser-and-svg-support) — icon theming and SVG

## See also

- [Core Platform](/dev/features/core-platform)
- [Subsystems](/dev/subsystems/)
