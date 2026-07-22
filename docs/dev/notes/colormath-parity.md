---
type: dev-note
tags:
  - note
---

# Colormath Parity (C++/sol2/Lua)

This note documents the C++/sol2 implementation that provides feature parity with
`assets/python/lib/colormath` while exposing a Lua-first API through `(require :colors)`.

## Goals

- Keep the canonical runtime in C++ + Lua.
- Provide all colormath capabilities as callable Lua functions.
- Prefer explicit hyphen-case function names over Python class mirroring.

## Implementation Overview

Primary files:

- `src/colors.h`
- `src/colors.cpp`
- `src/lua_colors.cpp`
- `assets/lua/tests/test-colors.fnl`

### Module Mapping

`color_conversions.py`

- RGB/XYZ/Lab/LCHab/Luv/LCHuv/xyY/HSV/HSL/CMY/CMYK/IPT conversions.
- Generic conversion entrypoint: `convert-color`.
- Conversion graph utilities: `conversion-path`, `can-convert`.

`chromatic_adaptation.py`

- Illuminant adaptation via `adapt-xyz`.
- Adaptation methods: Bradford, Von Kries, XYZ scaling.

`color_diff.py` + `color_diff_matrix.py`

- Scalar Delta E: `delta-e-cie1976`, `delta-e-cie1994`, `delta-e-cie2000`, `delta-e-cmc`.
- Matrix Delta E: `delta-e-cie1976-matrix`, `delta-e-cie1994-matrix`,
  `delta-e-cie2000-matrix`, `delta-e-cmc-matrix`.

`spectral_constants.py` + `density_standards.py` + `density.py`

- Spectral -> XYZ: `spectral-to-xyz`.
- ANSI/auto density: `ansi-density`, `auto-density`.
- Spectral and density tables are embedded in generated C++ data
  (`src/colormath_data_generated.h`) so runtime no longer depends on legacy
  Python colormath sources.

`color_appearance_models.py`

- Implemented appearance model entry points:
  - `model-nayatani95`
  - `model-hunt`
  - `model-rlab`
  - `model-atd95`
  - `model-llab`
  - `model-ciecam02`
  - `model-ciecam02m1`

`color_objects.py` (feature-equivalent utilities)

- RGB helper equivalents:
  - `rgb-to-upscaled`
  - `rgb-to-hex`
  - `rgb-from-hex`
  - `clamp-rgb`
- Observer/illuminant-aware conversions:
  - `xyz-to-lab`/`lab-to-xyz` with optional `(observer, illuminant)`
  - `xyz-to-luv`/`luv-to-xyz` with optional `(observer, illuminant)`
- Illuminant lookup: `get-illuminant`.

## Lua API Usage

```fennel
(local colors (require :colors))
(local glm (require :glm))

;; generic conversion
(local lab (colors.convert-color (glm.vec4 0.3 0.6 0.2 0) "rgb" "lab"))

;; explicit illuminant/observer for Lab
(local xyz (glm.vec3 42 50 39))
(local lab-d50 (colors.xyz-to-lab xyz "2" "d50"))
(local xyz-back (colors.lab-to-xyz lab-d50 "2" "d50"))

;; chromatic adaptation
(local xyz-d50 (colors.adapt-xyz xyz "d65" "d50" "2" "bradford"))

;; delta-e matrix
(local base (glm.vec3 50 2.6 -79.7))
(local candidates [(glm.vec3 50 2.6 -79.7) (glm.vec3 50 0 -82.7)])
(local delta-list (colors.delta-e-cie2000-matrix base candidates))

;; spectral + density
(local spectral [])
(for [i 1 50]
  (table.insert spectral (+ 35 (* i 0.5))))
(local xyz-from-spectral (colors.spectral-to-xyz spectral "2" "d65"))
(local density (colors.auto-density spectral))

;; appearance model
(local cam (colors.model-ciecam02 19.01 20.0 21.78 95.05 100.0 108.88 20.0 318.31 0.69 1.0 1.0 false))
```

## Validation

Focused parity tests live in `assets/lua/tests/test-colors.fnl` and cover:

- swatch generation
- roundtrips across all implemented spaces
- illuminant adaptation
- scalar + matrix delta-e
- spectral conversion + density
- generic conversion graph and helpers
- appearance model outputs

Run:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-colors:main
```

## Notes

- The public API intentionally uses functional entry points rather than Python class objects.
- This keeps bindings simple while preserving capability parity.


## See also

- [Cross Platform](/dev/subsystems/cross-platform)
