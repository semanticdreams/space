(local glm (require :glm))

(local MAX_DIR_LIGHTS 4)
(local MAX_POINT_LIGHTS 8)
(local MAX_SPOT_LIGHTS 4)

(local default-light-direction
  (glm.normalize (- (glm.vec3 200 200 200)
                    (glm.vec3 0 -100 0))))

(local default-directional
  {:direction default-light-direction
   :ambient (glm.vec3 0.4 0.4 0.4)
   :diffuse (glm.vec3 0.6 0.6 0.6)
   :specular (glm.vec3 1.0 1.0 1.0)})

(local default-point
  {:position (glm.vec3 0 0 0)
   :ambient (glm.vec3 0.0 0.0 0.0)
   :diffuse (glm.vec3 1.0 1.0 1.0)
   :specular (glm.vec3 1.0 1.0 1.0)
   :constant 1.0
   :linear 0.09
   :quadratic 0.032})

(local default-spot
  {:position (glm.vec3 0 0 0)
   :direction (glm.vec3 0 0 -1)
   :ambient (glm.vec3 0.0 0.0 0.0)
   :diffuse (glm.vec3 1.0 1.0 1.0)
   :specular (glm.vec3 1.0 1.0 1.0)
   :cutoff (math.cos (math.rad 12.5))
   :outer-cutoff (math.cos (math.rad 17.5))
   :constant 1.0
   :linear 0.09
   :quadratic 0.032})

(fn ensure-vec3 [value label]
  (assert (not (= value nil)) (.. label " is required"))
  (if (= (type value) :userdata)
      value
      (if (= (type value) :number)
          (glm.vec3 value value value)
          (if (= (type value) :table)
              (do
                (local x (or (. value 1) value.x))
                (local y (or (. value 2) value.y))
                (local z (or (. value 3) value.z))
                (assert (and x y z) (.. label " must provide x y z values"))
                (glm.vec3 x y z))
              (error (.. label " must be a glm.vec3 or 3-number table"))))))

(fn ensure-number [value label]
  (assert (not (= value nil)) (.. label " is required"))
  (assert (= (type value) :number) (.. label " must be a number"))
  value)

(fn normalize-direction [value label]
  (local dir (ensure-vec3 value label))
  (assert (> (glm.length dir) 1e-6) (.. label " must be non-zero"))
  (glm.normalize dir))

(fn normalize-directional [light defaults]
  (local base (or light {}))
  (local fallback (or defaults default-directional))
  {:direction (normalize-direction (or base.direction fallback.direction)
                                   "Directional light direction")
   :ambient (ensure-vec3 (or base.ambient fallback.ambient)
                         "Directional light ambient")
   :diffuse (ensure-vec3 (or base.diffuse fallback.diffuse)
                         "Directional light diffuse")
   :specular (ensure-vec3 (or base.specular fallback.specular)
                          "Directional light specular")
   :enabled? (not (= base.enabled? false))})

(fn normalize-point [light defaults]
  (local base (or light {}))
  (local fallback (or defaults default-point))
  {:position (ensure-vec3 (or base.position fallback.position)
                          "Point light position")
   :ambient (ensure-vec3 (or base.ambient fallback.ambient)
                         "Point light ambient")
   :diffuse (ensure-vec3 (or base.diffuse fallback.diffuse)
                         "Point light diffuse")
   :specular (ensure-vec3 (or base.specular fallback.specular)
                          "Point light specular")
   :constant (ensure-number (or base.constant fallback.constant)
                            "Point light constant attenuation")
   :linear (ensure-number (or base.linear fallback.linear)
                          "Point light linear attenuation")
   :quadratic (ensure-number (or base.quadratic fallback.quadratic)
                             "Point light quadratic attenuation")
   :enabled? (not (= base.enabled? false))})

(fn normalize-spot [light defaults]
  (local base (or light {}))
  (local fallback (or defaults default-spot))
  (local cutoff (ensure-number (or base.cutoff fallback.cutoff)
                               "Spot light cutoff"))
  (local outer-cutoff (ensure-number (or (. base :outer-cutoff) (. fallback :outer-cutoff))
                                     "Spot light outer cutoff"))
  (assert (> cutoff outer-cutoff)
          "Spot light cutoff must be greater than outer cutoff")
  {:position (ensure-vec3 (or base.position fallback.position)
                          "Spot light position")
   :direction (normalize-direction (or base.direction fallback.direction)
                                   "Spot light direction")
   :ambient (ensure-vec3 (or base.ambient fallback.ambient)
                         "Spot light ambient")
   :diffuse (ensure-vec3 (or base.diffuse fallback.diffuse)
                         "Spot light diffuse")
   :specular (ensure-vec3 (or base.specular fallback.specular)
                          "Spot light specular")
   :cutoff cutoff
   :outer-cutoff outer-cutoff
   :constant (ensure-number (or base.constant fallback.constant)
                            "Spot light constant attenuation")
   :linear (ensure-number (or base.linear fallback.linear)
                          "Spot light linear attenuation")
   :quadratic (ensure-number (or base.quadratic fallback.quadratic)
                             "Spot light quadratic attenuation")
   :enabled? (not (= base.enabled? false))})

(fn normalize-list [items normalizer defaults]
  (local out [])
  (when items
    (each [_ item (ipairs items)]
      (table.insert out (normalizer item defaults))))
  out)

(fn filter-enabled [items]
  (local out [])
  (each [_ item (ipairs items)]
    (when (not (= item.enabled? false))
      (table.insert out item)))
  out)

(fn LightSystem [opts]
  (local options (or opts {}))
  (local defaults (or options.defaults {}))
  (local active (or options.active {}))

  (var ambient
    (ensure-vec3 (or active.ambient defaults.ambient (glm.vec3 0 0 0))
                 "Ambient light"))

  (var directional
    (normalize-list (or active.directional defaults.directional [default-directional])
                    normalize-directional
                    default-directional))
  (var point
    (normalize-list (or active.point defaults.point [])
                    normalize-point
                    default-point))
  (var spot
    (normalize-list (or active.spot defaults.spot [])
                    normalize-spot
                    default-spot))

  (fn get-ambient []
    ambient)

  (fn set-ambient [value]
    (set ambient (ensure-vec3 value "Ambient light"))
    ambient)

  (fn get-directional []
    (filter-enabled directional))

  (fn get-point []
    (filter-enabled point))

  (fn get-spot []
    (filter-enabled spot))

  (fn set-directional [items]
    (set directional (normalize-list items normalize-directional default-directional))
    directional)

  (fn set-point [items]
    (set point (normalize-list items normalize-point default-point))
    point)

  (fn set-spot [items]
    (set spot (normalize-list items normalize-spot default-spot))
    spot)

  (fn add-directional [light]
    (table.insert directional (normalize-directional light default-directional))
    light)

  (fn add-point [light]
    (table.insert point (normalize-point light default-point))
    light)

  (fn add-spot [light]
    (table.insert spot (normalize-spot light default-spot))
    light)

  (fn clear []
    (set directional [])
    (set point [])
    (set spot [])
    (set ambient (glm.vec3 0 0 0)))

  {:get-ambient get-ambient
   :set-ambient set-ambient
   :get-directional get-directional
   :get-point get-point
   :get-spot get-spot
   :set-directional set-directional
   :set-point set-point
   :set-spot set-spot
   :add-directional add-directional
   :add-point add-point
   :add-spot add-spot
   :clear clear
   :defaults defaults
   :max-dir-lights MAX_DIR_LIGHTS
   :max-point-lights MAX_POINT_LIGHTS
   :max-spot-lights MAX_SPOT_LIGHTS})

LightSystem
