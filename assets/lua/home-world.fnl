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
(local PhysicsContainment (require :physics-containment))
(local TerrainRecords (require :scene-terrain-records))
(local LightSystemModule (require :light-system))
(local SkyboxState (require :skybox-state))
(local BackgroundState (require :background-state))

(local vec3->array (. MathUtils :vec3->array))
(local quat->array (. MathUtils :quat->array))
(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))
(local safe-vec3? CoordinateGuard.safe-vec3?)
(local sanitize-vec3 CoordinateGuard.sanitize-vec3)
(local finite-number? CoordinateGuard.finite-number?)

(local default-containment-config
  (PhysicsContainment.serialize-config (PhysicsContainment.default-config)))

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

(fn base-default-state []
  {:camera {:position [0 0 30]
            :rotation [1 0 0 0]}
   :physics {:containment default-containment-config}
   :graph {:graph {:nodes []
                   :edges []}
           :views {:open-node-keys []}}
   :scene {:panels []
           :terrains []
           :skybox (SkyboxState.default-state)
           :background (BackgroundState.default-state)}
   :hud {:panels []}})

(fn default-state []
  (local state (base-default-state))
  (set state.scene.lights (LightSystemModule.default-state))
  state)

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

(fn merge-preserved-graph-views-state [graph existing-state captured-state]
  (local existing-views (resolve-graph-views-state existing-state))
  (local captured-views (resolve-graph-views-state captured-state))
  (local supports-key?
    (fn [key]
      (and graph graph.has-key-loader-for-key (graph:has-key-loader-for-key key))))
  (local existing-open-views
    (if (= (type existing-views.open-views) :table)
        existing-views.open-views
        (icollect [_ key (ipairs (or existing-views.open-node-keys []))]
                  {:node-key key})))
  (local captured-open-views
    (if (= (type captured-views.open-views) :table)
        captured-views.open-views
        (icollect [_ key (ipairs (or captured-views.open-node-keys []))]
                  {:node-key key})))
  (local captured-keys {})
  (var merged-open-views [])

  (each [_ entry (ipairs captured-open-views)]
    (local key (and entry entry.node-key))
    (when (= (type key) :string)
      (set (. captured-keys key) true))
    (table.insert merged-open-views entry))

  (each [_ entry (ipairs existing-open-views)]
    (local key (and entry entry.node-key))
    (when (and (= (type key) :string)
               (not (. captured-keys key))
               (not (supports-key? key)))
      (table.insert merged-open-views entry)))

  {:open-views merged-open-views
   :open-node-keys (icollect [_ entry (ipairs merged-open-views)]
                             (and entry entry.node-key))})

(fn merge-preserved-graph-state [graph existing-state captured-state]
  (local existing-core (resolve-graph-core-state existing-state))
  (local captured-core (resolve-graph-core-state captured-state))
  (local supports-key?
    (fn [key]
      (and graph graph.has-key-loader-for-key (graph:has-key-loader-for-key key))))
  (local captured-nodes {})
  (local captured-edges {})
  (var merged-nodes [])
  (var merged-edges [])

  (each [_ key (ipairs (or captured-core.nodes []))]
    (set (. captured-nodes key) true)
    (table.insert merged-nodes key))

  (each [_ edge (ipairs (or captured-core.edges []))]
    (local composite (.. (or edge.source "") "->" (or edge.target "")))
    (set (. captured-edges composite) true)
    (table.insert merged-edges edge))

  (each [_ key (ipairs (or existing-core.nodes []))]
    (when (and (not (. captured-nodes key))
               (not (supports-key? key)))
      (table.insert merged-nodes key)))

  (each [_ edge (ipairs (or existing-core.edges []))]
    (local source-key edge.source)
    (local target-key edge.target)
    (local composite (.. (or source-key "") "->" (or target-key "")))
    (local preserve?
      (and (not (. captured-edges composite))
           (or (and source-key (not (supports-key? source-key)))
               (and target-key (not (supports-key? target-key))))))
    (when preserve?
      (table.insert merged-edges edge)))

  {:graph {:nodes merged-nodes
           :edges merged-edges}
   :views (merge-preserved-graph-views-state graph existing-state captured-state)})

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
               :graph-world-manager options.graph-world-manager
               :asset-path-resolver options.asset-path-resolver
               :state-path state-path
               :state (default-state)
               :active? false
               :initialized? false
               :runtime nil})

  (fn ensure-world-dir []
    (local (ok err) (pcall fs.create-dirs dir))
    (when (not ok)
      (error (string.format "HomeWorld failed to create %s: %s" dir err))))

  (fn persist-loaded-state! [world]
    (ensure-world-dir)
    (local (ok err) (pcall (fn [] (JsonUtils.write-json! world.state-path world.state))))
    (when (not ok)
      (error (string.format "HomeWorld failed to write %s during load: %s" world.state-path err))))

  (fn load-state [world]
    (local persisted (read-world-state world.state-path))
    (var repaired-persisted-state? false)
    (if persisted
        (do
          (set world.state (merge-state-defaults (base-default-state) persisted))
          (local persisted-lights (and persisted.scene persisted.scene.lights))
          (local persisted-skybox (and persisted.scene persisted.scene.skybox))
          (local persisted-background (and persisted.scene persisted.scene.background))
          (if persisted-lights
              (set world.state.scene.lights
                   (LightSystemModule.normalize-complete-state persisted-lights
                                                              (string.format "HomeWorld.load-state %s"
                                                                             world.id)))
              (do
                (set world.state.scene.lights (LightSystemModule.default-state))
                (set repaired-persisted-state? true)))
          (if persisted-skybox
              (set world.state.scene.skybox
                   (SkyboxState.normalize-complete-state persisted-skybox
                                                        (string.format "HomeWorld.load-state %s"
                                                                       world.id)))
              (do
                (set world.state.scene.skybox (SkyboxState.default-state))
                (set repaired-persisted-state? true)))
          (if persisted-background
              (set world.state.scene.background
                   (BackgroundState.normalize-complete-state persisted-background
                                                            (string.format "HomeWorld.load-state %s"
                                                                           world.id)))
              (do
                (set world.state.scene.background (BackgroundState.default-state))
                (set repaired-persisted-state? true))))
        (do
          (set world.state (default-state))
          (set world.state.scene.terrains (TerrainRecords.default-records))))
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
    (local containment
      (if (= (type physics-state.containment) :table)
          physics-state.containment
          (if (finite-number? physics-state.floor-y)
              (do
                (logging.warn (string.format
                                "[world] %s migrating persisted physics.floor-y to containment bounds"
                                world.id))
                {:mode "manual-bounds"
                 :bounds {:min [-500 physics-state.floor-y -500]
                          :max [500 500 500]}})
              (do
                (when (not (= physics-state.floor-y nil))
                  (logging.warn (string.format
                                  "[world] %s invalid persisted physics containment; resetting to default"
                                  world.id)))
                default-containment-config))))
    (set physics-state.containment
         (PhysicsContainment.serialize-config
           (PhysicsContainment.normalize-config containment)))
    (set physics-state.floor-y nil)
    (set world.state.physics physics-state)
    (when repaired-persisted-state?
      (persist-loaded-state! world)))

  (fn save-state [world]
    (ensure-world-dir)
    (local (ok err) (pcall (fn [] (JsonUtils.write-json! world.state-path world.state))))
    (when (not ok)
      (error (string.format "HomeWorld failed to write %s: %s" world.state-path err)))
    true)

  (fn resolve-runtime-containment-config [world]
    (local runtime world.runtime)
    (local runtime-config (and runtime runtime.physics-containment-config))
    (local state-config (and world.state world.state.physics world.state.physics.containment))
    (PhysicsContainment.serialize-config
      (PhysicsContainment.normalize-config (or runtime-config state-config default-containment-config))))

  (fn apply-runtime-containment! [world opts]
    (local options (or opts {}))
    (local config (resolve-runtime-containment-config world))
    (local scene (or options.scene
                     (and world.runtime world.runtime.scene)))
    (set app.physics-containment-config config)
    (PhysicsContainment.ensure-installed {:scene scene
                                          :config config})
    (when world.state
      (when (not world.state.physics)
        (set world.state.physics {}))
      (set world.state.physics.containment config))
    (when world.runtime
      (set world.runtime.physics-containment-config config))
    config)

  (fn clear-active-runtime-containment! [world]
    (local runtime world.runtime)
    (local runtime-scene (and runtime runtime.scene))
    (when (and runtime-scene
               (= app.physics-containment-scene runtime-scene))
      (PhysicsContainment.clear))
    true)

  (fn apply-runtime-physics-policy! []
    (when (and app.engine app.engine.physics)
      (app.engine.physics:setGravity 0 -25 0))
    true)

  (fn apply-runtime-light-state! [world]
    (local runtime world.runtime)
    (local scene (and runtime runtime.scene))
    (local scene-state (and world.state world.state.scene))
    (when (and scene scene.set-light-state)
      (scene:set-light-state (and scene-state scene-state.lights))))

  (fn apply-runtime-skybox-state! [world]
    (local runtime world.runtime)
    (local scene (and runtime runtime.scene))
    (local scene-state (and world.state world.state.scene))
    (when (and scene scene.set-skybox-state)
      (scene:set-skybox-state
        (SkyboxState.normalize-complete-state
          (assert (and scene-state scene-state.skybox)
                  (string.format "HomeWorld %s requires scene.skybox" world.id))
          (string.format "HomeWorld.apply-runtime-skybox-state %s" world.id)))))

  (fn apply-runtime-background-state! [world]
    (local runtime world.runtime)
    (local scene (and runtime runtime.scene))
    (local scene-state (and world.state world.state.scene))
    (when (and scene scene.set-background-state)
      (scene:set-background-state
        (BackgroundState.normalize-complete-state
          (assert (and scene-state scene-state.background)
                  (string.format "HomeWorld %s requires scene.background" world.id))
          (string.format "HomeWorld.apply-runtime-background-state %s" world.id)))))

  (fn capture-runtime-state [world ctx]
    (local runtime world.runtime)
    (local camera (and runtime runtime.camera))
    (local scene (and runtime runtime.scene))
    (local graph (and runtime runtime.graph))
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
      (set world.state.graph
           (merge-preserved-graph-state
             graph
             world.state.graph
             (graph-view:capture-state))))
    (when (and scene scene.capture-state)
      (local captured-scene (scene:capture-state))
      (local existing-scene (or world.state.scene {}))
      (set captured-scene.terrains
           (TerrainRecords.merge-preserved-records
             existing-scene.terrains
             captured-scene.terrains))
      (assert captured-scene.lights "HomeWorld.capture-runtime-state requires scene lights")
      (assert captured-scene.skybox "HomeWorld.capture-runtime-state requires scene skybox")
      (assert captured-scene.background "HomeWorld.capture-runtime-state requires scene background")
      (set world.state.scene captured-scene))
    (when (and hud hud.capture-state)
      (set world.state.hud (hud:capture-state)))
    (local physics-state (or world.state.physics {}))
    (set physics-state.containment (resolve-runtime-containment-config world))
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
    (GraphKeyLoaders.register graph {:world-manager (assert world.graph-world-manager
                                                         (.. "HomeWorld " world.id " requires :graph-world-manager"))
                                     :asset-path-resolver (assert world.asset-path-resolver
                                                                  (.. "HomeWorld " world.id " requires :asset-path-resolver"))})
    (local scene-scope (ctx.focus-manager:create-scope {:name (.. "scene:" world.id)
                                                        :directional-traversal-boundary? true}))
    (ctx.focus-manager:attach scene-scope ctx.focus-root)
    (local scene
      (Scene {:focus-manager ctx.focus-manager
              :focus-scope scene-scope
              :camera camera
              :icons ctx.icons
              :states ctx.states
              :movables ctx.movables
              :on-terrains-changed
              (fn [updated-scene]
                (PhysicsContainment.schedule-refresh
                  {:scene updated-scene
                   :config (resolve-runtime-containment-config world)}))
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
    (local containment-config
      (apply-runtime-containment! world {:scene scene}))
    (local runtime
      {:camera camera
       :physics-containment-config containment-config
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
      (clear-active-runtime-containment! world)
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
    (var created-runtime? false)
    (when (not world.runtime)
      (set world.runtime (create-runtime world ctx))
      (set created-runtime? true))
    (apply-runtime-physics-policy!)
    (apply-runtime-containment! world)
    (when (not created-runtime?)
      (apply-runtime-light-state! world)
      (apply-runtime-skybox-state! world))
    (apply-runtime-background-state! world)
    (set world.active? true))

  (fn deactivate [world ctx reason]
    (capture-runtime-state world ctx)
    (queue-runtime-restore-state world)
    (clear-active-runtime-containment! world)
    (set world.active? false)
    (when reason
      (logging.info (string.format "[world] %s deactivated (%s)" world.id reason))))

  (fn suspend [world ctx]
    (clear-runtime world ctx "suspend"))

  (fn resume [world ctx]
    (var created-runtime? false)
    (when (not world.runtime)
      (set world.runtime (create-runtime world ctx))
      (set created-runtime? true))
    (apply-runtime-physics-policy!)
    (apply-runtime-containment! world)
    (when (not created-runtime?)
      (apply-runtime-light-state! world)
      (apply-runtime-skybox-state! world))
    (apply-runtime-background-state! world)
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
  (set self.save-state save-state)
  self)

HomeWorld
