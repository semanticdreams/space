(local glm (require :glm))
(local {: Layout} (require :layout))
(local bt (require :bt))
(local native (require :perlin-terrain-native))

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
    fallback))

(fn vec3-approx= [a b]
  (and a b
       (< (math.abs (- a.x b.x)) 1e-6)
       (< (math.abs (- a.y b.y)) 1e-6)
       (< (math.abs (- a.z b.z)) 1e-6)))

(fn quat-approx= [a b]
  (and a b
       (< (math.abs (- a.x b.x)) 1e-6)
       (< (math.abs (- a.y b.y)) 1e-6)
       (< (math.abs (- a.z b.z)) 1e-6)
       (< (math.abs (- a.w b.w)) 1e-6)))

(local PhysicsBridge {})

(fn PhysicsBridge.available? []
  (and bt app.engine app.engine.physics))

(set PhysicsBridge.create-static-mesh
     (fn [mesh opts]
       (if (not (PhysicsBridge.available?))
           nil
           (do
             (local triangle-mesh (bt.TriangleMesh))
             (mesh:add-to-triangle-mesh triangle-mesh opts.position opts.rotation opts.scale true)
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

(fn RenderBuffer [ctx mesh params]
  (assert (and ctx ctx.triangle-vector)
          "PerlinTerrain requires a triangle-vector in the build context")
  (local vector ctx.triangle-vector)
  (local float-count (mesh:float-count))
  (var handle nil)
  (local state {:visible? true
                :uploaded? false
                :clip-region nil
                :depth-index 0
                :position nil
                :rotation nil
                :scale params.scale
                :opacity params.opacity})

  (fn ensure-handle []
    (when (not handle)
      (set handle (vector:allocate float-count))
      (set state.uploaded? false)))

  (fn release-handle []
    (when handle
      (when (and ctx ctx.untrack-triangle-handle)
        (ctx:untrack-triangle-handle handle))
      (vector:delete handle)
      (set handle nil)
      (set state.uploaded? false)))

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
         (local position (or args.position (glm.vec3 0 0 0)))
         (local rotation (or args.rotation (glm.quat 1 0 0 0)))
         (local depth-index (or args.depth-index 0))
         (local clip-region args.clip-region)
         (local opacity (or args.opacity self.opacity))
         (local scale (or args.scale self.scale))
         (local dirty?
           (or (not self.uploaded?)
               (not (vec3-approx= self.position position))
               (not (quat-approx= self.rotation rotation))
               (not (vec3-approx= self.scale scale))
               (not (= self.depth-index depth-index))
               (not (= self.opacity opacity))))
         (when dirty?
           (mesh:write-to-vector-buffer vector handle position rotation scale opacity depth-index)
           (set self.uploaded? true)
           (set self.position position)
           (set self.rotation rotation)
           (set self.scale scale)
           (set self.depth-index depth-index)
           (set self.opacity opacity))
         (set self.clip-region clip-region)
         (when (and ctx ctx.track-triangle-handle)
           (ctx:track-triangle-handle handle clip-region))))

  (set state.drop (fn [_self]
                    (release-handle)))

  state)

(fn PerlinTerrain [opts]
  (local options (or opts {}))
  (local terrain-width (or options.width 50))
  (local terrain-length (or options.length 50))
  (local seed (or options.seed 1337))
  (local scale (resolve-glm-vec3 options.scale (glm.vec3 20 1 20)))
  (local position (resolve-glm-vec3 options.position (glm.vec3 500 -100 -500)))
  (local rotation (resolve-glm-quat options.rotation (glm.quat 1 0 0 0)))
  (local opacity (or options.opacity 1.0))
  (local enable-physics (if (= options.physics nil) true (not (not options.physics))))

  (local mesh
    (native.PerlinTerrainMesh {:width terrain-width
                               :length terrain-length
                               :seed seed
                               :n1div (or options.n1div 30)
                               :n2div (or options.n2div 4)
                               :n3div (or options.n3div 1)
                               :n1scale (or options.n1scale 20)
                               :n2scale (or options.n2scale 2)
                               :n3scale (or options.n3scale 1)
                               :zroot (or options.zroot 2)
                               :zpower (or options.zpower 2.5)}))

  (local terrain-height (* (- (mesh:max-height) (mesh:min-height)) scale.y))
  (local world-size (glm.vec3 (* (mesh:width) scale.x)
                              (math.max terrain-height 1.0)
                              (* (mesh:length) scale.z)))

  (fn build [ctx]
    (local renderable (RenderBuffer ctx mesh {:scale scale :opacity opacity}))
    (local physics
      (if enable-physics
          (PhysicsBridge.create-static-mesh mesh {:position position :rotation rotation :scale scale})
          nil))

    (fn measurer [self]
      (set self.measure world-size))

    (fn layouter [self]
      (local culled? (self:effective-culled?))
      (renderable:set-visible (not culled?))
      (when (not culled?)
        (renderable:update {:position self.position
                            :rotation self.rotation
                            :scale scale
                            :clip-region self.clip-region
                            :depth-index self.depth-offset-index
                            :opacity opacity})))

    (local layout (Layout {:name "perlin-terrain"
                           :measurer measurer
                           :layouter layouter}))
    (layout:set-position position)
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

PerlinTerrain
