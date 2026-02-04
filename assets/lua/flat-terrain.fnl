(local glm (require :glm))
(local {: Layout} (require :layout))

(local colors (require :colors))
(local bt (require :bt))
(fn resolve-glm-vec3 [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :number) (glm.vec3 value value value)
    (= (type value) :table)
      (let [x (or (. value 1) value.x (. value "x") 0)
            y (or (. value 2) value.y (. value "y") 0)
            z (or (. value 3) value.z (. value "z") 0)]
        (glm.vec3 x y z))
    fallback))

(fn resolve-glm-vec4 [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :table)
      (let [r (or (. value 1) value.r (. value "r") 0)
            g (or (. value 2) value.g (. value "g") 0)
            b (or (. value 3) value.b (. value "b") 0)
            a (or (. value 4) value.a (. value "a") 1)]
        (glm.vec4 r g b a))
    fallback))

(fn resolve-glm-quat [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    fallback))

(local vertex-pattern
  [[0 0]
   [1 0]
   [0 1]
   [1 0]
   [1 1]
   [0 1]])

(local MeshBuilder {})

(set MeshBuilder.generate
     (fn [opts]
       (local grid-width (math.max 1 (math.floor (or opts.width 1))))
       (local grid-length (math.max 1 (math.floor (or opts.length 1))))
       (local colors {:dark (or opts.dark (glm.vec4 0.3 0.3 0.3 1.0))
                      :light (or opts.light (glm.vec4 0.7 0.7 0.7 1.0))})
       (local positions [])
       (local color-buffer [])
       (for [x 0 (- grid-width 1)]
         (for [z 0 (- grid-length 1)]
           (local checker (% (+ x z) 2))
           (local color (if (= checker 0) colors.dark colors.light))
           (each [_ offset (ipairs vertex-pattern)]
             (local px (+ x (. offset 1)))
             (local pz (+ z (. offset 2)))
             (table.insert positions (glm.vec3 px 0 pz))
             (table.insert color-buffer color))))
       {:positions positions
        :colors color-buffer
        :vertex-count (length positions)
        :width grid-width
        :length grid-length}))

(fn RenderBuffer [ctx mesh params]
       (assert (and ctx ctx.triangle-vector)
               "FlatTerrain requires a triangle-vector in the build context")
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
                     :scale params.scale
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
              (local scale self.scale)
              (local opacity (or args.opacity self.opacity))
              (set self.clip-region clip-region)
              (set self.depth-index depth-index)
              (for [i 1 vertex-count]
                (local vertex-offset (* (- i 1) 8))
                (local canonical (. mesh.positions i))
                (local scaled
                  (glm.vec3 (* canonical.x scale.x)
                        (* canonical.y scale.y)
                        (* canonical.z scale.z)))
                (local rotated (rotation:rotate scaled))
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

(set PhysicsBridge.create-plane
     (fn [opts]
       (if (not (PhysicsBridge.available?))
           nil
           (let [normal (PhysicsBridge.vec3->bt opts.normal)
                  constant (or opts.constant 0)
                 transform (bt.Transform)]
             (transform:setIdentity)
             (transform:setOrigin (PhysicsBridge.vec3->bt opts.position))
             (local shape (bt.StaticPlaneShape normal constant))
             (local motion-state (bt.DefaultMotionState transform))
             (local zero (bt.Vector3 0 0 0))
             (local info (bt.RigidBodyConstructionInfo 0 motion-state shape zero))
             (local body (bt.RigidBody info))
             (app.engine.physics:addRigidBody body)
             (local plane {:shape shape
                           :motion-state motion-state
                           :body body})
             (set plane.drop
                  (fn [self]
                    (when (and (PhysicsBridge.available?) self.body)
                      (app.engine.physics:removeRigidBody self.body))
                    (set self.body nil)))
             plane))))

(fn FlatTerrain [opts]
  (local options (or opts {}))
  (local terrain-width (or options.width 50))
  (local terrain-length (or options.length 50))
  (local scale (resolve-glm-vec3 options.scale (glm.vec3 20 1 20)))
  (local position (resolve-glm-vec3 options.position (glm.vec3 -500 -100 -500)))
  (local rotation (resolve-glm-quat options.rotation (glm.quat 1 0 0 0)))
  (local opacity (or options.opacity 1.0))

  (local theme (and app.themes app.themes.get-active-theme (app.themes.get-active-theme)))
  (local theme-colors (and theme theme.flat-terrain))
  (local colors {:dark (resolve-glm-vec4 (and options.colors options.colors.dark)
                                        (resolve-glm-vec4 (and theme-colors theme-colors.dark)
                                                          (glm.vec4 0.3 0.3 0.3 1.0)))
                 :light (resolve-glm-vec4 (and options.colors options.colors.light)
                                         (resolve-glm-vec4 (and theme-colors theme-colors.light)
                                                           (glm.vec4 0.7 0.7 0.7 1.0)))})

  (local mesh (MeshBuilder.generate {:width terrain-width
                                     :length terrain-length
                                     :dark colors.dark
                                     :light colors.light}))

  (local world-size (glm.vec3 (* mesh.width scale.x)
                          scale.y
                          (* mesh.length scale.z)))

  (fn build [ctx]
    (local renderable (RenderBuffer ctx mesh {:scale scale :opacity opacity}))
    (local plane
      (PhysicsBridge.create-plane {:normal (resolve-glm-vec3 options.plane-normal (glm.vec3 0 1 0))
                                   :position (resolve-glm-vec3 options.plane-position (glm.vec3 0 position.y 0))
                                   :constant (or options.plane-constant 0)}))

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

    (local layout (Layout {:name "flat-terrain"
                           :measurer measurer
                           :layouter layouter}))
    (layout:set-position position)
    (layout:set-rotation rotation)

    (fn drop [_self]
      (layout:drop)
      (renderable:drop)
      (when plane
        (plane:drop)))

    {:layout layout
     :drop drop}))

FlatTerrain
