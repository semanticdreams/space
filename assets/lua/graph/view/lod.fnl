(local glm (require :glm))
(local viewport-utils (require :viewport-utils))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn clone-vec3 [value]
  (and value
       (finite-number? value.x)
       (finite-number? value.y)
       (finite-number? value.z)
       (glm.vec3 value.x value.y value.z)))

(fn clone-quat [value]
  (and value
       (finite-number? value.w)
       (finite-number? value.x)
       (finite-number? value.y)
       (finite-number? value.z)
       (glm.quat value.w value.x value.y value.z)))

(fn position-distance [a b]
  (if (and a b)
      (glm.length (- a b))
      math.huge))

(fn rotation-distance [a b]
  (if (and a b)
      (math.abs (- 1.0 (math.abs (+ (* a.w b.w)
                                    (* a.x b.x)
                                    (* a.y b.y)
                                    (* a.z b.z)))))
      math.huge))

(fn projection-threshold->lod [pixels-per-world-unit]
  ;; These thresholds roughly preserve the old scene-distance behavior while
  ;; allowing orthographic hosts to drive LOD from visible zoom.
  (if (>= pixels-per-world-unit 1.5)
      0
      (if (>= pixels-per-world-unit 0.75)
          1
          (if (>= pixels-per-world-unit 0.35)
              2
              3))))

(fn distance-threshold->lod [distance]
  (if (< distance 250.0)
      0
      (if (< distance 500.0)
          1
          (if (< distance 800.0)
              2
              3))))

(fn screen-distance [a b]
  (if (and a b)
      (math.sqrt (+ (^ (- b.x a.x) 2)
                    (^ (- b.y a.y) 2)))
      nil))

(fn GraphViewLod [opts]
  (local options (or opts {}))
  (local camera options.camera)
  (local position-epsilon (or options.position-epsilon 1e-4))
  (local rotation-epsilon (or options.rotation-epsilon 1e-4))
  (local scale-epsilon (or options.scale-epsilon 1e-6))

  (fn current-surface []
    (or (and options.surface-provider (options.surface-provider))
        options.surface))

  (fn world-units-per-pixel []
    (local surface (current-surface))
    (local value (and surface surface.world-units-per-pixel))
    (if (and (finite-number? value)
             (> value 0))
        value
        nil))

  (fn capture-view-state [_self]
    (local units (world-units-per-pixel))
    (if units
        {:mode :orthographic-scale
         :world-units-per-pixel units}
        (do
          (local surface (current-surface))
          (local viewport (and surface (viewport-utils.to-table surface.viewport)))
          (local position (clone-vec3 (and camera camera.position)))
          (local rotation (clone-quat (and camera camera.rotation)))
          {:mode :camera-projection
           :viewport-width (and viewport viewport.width)
           :viewport-height (and viewport viewport.height)
           :projection-version (and surface surface.projection-version)
           :camera-position position
           :camera-rotation rotation})))

  (fn view-state-changed? [_self previous current]
    (if (or (not previous)
            (not current)
            (not (= previous.mode current.mode)))
        true
        (if (= current.mode :orthographic-scale)
            (> (math.abs (- current.world-units-per-pixel
                            previous.world-units-per-pixel))
               scale-epsilon)
            (or (> (position-distance current.camera-position previous.camera-position)
                   position-epsilon)
                (> (rotation-distance current.camera-rotation previous.camera-rotation)
                   rotation-epsilon)
                (not (= current.projection-version previous.projection-version))
                (not (= current.viewport-width previous.viewport-width))
                (not (= current.viewport-height previous.viewport-height))))))

  (fn project-point [position]
    (local surface (current-surface))
    (local viewport (and surface (viewport-utils.to-table surface.viewport)))
    (local view (or (and surface surface.get-view-matrix
                         (surface:get-view-matrix))
                    (and camera camera.get-view-matrix
                         (camera:get-view-matrix))))
    (local projection (and surface surface.projection))
    (if (and viewport
             view
             projection
             glm.project)
        (do
          (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
          (local projected (glm.project position view projection viewport-vec))
          (if (and projected
                   (finite-number? projected.x)
                   (finite-number? projected.y))
              {:x projected.x
               :y (- (+ viewport.height viewport.y) projected.y)}
              nil))
        nil))

  (fn projected-pixels-per-world-unit [position]
    (local center (project-point position))
    (local along-x (project-point (+ position (glm.vec3 1 0 0))))
    (local along-y (project-point (+ position (glm.vec3 0 1 0))))
    (local dx (screen-distance center along-x))
    (local dy (screen-distance center along-y))
    (math.max (or dx 0) (or dy 0)))

  (fn target-for-point [_self position]
    (local units (world-units-per-pixel))
    (if units
        (projection-threshold->lod (/ 1.0 units))
        (do
          (local pixels-per-world-unit (projected-pixels-per-world-unit position))
          (if (> pixels-per-world-unit 0)
              (projection-threshold->lod pixels-per-world-unit)
              (if (and camera camera.position)
                  (distance-threshold->lod
                    (glm.length (- position camera.position)))
                  0)))))

  {:capture-view-state capture-view-state
   :view-state-changed? view-state-changed?
   :target-for-point target-for-point
   :drop (fn [_self] nil)})

GraphViewLod
