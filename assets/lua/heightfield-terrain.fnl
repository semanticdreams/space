(local glm (require :glm))
(local {: Layout} (require :layout))
(local bt (require :bt))

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

(fn build-mesh [opts]
  (local chunks (or opts.chunks []))
  (local spacing (or opts.sample-spacing [20 20]))
  (local spacing-x (or (. spacing 1) spacing.x 20))
  (local spacing-z (or (. spacing 2) spacing.y spacing.z 20))
  (local positions [])
  (local colors [])
  (var min-local-x 0.0)
  (var min-local-z 0.0)
  (var max-local-x 0.0)
  (var max-local-z 0.0)
  (var min-height 0.0)
  (var max-height 0.0)
  (var first-height? true)

  (fn push-vertex [position color]
    (table.insert positions position)
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
	            (set max-height position.y))))
	    (when (< position.x min-local-x)
	      (set min-local-x position.x))
	    (when (< position.z min-local-z)
	      (set min-local-z position.z))
	    (when (> position.x max-local-x)
	      (set max-local-x position.x))
	    (when (> position.z max-local-z)
	      (set max-local-z position.z)))

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

  (local origin-offset (glm.vec3 min-local-x 0.0 min-local-z))
  (local rebased-positions
    (icollect [_ position (ipairs positions)]
      (glm.vec3 (- position.x min-local-x)
                position.y
                (- position.z min-local-z))))

  {:positions rebased-positions
   :colors colors
   :vertex-count (length positions)
   :origin-offset origin-offset
   :max-local-x (- max-local-x min-local-x)
   :max-local-z (- max-local-z min-local-z)
   :min-height min-height
   :max-height max-height})

(fn RenderBuffer [ctx mesh params]
  (assert (and ctx ctx.triangle-vector)
          "HeightfieldTerrain requires a triangle-vector in the build context")
  (local vector ctx.triangle-vector)
  (local vertex-count mesh.vertex-count)
  (local stride (* vertex-count 8))
  (var handle (vector:allocate stride))

  (fn ensure-handle []
    (when (not handle)
      (set handle (vector:allocate stride))))

  (fn release-handle []
    (when handle
      (when (and ctx ctx.untrack-triangle-handle)
        (ctx:untrack-triangle-handle handle))
      (vector:delete handle)
      (set handle nil)))

  (local state {:visible? true
                :opacity params.opacity
                :clip-region nil
                :depth-index 0})

  (set state.set-visible
       (fn [self visible?]
         (local desired (not (not visible?)))
         (when (not (= desired self.visible?))
           (set self.visible? desired)
           (if desired
               (ensure-handle)
               (release-handle)))))

  (set state.update
       (fn [self args]
         (when (not self.visible?)
           (self:set-visible true))
         (ensure-handle)
         (local rotation (or args.rotation (glm.quat 1 0 0 0)))
         (local position (or args.position (glm.vec3 0 0 0)))
         (local clip-region args.clip-region)
         (local depth-index (or args.depth-index 0))
         (local opacity (or args.opacity self.opacity))
         (set self.clip-region clip-region)
         (set self.depth-index depth-index)
         (for [i 1 vertex-count]
           (local vertex-offset (* (- i 1) 8))
           (local canonical (. mesh.positions i))
           (local rotated (rotation:rotate canonical))
           (local final-position (+ position rotated))
           (vector:set-glm-vec3 handle vertex-offset final-position)
           (local base-color (. mesh.colors i))
           (local final-color
             (glm.vec4 base-color.x base-color.y base-color.z (* base-color.w opacity)))
           (vector:set-glm-vec4 handle (+ vertex-offset 3) final-color)
           (vector:set-float handle (+ vertex-offset 7) depth-index))
         (when (and ctx ctx.track-triangle-handle)
           (ctx:track-triangle-handle handle clip-region))))

  (set state.drop (fn [_self]
                    (release-handle)))

  state)

(local PhysicsBridge {})

(fn PhysicsBridge.available? []
  (and bt app.engine app.engine.physics))

(fn PhysicsBridge.vec3->bt [value]
  (bt.Vector3 value.x value.y value.z))

(set PhysicsBridge.create-static-mesh
     (fn [mesh opts]
       (if (not (PhysicsBridge.available?))
           nil
           (do
             (local position (resolve-glm-vec3 opts.position (glm.vec3 0 0 0)))
             (local rotation (resolve-glm-quat opts.rotation (glm.quat 1 0 0 0)))
             (local triangle-mesh (bt.TriangleMesh))
             (for [i 1 mesh.vertex-count 3]
               (local v0 (+ position (rotation:rotate (. mesh.positions i))))
               (local v1 (+ position (rotation:rotate (. mesh.positions (+ i 1)))))
               (local v2 (+ position (rotation:rotate (. mesh.positions (+ i 2)))))
               (triangle-mesh:addTriangle (PhysicsBridge.vec3->bt v0)
                                          (PhysicsBridge.vec3->bt v1)
                                          (PhysicsBridge.vec3->bt v2)
                                          true))
             (local shape (bt.BvhTriangleMeshShape triangle-mesh true))
             (local transform (bt.Transform))
             (transform:setIdentity)
             (local motion-state (bt.DefaultMotionState transform))
             (local zero (bt.Vector3 0 0 0))
             (local info (bt.RigidBodyConstructionInfo 0 motion-state shape zero))
             (local body (bt.RigidBody info))
             (app.engine.physics:addRigidBody body)
             (local entry {:triangle-mesh triangle-mesh
                           :shape shape
                           :motion-state motion-state
                           :body body})
             (set entry.drop
                  (fn [self]
                    (when (and self.body (PhysicsBridge.available?))
                      (app.engine.physics:removeRigidBody self.body))
                    (set self.body nil)))
             entry))))

(fn HeightfieldTerrain [opts]
  (local options (or opts {}))
  (local position (resolve-glm-vec3 options.position (glm.vec3 0 -100 0)))
  (local rotation (resolve-glm-quat options.rotation (glm.quat 1 0 0 0)))
  (local opacity (or options.opacity 1.0))
  (local enable-physics (if (= options.physics nil) true (not (not options.physics))))
  (local mesh (build-mesh {:chunks options.chunks
                           :sample-spacing options.sample-spacing}))
  (local origin-offset (or mesh.origin-offset (glm.vec3 0 0 0)))
  (local layout-position (+ position (rotation:rotate origin-offset)))
  (local terrain-height (math.max (- mesh.max-height mesh.min-height) 1.0))
  (local world-size (glm.vec3 mesh.max-local-x
                              terrain-height
                              mesh.max-local-z))

  (fn build [ctx]
    (local renderable (RenderBuffer ctx mesh {:opacity opacity}))
    (local physics
      (if enable-physics
          (PhysicsBridge.create-static-mesh mesh {:position layout-position :rotation rotation})
          nil))

    (fn measurer [self]
      (set self.measure world-size))

    (fn layouter [self]
      (local culled? (self:effective-culled?))
      (renderable:set-visible (not culled?))
      (when (not culled?)
        (renderable:update {:position self.position
                            :rotation self.rotation
                            :clip-region self.clip-region
                            :depth-index self.depth-offset-index
                            :opacity opacity})))

    (local layout (Layout {:name "heightfield-terrain"
                           :measurer measurer
                           :layouter layouter}))
    (layout:set-position layout-position)
    (layout:set-rotation rotation)

    (fn drop [_self]
      (layout:drop)
      (renderable:drop)
      (when physics
        (physics:drop)))

    {:layout layout
     :drop drop
     :mesh mesh
     :physics physics}))

HeightfieldTerrain
