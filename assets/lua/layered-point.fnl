(local glm (require :glm))

(fn ensure-size [size]
  (or size 10.0))

(fn ensure-color [color]
  (or color (glm.vec4 1 0.2 0.2 1)))

(fn resolve-position [position]
  (if position
      (if (= (type position) :userdata)
          position
          (if (= (type position) :table)
              (glm.vec3 (or position.x (rawget position 1) 0)
                        (or position.y (rawget position 2) 0)
                        (or position.z (rawget position 3) 0))
              (if (= (type position) :number)
                  (glm.vec3 position position position)
                  (glm.vec3 0 0 0))))
      (glm.vec3 0 0 0)))

(fn offset-position [position z-offset]
  (if (and z-offset (not (= z-offset 0)))
      (glm.vec3 position.x position.y (+ position.z z-offset))
      position))

(fn LayeredPoint [opts]
  (local options (or opts {}))
  (local points (or options.points (and options.ctx options.ctx.points)))
  (assert points "LayeredPoint requires points")
  (local layers (or options.layers []))
  (assert (> (length layers) 0) "LayeredPoint requires at least one layer")
  (local base-index (or options.base-layer-index (length layers)))
  (local depth-offset-step (or options.depth-offset-step options.depth-step 1))
  (local base-depth-offset-index (or options.base-depth-offset-index 0))
  (local pointer-target options.pointer-target)
  (local base-position (resolve-position options.position))

  (fn build-layer [layer idx]
    (local resolved-size (ensure-size layer.size))
    (local resolved-color (ensure-color layer.color))
    (local depth-offset-index (or layer.depth-offset-index
                                  (+ base-depth-offset-index
                                     (* depth-offset-step (- idx base-index)))))
    (local z-offset layer.z-offset)
    (local point (points:create-point {:position (offset-position base-position z-offset)
                                       :color resolved-color
                                       :size resolved-size
                                       :depth-offset-index depth-offset-index}))
    {:point point
     :size resolved-size
     :color resolved-color
     :z-offset z-offset
     :depth-offset-index depth-offset-index})

  (local layer-records
    (icollect [idx layer (ipairs layers)]
      (build-layer layer idx)))
  (local base-layer (. layer-records base-index))
  (assert base-layer "LayeredPoint base layer is missing")
  (local self {:layers layer-records
               :base-layer-index base-index
               :position base-position
               :color base-layer.color
               :size base-layer.size
               :pointer-target pointer-target})

  (fn apply-position-values [self x y z]
    (var base self.position)
    (when (not base)
      (set base (glm.vec3 0 0 0))
      (set self.position base))
    (set base.x x)
    (set base.y y)
    (set base.z z)
    (each [_ layer (ipairs self.layers)]
      (local point layer.point)
      (local z-offset (or layer.z-offset 0))
      (local z-value (+ z z-offset))
      (if point.set-position-values
          (point:set-position-values x y z-value)
          (point:set-position (glm.vec3 x y z-value))))
    self)

  (fn apply-position [self position]
    (local resolved (resolve-position position))
    (apply-position-values self resolved.x resolved.y resolved.z))

  (set self.set-position (fn [self position]
                           (apply-position self position)))
  (set self.set-position-values
       (fn [self x y z]
         (apply-position-values self x y z)))

  (set self.set-color
       (fn [self color]
         (local resolved (ensure-color color))
         (local base (. self.layers self.base-layer-index))
         (set self.color resolved)
         (set base.color resolved)
         (base.point:set-color resolved)
         self))

  (set self.set-size
       (fn [self size]
         (local resolved (ensure-size size))
         (local base (. self.layers self.base-layer-index))
         (set self.size resolved)
         (set base.size resolved)
         (base.point:set-size resolved)
         self))

  (set self.set-layer
       (fn [self idx params]
         (local layer (. self.layers idx))
         (assert layer (string.format "LayeredPoint missing layer %d" idx))
         (local options (or params {}))
         (when options.color
           (local resolved (ensure-color options.color))
           (set layer.color resolved)
           (layer.point:set-color resolved))
         (when (not (= options.size nil))
           (local resolved (ensure-size options.size))
           (set layer.size resolved)
           (layer.point:set-size resolved))
         (when (not (= options.z-offset nil))
           (set layer.z-offset options.z-offset)
           (layer.point:set-position (offset-position self.position layer.z-offset)))
         (when (not (= options.depth-offset-index nil))
           (set layer.depth-offset-index options.depth-offset-index)
           (layer.point:set-depth-offset-index options.depth-offset-index))
         self))

  (set self.set-layer-size
       (fn [self idx size]
         (self:set-layer idx {:size size})))
  (set self.set-layer-color
       (fn [self idx color]
         (self:set-layer idx {:color color})))
  (set self.set-layer-depth-offset-index
       (fn [self idx depth-offset-index]
         (self:set-layer idx {:depth-offset-index depth-offset-index})))

  (set self.intersect (fn [_self ray]
                        (base-layer.point:intersect ray)))

  (set self.drop
       (fn [_self]
         (each [_ layer (ipairs layer-records)]
           (layer.point:drop))))

  self)

LayeredPoint
