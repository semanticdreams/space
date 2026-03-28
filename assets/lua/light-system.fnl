(local glm (require :glm))
(local MathUtils (require :math-utils))

(local vec3->array (. MathUtils :vec3->array))

(local MAX_AMBIENT_LIGHTS 1)
(local MAX_DIR_LIGHTS 4)
(local MAX_POINT_LIGHTS 8)
(local MAX_SPOT_LIGHTS 4)
(local SERIALIZED_DECIMAL_PLACES 6)
(local SERIALIZED_DECIMAL_FACTOR (^ 10 SERIALIZED_DECIMAL_PLACES))

(local light-type-specs
  [{:key "ambient"
    :label "ambient"
    :plural-label "ambient"
    :max-count MAX_AMBIENT_LIGHTS}
   {:key "directional"
    :label "directional"
    :plural-label "directional"
    :max-count MAX_DIR_LIGHTS}
   {:key "point"
    :label "point"
    :plural-label "points"
    :max-count MAX_POINT_LIGHTS}
   {:key "spot"
    :label "spot"
    :plural-label "spots"
    :max-count MAX_SPOT_LIGHTS}])

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn list-type-specs []
  (icollect [_ spec (ipairs light-type-specs)]
    (clone-table spec)))

(fn type-spec [type-key]
  (var resolved nil)
  (each [_ spec (ipairs light-type-specs)]
    (when (and (not resolved) (= spec.key type-key))
      (set resolved spec)))
  resolved)

(fn max-count-for-type [type-key]
  (local spec (type-spec type-key))
  (and spec (. spec :max-count)))

(fn light-enabled? [light]
  (if (= (type light) :table)
      (not (= light.enabled? false))
      true))

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

(fn generated-id [type-key idx]
  (if (= type-key "ambient")
      "ambient"
      (.. type-key "-" (tostring idx))))

(fn round-serialized-number [value]
  (if (not (= (type value) :number))
      value
      (do
        (local scaled (* value SERIALIZED_DECIMAL_FACTOR))
        (local rounded
          (/ (if (>= scaled 0)
                 (math.floor (+ scaled 0.5))
                 (math.ceil (- scaled 0.5)))
             SERIALIZED_DECIMAL_FACTOR))
        (if (< (math.abs rounded) (/ 1 SERIALIZED_DECIMAL_FACTOR))
            0
            rounded))))

(fn serialize-number [value]
  (and value (round-serialized-number value)))

(fn serialize-vec3 [value]
  (and value
       (icollect [_ component (ipairs (vec3->array value))]
         (round-serialized-number component))))

(local default-light-direction
  (glm.normalize (- (glm.vec3 200 200 200)
                    (glm.vec3 0 -100 0))))

(local default-ambient
  {:id "ambient"
   :color (glm.vec3 0 0 0)
   :enabled? true})

(local default-directional
  {:direction default-light-direction
   :ambient (glm.vec3 0.4 0.4 0.4)
   :diffuse (glm.vec3 0.6 0.6 0.6)
   :specular (glm.vec3 1.0 1.0 1.0)
   :specular-power 8.0
   :enabled? true})

(local default-point
  {:position (glm.vec3 0 0 0)
   :ambient (glm.vec3 0.0 0.0 0.0)
   :diffuse (glm.vec3 1.0 1.0 1.0)
   :specular (glm.vec3 1.0 1.0 1.0)
   :specular-power 8.0
   :constant 1.0
   :linear 0.09
   :quadratic 0.032
   :enabled? true})

(local default-spot
  {:position (glm.vec3 0 0 0)
   :direction (glm.vec3 0 0 -1)
   :ambient (glm.vec3 0.0 0.0 0.0)
   :diffuse (glm.vec3 1.0 1.0 1.0)
   :specular (glm.vec3 1.0 1.0 1.0)
   :specular-power 8.0
   :cutoff (math.cos (math.rad 12.5))
   :outer-cutoff (math.cos (math.rad 17.5))
   :constant 1.0
   :linear 0.09
   :quadratic 0.032
   :enabled? true})

(fn normalize-ambient-record [light defaults]
  (local raw (or light {}))
  (local fallback (or defaults default-ambient))
  (local color-source
    (if (= (type raw) :table)
        (if (or raw.color
                raw.ambient
                raw.id
                (not (= raw.enabled? nil)))
            (or raw.color raw.ambient)
            (if (> (length raw) 0)
                raw
                nil))
        raw))
  {:id (tostring (or (and (= (type raw) :table) raw.id)
                     fallback.id
                     "ambient"))
   :color (ensure-vec3 (or color-source fallback.color fallback.ambient)
                       "Ambient light color")
   :enabled? (if (= (and (= (type raw) :table) raw.enabled?) nil)
                  (light-enabled? fallback)
                  (light-enabled? raw))})

(fn normalize-directional [light defaults idx]
  (local base (or light {}))
  (local fallback (or defaults default-directional))
  {:id (tostring (or base.id fallback.id (generated-id "directional" idx)))
   :direction (normalize-direction (or base.direction fallback.direction)
                                   "Directional light direction")
   :ambient (ensure-vec3 (or base.ambient fallback.ambient)
                         "Directional light ambient")
   :diffuse (ensure-vec3 (or base.diffuse fallback.diffuse)
                         "Directional light diffuse")
   :specular (ensure-vec3 (or base.specular fallback.specular)
                          "Directional light specular")
   :specular-power (ensure-number (or base.specular-power fallback.specular-power)
                                  "Directional light specular power")
   :enabled? (if (= base.enabled? nil)
                  (light-enabled? fallback)
                  (light-enabled? base))})

(fn normalize-point [light defaults idx]
  (local base (or light {}))
  (local fallback (or defaults default-point))
  {:id (tostring (or base.id fallback.id (generated-id "point" idx)))
   :position (ensure-vec3 (or base.position fallback.position)
                          "Point light position")
   :ambient (ensure-vec3 (or base.ambient fallback.ambient)
                         "Point light ambient")
   :diffuse (ensure-vec3 (or base.diffuse fallback.diffuse)
                         "Point light diffuse")
   :specular (ensure-vec3 (or base.specular fallback.specular)
                          "Point light specular")
   :specular-power (ensure-number (or base.specular-power fallback.specular-power)
                                  "Point light specular power")
   :constant (ensure-number (or base.constant fallback.constant)
                            "Point light constant attenuation")
   :linear (ensure-number (or base.linear fallback.linear)
                          "Point light linear attenuation")
   :quadratic (ensure-number (or base.quadratic fallback.quadratic)
                             "Point light quadratic attenuation")
   :enabled? (if (= base.enabled? nil)
                  (light-enabled? fallback)
                  (light-enabled? base))})

(fn normalize-spot [light defaults idx]
  (local base (or light {}))
  (local fallback (or defaults default-spot))
  (local cutoff (ensure-number (or base.cutoff fallback.cutoff)
                               "Spot light cutoff"))
  (local outer-cutoff (ensure-number (or (. base :outer-cutoff) (. fallback :outer-cutoff))
                                     "Spot light outer cutoff"))
  (assert (> cutoff outer-cutoff)
          "Spot light cutoff must be greater than outer cutoff")
  {:id (tostring (or base.id fallback.id (generated-id "spot" idx)))
   :position (ensure-vec3 (or base.position fallback.position)
                          "Spot light position")
   :direction (normalize-direction (or base.direction fallback.direction)
                                   "Spot light direction")
   :ambient (ensure-vec3 (or base.ambient fallback.ambient)
                         "Spot light ambient")
   :diffuse (ensure-vec3 (or base.diffuse fallback.diffuse)
                         "Spot light diffuse")
   :specular (ensure-vec3 (or base.specular fallback.specular)
                          "Spot light specular")
   :specular-power (ensure-number (or base.specular-power fallback.specular-power)
                                  "Spot light specular power")
   :cutoff cutoff
   :outer-cutoff outer-cutoff
   :constant (ensure-number (or base.constant fallback.constant)
                            "Spot light constant attenuation")
   :linear (ensure-number (or base.linear fallback.linear)
                          "Spot light linear attenuation")
   :quadratic (ensure-number (or base.quadratic fallback.quadratic)
                             "Spot light quadratic attenuation")
   :enabled? (if (= base.enabled? nil)
                  (light-enabled? fallback)
                  (light-enabled? base))})

(fn serialize-ambient-record [record]
  {:id (or record.id "ambient")
   :color (serialize-vec3 record.color)
   :enabled? (light-enabled? record)})

(fn serialize-directional-record [record]
  {:id record.id
   :direction (serialize-vec3 record.direction)
   :ambient (serialize-vec3 record.ambient)
   :diffuse (serialize-vec3 record.diffuse)
   :specular (serialize-vec3 record.specular)
   :specular-power (serialize-number record.specular-power)
   :enabled? (light-enabled? record)})

(fn serialize-point-record [record]
  {:id record.id
   :position (serialize-vec3 record.position)
   :ambient (serialize-vec3 record.ambient)
   :diffuse (serialize-vec3 record.diffuse)
   :specular (serialize-vec3 record.specular)
   :specular-power (serialize-number record.specular-power)
   :constant (serialize-number record.constant)
   :linear (serialize-number record.linear)
   :quadratic (serialize-number record.quadratic)
   :enabled? (light-enabled? record)})

(fn serialize-spot-record [record]
  {:id record.id
   :position (serialize-vec3 record.position)
   :direction (serialize-vec3 record.direction)
   :ambient (serialize-vec3 record.ambient)
   :diffuse (serialize-vec3 record.diffuse)
   :specular (serialize-vec3 record.specular)
   :specular-power (serialize-number record.specular-power)
   :cutoff (serialize-number record.cutoff)
   :outer-cutoff (serialize-number record.outer-cutoff)
   :constant (serialize-number record.constant)
   :linear (serialize-number record.linear)
   :quadratic (serialize-number record.quadratic)
   :enabled? (light-enabled? record)})

(fn normalize-list [items type-key normalizer defaults]
  (local out [])
  (when items
    (each [idx item (ipairs items)]
      (table.insert out (normalizer item defaults idx))))
  (local max-count (max-count-for-type type-key))
  (assert (or (not max-count) (<= (length out) max-count))
          (.. "Too many " type-key " lights (" (tostring (length out))
              " > " (tostring max-count) ")"))
  out)

(fn serialize-list [items serializer]
  (icollect [_ item (ipairs (or items []))]
    (serializer item)))

(fn filter-enabled [items]
  (local out [])
  (each [_ item (ipairs (or items []))]
    (when (light-enabled? item)
      (table.insert out item)))
  out)

(fn state-count [state type-key]
  (if (= type-key "ambient")
      (if (and state state.ambient) 1 0)
      (length (or (and state (. state type-key)) []))))

(fn pick-list-default [items idx fallback]
  (if (and (= (type items) :table) (> (length items) 0))
      (or (. items idx) (. items 1) fallback)
      fallback))

(fn normalize-state [state opts]
  (local options (or opts {}))
  (local active (or state {}))
  (local defaults (or options.defaults {}))
  (local fill-missing-lists?
    (if (= options.fill-missing-lists? nil)
        false
        (not (not options.fill-missing-lists?))))
  (local ambient
    (normalize-ambient-record (or active.ambient defaults.ambient default-ambient)
                              default-ambient))
  (local directional-source
    (if (not (= active.directional nil))
        active.directional
        (if fill-missing-lists?
            (or defaults.directional [default-directional])
            [])))
  (local point-source
    (if (not (= active.point nil))
        active.point
        (if fill-missing-lists?
            (or defaults.point [])
            [])))
  (local spot-source
    (if (not (= active.spot nil))
        active.spot
        (if fill-missing-lists?
            (or defaults.spot [])
            [])))
  (local directional
    (normalize-list directional-source
                    "directional"
                    normalize-directional
                    (pick-list-default defaults.directional 1 default-directional)))
  (local point
    (normalize-list point-source
                    "point"
                    normalize-point
                    (pick-list-default defaults.point 1 default-point)))
  (local spot
    (normalize-list spot-source
                    "spot"
                    normalize-spot
                    (pick-list-default defaults.spot 1 default-spot)))
  {:ambient (serialize-ambient-record ambient)
   :directional (serialize-list directional serialize-directional-record)
   :point (serialize-list point serialize-point-record)
   :spot (serialize-list spot serialize-spot-record)})

(fn default-state [defaults]
  (normalize-state nil {:defaults defaults
                        :fill-missing-lists? true}))

(fn default-record-for-type [type-key opts]
  (local options (or opts {}))
  (local id (or options.id (generated-id type-key (or options.index 1))))
  (local defaults (or options.defaults {}))
  (if (= type-key "ambient")
      (serialize-ambient-record
        (normalize-ambient-record {:id id}
                                  (or defaults.ambient default-ambient)))
      (= type-key "directional")
      (serialize-directional-record
        (normalize-directional {:id id}
                               (pick-list-default defaults.directional
                                                  (or options.index 1)
                                                  default-directional)
                               (or options.index 1)))
      (= type-key "point")
      (serialize-point-record
        (normalize-point {:id id}
                         (pick-list-default defaults.point
                                            (or options.index 1)
                                            default-point)
                         (or options.index 1)))
      (= type-key "spot")
      (serialize-spot-record
        (normalize-spot {:id id}
                        (pick-list-default defaults.spot
                                           (or options.index 1)
                                           default-spot)
                        (or options.index 1)))
      (error (.. "Unknown light type " (tostring type-key)))))

(fn require-complete-state [state context]
  (local label (or context "Light state"))
  (assert (= (type state) :table) (.. label " requires table state"))
  (assert (= (type state.ambient) :table) (.. label " requires :ambient table"))
  (assert (= (type state.directional) :table) (.. label " requires :directional table"))
  (assert (= (type state.point) :table) (.. label " requires :point table"))
  (assert (= (type state.spot) :table) (.. label " requires :spot table"))
  state)

(fn normalize-complete-state [state context]
  (normalize-state
    (require-complete-state state context)))

(fn LightSystem [opts]
  (local options (or opts {}))
  (local defaults (or options.defaults {}))
  (var ambient-record nil)
  (var directional [])
  (var point [])
  (var spot [])

  (fn apply-normalized-state [normalized]
    (set ambient-record
         (normalize-ambient-record normalized.ambient default-ambient))
    (set directional
         (normalize-list normalized.directional
                         "directional"
                         normalize-directional
                         default-directional))
    (set point
         (normalize-list normalized.point
                         "point"
                         normalize-point
                         default-point))
    (set spot
         (normalize-list normalized.spot
                         "spot"
                         normalize-spot
                         default-spot))
    {:ambient (serialize-ambient-record ambient-record)
     :directional (serialize-list directional serialize-directional-record)
     :point (serialize-list point serialize-point-record)
     :spot (serialize-list spot serialize-spot-record)})

  (fn get-state [_self]
    {:ambient (serialize-ambient-record ambient-record)
     :directional (serialize-list directional serialize-directional-record)
     :point (serialize-list point serialize-point-record)
     :spot (serialize-list spot serialize-spot-record)})

  (fn set-state [_self state]
    (local normalized
      (normalize-complete-state state "LightSystem.set-state"))
    (apply-normalized-state normalized))

  (fn get-ambient [_self]
    (if (light-enabled? ambient-record)
        ambient-record.color
        (glm.vec3 0 0 0)))

  (fn set-ambient [_self value]
    (set ambient-record (normalize-ambient-record value ambient-record))
    ambient-record)

  (fn get-directional [_self]
    (filter-enabled directional))

  (fn get-point [_self]
    (filter-enabled point))

  (fn get-spot [_self]
    (filter-enabled spot))

  (fn set-directional [_self items]
    (set directional (normalize-list items "directional" normalize-directional default-directional))
    directional)

  (fn set-point [_self items]
    (set point (normalize-list items "point" normalize-point default-point))
    point)

  (fn set-spot [_self items]
    (set spot (normalize-list items "spot" normalize-spot default-spot))
    spot)

  (fn add-directional [_self light]
    (assert (< (length directional) MAX_DIR_LIGHTS)
            (.. "Cannot add more than " (tostring MAX_DIR_LIGHTS) " directional lights"))
    (table.insert directional
                  (normalize-directional light default-directional (+ (length directional) 1)))
    (. directional (length directional)))

  (fn add-point [_self light]
    (assert (< (length point) MAX_POINT_LIGHTS)
            (.. "Cannot add more than " (tostring MAX_POINT_LIGHTS) " point lights"))
    (table.insert point
                  (normalize-point light default-point (+ (length point) 1)))
    (. point (length point)))

  (fn add-spot [_self light]
    (assert (< (length spot) MAX_SPOT_LIGHTS)
            (.. "Cannot add more than " (tostring MAX_SPOT_LIGHTS) " spot lights"))
    (table.insert spot
                  (normalize-spot light default-spot (+ (length spot) 1)))
    (. spot (length spot)))

  (fn clear [_self]
    (apply-normalized-state (default-state defaults)))

  (apply-normalized-state
    (if (= options.active nil)
        (default-state defaults)
        (normalize-complete-state options.active "LightSystem")))

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
   :get-state get-state
   :set-state set-state
   :clear clear
   :defaults defaults
   :max-ambient-lights MAX_AMBIENT_LIGHTS
   :max-dir-lights MAX_DIR_LIGHTS
   :max-point-lights MAX_POINT_LIGHTS
   :max-spot-lights MAX_SPOT_LIGHTS})

{:LightSystem LightSystem
 :list-type-specs list-type-specs
 :type-spec type-spec
 :max-count-for-type max-count-for-type
 :normalize-state normalize-state
 :normalize-complete-state normalize-complete-state
 :default-state default-state
 :default-record-for-type default-record-for-type
 :state-count state-count}
