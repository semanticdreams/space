(local glm (require :glm))
(local HeightfieldTerrainSpace (require :heightfield-terrain-space))
(local {:intersect-triangle intersect-triangle} (require :ray-triangle))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainGrid (require :heightfield-terrain-grid))
(local viewport-utils (require :viewport-utils))

(local M {})

(local ray-axis-epsilon 1e-6)

(local resolve-rotation HeightfieldTerrainSpace.resolve-rotation)
(local query-local->canonical-local (. HeightfieldTerrainSpace :query-local->canonical-local))
(local canonical-local->query-local (. HeightfieldTerrainSpace :canonical-local->query-local))
(local canonical-domain-bounds (. HeightfieldTerrainSpace :canonical-domain-bounds))
(local query-domain-bounds (. HeightfieldTerrainSpace :query-domain-bounds))
(local local->world HeightfieldTerrainSpace.local->world)
(local world->local HeightfieldTerrainSpace.world->local)

(local spacing HeightfieldTerrainGrid.spacing)
(local build-chunk-map HeightfieldTerrainGrid.build-chunk-map)
(local sample-height-global HeightfieldTerrainGrid.sample-height-global)

(fn nearest-sample-coord [record local-point]
  (local sample-spacing (spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local canonical-local (query-local->canonical-local record local-point))
  (local sample-x
    (math.max bounds.min-sample-x
              (math.min bounds.max-sample-x
                        (math.floor (+ (/ canonical-local.x spacing-x) 0.5)))))
  (local sample-z
    (math.max bounds.min-sample-z
              (math.min bounds.max-sample-z
                        (math.floor (+ (/ canonical-local.z spacing-z) 0.5)))))
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

(fn rect-target-between-local-points [record start-local-point end-local-point]
  (local sample-spacing (spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local start-canonical (query-local->canonical-local record start-local-point))
  (local end-canonical (query-local->canonical-local record end-local-point))
  (local min-local-x (math.min start-canonical.x end-canonical.x))
  (local max-local-x (math.max start-canonical.x end-canonical.x))
  (local min-local-z (math.min start-canonical.z end-canonical.z))
  (local max-local-z (math.max start-canonical.z end-canonical.z))
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

(fn surface-info-at-local-point [record local-x local-z]
  (local sample-spacing (spacing record))
  (local spacing-x (. sample-spacing 1))
  (local spacing-z (. sample-spacing 2))
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local canonical-local
    (query-local->canonical-local record (glm.vec3 local-x 0 local-z)))
  (local domain-bounds (canonical-domain-bounds record))
  (if (or (< canonical-local.x domain-bounds.min-x)
          (> canonical-local.x domain-bounds.max-x)
          (< canonical-local.z domain-bounds.min-z)
          (> canonical-local.z domain-bounds.max-z))
      nil
      (do
        (local chunk-map (build-chunk-map record))
        (local max-cell-x (- bounds.max-sample-x 1))
        (local max-cell-z (- bounds.max-sample-z 1))
        (local raw-cell-x (math.floor (/ canonical-local.x spacing-x)))
        (local raw-cell-z (math.floor (/ canonical-local.z spacing-z)))
        (local cell-x (math.max bounds.min-sample-x (math.min raw-cell-x max-cell-x)))
        (local cell-z (math.max bounds.min-sample-z (math.min raw-cell-z max-cell-z)))
        (local h00 (sample-height-global record chunk-map cell-x cell-z))
        (local h01 (sample-height-global record chunk-map cell-x (+ cell-z 1)))
        (local h10 (sample-height-global record chunk-map (+ cell-x 1) cell-z))
        (local h11 (sample-height-global record chunk-map (+ cell-x 1) (+ cell-z 1)))
        (if (or (= h00 nil) (= h01 nil) (= h10 nil) (= h11 nil))
            nil
            (do
              (local local-u (/ (- canonical-local.x (* cell-x spacing-x)) spacing-x))
              (local local-v (/ (- canonical-local.z (* cell-z spacing-z)) spacing-z))
              (local local-y
                (if (<= (+ local-u local-v) 1.0)
                    (+ (* h00 (- 1.0 local-u local-v))
                       (* h01 local-v)
                       (* h10 local-u))
                    (+ (* h10 (- 1.0 local-v))
                       (* h01 (- 1.0 local-u))
                       (* h11 (- (+ local-u local-v) 1.0)))))
              {:local-point (glm.vec3 local-x local-y local-z)
               :local-surface-y local-y
               :cell-x cell-x
               :cell-z cell-z
               :u local-u
               :v local-v
               :h00 h00
               :h01 h01
               :h10 h10
               :h11 h11})))))

(fn surface-info-at-world-point [record world-point]
  (if (and record world-point)
      (do
        (local local-point (world->local record world-point))
        (local info (surface-info-at-local-point record local-point.x local-point.z))
        (if info
            (do
              (set info.world-point (local->world record info.local-point))
              info)
            nil))
      nil))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn assert-finite-vec3 [vec label]
  (when (or (not vec)
            (not (finite-number? vec.x))
            (not (finite-number? vec.y))
            (not (finite-number? vec.z)))
    (error (.. "HeightfieldTerrainQuery.screen-rect-target produced non-finite " label))))

(fn screen-pos-ray-from-matrices [pos view projection viewport]
  (local vp (viewport-utils.to-table viewport))
  (assert vp "screen-rect-target requires a viewport")
  (assert view "screen-rect-target requires a view matrix")
  (assert projection "screen-rect-target requires a projection matrix")
  (local sample-pos
    (or (viewport-utils.input-pos->viewport-pos pos vp app.engine)
        {:x (+ vp.x (/ vp.width 2))
         :y (+ vp.y (/ vp.height 2))}))
  (local px (or sample-pos.x vp.x))
  (local py (or sample-pos.y vp.y))
  (local inverted-y (- (+ vp.height vp.y) py))
  (local viewport-vec (viewport-utils.to-glm-vec4 vp))
  (local near (glm.unproject (glm.vec3 px inverted-y 0.0) view projection viewport-vec))
  (local far (glm.unproject (glm.vec3 px inverted-y 1.0) view projection viewport-vec))
  (local direction (glm.normalize (- far near)))
  (assert-finite-vec3 near "near")
  (assert-finite-vec3 far "far")
  (assert-finite-vec3 direction "direction")
  {:origin near :direction direction})

(fn screen-rect-target [record start-pos end-pos opts]
  (local options (or opts {}))
  (if (or (not record) (not start-pos) (not end-pos))
      nil
      (do
        (local start-ray
          (if (and options.view options.projection options.viewport)
              (screen-pos-ray-from-matrices start-pos options.view options.projection options.viewport)
              (app.screen-pos-ray start-pos options)))
        (local end-ray
          (if (and options.view options.projection options.viewport)
              (screen-pos-ray-from-matrices end-pos options.view options.projection options.viewport)
              (app.screen-pos-ray end-pos options)))
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
      (let [p00 (canonical-local->query-local record (glm.vec3 (* cell-x spacing-x) (+ 0.0 h00) (* cell-z spacing-z)))
            p01 (canonical-local->query-local record (glm.vec3 (* cell-x spacing-x) (+ 0.0 h01) (* (+ cell-z 1) spacing-z)))
            p10 (canonical-local->query-local record (glm.vec3 (* (+ cell-x 1) spacing-x) (+ 0.0 h10) (* cell-z spacing-z)))
            p11 (canonical-local->query-local record (glm.vec3 (* (+ cell-x 1) spacing-x) (+ 0.0 h11) (* (+ cell-z 1) spacing-z)))
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
  (local bounds (query-domain-bounds record))
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

  (if (and (update-axis ox dx bounds.min-x bounds.max-x)
           (update-axis oz dz bounds.min-z bounds.max-z)
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
  (local start-canonical (query-local->canonical-local record start-point))
  (local clamp-cell-x
    (fn [value]
      (math.max bounds.min-sample-x
                (math.min (- bounds.max-sample-x 1) value))))
  (local clamp-cell-z
    (fn [value]
      (math.max bounds.min-sample-z
                (math.min (- bounds.max-sample-z 1) value))))
  (local cell-x (clamp-cell-x (math.floor (/ start-canonical.x spacing-x))))
  (local cell-z (clamp-cell-z (math.floor (/ start-canonical.z spacing-z))))
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
  (local next-boundary-point-x
    (and (not (= step-x 0))
         (canonical-local->query-local record
                                       (glm.vec3 (* (+ cell-x (if (> step-x 0) 1 0)) spacing-x)
                                                 0
                                                 0))))
  (local next-boundary-point-z
    (and (not (= step-z 0))
         (canonical-local->query-local record
                                       (glm.vec3 0
                                                 0
                                                 (* (+ cell-z (if (> step-z 0) 1 0)) spacing-z)))))
  (local next-boundary-x
    (and next-boundary-point-x next-boundary-point-x.x))
  (local next-boundary-z
    (and next-boundary-point-z next-boundary-point-z.z))
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
    (local canonical-point
      (query-local->canonical-local record
                                    (if (= spacing spacing-x)
                                        (glm.vec3 value 0 0)
                                        (glm.vec3 0 0 value))))
    (local canonical-value
      (if (= spacing spacing-x)
          canonical-point.x
          canonical-point.z))
    (< (math.abs (- canonical-value (* (math.floor (/ canonical-value spacing)) spacing))) 1e-6))

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

(local vertical-domain-surface-hit
  (fn [record local-ray-value interval]
    (if (or (>= (math.abs local-ray-value.direction.x) ray-axis-epsilon)
            (>= (math.abs local-ray-value.direction.z) ray-axis-epsilon)
            (< (math.abs local-ray-value.direction.y) ray-axis-epsilon))
        nil
        (do
          (local info
            (surface-info-at-local-point record
                                         local-ray-value.origin.x
                                         local-ray-value.origin.z))
          (if (not info)
              nil
              (do
                (local t
                  (/ (- info.local-surface-y local-ray-value.origin.y)
                     local-ray-value.direction.y))
                (if (or (< t (- interval.t0 1e-6))
                        (> t (+ interval.t1 1e-6))
                        (< t 0))
                    nil
                    {:distance t
                     :world-point (local->world record info.local-point)
                     :local-point info.local-point
                     :sample (nearest-sample-coord record info.local-point)
                     :target (sample-target record info.local-point)})))))))

(fn M.raycast-record [record ray]
  (local strict-hit (raycast-record-fast record ray))
  (if strict-hit
      strict-hit
      (do
        (local local-ray-value (local-ray record ray))
        (local interval (xz-ray-interval record local-ray-value))
        (and interval
             (vertical-domain-surface-hit record local-ray-value interval)))))

(fn M.domain-hit-record [record ray]
  (M.raycast-record record ray))

(fn M.screen-rect-target [record start-pos end-pos opts]
  (screen-rect-target record start-pos end-pos opts))

{:raycast-record M.raycast-record
 :raycast-record-fast raycast-record-fast
 :domain-hit-record M.domain-hit-record
 :screen-rect-target M.screen-rect-target
 :surface-info-at-local-point surface-info-at-local-point
 :surface-info-at-world-point surface-info-at-world-point
 :world->local world->local
 :local->world local->world
 :nearest-sample-coord nearest-sample-coord
 :sample-target sample-target
 :rect-target-between-local-points rect-target-between-local-points}
