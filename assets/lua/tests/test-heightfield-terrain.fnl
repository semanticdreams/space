(local glm (require :glm))
(local bt (require :bt))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))
(local {: LayoutRoot} (require :layout))
(local Signal (require :signal))
(local HeightfieldTerrain (require :heightfield-terrain))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local TerrainRecords (require :scene-terrain-records))

(local tests [])

(fn make-heights [width depth value-fn]
  (local heights [])
  (for [z 0 (- depth 1)]
    (for [x 0 (- width 1)]
      (table.insert heights (value-fn x z))))
  heights)

(fn record-defaults-normalize-heightfield-data []
  (local record (TerrainRecords.default-record-for-kind "heightfield-terrain"))
  (assert (= record.kind "heightfield-terrain"))
  (assert (= (. record.options.chunk-samples 1) 17))
  (assert (= (. record.options.chunk-samples 2) 17))
  (assert (= (. record.options.sample-spacing 1) 20))
  (assert (= (. record.options.sample-spacing 2) 20))
  (assert (= (length record.chunks) 1))
    (local chunk (. record.chunks 1))
    (assert (= (. chunk.coord 1) 0))
    (assert (= (. chunk.coord 2) 0))
    (assert (= (length chunk.heights) (* 17 17))))

(fn record-normalizes-negative-chunk-coordinates []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :chunks [{:coord [-1 0]
                                                :size [17 17]}
                                               {:coord [0 -2]
                                                :size [17 17]}]}))
  (assert (= (length record.chunks) 2))
  (assert (= (. (. (. record.chunks 1) :coord) 1) -1))
  (assert (= (. (. (. record.chunks 2) :coord) 2) -2)))

(fn perlin-application-supports-negative-chunk-coordinates []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :chunks [{:coord [-1 0]
                                                :size [17 17]}
                                               {:coord [0 0]
                                                :size [17 17]}]}))
  (HeightfieldTerrainData.apply-perlin-record! record {:seed 99
                                                       :n1div 30
                                                       :n2div 4
                                                       :n3div 1
                                                       :n1scale 20
                                                       :n2scale 2
                                                       :n3scale 1
                                                       :zroot 2
                                                       :zpower 2.5})
  (local left-chunk (. record.chunks 1))
  (local right-chunk (. record.chunks 2))
  (assert (not (= (. left-chunk.heights 1) nil)))
  (assert (not (= (. right-chunk.heights 1) nil)))
  (assert (not (= (. left-chunk.heights 1) (. right-chunk.heights 1)))
          "negative chunk coordinates should still map to distinct perlin samples"))

(fn flat-fill-can-target-a_rectangle []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:chunk-samples [5 5]}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (HeightfieldTerrainData.fill-record! record 7.0 {:mode :rect
                                                   :x0 1
                                                   :z0 1
                                                   :x1 2
                                                   :z1 2})
  (local heights (. (. record.chunks 1) :heights))
  (assert (= (. heights 1) 0.0) "samples outside the rect should remain unchanged")
  (assert (= (. heights 7) 7.0) "rect fill should update sample [1,1]")
  (assert (= (. heights 8) 7.0) "rect fill should update sample [2,1]")
  (assert (= (. heights 12) 7.0) "rect fill should update sample [1,2]")
  (assert (= (. heights 13) 7.0) "rect fill should update sample [2,2]")
  (assert (= record.options.default-height 0.0)
          "rect fill should not rewrite default-height for future chunks"))

(fn perlin-application-can-target-a-rectangle []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:chunk-samples [5 5]}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (HeightfieldTerrainData.apply-perlin-record! record {:target {:mode :rect
                                                                :x0 1
                                                                :z0 1
                                                                :x1 3
                                                                :z1 3}
                                                       :seed 99
                                                       :n1div 30
                                                       :n2div 4
                                                       :n3div 1
                                                       :n1scale 20
                                                       :n2scale 2
                                                       :n3scale 1
                                                       :zroot 2
                                                       :zpower 2.5})
  (local heights (. (. record.chunks 1) :heights))
  (var changed-count 0)
  (each [idx value (ipairs heights)]
    (when (not (= value 0.0))
      (set changed-count (+ changed-count 1))))
  (assert (= (. heights 1) 0.0) "perlin rect should leave samples outside the target unchanged")
  (assert (> changed-count 0) "perlin rect should update at least one targeted sample")
  (assert (= record.options.default-height 0.0)
          "perlin rect should not rewrite default-height"))

(fn resize-preserves-overlapping-chunks-and-fills-new-ones []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:chunk-samples [5 5]
                                                :default-height 0.0}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [x z] (+ x (* z 10))))}]}))
  (HeightfieldTerrainData.resize-record! record {:min-chunk-x -1
                                                 :min-chunk-z 0
                                                 :max-chunk-x 1
                                                 :max-chunk-z 0
                                                 :fill-height 3.5})
  (assert (= (length record.chunks) 3) "resize should create the requested chunk coverage")
  (local left (. record.chunks 1))
  (local center (. record.chunks 2))
  (local right (. record.chunks 3))
  (assert (= (. left.coord 1) -1) "resize should include new negative chunk coverage")
  (assert (= (. center.coord 1) 0) "resize should preserve overlapping chunk coordinates")
  (assert (= (. right.coord 1) 1) "resize should include new positive chunk coverage")
  (assert (= (. center.heights 1) 0) "resize should preserve overlapping chunk data")
  (assert (= (. center.heights 25) 44) "resize should preserve all overlapping chunk samples")
  (assert (= (. left.heights 1) 3.5) "resize should fill new chunks with the requested fill height")
  (assert (= (. right.heights 25) 3.5) "resize should fill every sample in new chunks")
  (assert (= record.options.default-height 3.5) "resize should update default-height for future chunks"))

(fn adjust-height-supports-rectangles-and-whole-terrain []
  (local record
    (TerrainRecords.normalize-record {:kind "heightfield-terrain"
                                      :options {:chunk-samples [5 5]
                                                :default-height 1.0}
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights (make-heights 5 5 (fn [_x _z] 1.0))}]}))
  (HeightfieldTerrainData.adjust-record! record 2.0 {:mode :rect
                                                     :x0 1
                                                     :z0 1
                                                     :x1 2
                                                     :z1 2})
  (local heights (. (. record.chunks 1) :heights))
  (assert (= (. heights 1) 1.0) "adjust rect should leave outside samples unchanged")
  (assert (= (. heights 7) 3.0) "adjust rect should raise targeted samples")
  (assert (= record.options.default-height 1.0) "adjust rect should not rewrite default height")
  (HeightfieldTerrainData.adjust-record! record -1.5 {:mode :whole})
  (assert (= (. heights 1) -0.5) "whole adjust should affect every sample")
  (assert (= (. heights 7) 1.5) "whole adjust should apply on top of prior rect edits")
  (assert (= record.options.default-height -0.5) "whole adjust should update default height"))

(fn terrain-uploads-to-triangle-buffer []
  (var tracked 0)
  (var untracked 0)
  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector
              :track-triangle-handle (fn [_self _handle _clip] (set tracked (+ tracked 1)))
              :untrack-triangle-handle (fn [_self _handle] (set untracked (+ untracked 1)))})
  (local builder
    (HeightfieldTerrain {:position (glm.vec3 0 -3 0)
                         :physics false
                         :sample-spacing [2 2]
                         :chunks [{:coord [0 0]
                                   :size [5 5]
                                   :heights (make-heights 5 5 (fn [x z] (+ (* x 0.2) (* z 0.3))))}]}))
  (local entity (builder ctx))
  (local root (LayoutRoot {:log-dirt? false}))
  (entity.layout:set-root root)
  (root:update)

  (local vector-len (vector:length))
  (assert (> vector-len 0) "Heightfield terrain should upload triangle data")
  (local (dirty-from dirty-to) (vector:dirty-range))
  (assert (= dirty-from 0) "Heightfield terrain should dirty the vector from index zero")
  (assert (= dirty-to vector-len) "Heightfield terrain should dirty all uploaded data")
  (assert (> tracked 0) "Heightfield terrain should register a tracked triangle handle")

  (entity:drop)
  (assert (> untracked 0) "Heightfield terrain should untrack triangle handle on drop"))

(fn terrain-checker-pattern-alternates-across-chunk-seams []
  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector})
  (local builder
    (HeightfieldTerrain {:physics false
                         :sample-spacing [2 2]
                         :chunks [{:coord [0 0]
                                   :size [3 2]
                                   :heights (make-heights 3 2 (fn [_x _z] 0.0))}
                                  {:coord [1 0]
                                   :size [3 2]
                                   :heights (make-heights 3 2 (fn [_x _z] 0.0))}]}))
  (local entity (builder ctx))
  (local mesh entity.mesh)
  (local left-seam-color (. mesh.colors 7))
  (local right-seam-color (. mesh.colors 13))
  (assert left-seam-color "Expected a color for the last cell of the left chunk")
  (assert right-seam-color "Expected a color for the first cell of the right chunk")
  (assert (or (not (= left-seam-color.x right-seam-color.x))
              (not (= left-seam-color.y right-seam-color.y))
              (not (= left-seam-color.z right-seam-color.z)))
          "Checker pattern should alternate across chunk seams")
  (entity:drop))

(fn terrain-respects-array-rotation-from-record-data []
  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector})
  (local quarter-turn (glm.quat (/ math.pi 2) (glm.vec3 0 1 0)))
  (local builder
    (HeightfieldTerrain {:position [10 -4 20]
                         :rotation [quarter-turn.w quarter-turn.x quarter-turn.y quarter-turn.z]
                         :physics false
                         :sample-spacing [2 2]
                         :chunks [{:coord [-1 0]
                                   :size [3 2]
                                   :heights (make-heights 3 2 (fn [_x _z] 0.0))}]}))
  (local entity (builder ctx))
  (assert (< (math.abs (- entity.layout.rotation.w quarter-turn.w)) 1e-4)
          "heightfield runtime should preserve quaternion w from array rotation data")
  (assert (< (math.abs (- entity.layout.rotation.x quarter-turn.x)) 1e-4)
          "heightfield runtime should preserve quaternion x from array rotation data")
  (assert (< (math.abs (- entity.layout.rotation.y quarter-turn.y)) 1e-4)
          "heightfield runtime should preserve quaternion y from array rotation data")
  (assert (< (math.abs (- entity.layout.rotation.z quarter-turn.z)) 1e-4)
          "heightfield runtime should preserve quaternion z from array rotation data")
  (assert (< (math.abs (- entity.layout.position.x 10)) 1e-4)
          "heightfield runtime should rotate the origin offset into world x")
  (assert (< (math.abs (- entity.layout.position.z 24)) 1e-4)
          "heightfield runtime should rotate the origin offset into world z")
  (entity:drop))

(fn terrain-selection-overlay-follows-selection-target []
  (local original-themes app.themes)
  (set app.themes
       {:get-active-theme (fn []
                            {:terrain-selection {:fill (glm.vec4 0.2 0.5 0.9 0.2)
                                                 :border (glm.vec4 0.2 0.5 0.9 0.95)}})})
  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector})
  (local builder
    (HeightfieldTerrain {:physics false
                         :sample-spacing [2 2]
                         :chunk-samples [5 5]
                         :chunks [{:coord [0 0]
                                   :size [5 5]
                                   :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local entity (builder ctx))
  (local root (LayoutRoot {:log-dirt? false}))
  (entity.layout:set-root root)
  (root:update)
  (local base-length (vector:length))
  (entity:set-selection-target {:mode :rect
                                :x0 1
                                :z0 1
                                :x1 3
                                :z1 3})
  (root:update)
  (local selected-length (vector:length))
  (assert (> selected-length base-length)
          "terrain selection should add overlay triangles above the terrain mesh")
  (local target (entity:get-selection-target))
  (assert (= target.x0 1))
  (assert (= target.z1 3))
  (entity:set-preview-target {:mode :rect
                              :x0 0
                              :z0 0
                              :x1 1
                              :z1 1})
  (root:update)
  (local committed-while-previewing (entity:get-selection-target))
  (assert (= committed-while-previewing.x0 1)
          "preview should not overwrite the committed terrain selection")
  (entity:clear-preview-target)
  (root:update)
  (local committed-after-preview (entity:get-selection-target))
  (assert (= committed-after-preview.x0 1)
          "clearing preview should restore the committed terrain selection")
  (entity:clear-selection-target)
  (assert (= (entity:get-selection-target) nil)
          "terrain selection should clear the stored target")
  (entity:drop)
  (set app.themes original-themes))

(fn terrain-selection-overlay-reacts-to-theme-changes []
  (local original-themes app.themes)
  (local original-engine app.engine)
  (var current-fill (glm.vec4 0.2 0.5 0.9 0.2))
  (var current-border (glm.vec4 0.2 0.5 0.9 0.95))
  (set app.themes
       {:get-active-theme (fn []
                            {:terrain-selection {:fill current-fill
                                                 :border current-border}})})
  (set app.engine {:events {:updated (Signal)}})
  (local handle-state {:next-handle 1
                       :writes {}})
  (local vector
    {:allocate (fn [self size]
                 (local handle {:id handle-state.next-handle :size size})
                 (set handle-state.next-handle (+ handle-state.next-handle 1))
                 handle)
     :reallocate (fn [_self handle size]
                   (set handle.size size))
     :delete (fn [_self _handle] nil)
     :set-glm-vec3 (fn [_self _handle _offset _value] nil)
     :set-float (fn [_self _handle _offset _value] nil)
     :set-glm-vec4 (fn [_self handle offset value]
                     (local key (.. handle.id ":" offset))
                     (set (. handle-state.writes key)
                          [value.x value.y value.z value.w]))})
  (local ctx {:triangle-vector vector})
  (local builder
    (HeightfieldTerrain {:physics false
                         :sample-spacing [2 2]
                         :chunk-samples [5 5]
                         :chunks [{:coord [0 0]
                                   :size [5 5]
                                   :heights (make-heights 5 5 (fn [_x _z] 0.0))}]}))
  (local entity (builder ctx))
  (local root (LayoutRoot {:log-dirt? false}))
  (entity.layout:set-root root)
  (entity:set-selection-target {:mode :rect
                                :x0 1
                                :z0 1
                                :x1 2
                                :z1 2})
  (root:update)
  (local first-color (. handle-state.writes "2:3"))
  (assert first-color "selection overlay should write fill colors for its fill handle")
  (set current-fill (glm.vec4 0.85 0.25 0.18 0.33))
  (set current-border (glm.vec4 0.9 0.3 0.2 0.98))
  (app.engine.events.updated:emit 0.016)
  (root:update)
  (local changed-color (. handle-state.writes "2:3"))
  (assert changed-color "selection overlay should still write fill colors after theme change")
  (assert (not (= (. first-color 1) (. changed-color 1)))
          "selection overlay fill should update when the active theme changes")
  (entity:drop)
  (set app.engine original-engine)
  (set app.themes original-themes))

(fn heightfield-physics-catches-falling-body []
  (assert bt "Heightfield terrain physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (app.engine.physics:setGravity 0 -10 0)

  (local vector (VectorBuffer 0))
  (local ctx {:triangle-vector vector})
  (local terrain-builder
    (HeightfieldTerrain {:position (glm.vec3 0 -4 0)
                         :physics true
                         :sample-spacing [2 2]
                         :chunks [{:coord [0 0]
                                   :size [17 17]
                                   :heights (make-heights 17 17 (fn [_x _z] 0.0))}]}))
  (local terrain (terrain-builder ctx))

  (local start-height 18.0)
  (var fall-body nil)

  (fn cleanup []
    (when fall-body
      (app.engine.physics:removeRigidBody fall-body)
      (set fall-body nil))
    (terrain:drop))

  (local result
    (table.pack
      (pcall
        (fn []
          (local fall-shape (bt.BoxShape (bt.Vector3 1 1 1)))
          (local fall-transform (bt.Transform))
          (fall-transform:setIdentity)
          (fall-transform:setOrigin (bt.Vector3 8 start-height 8))
          (local fall-motion (bt.DefaultMotionState fall-transform))
          (local inertia (bt.Vector3 0 0 0))
          (fall-shape:calculateLocalInertia 1.0 inertia)
          (local fall-ci (bt.RigidBodyConstructionInfo 1.0 fall-motion fall-shape inertia))
          (set fall-body (bt.RigidBody fall-ci))
          (app.engine.physics:addRigidBody fall-body)

          (for [_ 1 180]
            (app.engine.physics:update 0))

          (local final-transform (fall-body:getCenterOfMassTransform))
          (local origin (final-transform:getOrigin))
          (assert (< origin.y start-height) "Body should move downward under gravity")
          (assert (> origin.y -20) "Body fell through heightfield terrain")))))
  (local ok (. result 1))
  (local err (. result 2))
  (cleanup)
  (when (not ok)
    (error err)))

(table.insert tests {:name "Heightfield terrain record defaults normalize chunk data"
                     :fn record-defaults-normalize-heightfield-data})
(table.insert tests {:name "Heightfield terrain record accepts negative chunk coordinates"
                     :fn record-normalizes-negative-chunk-coordinates})
(table.insert tests {:name "Heightfield terrain perlin supports negative chunk coordinates"
                     :fn perlin-application-supports-negative-chunk-coordinates})
(table.insert tests {:name "Heightfield terrain flat fill supports rectangular targets"
                     :fn flat-fill-can-target-a_rectangle})
(table.insert tests {:name "Heightfield terrain perlin supports rectangular targets"
                     :fn perlin-application-can-target-a-rectangle})
(table.insert tests {:name "Heightfield terrain resize preserves overlap and fills new chunks"
                     :fn resize-preserves-overlapping-chunks-and-fills-new-ones})
(table.insert tests {:name "Heightfield terrain adjust supports rectangles and whole terrain"
                     :fn adjust-height-supports-rectangles-and-whole-terrain})
(table.insert tests {:name "Heightfield terrain uploads triangle buffer data"
                     :fn terrain-uploads-to-triangle-buffer})
(table.insert tests {:name "Heightfield terrain checker pattern alternates across chunk seams"
                     :fn terrain-checker-pattern-alternates-across-chunk-seams})
(table.insert tests {:name "Heightfield terrain respects array rotation from record data"
                     :fn terrain-respects-array-rotation-from-record-data})
(table.insert tests {:name "Heightfield terrain selection overlay follows selection target"
                     :fn terrain-selection-overlay-follows-selection-target})
(table.insert tests {:name "Heightfield terrain selection overlay reacts to theme changes"
                     :fn terrain-selection-overlay-reacts-to-theme-changes})
(table.insert tests {:name "Heightfield terrain integrates with Bullet physics"
                     :fn heightfield-physics-catches-falling-body})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "heightfield-terrain"
                       :tests tests})))

{:name "heightfield-terrain"
 :tests tests
 :main main}
