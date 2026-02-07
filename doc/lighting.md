**Lighting**
The runtime lighting stack is driven by `LightSystem` instances and consumed by mesh/triangle renderers via `app.lights`. Themes provide defaults, but the lighting system is independent of any theme, and you can add lights at runtime.

**Quick Start**
```fnl
(local LightSystem (require :light-system))
(local glm (require :glm))

;; Create a light system and install it.
(set app.lights
     (LightSystem {:active {:ambient (glm.vec3 0.2 0.2 0.2)
                            :directional [{:direction (glm.normalize (glm.vec3 0.4 1.0 0.2))
                                           :ambient (glm.vec3 0.1 0.1 0.1)
                                           :diffuse (glm.vec3 0.7 0.7 0.7)
                                           :specular (glm.vec3 1.0 1.0 1.0)}]
                            :point []
                            :spot []}}))
```

**Theme Defaults**
Themes expose default lighting under `:lights` (see `assets/lua/light-theme.fnl` and `assets/lua/dark-theme.fnl`). The theme values are used only when a `LightSystem` is created with `:defaults`. Example:
```fnl
(local LightSystem (require :light-system))
(local theme (require :light-theme))

(local lights
  (LightSystem {:defaults (:lights (theme))
                :active {:ambient (glm.vec3 0.1 0.1 0.1)}}))
```
You can ignore theme defaults entirely and build the light system yourself.

**Runtime Updates**
`LightSystem` exposes setters and `add-*` methods so you can add lights later (e.g. UI-driven changes):
```fnl
(app.lights:add-directional {:direction (glm.normalize (glm.vec3 -0.8 0.5 0.2))
                             :ambient (glm.vec3 0.0 0.0 0.0)
                             :diffuse (glm.vec3 0.6 0.7 0.9)
                             :specular (glm.vec3 0.8 0.9 1.0)})

(app.lights:add-point {:position (glm.vec3 4 6 -8)
                       :ambient (glm.vec3 0 0 0)
                       :diffuse (glm.vec3 1.2 1.0 0.8)
                       :specular (glm.vec3 1.0 0.9 0.8)
                       :constant 1.0
                       :linear 0.03
                       :quadratic 0.002})
```

**Light Types**
- `ambient` (vec3): Scene-wide base illumination.
- `directional`: Infinite light, direction must be non-zero.
- `point`: Local light with attenuation (`constant`, `linear`, `quadratic`).
- `spot`: Point light with direction + cone cutoff. `:cutoff` and `:outer-cutoff`
  are cosine values (use `(math.cos (math.rad degrees))`).

Lights can be disabled by setting `:enabled? false`. Disabled lights are ignored by renderers.

**Limits**
Renderers enforce max counts to match shader arrays:
- Directional: 4
- Point: 8
- Spot: 4

Exceeding these limits throws an assertion in `LightUtils.apply-lights`.

**Where Lights Are Consumed**
Both mesh and triangle renderers require `app.lights` to be set; they assert if missing.
If you’re building a new app entry point or test harness, make sure lighting is initialized
before rendering.
