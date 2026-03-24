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
  {:mode :rect
   :x0 coord.x
   :z0 coord.z
   :x1 coord.x
   :z1 coord.z})

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
  (local start-sample (nearest-sample-coord record start-local-point))
  (local end-sample (nearest-sample-coord record end-local-point))
  {:mode :rect
   :x0 (math.min start-sample.x end-sample.x)
   :z0 (math.min start-sample.z end-sample.z)
   :x1 (math.max start-sample.x end-sample.x)
   :z1 (math.max start-sample.z end-sample.z)})

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

(fn screen-point [position view projection viewport]
  (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
  (local projected (glm.project position view projection viewport-vec))
  (when (not projected)
    (lua "return nil"))
  {:x projected.x
   :y (- (+ viewport.height viewport.y) projected.y)
   :z projected.z})

(fn cross-2d [ax ay bx by]
  (- (* ax by) (* ay bx)))

(fn barycentric-2d [point a b c]
  (local v0x (- b.x a.x))
  (local v0y (- b.y a.y))
  (local v1x (- c.x a.x))
  (local v1y (- c.y a.y))
  (local v2x (- point.x a.x))
  (local v2y (- point.y a.y))
  (local denom (cross-2d v0x v0y v1x v1y))
  (if (< (math.abs denom) 1e-6)
      nil
      (do
        (local inv-denom (/ 1.0 denom))
        (local v (* (cross-2d v2x v2y v1x v1y) inv-denom))
        (local w (* (cross-2d v0x v0y v2x v2y) inv-denom))
        (local u (- 1.0 v w))
        {:u u :v v :w w})))

(fn barycentric-inside? [bary]
  (and bary
       (>= bary.u -1e-5)
       (>= bary.v -1e-5)
       (>= bary.w -1e-5)))

(fn interpolate-vec3 [a b c bary]
  (+ (* a (glm.vec3 bary.u))
     (* b (glm.vec3 bary.v))
     (* c (glm.vec3 bary.w))))

(fn triangle-screen-hit [record point local-a local-b local-c world-a world-b world-c view projection viewport]
  (local screen-a (screen-point world-a view projection viewport))
  (local screen-b (screen-point world-b view projection viewport))
  (local screen-c (screen-point world-c view projection viewport))
  (local bary (and screen-a screen-b screen-c (barycentric-2d point screen-a screen-b screen-c)))
  (if (not (barycentric-inside? bary))
      nil
      (do
        (local local-point (interpolate-vec3 local-a local-b local-c bary))
        (local world-point (interpolate-vec3 world-a world-b world-c bary))
        (local depth (+ (* screen-a.z bary.u)
                        (* screen-b.z bary.v)
                        (* screen-c.z bary.w)))
        {:distance depth
         :depth depth
         :local-point local-point
         :world-point world-point
         :sample (nearest-sample-coord record local-point)
         :target (sample-target record local-point)})))

(fn nearest-screen-sample-hit [record point view projection viewport]
  (local max-distance 32.0)
  (local max-distance-squared (* max-distance max-distance))
  (var best nil)
  (each [_ chunk (ipairs (or record.chunks []))]
    (local size (chunk-size chunk))
    (local chunk-width (. size 1))
    (local chunk-length (. size 2))
    (for [sample-x 0 (- chunk-width 1)]
      (for [sample-z 0 (- chunk-length 1)]
        (local local-point (canonical-local-point record chunk sample-x sample-z))
        (local world-point (local->world record local-point))
        (local screen (screen-point world-point view projection viewport))
        (when screen
          (local dx (- screen.x point.x))
          (local dy (- screen.y point.y))
          (local distance-squared (+ (* dx dx) (* dy dy)))
          (when (and (<= distance-squared max-distance-squared)
                     (or (not best)
                         (< distance-squared best.distance-squared)
                         (and (= distance-squared best.distance-squared)
                              (< screen.z best.depth))))
            (set best {:distance-squared distance-squared
                       :depth screen.z
                       :local-point local-point
                       :world-point world-point
                       :sample (nearest-sample-coord record local-point)
                       :target (sample-target record local-point)}))))))
  best)

(fn screen-hit-record [record point view projection viewport]
  (assert (and glm glm.project) "HeightfieldTerrainQuery.screen-hit-record requires glm.project")
  (var best nil)
  (each [_ chunk (ipairs (or record.chunks []))]
    (local size (chunk-size chunk))
    (local chunk-width (. size 1))
    (local chunk-length (. size 2))
    (for [sample-x 0 (- chunk-width 2)]
      (for [sample-z 0 (- chunk-length 2)]
        (local p00-local (canonical-local-point record chunk sample-x sample-z))
        (local p01-local (canonical-local-point record chunk sample-x (+ sample-z 1)))
        (local p10-local (canonical-local-point record chunk (+ sample-x 1) sample-z))
        (local p11-local (canonical-local-point record chunk (+ sample-x 1) (+ sample-z 1)))
        (local p00 (local->world record p00-local))
        (local p01 (local->world record p01-local))
        (local p10 (local->world record p10-local))
        (local p11 (local->world record p11-local))
        (each [_ hit (ipairs [(triangle-screen-hit record point p00-local p01-local p10-local p00 p01 p10 view projection viewport)
                              (triangle-screen-hit record point p10-local p01-local p11-local p10 p01 p11 view projection viewport)])]
          (when (and hit
                     (or (not best) (< hit.depth best.depth)))
            (set best hit))))))
  (or best
      (nearest-screen-sample-hit record point view projection viewport)))

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

(fn M.screen-hit-record [record point opts]
  (local options (or opts {}))
  (screen-hit-record record point options.view options.projection options.viewport))

(fn M.target-between-hits [record start-hit end-hit]
  (assert record "HeightfieldTerrainQuery.target-between-hits requires a record")
  (assert start-hit "HeightfieldTerrainQuery.target-between-hits requires a start hit")
  (assert end-hit "HeightfieldTerrainQuery.target-between-hits requires an end hit")
  (rect-target-between-local-points record start-hit.local-point end-hit.local-point))

{:raycast-record M.raycast-record
 :raycast-record-fast raycast-record-fast
 :domain-hit-record M.domain-hit-record
 :screen-hit-record M.screen-hit-record
 :target-between-hits M.target-between-hits
 :raycast-record-exact raycast-record-exact
 :world->local world->local
 :local->world local->world
 :nearest-sample-coord nearest-sample-coord
 :sample-target sample-target
 :rect-target-between-local-points rect-target-between-local-points}
