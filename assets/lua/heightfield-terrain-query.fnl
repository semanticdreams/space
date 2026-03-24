(local glm (require :glm))
(local {:intersect-triangle intersect-triangle} (require :ray-triangle))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainGrid (require :heightfield-terrain-grid))
(local MathUtils (require :math-utils))
(local viewport-utils (require :viewport-utils))

(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(local M {})

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
  (if (and x-range z-range)
      (HeightfieldTerrainData.rectangular-sample-target record
        {:x0 x-range.min
         :z0 z-range.min
         :x1 x-range.max
         :z1 z-range.max})
      nil))

(fn resolve-screen-rect [start-pos end-pos]
  (var min-x (math.min start-pos.x end-pos.x))
  (var max-x (math.max start-pos.x end-pos.x))
  (var min-y (math.min start-pos.y end-pos.y))
  (var max-y (math.max start-pos.y end-pos.y))
  (when (= min-x max-x)
    (set min-x (- min-x 0.5))
    (set max-x (+ max-x 0.5)))
  (when (= min-y max-y)
    (set min-y (- min-y 0.5))
    (set max-y (+ max-y 0.5)))
  {:top-left {:x min-x :y min-y}
   :top-right {:x max-x :y min-y}
   :bottom-right {:x max-x :y max-y}
   :bottom-left {:x min-x :y max-y}})

(fn unproject-screen-point [point depth view projection viewport]
  (local sample-pos (viewport-utils.input-pos->viewport-pos point viewport app.engine))
  (if (not sample-pos)
      nil
      (do
        (local px (or sample-pos.x viewport.x))
        (local py (or sample-pos.y viewport.y))
        (local inverted-y (- (+ viewport.height viewport.y) py))
        (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
        (glm.unproject (glm.vec3 px inverted-y depth) view projection viewport-vec))))

(fn average-points [points]
  (var total (glm.vec3 0 0 0))
  (var count 0)
  (each [_ point (ipairs (or points []))]
    (when point
      (set total (+ total point))
      (set count (+ count 1))))
  (if (> count 0)
      (/ total (glm.vec3 count))
      nil))

(fn plane-from-points [a b c inside-point]
  (local raw-normal (glm.cross (- b a) (- c a)))
  (if (< (glm.length raw-normal) 1e-6)
      nil
      (do
        (var normal (glm.normalize raw-normal))
        (when (< (glm.dot normal (- inside-point a)) 0)
          (set normal (* normal (glm.vec3 -1))))
        {:point a
         :normal normal})))

(fn build-screen-rect-planes [start-pos end-pos view projection viewport]
  (local rect (resolve-screen-rect start-pos end-pos))
  (local near-top-left (unproject-screen-point rect.top-left 0.0 view projection viewport))
  (local near-top-right (unproject-screen-point rect.top-right 0.0 view projection viewport))
  (local near-bottom-right (unproject-screen-point rect.bottom-right 0.0 view projection viewport))
  (local near-bottom-left (unproject-screen-point rect.bottom-left 0.0 view projection viewport))
  (local far-top-left (unproject-screen-point rect.top-left 1.0 view projection viewport))
  (local far-top-right (unproject-screen-point rect.top-right 1.0 view projection viewport))
  (local far-bottom-right (unproject-screen-point rect.bottom-right 1.0 view projection viewport))
  (local far-bottom-left (unproject-screen-point rect.bottom-left 1.0 view projection viewport))
  (if (or (not near-top-left)
          (not near-top-right)
          (not near-bottom-right)
          (not near-bottom-left)
          (not far-top-left)
          (not far-top-right)
          (not far-bottom-right)
          (not far-bottom-left))
      nil
      (do
        (local inside-point
          (average-points [far-top-left
                           far-top-right
                           far-bottom-right
                           far-bottom-left]))
        (local planes
          [(plane-from-points near-top-left near-top-right near-bottom-right inside-point)
           (plane-from-points near-top-left near-bottom-left far-bottom-left inside-point)
           (plane-from-points near-bottom-right near-top-right far-top-right inside-point)
           (plane-from-points near-top-right near-top-left far-top-left inside-point)
           (plane-from-points near-bottom-left near-bottom-right far-bottom-right inside-point)])
        (if (and (. planes 1) (. planes 2) (. planes 3) (. planes 4) (. planes 5))
            planes
            nil))))

(fn local-plane [record plane]
  (local rotation (resolve-rotation record))
  (local inverse (rotation:inverse))
  {:point (world->local record plane.point)
   :normal (glm.normalize (inverse:rotate plane.normal))})

(fn point-inside-planes? [point planes]
  (var inside? true)
  (each [_ plane (ipairs (or planes []))]
    (when (< (glm.dot plane.normal (- point plane.point)) -1e-6)
      (set inside? false)))
  inside?)

(fn chunk-local-corners [record chunk]
  (local coord (or chunk.coord [0 0]))
  (local chunk-x (integer-field (or (. coord 1) coord.x 0) 0))
  (local chunk-z (integer-field (or (. coord 2) coord.y coord.z 0) 0))
  (local size (chunk-size chunk))
  (local width (. size 1))
  (local depth (. size 2))
  (local sample-counts (chunk-samples record))
  (local stride-x (- (. sample-counts 1) 1))
  (local stride-z (- (. sample-counts 2) 1))
  (local sample-spacing (spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (local min-x (* chunk-x stride-x spacing-x))
  (local min-z (* chunk-z stride-z spacing-z))
  (local max-x (+ min-x (* (- width 1) spacing-x)))
  (local max-z (+ min-z (* (- depth 1) spacing-z)))
  (var min-y math.huge)
  (var max-y (- math.huge))
  (each [_ height (ipairs (or chunk.heights []))]
    (set min-y (math.min min-y height))
    (set max-y (math.max max-y height)))
  (when (= min-y math.huge)
    (set min-y 0.0)
    (set max-y 0.0))
  [(glm.vec3 min-x min-y min-z)
   (glm.vec3 min-x min-y max-z)
   (glm.vec3 max-x min-y min-z)
   (glm.vec3 max-x min-y max-z)
   (glm.vec3 min-x max-y min-z)
   (glm.vec3 min-x max-y max-z)
   (glm.vec3 max-x max-y min-z)
   (glm.vec3 max-x max-y max-z)])

(fn corners-intersect-planes? [corners planes]
  (var intersects? true)
  (each [_ plane (ipairs (or planes []))]
    (var any-inside? false)
    (each [_ corner (ipairs (or corners []))]
      (when (>= (glm.dot plane.normal (- corner plane.point)) -1e-6)
        (set any-inside? true)))
    (when (not any-inside?)
      (set intersects? false)))
  intersects?)

(fn collect-screen-rect-samples [record planes]
  (local sample-counts (chunk-samples record))
  (local stride-x (- (. sample-counts 1) 1))
  (local stride-z (- (. sample-counts 2) 1))
  (local seen {})
  (var min-sample-x nil)
  (var max-sample-x nil)
  (var min-sample-z nil)
  (var max-sample-z nil)
  (var sample-count 0)

  (fn mark-seen! [sample-x sample-z]
    (local row (or (. seen sample-z) {}))
    (when (= (. seen sample-z) nil)
      (set (. seen sample-z) row))
    (set (. row sample-x) true))

  (fn seen? [sample-x sample-z]
    (not (= (. (or (. seen sample-z) {}) sample-x) nil)))

  (fn record-sample! [sample-x sample-z]
    (set sample-count (+ sample-count 1))
    (if (= min-sample-x nil)
        (do
          (set min-sample-x sample-x)
          (set max-sample-x sample-x)
          (set min-sample-z sample-z)
          (set max-sample-z sample-z))
        (do
          (when (< sample-x min-sample-x)
            (set min-sample-x sample-x))
          (when (> sample-x max-sample-x)
            (set max-sample-x sample-x))
          (when (< sample-z min-sample-z)
            (set min-sample-z sample-z))
          (when (> sample-z max-sample-z)
            (set max-sample-z sample-z)))))

  (each [_ chunk (ipairs (or record.chunks []))]
    (when (corners-intersect-planes? (chunk-local-corners record chunk) planes)
      (local coord (or chunk.coord [0 0]))
      (local chunk-x (integer-field (or (. coord 1) coord.x 0) 0))
      (local chunk-z (integer-field (or (. coord 2) coord.y coord.z 0) 0))
      (local base-sample-x (* chunk-x stride-x))
      (local base-sample-z (* chunk-z stride-z))
      (local size (chunk-size chunk))
      (local width (. size 1))
      (local depth (. size 2))
      (for [sample-z 0 (- depth 1)]
        (for [sample-x 0 (- width 1)]
          (local global-sample-x (+ base-sample-x sample-x))
          (local global-sample-z (+ base-sample-z sample-z))
          (when (not (seen? global-sample-x global-sample-z))
            (local sample-point (canonical-local-point record chunk sample-x sample-z))
            (when (point-inside-planes? sample-point planes)
              (mark-seen! global-sample-x global-sample-z)
              (record-sample! global-sample-x global-sample-z)))))))
  (if (> sample-count 0)
      {:x0 min-sample-x
       :z0 min-sample-z
       :x1 max-sample-x
       :z1 max-sample-z
       :sample-count sample-count}
      nil))

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
        (local world-planes (build-screen-rect-planes start-pos end-pos view projection viewport))
        (if (not world-planes)
            nil
            (do
              (local planes [])
              (each [_ plane (ipairs world-planes)]
                (table.insert planes (local-plane record plane)))
              (local selected-bounds (collect-screen-rect-samples record planes))
              (and selected-bounds
                   (HeightfieldTerrainData.rectangular-sample-target record
                     {:x0 selected-bounds.x0
                      :z0 selected-bounds.z0
                      :x1 selected-bounds.x1
                      :z1 selected-bounds.z1})))))))

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

(fn triangle-hits-for-cell [record chunk sample-x sample-z ray]
  (local p00-local (canonical-local-point record chunk sample-x sample-z))
  (local p01-local (canonical-local-point record chunk sample-x (+ sample-z 1)))
  (local p10-local (canonical-local-point record chunk (+ sample-x 1) sample-z))
  (local p11-local (canonical-local-point record chunk (+ sample-x 1) (+ sample-z 1)))
  (local p00 (local->world record p00-local))
  (local p01 (local->world record p01-local))
  (local p10 (local->world record p10-local))
  (local p11 (local->world record p11-local))
  [(intersect-triangle ray p00 p01 p10)
   (intersect-triangle ray p10 p01 p11)])

(fn raycast-record-exact [record ray]
  (var best nil)

  (fn maybe-remember-hit [hit]
    (when (and hit (or (not best) (< hit.distance best.distance)))
      (local local-point (world->local record hit.point))
      (set best {:distance hit.distance
                 :world-point hit.point
                 :local-point local-point
                 :sample (nearest-sample-coord record local-point)
                 :target (sample-target record local-point)})))

  (each [_ chunk (ipairs (or record.chunks []))]
    (local size (chunk-size chunk))
    (local chunk-width (. size 1))
    (local chunk-length (. size 2))
    (for [sample-x 0 (- chunk-width 2)]
      (for [sample-z 0 (- chunk-length 2)]
        (each [_ hit (ipairs (triangle-hits-for-cell record chunk sample-x sample-z ray))]
          (maybe-remember-hit hit)))))

  best)

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
            p11 (glm.vec3 (+ 0.0 (* (+ cell-x 1) spacing-x)) (+ 0.0 h11) (+ 0.0 (* (+ cell-z 1) spacing-z)))]
        [(intersect-triangle ray p00 p01 p10)
         (intersect-triangle ray p10 p01 p11)])))

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
    (if (< (math.abs direction) 1e-6)
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

(fn raycast-record-fast [record ray]
  (local local-ray-value (local-ray record ray))
  (local interval (xz-ray-interval record local-ray-value))
  (if (not interval)
      nil
      (let [sample-counts (chunk-samples record)
            stride-x (- (. sample-counts 1) 1)
            stride-z (- (. sample-counts 2) 1)
            bounds (HeightfieldTerrainData.sample-bounds record)
            sample-spacing (spacing record)
            spacing-x (. sample-spacing 1)
            spacing-z (. sample-spacing 2)
            chunk-map (build-chunk-map record)
            start-point (+ local-ray-value.origin (* local-ray-value.direction (+ interval.t0 1e-6)))
            clamp-cell-x (fn [value]
                           (math.max bounds.min-sample-x
                                     (math.min (- bounds.max-sample-x 1) value)))
            clamp-cell-z (fn [value]
                           (math.max bounds.min-sample-z
                                     (math.min (- bounds.max-sample-z 1) value)))]
        (var cell-x (clamp-cell-x (math.floor (/ start-point.x spacing-x))))
        (var cell-z (clamp-cell-z (math.floor (/ start-point.z spacing-z))))
        (local step-x (if (> local-ray-value.direction.x 0) 1
                          (if (< local-ray-value.direction.x 0) -1 0)))
        (local step-z (if (> local-ray-value.direction.z 0) 1
                          (if (< local-ray-value.direction.z 0) -1 0)))
        (local next-boundary-x
          (if (= step-x 0)
              nil
              (* (+ cell-x (if (> step-x 0) 1 0)) spacing-x)))
        (local next-boundary-z
          (if (= step-z 0)
              nil
              (* (+ cell-z (if (> step-z 0) 1 0)) spacing-z)))
        (var t-max-x
          (if next-boundary-x
              (/ (- next-boundary-x local-ray-value.origin.x) local-ray-value.direction.x)
              math.huge))
        (var t-max-z
          (if next-boundary-z
              (/ (- next-boundary-z local-ray-value.origin.z) local-ray-value.direction.z)
              math.huge))
        (local t-delta-x
          (if (= step-x 0)
              math.huge
              (/ spacing-x (math.abs local-ray-value.direction.x))))
        (local t-delta-z
          (if (= step-z 0)
              math.huge
              (/ spacing-z (math.abs local-ray-value.direction.z))))
        (var best nil)
        (fn maybe-remember-hit [hit]
          (when (and hit
                     (>= hit.distance interval.t0)
                     (<= hit.distance interval.t1))
            (let [world-point (local->world record hit.point)
                  local-point hit.point]
              (if (or (not best) (< hit.distance best.distance))
                  (set best {:distance hit.distance
                             :world-point world-point
                             :local-point local-point
                             :sample (nearest-sample-coord record local-point)
                             :target (sample-target record local-point)})))))
        (if (and (= step-x 0) (= step-z 0))
            (do
              (local near-boundary?
                (fn [value spacing]
                  (< (math.abs (- value (* (math.floor (/ value spacing)) spacing))) 1e-6)))
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
                    (each [_ hit (ipairs (local-triangle-hits-for-cell
                                           record chunk-map candidate-x candidate-z local-ray-value))]
                      (maybe-remember-hit hit)))))
              best)
            (do
              (local step-epsilon 1e-6)
              (while (and (>= cell-x bounds.min-sample-x)
                          (< cell-x bounds.max-sample-x)
                          (>= cell-z bounds.min-sample-z)
                          (< cell-z bounds.max-sample-z))
                (each [_ hit (ipairs (local-triangle-hits-for-cell record chunk-map cell-x cell-z local-ray-value))]
                  (maybe-remember-hit hit))
                (if (<= (math.abs (- t-max-x t-max-z)) step-epsilon)
                    (do
                      (when (> t-max-x interval.t1)
                        (lua "break"))
                      (set cell-x (+ cell-x step-x))
                      (set cell-z (+ cell-z step-z))
                      (set t-max-x (+ t-max-x t-delta-x))
                      (set t-max-z (+ t-max-z t-delta-z)))
                    (if (< t-max-x t-max-z)
                        (do
                          (when (> t-max-x interval.t1)
                            (lua "break"))
                          (set cell-x (+ cell-x step-x))
                          (set t-max-x (+ t-max-x t-delta-x)))
                        (do
                          (when (> t-max-z interval.t1)
                            (lua "break"))
                          (set cell-z (+ cell-z step-z))
                          (set t-max-z (+ t-max-z t-delta-z))))))
              best)))))

(fn M.raycast-record [record ray]
  (raycast-record-fast record ray))

(fn M.domain-hit-record [record ray]
  (M.raycast-record record ray))

(fn M.screen-rect-target [record start-pos end-pos opts]
  (screen-rect-target record start-pos end-pos opts))

(fn M.target-between-hits [record start-hit end-hit]
  (assert record "HeightfieldTerrainQuery.target-between-hits requires a record")
  (assert start-hit "HeightfieldTerrainQuery.target-between-hits requires a start hit")
  (assert end-hit "HeightfieldTerrainQuery.target-between-hits requires an end hit")
  (rect-target-between-local-points record start-hit.local-point end-hit.local-point))

{:raycast-record M.raycast-record
 :raycast-record-fast raycast-record-fast
 :domain-hit-record M.domain-hit-record
 :screen-rect-target M.screen-rect-target
 :target-between-hits M.target-between-hits
 :raycast-record-exact raycast-record-exact
 :world->local world->local
 :local->world local->world
 :nearest-sample-coord nearest-sample-coord
 :sample-target sample-target
 :rect-target-between-local-points rect-target-between-local-points}
