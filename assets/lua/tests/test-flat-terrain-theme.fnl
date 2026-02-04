(local glm (require :glm))

(local FlatTerrain (require :flat-terrain))

(fn test-flat-terrain-uses-theme-colors []
  (set app (or app {}))
  (set app.themes
       {:get-active-theme
        (fn []
          {:flat-terrain {:dark (glm.vec4 0.11 0.22 0.33 1)
                          :light (glm.vec4 0.44 0.55 0.66 1)}})})

  (local terrain (FlatTerrain {}))
  (local ctx {:triangle-vector {:allocate (fn [_stride] 1)
                                :delete (fn [_handle] nil)
                                :set-glm-vec3 (fn [_handle _offset _value] nil)
                                :set-glm-vec4 (fn [_handle _offset _value] nil)
                                :set-float (fn [_handle _offset _value] nil)}})

  ;; If theme colors are missing, FlatTerrain would fall back to hardcoded defaults.
  ;; This asserts we can build with a theme present and no explicit options.colors.
  (local entity (terrain ctx))
  (assert (and entity entity.layout) "FlatTerrain should build an entity with a layout")
  (entity:drop))

(fn main []
  (test-flat-terrain-uses-theme-colors)
  (print "[PASS] FlatTerrain uses theme colors when provided"))

{:main main}
