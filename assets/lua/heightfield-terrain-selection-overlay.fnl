(local glm (require :glm))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainGrid (require :heightfield-terrain-grid))

(fn clone-target [target]
  (if (= (type target) :table)
      {:mode target.mode
       :x0 target.x0
       :z0 target.z0
       :x1 target.x1
       :z1 target.z1}
      nil))

(fn resolve-active-theme []
  (and app.themes app.themes.get-active-theme (app.themes.get-active-theme)))

(fn resolve-selection-colors []
  (local theme (assert (resolve-active-theme)
                       "Heightfield terrain selection overlay requires an active theme"))
  (local colors (assert theme.terrain-selection
                        "Active theme is missing terrain-selection colors"))
  {:fill colors.fill
   :border colors.border})

(fn vec4-equal? [a b]
  (and a
       b
       (= a.x b.x)
       (= a.y b.y)
       (= a.z b.z)
       (= a.w b.w)))

(fn make-triangle-buffer [ctx]
  (assert (and ctx ctx.triangle-vector)
          "Heightfield terrain selection overlay requires ctx.triangle-vector")
  (local vector ctx.triangle-vector)
  (var handle nil)
  (var stride 0)
  (var vertex-count 0)
  (var visible? false)

  (fn release-handle []
    (when handle
      (when (and ctx ctx.untrack-triangle-handle)
        (ctx:untrack-triangle-handle handle))
      (vector:delete handle)
      (set handle nil)
      (set stride 0)
      (set vertex-count 0)))

  (fn ensure-capacity [next-vertex-count]
    (local next-stride (* next-vertex-count 8))
    (if (not handle)
        (do
          (set handle (vector:allocate next-stride))
          (set stride next-stride))
        (when (not (= stride next-stride))
          (vector:reallocate handle next-stride)
          (set stride next-stride)))
    (set vertex-count next-vertex-count))

  {:set-visible (fn [_self next-visible?]
                  (local desired (not (not next-visible?)))
                  (when (not (= visible? desired))
                    (set visible? desired)
                    (when (not visible?)
                      (release-handle))))
   :visible? (fn [_self] visible?)
   :set-mesh (fn [_self mesh]
               (local positions (or (and mesh mesh.positions) []))
               (local next-count (length positions))
               (if (= next-count 0)
                   (do
                     (set visible? false)
                     (release-handle))
                   (do
                     (set visible? true)
                     (ensure-capacity next-count))))
   :update (fn [_self opts]
             (when (and visible? handle (> vertex-count 0))
               (local mesh (assert opts.mesh "triangle buffer update requires mesh"))
               (local rotation (or opts.rotation (glm.quat 1 0 0 0)))
               (local position (or opts.position (glm.vec3 0 0 0)))
               (local clip-region opts.clip-region)
               (local depth-index (or opts.depth-index 0))
               (for [i 1 vertex-count]
                 (local vertex-offset (* (- i 1) 8))
                 (local local-position (. mesh.positions i))
                 (local rotated (rotation:rotate local-position))
                 (vector:set-glm-vec3 handle vertex-offset (+ position rotated))
                 (vector:set-glm-vec4 handle (+ vertex-offset 3) (. mesh.colors i))
                 (vector:set-float handle (+ vertex-offset 7) depth-index))
               (when (and ctx ctx.track-triangle-handle)
                 (ctx:track-triangle-handle handle clip-region))))
   :drop (fn [_self]
           (release-handle))})

(fn append-triangle [positions colors p0 p1 p2 color]
  (table.insert positions p0)
  (table.insert positions p1)
  (table.insert positions p2)
  (table.insert colors color)
  (table.insert colors color)
  (table.insert colors color))

(fn rebase-local-point [point origin-offset lift]
  (glm.vec3 (- point.x origin-offset.x)
            (+ point.y lift)
            (- point.z origin-offset.z)))

(fn affected-cell-bounds [target]
  {:min-cell-x (- target.x0 1)
   :min-cell-z (- target.z0 1)
   :max-cell-x target.x1
   :max-cell-z target.z1})

(fn cell-points [record chunk-map cell-x cell-z]
  (local p00 (HeightfieldTerrainGrid.sample-local-point record chunk-map cell-x cell-z))
  (local p01 (HeightfieldTerrainGrid.sample-local-point record chunk-map cell-x (+ cell-z 1)))
  (local p10 (HeightfieldTerrainGrid.sample-local-point record chunk-map (+ cell-x 1) cell-z))
  (local p11 (HeightfieldTerrainGrid.sample-local-point record chunk-map (+ cell-x 1) (+ cell-z 1)))
  (if (and p00 p01 p10 p11)
      {:p00 p00 :p01 p01 :p10 p10 :p11 p11}
      nil))

(fn cell-present? [record chunk-map cell-x cell-z]
  (not (= (cell-points record chunk-map cell-x cell-z) nil)))

(fn append-border-segment [positions colors p0 p1 half-thickness color]
  (local delta (glm.vec3 (- p1.x p0.x) 0 (- p1.z p0.z)))
  (local delta-length (glm.length delta))
  (when (> delta-length 1e-6)
    (local normal (* (/ 1.0 delta-length) (glm.vec3 (- delta.z) 0 delta.x)))
    (local offset (* normal (glm.vec3 half-thickness)))
    (local v0 (- p0 offset))
    (local v1 (+ p0 offset))
    (local v2 (- p1 offset))
    (local v3 (+ p1 offset))
    (append-triangle positions colors v0 v1 v2 color)
    (append-triangle positions colors v2 v1 v3 color)))

(fn build-fill-mesh [record chunk-map target origin-offset fill-color lift]
  (local positions [])
  (local colors [])
  (local bounds (affected-cell-bounds target))
  (for [cell-x bounds.min-cell-x bounds.max-cell-x]
    (for [cell-z bounds.min-cell-z bounds.max-cell-z]
      (local points (cell-points record chunk-map cell-x cell-z))
      (when points
        (append-triangle positions colors
                         (rebase-local-point points.p00 origin-offset lift)
                         (rebase-local-point points.p01 origin-offset lift)
                         (rebase-local-point points.p10 origin-offset lift)
                         fill-color)
        (append-triangle positions colors
                         (rebase-local-point points.p10 origin-offset lift)
                         (rebase-local-point points.p01 origin-offset lift)
                         (rebase-local-point points.p11 origin-offset lift)
                         fill-color))))
  {:positions positions
   :colors colors})

(fn build-border-mesh [record chunk-map target origin-offset border-color lift]
  (local sample-spacing (HeightfieldTerrainGrid.spacing record))
  (local thickness (* 0.12 (math.min (. sample-spacing 1) (. sample-spacing 2))))
  (local half-thickness (/ thickness 2.0))
  (local positions [])
  (local colors [])
  (local bounds (affected-cell-bounds target))
  (for [cell-x bounds.min-cell-x bounds.max-cell-x]
    (for [cell-z bounds.min-cell-z bounds.max-cell-z]
      (local points (cell-points record chunk-map cell-x cell-z))
      (when points
        (when (not (cell-present? record chunk-map cell-x (- cell-z 1)))
          (append-border-segment positions colors
                                 (rebase-local-point points.p00 origin-offset lift)
                                 (rebase-local-point points.p10 origin-offset lift)
                                 half-thickness
                                 border-color))
        (when (not (cell-present? record chunk-map cell-x (+ cell-z 1)))
          (append-border-segment positions colors
                                 (rebase-local-point points.p01 origin-offset lift)
                                 (rebase-local-point points.p11 origin-offset lift)
                                 half-thickness
                                 border-color))
        (when (not (cell-present? record chunk-map (- cell-x 1) cell-z))
          (append-border-segment positions colors
                                 (rebase-local-point points.p00 origin-offset lift)
                                 (rebase-local-point points.p01 origin-offset lift)
                                 half-thickness
                                 border-color))
        (when (not (cell-present? record chunk-map (+ cell-x 1) cell-z))
          (append-border-segment positions colors
                                 (rebase-local-point points.p10 origin-offset lift)
                                 (rebase-local-point points.p11 origin-offset lift)
                                 half-thickness
                                 border-color)))))
  {:positions positions
   :colors colors})

(fn HeightfieldTerrainSelectionOverlay [ctx opts]
  (local options (or opts {}))
  (local record (assert options.record
                        "HeightfieldTerrainSelectionOverlay requires :record"))
  (local origin-offset (or options.origin-offset (glm.vec3 0 0 0)))
  (local chunk-map (HeightfieldTerrainGrid.build-chunk-map record))
  (local fill-buffer (make-triangle-buffer ctx))
  (local border-buffer (make-triangle-buffer ctx))
  (var selection-target nil)
  (var preview-target nil)
  (var fill-mesh {:positions [] :colors []})
  (var border-mesh {:positions [] :colors []})
  (var last-theme-ref nil)
  (var last-fill-color nil)
  (var last-border-color nil)

  (fn effective-target []
    (or preview-target selection-target))

  (fn rebuild-meshes []
    (local active-target (effective-target))
    (if active-target
        (do
          (set last-theme-ref (resolve-active-theme))
          (local colors (resolve-selection-colors))
          (local sample-spacing (HeightfieldTerrainGrid.spacing record))
          (local lift (* 0.01 (math.min (. sample-spacing 1) (. sample-spacing 2))))
          (set last-fill-color colors.fill)
          (set last-border-color colors.border)
          (set fill-mesh (build-fill-mesh record chunk-map active-target origin-offset colors.fill lift))
          (set border-mesh (build-border-mesh record chunk-map active-target origin-offset colors.border (* lift 1.5)))
          (fill-buffer:set-mesh fill-mesh)
          (border-buffer:set-mesh border-mesh))
        (do
          (set last-theme-ref nil)
          (set last-fill-color nil)
          (set last-border-color nil)
          (set fill-mesh {:positions [] :colors []})
          (set border-mesh {:positions [] :colors []})
          (fill-buffer:set-mesh fill-mesh)
          (border-buffer:set-mesh border-mesh))))

  {:get-selection-target (fn [_self]
                           (clone-target selection-target))
   :get-preview-target (fn [_self]
                         (clone-target preview-target))
   :has-active-target? (fn [_self]
                         (not (= (effective-target) nil)))
   :set-selection-target (fn [_self target]
                           (set selection-target
                                (if target
                                    (HeightfieldTerrainData.normalize-target record target)
                                    nil))
                           (set preview-target nil)
                           (rebuild-meshes)
                           selection-target)
   :clear-selection-target (fn [self]
                             (self:set-selection-target nil))
   :set-preview-target (fn [_self target]
                         (set preview-target
                              (if target
                                  (HeightfieldTerrainData.normalize-target record target)
                                  nil))
                         (rebuild-meshes)
                         preview-target)
   :clear-preview-target (fn [_self]
                           (when preview-target
                             (set preview-target nil)
                             (rebuild-meshes))
                           true)
   :refresh-theme! (fn [_self]
                     (if (and (effective-target)
                              (not (= (resolve-active-theme) last-theme-ref)))
                         (do
                           (rebuild-meshes)
                           true)
                         false))
   :update (fn [_self opts]
             (local depth-index (or opts.depth-index 0))
             (fill-buffer:update {:mesh fill-mesh
                                  :position opts.position
                                  :rotation opts.rotation
                                  :clip-region opts.clip-region
                                  :depth-index depth-index})
             (border-buffer:update {:mesh border-mesh
                                    :position opts.position
                                    :rotation opts.rotation
                                    :clip-region opts.clip-region
                                    :depth-index (+ depth-index 1)}))
   :drop (fn [_self]
           (fill-buffer:drop)
           (border-buffer:drop))})

HeightfieldTerrainSelectionOverlay
