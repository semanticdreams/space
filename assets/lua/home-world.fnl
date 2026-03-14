(local glm (require :glm))
(local fs (require :fs))
(local json (require :json))
(local logging (require :logging))
(local JsonUtils (require :json-utils))
(local Camera (require :camera))
(local Scene (require :scene))
(local {: FirstPersonControls} (require :first-person-controls))
(local Graph (require :graph/init))
(local GraphView (require :graph/view))
(local GraphKeyLoaders (require :graph/key-loaders))
(local ObjectSelector (require :object-selector))
(local MathUtils (require :math-utils))
(local CoordinateGuard (require :coordinate-guard))
(local PhysicsFloor (require :physics-floor))
(local TerrainRecords (require :scene-terrain-records))

(local vec3->array (. MathUtils :vec3->array))
(local quat->array (. MathUtils :quat->array))
(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))
(local safe-vec3? CoordinateGuard.safe-vec3?)
(local sanitize-vec3 CoordinateGuard.sanitize-vec3)
(local finite-number? CoordinateGuard.finite-number?)

(local default-floor-y PhysicsFloor.default-floor-y)

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn merge-state-defaults [defaults persisted]
  (if (not (= (type defaults) :table))
      (if (= persisted nil) defaults persisted)
      (do
        (local out {})
        (local source
          (if (= (type persisted) :table)
              persisted
              {}))
        (each [k v (pairs defaults)]
          (set (. out k) (merge-state-defaults v (. source k))))
        (each [k v (pairs source)]
          (when (= (. out k) nil)
            (set (. out k) (clone-table v))))
        out)))

(fn default-state []
  {:camera {:position [0 0 30]
            :rotation [1 0 0 0]}
   :physics {:floor-y default-floor-y}
   :graph {:graph {:nodes []
                   :edges []}
           :views {:open-node-keys []}}
   :scene {:panels []
           :terrains []}
   :hud {:panels []}})

(fn resolve-graph-core-state [state]
  (local payload (or state {}))
  (if (and (= (type payload.graph) :table))
      payload.graph
      {:nodes (or payload.nodes [])
       :edges (or payload.edges [])}))

(fn resolve-graph-views-state [state]
  (local payload (or state {}))
  (if (and (= (type payload.views) :table))
      payload.views
      (if (and (= (type payload.open-node-keys) :table))
          {:open-node-keys payload.open-node-keys}
          {})))

(fn read-world-state [path]
  (if (not (fs.exists path))
      nil
      (do
        (local (ok-read content) (pcall fs.read-file path))
        (if (not ok-read)
            (error (string.format "HomeWorld failed to read %s: %s" path content))
            (do
              (local (ok-parse decoded) (pcall json.loads content))
              (when (not ok-parse)
                (error (string.format "HomeWorld failed to parse %s: %s" path decoded)))
              (when (not (= (type decoded) :table))
                (error (string.format "HomeWorld expected table in %s" path)))
              decoded)))))

(fn HomeWorld [opts]
  (local options (or opts {}))
  (local id (assert options.id "HomeWorld requires :id"))
  (local name (or options.name "home"))
  (local type-name (or options.type "home"))
  (local dir (assert options.dir "HomeWorld requires :dir"))
  (local state-path (fs.join-path dir "world.json"))

  (local self {:id id
               :name name
               :type type-name
               :dir dir
               :state-path state-path
               :state (default-state)
               :active? false
               :initialized? false
               :runtime nil})

  (fn ensure-world-dir []
    (local (ok err) (pcall fs.create-dirs dir))
    (when (not ok)
      (error (string.format "HomeWorld failed to create %s: %s" dir err))))

  (fn load-state [world]
    (local persisted (read-world-state world.state-path))
    (set world.state (merge-state-defaults (default-state) persisted))
    (when (not persisted)
      (when (not world.state.scene)
        (set world.state.scene {}))
      (set world.state.scene.terrains (TerrainRecords.default-records)))
    (local camera-state (or (and world.state world.state.camera) {}))
    (local raw-position camera-state.position)
    (local (ok parsed-position) (pcall array->vec3 raw-position))
    (local camera-position
      (if ok
          parsed-position
          nil))
    (if (safe-vec3? camera-position)
        (set camera-state.position (vec3->array camera-position))
        (do
          (logging.warn (string.format
                          "[world] %s invalid persisted camera.position; resetting to default"
                          world.id))
          (set camera-state.position [0 0 30])))
    (set world.state.camera camera-state)
    (local physics-state (or (and world.state world.state.physics) {}))
    (local floor-y physics-state.floor-y)
    (if (finite-number? floor-y)
        (set physics-state.floor-y floor-y)
        (do
          (logging.warn (string.format
                          "[world] %s invalid persisted physics.floor-y; resetting to default"
                          world.id))
          (set physics-state.floor-y default-floor-y)))
    (set world.state.physics physics-state))

  (fn save-state [world]
    (ensure-world-dir)
    (local (ok err) (pcall (fn [] (JsonUtils.write-json! world.state-path world.state))))
    (when (not ok)
      (error (string.format "HomeWorld failed to write %s: %s" world.state-path err)))
    true)

  (fn resolve-runtime-floor-y [world]
    (local runtime world.runtime)
    (local runtime-floor (and runtime runtime.physics-floor-y))
    (local state-floor (and world.state world.state.physics world.state.physics.floor-y))
    (if (finite-number? runtime-floor)
        runtime-floor
        (if (finite-number? state-floor)
            state-floor
            default-floor-y)))

  (fn apply-runtime-floor! [world]
    (local floor-y (resolve-runtime-floor-y world))
    (set app.physics-floor-y floor-y)
    (PhysicsFloor.ensure-installed {:floor-y floor-y})
    (when world.state
      (when (not world.state.physics)
        (set world.state.physics {}))
      (set world.state.physics.floor-y floor-y))
    (when world.runtime
      (set world.runtime.physics-floor-y floor-y))
    floor-y)

  (fn capture-runtime-state [world ctx]
    (local runtime world.runtime)
    (local camera (and runtime runtime.camera))
    (local scene (and runtime runtime.scene))
    (local graph-view (and runtime runtime.graph-view))
    (local hud (and ctx ctx.hud))
    (when camera
      (local position (sanitize-vec3 camera.position (glm.vec3 0 0 30)))
      (when (not (= position camera.position))
        (logging.warn (string.format
                        "[world] %s camera position out of bounds during capture; resetting to default"
                        world.id)))
      (set world.state.camera
           {:position (vec3->array position)
            :rotation (quat->array camera.rotation)}))
    (when (and graph-view graph-view.capture-state)
      (set world.state.graph (graph-view:capture-state)))
    (when (and scene scene.capture-state)
      (set world.state.scene (scene:capture-state)))
    (when (and hud hud.capture-state)
      (set world.state.hud (hud:capture-state)))
    (local floor-y (resolve-runtime-floor-y world))
    (local physics-state (or world.state.physics {}))
    (set physics-state.floor-y floor-y)
    (set world.state.physics physics-state))

  (fn queue-runtime-restore-state [world]
    (local runtime world.runtime)
    (when runtime
      (set runtime.pending-graph-views-state
           (clone-table (resolve-graph-views-state (and world.state world.state.graph))))
      (set runtime.pending-hud-state
           (clone-table (and world.state world.state.hud)))))

  (fn create-runtime [world ctx]
    (local camera-state (or (and world.state world.state.camera) {}))
    (local floor-y (apply-runtime-floor! world))
    (local (ok parsed-camera-position) (pcall array->vec3 camera-state.position))
    (local loaded-camera-position
      (if ok
          parsed-camera-position
          nil))
    (local camera-position
      (sanitize-vec3 loaded-camera-position
                     (glm.vec3 0 0 30)))
    (when (not (= camera-position loaded-camera-position))
      (logging.warn (string.format
                      "[world] %s invalid camera restore position; using default"
                      world.id)))
    (local camera (Camera {:position camera-position}))
    (local rotation (array->quat camera-state.rotation))
    (when rotation
      (camera:set-rotation rotation))

    (local controls (FirstPersonControls {:camera camera}))
    (local graph (Graph {}))
    (GraphKeyLoaders.register graph)
    (local scene-scope (ctx.focus-manager:create-scope {:name (.. "scene:" world.id)
                                                        :directional-traversal-boundary? true}))
    (ctx.focus-manager:attach scene-scope ctx.focus-root)
    (local scene
      (Scene {:focus-manager ctx.focus-manager
              :focus-scope scene-scope
              :icons ctx.icons
              :states ctx.states
              :movables ctx.movables
              :graph graph}))
    (local object-selector
      (ObjectSelector {:ctx (and ctx.hud ctx.hud.build-context)
                       :enabled? true}))
    (when (and scene scene.build-context)
      (set scene.build-context.object-selector object-selector))
    (when (and ctx.hud ctx.hud.build-context)
      (set ctx.hud.build-context.object-selector object-selector))
    (local graph-view
      (GraphView {:graph graph
                  :ctx (and scene scene.build-context)
                  :movables ctx.movables
                  :selector object-selector
                  :view-target ctx.hud
                  :camera camera
                  :pointer-target scene
                  :data-dir world.dir}))
    (local graph-state (resolve-graph-core-state world.state.graph))
    (local graph-views-state (resolve-graph-views-state world.state.graph))
    (scene:build-default {:terrains (and world.state world.state.scene world.state.scene.terrains)})
    (when (and graph graph.restore-state graph-state)
      (graph:restore-state graph-state))
    (when (and scene scene.restore-state world.state.scene)
      (scene:restore-state world.state.scene))
    (local runtime
      {:camera camera
       :physics-floor-y floor-y
       :first-person-controls controls
       :scene-scope scene-scope
       :scene scene
       :object-selector object-selector
       :graph graph
       :graph-view graph-view
       :pending-graph-views-state (clone-table graph-views-state)
       :pending-hud-state (clone-table world.state.hud)})
    (set runtime.restore-hud-state
         (fn [rt hud]
           (when (and rt.pending-graph-views-state
                      rt.graph-view
                      rt.graph-view.restore-views-state)
             (rt.graph-view:restore-views-state rt.pending-graph-views-state)
             (set rt.pending-graph-views-state nil))
           (when (and hud hud.restore-state rt.pending-hud-state)
             (hud:restore-state rt.pending-hud-state)
             (set rt.pending-hud-state nil))))
    runtime)

  (fn clear-runtime [world ctx reason]
    (local runtime world.runtime)
    (when runtime
      (capture-runtime-state world ctx)
      (when runtime.first-person-controls
        (runtime.first-person-controls:drop)
        (set runtime.first-person-controls nil))
      (when runtime.graph-view
        (runtime.graph-view:drop)
        (set runtime.graph-view nil))
      (when runtime.object-selector
        (runtime.object-selector:drop)
        (set runtime.object-selector nil))
      (when runtime.scene
        (runtime.scene:drop)
        (set runtime.scene nil))
      (when runtime.graph
        (runtime.graph:drop)
        (set runtime.graph nil))
      (when runtime.camera
        (runtime.camera:drop)
        (set runtime.camera nil))
      (set runtime.scene-scope nil)
      (set world.runtime nil)
      (when reason
        (logging.info (string.format "[world] %s runtime cleared (%s)" world.id reason)))))

  (fn init [world _ctx]
    (when (not world.initialized?)
      (ensure-world-dir)
      (load-state world)
      (set world.initialized? true)))

  (fn activate [world ctx]
    (world:init ctx)
    (when (not world.runtime)
      (set world.runtime (create-runtime world ctx)))
    (apply-runtime-floor! world)
    (set world.active? true))

  (fn deactivate [world ctx reason]
    (capture-runtime-state world ctx)
    (queue-runtime-restore-state world)
    (set world.active? false)
    (when reason
      (logging.info (string.format "[world] %s deactivated (%s)" world.id reason))))

  (fn suspend [world ctx]
    (clear-runtime world ctx "suspend"))

  (fn resume [world ctx]
    (when (not world.runtime)
      (set world.runtime (create-runtime world ctx)))
    (apply-runtime-floor! world)
    (set world.active? true))

  (fn drop [world ctx reason]
    (set world.active? false)
    (clear-runtime world ctx (or reason "drop"))
    (save-state world))

  (fn update [_world _delta _opts]
    nil)

  (fn get-runtime [world]
    world.runtime)

  (fn get-hud-contrib [_world]
    nil)

  (set self.init init)
  (set self.activate activate)
  (set self.deactivate deactivate)
  (set self.suspend suspend)
  (set self.resume resume)
  (set self.drop drop)
  (set self.update update)
  (set self.get-runtime get-runtime)
  (set self.get-hud-contrib get-hud-contrib)
  self)

HomeWorld
