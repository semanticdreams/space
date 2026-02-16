# XDG Icon Browser + SVG Support Status

## Current Status

- The icon browser now reads real data from `assets/data/xdg-icons.json` in the E2E snapshot.
- We removed the E2E test fakes that injected a mock icon JSON and the material icon fallback.
- The UI no longer mixes material glyphs with XDG icons; it attempts to render only XDG image paths.
- The dataset is dominated by SVG paths (especially `hicolor`), and the current texture loader does not support SVG.
- Because SVGs cannot be loaded today, the grid is mostly empty unless a theme has PNG/XPM paths.

## Problem Summary

- XDG icon themes rely heavily on SVG assets.
- The engine’s image pipeline does not decode SVG, so `Image` cannot render most XDG icons.
- This blocks finishing the icon browser with real XDG data.

## Plan

1. Add SVG rasterization via `resvg` C API in the engine.
2. Expose SVG rasterization to Fennel as a binding.
3. For SVG inputs, rasterize into RGBA and cache the result on disk.
4. Use a small custom header on cached files for efficient load and validation.
5. Use the cached RGBA path in the icon browser so SVGs render without per-frame rasterization.

## Notes

- The cache should be keyed by SVG path + target size + theme to avoid collisions.
- The icon browser will then display real XDG icons consistently across themes.
