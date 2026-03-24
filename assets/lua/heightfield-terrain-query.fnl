(local glm (require :glm))
(local {:intersect-triangle intersect-triangle} (require :ray-triangle))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainGrid (require :heightfield-terrain-grid))
(local MathUtils (require :math-utils))
(local viewport-utils (require :viewport-utils))

(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(local M {})

(local ray-axis-epsilon 1e-6)

(fn resolve-position [record]
  (array->vec3 (or (and record record.options record.options.position) [0 0 0])))

(fn resolve-rotation [record]
  (array->quat (or (and record record.options record.options.rotation) [1 0 0 0])))

(local spacing HeightfieldTerrainGrid.spacing)
(local chunk-samples HeightfieldTerrainGrid.chunk-samples)
(local integer-field HeightfieldTerrainGrid.integer-field)
(local chunk-key HeightfieldTerrainGrid.chunk-key)
(local build-chunk-map HeightfieldTerrainGrid.build-chunk-map)
(local sample-height-global HeightfieldTerrainGrid.sample-height-global)
(local sample-local-point HeightfieldTerrainGrid.sample-local-point)

(fn chunk-height [chunk sample-x sample-z]
  (local size (or chunk.size [17 17]))
  (local width (or (. size 1) size.x 17))
  (local idx (+ (* sample-z width) sample-x 1))
  (or (. chunk.heights idx) 0.0))

(fn chunk-size [chunk]
  (local size (or chunk.size [17 17]))
  [(integer-field (or (. size 1) size.x 17) 17)
   (integer-field (or (. size 2) size.y size.z 17) 17)])

(fn floor-div [value divisor]
  (math.floor (/ value divisor)))

(fn canonical-local-point [record chunk sample-x sample-z]
  (local coord (or chunk.coord [0 0]))
  (local chunk-x (integer-field (or (. coord 1) coord.x 0) 0))
  (local chunk-z (integer-field (or (. coord 2) coord.y coord.z 0) 0))
  (local sample-counts (chunk-samples record))
  (local sample-width (. sample-counts 1))
  (local sample-depth (. sample-counts 2))
  (local sample-spacing (spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (glm.vec3 (+ (* chunk-x (- sample-width 1) spacing-x)
               (* sample-x spacing-x))
            (chunk-height chunk sample-x sample-z)
            (+ (* chunk-z (- sample-depth 1) spacing-z)
               (* sample-z spacing-z))))

(fn local->world [record local-point]
  (local rotation (resolve-rotation record))
  (+ (resolve-position record)
     (rotation:rotate local-point)))

(fn world->local [record world-point]
  (local rotation (resolve-rotation record))
  (local inverse (rotation:inverse))
  (inverse:rotate (- world-point (resolve-position record))))

(fn nearest-sample-coord [record local-point]
  (local sample-spacing (spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local sample-x
    (math.max bounds.min-sample-x
              (math.min bounds.max-sample-x
                        (math.floor (+ (/ local-point.x spacing-x) 0.5)))))
  (local sample-z
    (math.max bounds.min-sample-z
              (math.min bounds.max-sample-z
                        (math.floor (+ (/ local-point.z spacing-z) 0.5)))))
  {:x sample-x
   :z sample-z})

(fn sample-target [record local-point]
  (local coord (nearest-sample-coord record local-point))
  (HeightfieldTerrainData.rectangular-sample-target record
    {:x0 coord.x
     :z0 coord.z
     :x1 coord.x
     :z1 coord.z}))

(fn covered-sample-range [min-local-value max-local-value spacing bounds-min bounds-max]
  (local epsilon 1e-6)
  (local min-sample
    (math.max bounds-min
              (math.ceil (/ (- min-local-value epsilon) spacing))))
  (local max-sample
    (math.min bounds-max
              (math.floor (/ (+ max-local-value epsilon) spacing))))
  (if (> min-sample max-sample)
      nil
      {:min min-sample
       :max max-sample}))

(fn local-plane-hit [record ray]
  (local rotation (resolve-rotation record))
  (local inverse (rotation:inverse))
  (local local-origin (world->local record ray.origin))
  (local local-direction (inverse:rotate ray.direction))
  (local dir-y local-direction.y)
  (if (< (math.abs dir-y) 1e-6)
      nil
      (let [distance (/ (- local-origin.y) dir-y)]
        (if (< distance 0)
            nil
            (+ local-origin (* local-direction distance))))))

(fn local-point-inside-bounds? [record local-point]
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local sample-spacing (spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (local min-x (* bounds.min-sample-x spacing-x))
  (local max-x (* bounds.max-sample-x spacing-x))
  (local min-z (* bounds.min-sample-z spacing-z))
  (local max-z (* bounds.max-sample-z spacing-z))
  (and (>= local-point.x (- min-x 1e-6))
       (<= local-point.x (+ max-x 1e-6))
       (>= local-point.z (- min-z 1e-6))
       (<= local-point.z (+ max-z 1e-6))))

(fn make-domain-hit [record local-point ray]
  (local world-point (local->world record local-point))
  {:distance (glm.length (- world-point ray.origin))
   :world-point world-point
   :local-point local-point
   :sample (nearest-sample-coord record local-point)
   :target (sample-target record local-point)})

(fn rect-target-between-local-points [record start-local-point end-local-point]
  (local sample-spacing (spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local min-local-x (math.min start-local-point.x end-local-point.x))
  (local max-local-x (math.max start-local-point.x end-local-point.x))
  (local min-local-z (math.min start-local-point.z end-local-point.z))
  (local max-local-z (math.max start-local-point.z end-local-point.z))
  (local x-range
    (covered-sample-range min-local-x
                          max-local-x
                          spacing-x
                          bounds.min-sample-x
                          bounds.max-sample-x))
  (local z-range
    (covered-sample-range min-local-z
                          max-local-z
                          spacing-z
                          bounds.min-sample-z
                          bounds.max-sample-z))
  (local target
    (if (and x-range z-range)
        (HeightfieldTerrainData.rectangular-sample-target record
          {:x0 x-range.min
           :z0 z-range.min
           :x1 x-range.max
           :z1 z-range.max})
        nil))
  target)

(fn screen-rect-target [record start-pos end-pos opts]
  (local options (or opts {}))
  (local view (or options.view
                  (and app.scene app.scene.get-view-matrix (app.scene:get-view-matrix))
                  (and app.camera app.camera.get-view-matrix (app.camera:get-view-matrix))))
  (local projection (or options.projection
                        (and app.scene app.scene.projection)
                        app.projection))
  (local viewport (viewport-utils.to-table (or options.viewport app.viewport)))
  (if (or (not record)
          (not start-pos)
          (not end-pos)
          (not view)
          (not projection))
      nil
      (do
        (local start-ray (app.screen-pos-ray start-pos
                                             {:view view
                                              :projection projection
                                              :viewport viewport}))
        (local end-ray (app.screen-pos-ray end-pos
                                           {:view view
                                            :projection projection
                                            :viewport viewport}))
        (local start-hit (and start-ray (M.raycast-record record start-ray)))
        (local end-hit (and end-ray (M.raycast-record record end-ray)))
        (if (or (not start-hit) (not end-hit))
            nil
            (rect-target-between-local-points record
                                              start-hit.local-point
                                              end-hit.local-point)))))

(fn maybe-update-best [record best hit]
  (if (and hit (or (not best) (< hit.distance best.distance)))
      (do
        (local local-point (world->local record hit.point))
        {:distance hit.distance
         :world-point hit.point
         :local-point local-point
         :sample (nearest-sample-coord record local-point)
         :target (sample-target record local-point)})
      best))

(fn local-triangle-hits-for-cell [record chunk-map cell-x cell-z ray]
  (local sample-spacing (spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (local h00 (sample-height-global record chunk-map cell-x cell-z))
  (local h01 (sample-height-global record chunk-map cell-x (+ cell-z 1)))
  (local h10 (sample-height-global record chunk-map (+ cell-x 1) cell-z))
  (local h11 (sample-height-global record chunk-map (+ cell-x 1) (+ cell-z 1)))
  (if (or (= h00 nil) (= h01 nil) (= h10 nil) (= h11 nil))
      []
      (let [p00 (glm.vec3 (+ 0.0 (* cell-x spacing-x)) (+ 0.0 h00) (+ 0.0 (* cell-z spacing-z)))
            p01 (glm.vec3 (+ 0.0 (* cell-x spacing-x)) (+ 0.0 h01) (+ 0.0 (* (+ cell-z 1) spacing-z)))
            p10 (glm.vec3 (+ 0.0 (* (+ cell-x 1) spacing-x)) (+ 0.0 h10) (+ 0.0 (* cell-z spacing-z)))
            p11 (glm.vec3 (+ 0.0 (* (+ cell-x 1) spacing-x)) (+ 0.0 h11) (+ 0.0 (* (+ cell-z 1) spacing-z)))
            tri0 (intersect-triangle ray p00 p01 p10)
            tri1 (intersect-triangle ray p10 p01 p11)
            hits []]
        (when tri0
          (table.insert hits tri0))
        (when tri1
          (table.insert hits tri1))
        hits)))

(fn local-ray [record ray]
  (local rotation (resolve-rotation record))
  (local inverse (rotation:inverse))
  {:origin (world->local record ray.origin)
   :direction (inverse:rotate ray.direction)})

(fn xz-ray-interval [record ray]
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local sample-spacing (spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (local min-x (* bounds.min-sample-x spacing-x))
  (local max-x (* bounds.max-sample-x spacing-x))
  (local min-z (* bounds.min-sample-z spacing-z))
  (local max-z (* bounds.max-sample-z spacing-z))
  (local ox ray.origin.x)
  (local oz ray.origin.z)
  (local dx ray.direction.x)
  (local dz ray.direction.z)
  (var t-min 0.0)
  (var t-max math.huge)

  (fn update-axis [origin direction axis-min axis-max]
    (if (< (math.abs direction) ray-axis-epsilon)
        (and (>= origin axis-min) (<= origin axis-max))
        (let [inv (/ 1.0 direction)
              t0 (* (- axis-min origin) inv)
              t1 (* (- axis-max origin) inv)
              axis-entry (math.min t0 t1)
              axis-exit (math.max t0 t1)]
          (when (> axis-entry t-min)
            (set t-min axis-entry))
          (when (< axis-exit t-max)
            (set t-max axis-exit))
          (<= t-min t-max))))

  (if (and (update-axis ox dx min-x max-x)
           (update-axis oz dz min-z max-z)
           (>= t-max 0))
      {:t0 (math.max t-min 0.0)
       :t1 t-max}
      nil))

(fn make-traversal-state [record local-ray-value interval]
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local sample-spacing (spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (local start-point (+ local-ray-value.origin (* local-ray-value.direction (+ interval.t0 1e-6))))
  (local clamp-cell-x
    (fn [value]
      (math.max bounds.min-sample-x
                (math.min (- bounds.max-sample-x 1) value))))
  (local clamp-cell-z
    (fn [value]
      (math.max bounds.min-sample-z
                (math.min (- bounds.max-sample-z 1) value))))
  (local cell-x (clamp-cell-x (math.floor (/ start-point.x spacing-x))))
  (local cell-z (clamp-cell-z (math.floor (/ start-point.z spacing-z))))
  (local direction-x
    (if (< (math.abs local-ray-value.direction.x) ray-axis-epsilon)
        0.0
        local-ray-value.direction.x))
  (local direction-z
    (if (< (math.abs local-ray-value.direction.z) ray-axis-epsilon)
        0.0
        local-ray-value.direction.z))
  (local step-x
    (if (> direction-x 0) 1
        (if (< direction-x 0) -1 0)))
  (local step-z
    (if (> direction-z 0) 1
        (if (< direction-z 0) -1 0)))
  (local next-boundary-x
    (if (= step-x 0)
        nil
        (* (+ cell-x (if (> step-x 0) 1 0)) spacing-x)))
  (local next-boundary-z
    (if (= step-z 0)
        nil
        (* (+ cell-z (if (> step-z 0) 1 0)) spacing-z)))
  {:bounds bounds
   :chunk-map (build-chunk-map record)
   :cell-x cell-x
   :cell-z cell-z
   :spacing-x spacing-x
   :spacing-z spacing-z
   :start-point start-point
   :step-x step-x
   :step-z step-z
   :t-max-x (if next-boundary-x
                (/ (- next-boundary-x local-ray-value.origin.x) direction-x)
                math.huge)
   :t-max-z (if next-boundary-z
                (/ (- next-boundary-z local-ray-value.origin.z) direction-z)
                math.huge)
   :t-delta-x (if (= step-x 0)
                  math.huge
                  (/ spacing-x (math.abs direction-x)))
   :t-delta-z (if (= step-z 0)
                  math.huge
                  (/ spacing-z (math.abs direction-z)))})

(fn maybe-remember-best-hit [record interval best-ref hit]
  (when (and hit
             (>= hit.distance interval.t0)
             (<= hit.distance interval.t1))
    (local best (. best-ref.best))
    (if (or (not best) (< hit.distance best.distance))
        (set best-ref.best {:distance hit.distance
                            :world-point (local->world record hit.point)
                            :local-point hit.point
                            :sample (nearest-sample-coord record hit.point)
                            :target (sample-target record hit.point)}))))

(fn scan-cell-hits! [record interval best-ref chunk-map cell-x cell-z local-ray-value]
  (each [_ hit (ipairs (local-triangle-hits-for-cell record chunk-map cell-x cell-z local-ray-value))]
    (maybe-remember-best-hit record interval best-ref hit)))

(fn raycast-zero-step [record interval traversal local-ray-value]
  (local bounds traversal.bounds)
  (local cell-x traversal.cell-x)
  (local cell-z traversal.cell-z)
  (local chunk-map traversal.chunk-map)
  (local start-point traversal.start-point)
  (local spacing-x traversal.spacing-x)
  (local spacing-z traversal.spacing-z)
  (local best-ref {:best nil})

  (fn near-boundary? [value spacing]
    (< (math.abs (- value (* (math.floor (/ value spacing)) spacing))) 1e-6))

  (local candidate-cells-x [cell-x])
  (local candidate-cells-z [cell-z])
  (when (and (near-boundary? start-point.x spacing-x)
             (> cell-x bounds.min-sample-x))
    (table.insert candidate-cells-x (- cell-x 1)))
  (when (and (near-boundary? start-point.z spacing-z)
             (> cell-z bounds.min-sample-z))
    (table.insert candidate-cells-z (- cell-z 1)))
  (each [_ candidate-x (ipairs candidate-cells-x)]
    (each [_ candidate-z (ipairs candidate-cells-z)]
      (when (and (>= candidate-x bounds.min-sample-x)
                 (< candidate-x bounds.max-sample-x)
                 (>= candidate-z bounds.min-sample-z)
                 (< candidate-z bounds.max-sample-z))
        (scan-cell-hits! record interval best-ref chunk-map candidate-x candidate-z local-ray-value))))
  best-ref.best)

(fn raycast-grid-walk [record interval traversal local-ray-value]
  (local bounds traversal.bounds)
  (local chunk-map traversal.chunk-map)
  (local step-epsilon 1e-6)
  (local best-ref {:best nil})
  (var cell-x traversal.cell-x)
  (var cell-z traversal.cell-z)
  (var t-max-x traversal.t-max-x)
  (var t-max-z traversal.t-max-z)

  (while (and (>= cell-x bounds.min-sample-x)
              (< cell-x bounds.max-sample-x)
              (>= cell-z bounds.min-sample-z)
              (< cell-z bounds.max-sample-z))
    (scan-cell-hits! record interval best-ref chunk-map cell-x cell-z local-ray-value)
    (if (<= (math.abs (- t-max-x t-max-z)) step-epsilon)
        (do
          (when (> t-max-x interval.t1)
            (lua "break"))
          (set cell-x (+ cell-x traversal.step-x))
          (set cell-z (+ cell-z traversal.step-z))
          (set t-max-x (+ t-max-x traversal.t-delta-x))
          (set t-max-z (+ t-max-z traversal.t-delta-z)))
        (if (< t-max-x t-max-z)
            (do
              (when (> t-max-x interval.t1)
                (lua "break"))
              (set cell-x (+ cell-x traversal.step-x))
              (set t-max-x (+ t-max-x traversal.t-delta-x)))
            (do
              (when (> t-max-z interval.t1)
                (lua "break"))
              (set cell-z (+ cell-z traversal.step-z))
              (set t-max-z (+ t-max-z traversal.t-delta-z))))))
  best-ref.best)

(fn raycast-record-fast [record ray]
  (local local-ray-value (local-ray record ray))
  (local interval (xz-ray-interval record local-ray-value))
  (if (not interval)
      nil
      (do
        (local traversal (make-traversal-state record local-ray-value interval))
        (if (and (= traversal.step-x 0) (= traversal.step-z 0))
            (raycast-zero-step record interval traversal local-ray-value)
            (raycast-grid-walk record interval traversal local-ray-value)))))

(fn M.raycast-record [record ray]
  (raycast-record-fast record ray))

(fn M.domain-hit-record [record ray]
  (M.raycast-record record ray))

(fn M.screen-rect-target [record start-pos end-pos opts]
  (screen-rect-target record start-pos end-pos opts))

{:raycast-record M.raycast-record
 :raycast-record-fast raycast-record-fast
 :domain-hit-record M.domain-hit-record
 :screen-rect-target M.screen-rect-target
 :world->local world->local
 :local->world local->world
 :nearest-sample-coord nearest-sample-coord
 :sample-target sample-target
 :rect-target-between-local-points rect-target-between-local-points}
