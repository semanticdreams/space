(local glm (require :glm))
(local {: Layout} (require :layout))
(local HeightfieldTerrainSpace (require :heightfield-terrain-space))
(local HeightfieldTerrainSelectionOverlay (require :heightfield-terrain-selection-overlay))
(local HeightfieldTerrainPhysics (require :heightfield-terrain-physics))
(local {: StaticTriangleBuffer} (require :static-triangle-buffer))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn resolve-glm-vec3 [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :number) (glm.vec3 value value value)
    (= (type value) :table)
      (do
        (local x (or (. value 1) value.x (. value "x") 0))
        (local y (or (. value 2) value.y (. value "y") 0))
        (local z (or (. value 3) value.z (. value "z") 0))
        (glm.vec3 x y z))
    fallback))

(fn resolve-glm-quat [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :table)
      (do
        (local w (or (. value 1) value.w 1))
        (local x (or (. value 2) value.x 0))
        (local y (or (. value 3) value.y 0))
        (local z (or (. value 4) value.z 0))
        (glm.quat w x y z))
    fallback))

(fn chunk-xy [chunk]
  (local coord (or chunk.coord [0 0]))
  [(or (. coord 1) coord.x 0)
   (or (. coord 2) coord.y coord.z 0)])

(fn chunk-size [chunk]
  (local size (or chunk.size [17 17]))
  [(or (. size 1) size.x 17)
   (or (. size 2) size.y size.z 17)])

(fn chunk-height [chunk sample-x sample-z]
  (local size (chunk-size chunk))
  (local width (. size 1))
  (local heights (or chunk.heights []))
  (local idx (+ (* sample-z width) sample-x 1))
  (or (. heights idx) 0.0))

(fn quat->array [rotation]
  [rotation.w rotation.x rotation.y rotation.z])

(fn vec3->array [value]
  [value.x value.y value.z])

(fn checker-color [cell-x cell-z avg-height]
  (local base
    (if (= (% (+ cell-x cell-z) 2) 0)
        (glm.vec4 0.24 0.47 0.26 1.0)
        (glm.vec4 0.31 0.56 0.32 1.0)))
  (local tint
    (if (finite-number? avg-height)
        (math.max -0.08 (math.min 0.08 (* avg-height 0.02)))
        0.0))
  (glm.vec4 (math.max 0.0 (math.min 1.0 (+ base.x tint)))
            (math.max 0.0 (math.min 1.0 (+ base.y tint)))
            (math.max 0.0 (math.min 1.0 (+ base.z tint)))
            1.0))

(fn build-mesh [record]
  (local chunks (or record.chunks []))
  (local spacing (or (and record.options record.options.sample-spacing) [20 20]))
  (local spacing-x (or (. spacing 1) spacing.x 20))
  (local spacing-z (or (. spacing 2) spacing.y spacing.z 20))
  (local bounds (HeightfieldTerrainSpace.canonical-domain-bounds record))
  (local positions [])
  (local colors [])
  (var min-height 0.0)
  (var max-height 0.0)
  (var first-height? true)

  (fn push-vertex [position color]
    (table.insert positions
                  (HeightfieldTerrainSpace.canonical-local->runtime-local record position))
    (table.insert colors color)
    (if first-height?
        (do
          (set min-height position.y)
          (set max-height position.y)
          (set first-height? false))
        (do
          (when (< position.y min-height)
            (set min-height position.y))
          (when (> position.y max-height)
            (set max-height position.y)))))

  (each [_ chunk (ipairs chunks)]
    (local coord (chunk-xy chunk))
    (local size (chunk-size chunk))
    (local chunk-width (. size 1))
    (local chunk-length (. size 2))
    (local base-x (* (. coord 1) (- chunk-width 1) spacing-x))
    (local base-z (* (. coord 2) (- chunk-length 1) spacing-z))
    (for [sample-x 0 (- chunk-width 2)]
      (for [sample-z 0 (- chunk-length 2)]
        (local world-x (+ base-x (* sample-x spacing-x)))
        (local world-z (+ base-z (* sample-z spacing-z)))
        (local p00 (glm.vec3 world-x
                             (chunk-height chunk sample-x sample-z)
                             world-z))
        (local p01 (glm.vec3 world-x
                             (chunk-height chunk sample-x (+ sample-z 1))
                             (+ world-z spacing-z)))
        (local p10 (glm.vec3 (+ world-x spacing-x)
                             (chunk-height chunk (+ sample-x 1) sample-z)
                             world-z))
        (local p11 (glm.vec3 (+ world-x spacing-x)
                             (chunk-height chunk (+ sample-x 1) (+ sample-z 1))
                             (+ world-z spacing-z)))
        (local avg-height (/ (+ p00.y p01.y p10.y p11.y) 4.0))
        (local global-cell-x (+ (* (. coord 1) (- chunk-width 1)) sample-x))
        (local global-cell-z (+ (* (. coord 2) (- chunk-length 1)) sample-z))
        (local color (checker-color global-cell-x global-cell-z avg-height))
        (push-vertex p00 color)
        (push-vertex p01 color)
	        (push-vertex p10 color)
	        (push-vertex p10 color)
	        (push-vertex p01 color)
	        (push-vertex p11 color))))

  {:positions positions
   :colors colors
   :vertex-count (length positions)
   :max-local-x (- bounds.max-x bounds.min-x)
   :max-local-z (- bounds.max-z bounds.min-z)
   :min-height min-height
   :max-height max-height})

(fn RenderBuffer [ctx mesh params]
  (StaticTriangleBuffer ctx {:positions mesh.positions
                             :colors mesh.colors
                             :opacity params.opacity}))

(fn build-heightfield-record [opts position rotation]
  {:kind "heightfield-terrain"
   :options {:position (vec3->array position)
             :rotation (quat->array rotation)
             :sample-spacing (or opts.sample-spacing [20 20])
             :chunk-samples (or opts.chunk-samples
                                (and (. (or opts.chunks []) 1)
                                     (. (. (or opts.chunks []) 1) :size))
                                [17 17])}
   :chunks (or opts.chunks [])})

(fn HeightfieldTerrain [opts]
  (local options (or opts {}))
  (local position (resolve-glm-vec3 options.position (glm.vec3 0 -100 0)))
  (local rotation (resolve-glm-quat options.rotation (glm.quat 1 0 0 0)))
  (local opacity (or options.opacity 1.0))
  (local enable-physics (if (= options.physics nil) true (not (not options.physics))))
  (local terrain-record (build-heightfield-record options position rotation))
  (local mesh (build-mesh terrain-record))
  (local layout-position
    (HeightfieldTerrainSpace.runtime-layout-position terrain-record position rotation))
  (local terrain-height (math.max (- mesh.max-height mesh.min-height) 1.0))
  (local world-size (glm.vec3 mesh.max-local-x
                              terrain-height
                              mesh.max-local-z))

  (fn build [ctx]
    (local renderable (RenderBuffer ctx mesh {:opacity opacity}))
    (local selection-overlay (HeightfieldTerrainSelectionOverlay ctx {:record terrain-record}))
    (var updated-handler nil)
    (local physics
      (if enable-physics
          (HeightfieldTerrainPhysics.create-heightfield terrain-record)
          nil))

    (fn measurer [self]
      (set self.measure world-size))

    (fn layouter [self]
      (when (and physics physics.sync-layout-transform)
        (physics:sync-layout-transform self.position self.rotation))
      (local culled? (self:effective-culled?))
      (renderable:set-visible (not culled?))
      (when (not culled?)
        (renderable:update {:position self.position
                            :rotation self.rotation
                            :clip-region self.clip-region
                            :depth-index self.depth-offset-index
                            :opacity opacity}))
      (selection-overlay:update {:position self.position
                                 :rotation self.rotation
                                 :clip-region self.clip-region
                                 :depth-index (+ self.depth-offset-index 1)}))

    (local layout (Layout {:name "heightfield-terrain"
                           :measurer measurer
                           :layouter layouter}))
    (layout:set-position layout-position)
    (layout:set-rotation rotation)

    (set updated-handler
         (and app.engine
              app.engine.events
              app.engine.events.updated
              (app.engine.events.updated:connect
                (fn [_delta]
                  (when (selection-overlay:refresh-theme!)
                    (layout:mark-layout-dirty))))))

    (fn drop [_self]
      (when (and app.engine
                 app.engine.events
                 app.engine.events.updated
                 updated-handler)
        (app.engine.events.updated:disconnect updated-handler true)
        (set updated-handler nil))
      (layout:drop)
      (renderable:drop)
      (selection-overlay:drop)
      (when physics
        (physics:drop)))

    {:layout layout
     :drop drop
     :mesh mesh
     :get-local-bounds (fn [_self]
                         {:min (glm.vec3 0 mesh.min-height 0)
                          :max (glm.vec3 mesh.max-local-x
                                         mesh.max-height
                                         mesh.max-local-z)})
     :set-selection-target (fn [self target]
                             (selection-overlay:set-selection-target target)
                             (when self.layout
                               (self.layout:mark-layout-dirty))
                             true)
     :clear-selection-target (fn [self]
                               (selection-overlay:clear-selection-target)
                               (when self.layout
                                 (self.layout:mark-layout-dirty))
                               true)
     :get-selection-target (fn [_self]
                             (selection-overlay:get-selection-target))
     :physics physics}))

HeightfieldTerrain
