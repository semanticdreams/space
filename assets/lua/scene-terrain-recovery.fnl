(local glm (require :glm))
(local MathUtils (require :math-utils))
(local BoundsUtils (require :bounds-utils))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainGrid (require :heightfield-terrain-grid))
(local LayoutPhysicsBodies (require :layout-physics-bodies))
(local TerrainQuery (require :terrain-query))
(local TerrainQueryRecord (require :terrain-query-record))

(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(local default-below-surface-threshold 1.0)
(local identity-bounds {:position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)
                        :size (glm.vec3 0 0 0)})

(fn binding-enabled? [binding]
  (and binding (not (= binding.enabled? false))))

(fn move-panel-element-origin-position [scene element next-position]
  (assert scene "SceneTerrainRecovery panel move requires scene")
  (assert element "SceneTerrainRecovery panel move requires element")
  (assert next-position "SceneTerrainRecovery panel move requires position")
  (local layout (and element element.layout))
  (assert layout "SceneTerrainRecovery panel move requires element layout")
  (if (LayoutPhysicsBodies.reposition-element (and scene scene.entity)
                                              element
                                              next-position
                                              layout.rotation)
      true
      (do
        (set layout.position next-position)
        (layout:mark-layout-dirty)
        true)))

(fn resolve-position [record]
  (array->vec3 (or (and record record.options record.options.position) [0 0 0])))

(fn resolve-rotation [record]
  (array->quat (or (and record record.options record.options.rotation) [1 0 0 0])))

(fn clamp [value min-value max-value]
  (math.max min-value (math.min max-value value)))

(fn terrain-domain-bounds [record]
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local sample-spacing (HeightfieldTerrainGrid.spacing record))
  {:min-x (* bounds.min-sample-x (. sample-spacing 1))
   :max-x (* bounds.max-sample-x (. sample-spacing 1))
   :min-z (* bounds.min-sample-z (. sample-spacing 2))
   :max-z (* bounds.max-sample-z (. sample-spacing 2))})

(fn world->local [record world-point]
  (local rotation (resolve-rotation record))
  (local inverse (rotation:inverse))
  (inverse:rotate (- world-point (resolve-position record))))

(fn local->world [record local-point]
  (local rotation (resolve-rotation record))
  (+ (resolve-position record)
     (rotation:rotate local-point)))

(fn lowest-surface-at-origin [scene origin]
  (var best nil)
  (each [_ metadata (ipairs (or (and scene scene.scene-terrains) []))]
    (local record (and metadata metadata.record))
    (local query-record (TerrainQueryRecord.from-metadata metadata))
    (local info
      (and query-record origin
           (TerrainQuery.surface-info-at-world-point query-record origin)))
    (when info
      (local world-surface-y (and info.world-point info.world-point.y))
      (when (and world-surface-y
                 (or (not best)
                     (< world-surface-y best.world-surface-y)))
        (set best {:terrain-record record
                   :query-record query-record
                   :world-point info.world-point
                   :world-surface-y world-surface-y
                   :local-point info.local-point
                   :local-surface-y info.local-surface-y}))))
  best)

(fn terrain-domain-bounds-world [record]
  (local bounds (terrain-domain-bounds record))
  {:min-x bounds.min-x
   :max-x bounds.max-x
   :min-z bounds.min-z
   :max-z bounds.max-z})

(fn nearest-surface-to-origin [scene origin]
  (var best nil)
  (each [_ metadata (ipairs (or (and scene scene.scene-terrains) []))]
    (local record (and metadata metadata.record))
    (local query-record (TerrainQueryRecord.from-metadata metadata))
    (when query-record
      (local bounds (terrain-domain-bounds-world query-record))
      (local local-point (world->local query-record origin))
      (local clamped-local-x (clamp local-point.x bounds.min-x bounds.max-x))
      (local clamped-local-z (clamp local-point.z bounds.min-z bounds.max-z))
      (local info
        (TerrainQuery.surface-info-at-local-point query-record clamped-local-x clamped-local-z))
      (when info
        (local world-point (local->world query-record info.local-point))
        (local dx (- world-point.x origin.x))
        (local dz (- world-point.z origin.z))
        (local horizontal-distance (math.sqrt (+ (* dx dx) (* dz dz))))
        (when (or (not best)
                  (< horizontal-distance best.horizontal-distance)
                  (and (= horizontal-distance best.horizontal-distance)
                       (< world-point.y best.world-surface-y)))
          (set best {:terrain-record record
                     :query-record query-record
                     :world-point world-point
                     :world-surface-y world-point.y
                     :local-point info.local-point
                     :local-surface-y info.local-surface-y
                     :horizontal-distance horizontal-distance})))))
  best)

(fn support-aabb [entry]
  (local get-support-bounds
    (assert entry.get-support-bounds
            "SceneTerrainRecovery entry requires :get-support-bounds"))
  (local bounds
    (assert (entry:get-support-bounds)
            "SceneTerrainRecovery support bounds must not be nil"))
  (BoundsUtils.bounds-aabb-min-max identity-bounds bounds))

(fn default-panel-entry [scene metadata]
  (local binding (and metadata metadata.terrain-binding))
  (local element (and metadata metadata.element))
  (local layout (and element element.layout))
  (if (and (binding-enabled? binding) element layout)
      {:owner element
       :element element
       :layout layout
       :get-origin-position
       (or binding.get-origin-position
           (fn [_entry]
             layout.position))
       :get-support-bounds
       (or binding.get-support-bounds
           (fn [_entry]
             {:position layout.position
              :rotation layout.rotation
              :size (or layout.size layout.measure (glm.vec3 0 0 0))}))
       :move-origin-position!
       (or binding.move-origin-position!
           (fn [_entry next-position]
             (move-panel-element-origin-position scene element next-position)))}
      nil))

(fn collect-entries [scene]
  (local entries [])
  (local by-owner {})
  (each [_ metadata (ipairs (or (and scene scene.scene-children) []))]
    (local entry (default-panel-entry scene metadata))
    (when entry
      (set (. by-owner entry.owner) entry)
      (table.insert entries entry)))
  (each [_ registered (ipairs (or (and scene scene.entity scene.entity.scene-objects) []))]
    (local binding (and registered registered.terrain-binding))
    (local owner (or (and registered registered.owner)
                     (and registered registered.element)))
    (when (and (binding-enabled? binding) owner)
      (local existing (. by-owner owner))
      (local next-entry {:owner owner
                         :element (or (and registered registered.element)
                                      (and existing existing.element))
                         :layout (or (and registered registered.element registered.element.layout)
                                     (and existing existing.layout))
                         :get-origin-position
                         (or binding.get-origin-position
                             (and existing existing.get-origin-position))
                         :get-support-bounds
                         (or binding.get-support-bounds
                             (and existing existing.get-support-bounds))
                         :move-origin-position!
                         (or binding.move-origin-position!
                             (and existing existing.move-origin-position!))})
      (assert next-entry.get-origin-position
              "SceneTerrainRecovery entry requires :get-origin-position")
      (assert next-entry.get-support-bounds
              "SceneTerrainRecovery entry requires :get-support-bounds")
      (assert next-entry.move-origin-position!
              "SceneTerrainRecovery entry requires :move-origin-position!")
      (if existing
          (do
            (set existing.element next-entry.element)
            (set existing.layout next-entry.layout)
            (set existing.get-origin-position next-entry.get-origin-position)
            (set existing.get-support-bounds next-entry.get-support-bounds)
            (set existing.move-origin-position! next-entry.move-origin-position!))
          (do
            (set (. by-owner owner) next-entry)
            (table.insert entries next-entry)))))
  entries)

(fn recover-entry! [scene entry opts]
  (local options (or opts {}))
  (local threshold (or options.below-surface-threshold default-below-surface-threshold))
  (local origin (entry:get-origin-position))
  (local aabb (support-aabb entry))
  (local bottom-offset-y (- aabb.min.y origin.y))
  (local bottom-y aabb.min.y)
  (local support (lowest-surface-at-origin scene origin))
  (if support
      (if (< bottom-y (- support.world-surface-y threshold))
          (do
            (entry:move-origin-position!
              (glm.vec3 origin.x
                        (- support.world-surface-y bottom-offset-y)
                        origin.z))
            {:entry entry
             :recovered? true
             :mode :vertical
             :target support})
          {:entry entry
           :recovered? false
           :mode :supported
           :target support})
      (do
        (local nearest (nearest-surface-to-origin scene origin))
        (if nearest
            (do
              (entry:move-origin-position!
                (glm.vec3 nearest.world-point.x
                          (- nearest.world-surface-y bottom-offset-y)
                          nearest.world-point.z))
              {:entry entry
               :recovered? true
               :mode :nearest
               :target nearest})
            {:entry entry
             :recovered? false
             :mode :no-terrain
             :target nil}))))

(fn recover [scene opts]
  (assert scene "SceneTerrainRecovery.recover requires scene")
  (when (and scene scene.update)
    (scene:update))
  (local results [])
  (each [_ entry (ipairs (collect-entries scene))]
    (table.insert results (recover-entry! scene entry opts)))
  (when (and scene scene.sync-physics-bodies)
    (scene:sync-physics-bodies))
  (when (and scene scene.sync-scene-objects)
    (scene:sync-scene-objects))
  results)

{:default-below-surface-threshold default-below-surface-threshold
 :collect-entries collect-entries
 :recover recover}
