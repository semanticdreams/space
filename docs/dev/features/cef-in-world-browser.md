---
type: feature
status: shipped
parent-goal: core-platform
tags:
  - feature
  - browser
  - cef
  - in-world
created: 2026-07-14
updated: 2026-07-14
---

# CEF in-world browser

## Summary

Chromium Embedded Framework integration for rendering web content onto arbitrary 3D surfaces. Browser instances are managed as world-surface textures that can be mapped to any mesh/material.

## Motivation

Spatial computing benefits from in-world web content — reference documentation, live dashboards, web apps rendered on 3D surfaces. Rather than a flat overlay, web content should be a first-class world object.

## Design

- **CEF integration**: Linux-only; CMake manages CEF download/version pinning
- **Surface API**: `app.engine.browser:create-surface` with id, url, texture-name, width, height, max-fps
- **Texture binding**: `:texture-name` binds the rendered page to any mesh/material texture slot
- **Input routing**: `send-mouse-move`, `send-mouse-click`, `send-mouse-wheel`, `set-focus` for world-space interaction
- **Opt-in cube demo**: 6-face browser cube via `SPACE_BROWSER_CUBE_DEMO=1`

## Tasks

- [x] CEF library download and CMake integration
- [x] Browser surface creation and GL texture output
- [x] Mouse/keyboard input routing
- [x] Multi-surface support
- [x] Opt-in cube demo

## Related

- Goal: [Core Platform](/dev/features/core-platform)
- Depends on: [Layout Widget Engine](/dev/features/layout-widget-engine) — CEF surfaces use the layout engine
- See: [README](https://github.com/semanticdreams/space) (CEF build setup)
- See: [Cef In World Browsing](/dev/notes/cef-in-world-browsing), [Cef Icu Fd Crash](/dev/notes/cef-icu-fd-crash)
