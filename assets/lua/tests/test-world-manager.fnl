(local tests [])
(local fs (require :fs))
(local json (require :json))
(local bt (require :bt))
(local WorldManager (require :world-manager))
(local HomeWorld (require :home-world))
(local CanvasModes (require :canvas-modes))
(local PhysicsContainment (require :physics-containment))
(local LightSystemModule (require :light-system))
(local SkyboxState (require :skybox-state))
(local BackgroundState (require :background-state))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "world-manager-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "world-manager-" (os.time) "-" temp-counter)))

(fn ensure-built-in-canvas-modes! []
  (local registry (CanvasModes.ensure-registry))
  (when (not (. registry.modes "graph"))
    (CanvasModes.register-mode
      {:id "graph"
       :label "Graph"
       :icon "account_tree"
       :button-name "graph-canvas-mode"
       :show-in-sidebar? true
       :activate (fn [_ctx] {:mode-id "graph"})
       :deactivate (fn [_ctx _session] true)}))
  (when (not (. registry.modes "drawing"))
    (CanvasModes.register-mode
      {:id "drawing"
       :label "Draw"
       :icon "draw"
       :button-name "drawing-canvas-mode"
       :show-in-sidebar? true
       :activate (fn [ctx]
                   (ctx:set-update!
                     (fn [payload]
                       (local runtime (and payload payload.runtime))
                       (when (and runtime runtime.drawing-render)
                         (runtime.drawing-render:update))
                       nil))
                   {:mode-id "drawing"})
       :deactivate (fn [_ctx _session] true)}))
  true)

(fn with-temp-dir [f]
  (ensure-built-in-canvas-modes!)
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn write-world-json! [world-dir state]
  (fs.write-file (fs.join-path world-dir "world.json")
                 (json.dumps state)))

(fn make-skybox-state [opts]
  (local options (or opts {}))
  (SkyboxState.normalize-complete-state
    {:enabled? (if (= options.enabled? nil) true options.enabled?)
     :default {:name (or options.name "lake")
               :brightness (or options.brightness 0.1)}
     :by-theme (or options.by-theme {})}
    "test-world-manager skybox state"))

(fn make-background-state [opts]
  (local options (or opts {}))
  (BackgroundState.normalize-complete-state
    {:color (or options.color [0.0 0.0 0.0])}
    "test-world-manager background state"))

(fn make-fake-world-factory [stats]
  (fn [opts]
    (local runtime {:camera {:id (.. "camera-" opts.id)}
                    :scene {:id (.. "scene-" opts.id)}
                    :graph {:id (.. "graph-" opts.id)}})
    (set (. stats.created opts.id) true)
    {:id opts.id
     :name opts.name
     :type opts.type
     :dir opts.dir
     :init (fn [_self _ctx]
             (set (. stats.init opts.id) (+ 1 (or (. stats.init opts.id) 0))))
     :activate (fn [_self _ctx]
                 (set (. stats.activate opts.id) (+ 1 (or (. stats.activate opts.id) 0))))
     :deactivate (fn [_self _ctx _reason]
                   (set (. stats.deactivate opts.id) (+ 1 (or (. stats.deactivate opts.id) 0))))
     :suspend (fn [_self _ctx]
                (set (. stats.suspend opts.id) (+ 1 (or (. stats.suspend opts.id) 0))))
     :resume (fn [_self _ctx]
               (set (. stats.resume opts.id) (+ 1 (or (. stats.resume opts.id) 0))))
     :drop (fn [_self _ctx _reason]
             (set (. stats.drop opts.id) (+ 1 (or (. stats.drop opts.id) 0))))
     :update (fn [_self _delta _opts] nil)
     :get-runtime (fn [_self] runtime)
     :get-hud-contrib (fn [_self] nil)}))

(fn make-physics-count-world-factory []
  (fn [opts]
    (var body nil)
    (fn remove-body []
      (when (and body app.engine app.engine.physics)
        (app.engine.physics:removeRigidBody body)
        (set body nil)))
    (fn create-body []
      (when (and (not body) app.engine app.engine.physics bt)
        (local shape (bt.StaticPlaneShape (bt.Vector3 0 1 0) 0))
        (local transform (bt.Transform))
        (transform:setIdentity)
        (local motion-state (bt.DefaultMotionState transform))
        (local zero (bt.Vector3 0 0 0))
        (local info (bt.RigidBodyConstructionInfo 0 motion-state shape zero))
        (set body (bt.RigidBody info))
        (app.engine.physics:addRigidBody body)))
    {:id opts.id
     :name opts.name
     :type opts.type
     :dir opts.dir
     :init (fn [_self _ctx] nil)
     :activate (fn [_self _ctx] (create-body))
     :deactivate (fn [_self _ctx _reason] nil)
     :suspend (fn [_self _ctx] (remove-body))
     :resume (fn [_self _ctx] (create-body))
     :drop (fn [_self _ctx _reason] (remove-body))
     :update (fn [_self _delta _opts] nil)
     :get-runtime (fn [_self] {:camera {:id (.. "camera-" opts.id)}
                               :scene {:id (.. "scene-" opts.id)}
                               :graph {:id (.. "graph-" opts.id)}})
     :get-hud-contrib (fn [_self] nil)}))

(fn collision-object-count []
  (assert (and app.engine app.engine.physics app.engine.physics.getWorld)
          "Physics world is required for collision object counting")
  (local world (app.engine.physics:getWorld))
  (assert world "Physics.getWorld returned nil")
  (local objects (world:getCollisionObjectArray))
  (length objects))

(fn manager-creates-and-activates-default-home []
  (with-temp-dir
    (fn [root]
      (local stats {:created {} :init {} :activate {} :deactivate {} :suspend {} :resume {} :drop {}})
      (var active-entry nil)
      (local manager
        (WorldManager {:root-dir root
                       :create-world (make-fake-world-factory stats)
                       :context-fn (fn [] {})
                       :on-active-runtime (fn [entry runtime]
                                            (set active-entry {:entry entry :runtime runtime}))}))
      (local tabs (manager:list-tabs))
      (assert (= (length tabs) 1) "expected one default world tab")
      (assert (= (. (. tabs 1) :name) "home") "expected default tab name 'home'")
      (assert (manager:activate-first) "activate-first should succeed")
      (local active-id (manager:active-world-id))
      (assert active-id "active world id should be set")
      (assert (= (. stats.init active-id) 1) "world should initialize once")
      (assert (= (. stats.activate active-id) 1) "world should activate once")
      (assert (and active-entry active-entry.runtime) "on-active-runtime should receive runtime")
      true)))

(fn manager-adds-and-switches-home-tabs []
  (with-temp-dir
    (fn [root]
      (local stats {:created {} :init {} :activate {} :deactivate {} :suspend {} :resume {} :drop {}})
      (local manager
        (WorldManager {:root-dir root
                       :create-world (make-fake-world-factory stats)
                       :context-fn (fn [] {})}))
      (manager:activate-first)
      (local first-id (manager:active-world-id))
      (local second (manager:create-home-world {:activate? true}))
      (assert second "expected second world record")
      (assert (= second.name "home-2") "expected second home world to be named home-2")
      (assert (not (= first-id (manager:active-world-id))) "active world should switch to new world")
      (assert (= (. stats.deactivate first-id) 1) "first world should deactivate once")
      (assert (= (. stats.suspend first-id) 1) "first world should suspend immediately on switch")
      (local tabs (manager:list-tabs))
      (assert (= (length tabs) 2) "expected two tabs after create-home-world")
      true)))

(fn manager-closing-last-world-signals-empty []
  (with-temp-dir
    (fn [root]
      (local stats {:created {} :init {} :activate {} :deactivate {} :suspend {} :resume {} :drop {}})
      (var empty-calls 0)
      (local manager
        (WorldManager {:root-dir root
                       :create-world (make-fake-world-factory stats)
                       :context-fn (fn [] {})
                       :on-empty (fn [] (set empty-calls (+ empty-calls 1)))}))
      (manager:activate-first)
      (assert (manager:close-active-world) "closing active world should succeed")
      (assert (= empty-calls 1) "on-empty should be called exactly once")
      (assert (= (manager:count) 0) "all worlds should be closed")
      true)))

(fn manager-colon-activate-index-regression []
  (with-temp-dir
    (fn [root]
      (local manager
        (WorldManager {:root-dir root
                       :create-world (make-fake-world-factory {:created {}
                                                               :init {}
                                                               :activate {}
                                                               :deactivate {}
                                                               :suspend {}
                                                               :resume {}
                                                               :drop {}})
                       :context-fn (fn [] {})}))
      (manager:activate-first)
      (manager:create-home-world {:activate? false})
      (assert (= (manager:count) 2) "expected two worlds after create-home-world")
      ;; Regression for tab click path: colon-call should treat numeric index correctly.
      (assert (manager:activate-index 2) "activate-index should accept colon-call index")
      (local active-world (manager:active-world))
      (assert (= (and active-world active-world.name) "home-2"))
      true)))

(fn manager-errors-on-corrupt-index []
  (with-temp-dir
    (fn [root]
      (fs.write-file (fs.join-path root "index.json") "{broken")
      (local (ok err)
        (pcall (fn []
                 (WorldManager {:root-dir root
                                :create-world (make-fake-world-factory {:created {}
                                                                        :init {}
                                                                        :activate {}
                                                                        :deactivate {}
                                                                        :suspend {}
                                                                        :resume {}
                                                                        :drop {}})
                                :context-fn (fn [] {})}))))
      (assert (not ok) "WorldManager should error when index.json is invalid")
      (assert (string.find (tostring err) "failed to parse")
              "Expected parse failure for invalid world index")
      true)))

(fn manager-switch-suspends-inactive-world-in-physics []
  (with-temp-dir
    (fn [root]
      (assert bt "Physics integration test requires bt module")
      (assert (and app.engine app.engine.physics) "Physics integration test requires engine physics")
      (local baseline (collision-object-count))
      (local manager
        (WorldManager {:root-dir root
                       :create-world (make-physics-count-world-factory)
                       :context-fn (fn [] {})}))
      (var ok false)
      (var err-msg nil)
      (local (ok-run err-or-nil)
        (pcall
          (fn []
            (manager:activate-first)
            (local after-first (collision-object-count))
            (assert (= after-first (+ baseline 1))
                    (string.format "Expected one active-world body (baseline=%d after-first=%d)"
                                   baseline after-first))
            (manager:create-home-world {:activate? true})
            (local after-switch (collision-object-count))
            (assert (= after-switch (+ baseline 1))
                    (string.format "Expected switch to keep exactly one world body (baseline=%d after-switch=%d)"
                                   baseline after-switch))
            (set ok true))))
      (when (not ok-run)
        (set err-msg err-or-nil))
      (manager:drop)
      (local final-count (collision-object-count))
      (assert (= final-count baseline)
              (string.format "WorldManager.drop should restore physics object count (baseline=%d final=%d)"
                             baseline final-count))
      (when (not ok-run)
        (error err-msg))
      ok)))

(fn home-world-errors-on-corrupt-state []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (fs.write-file (fs.join-path world-dir "world.json") "{broken")
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (local (ok err)
        (pcall (fn []
                 (world:init {}))))
      (assert (not ok) "HomeWorld should error when world.json is invalid")
      (assert (string.find (tostring err) "failed to parse")
              "Expected parse failure for invalid world state")
      true)))

(fn home-world-sanitizes-poisoned-camera-position []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [1001000 0 0]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)
                                  :background (make-background-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local position (and world.state world.state.camera world.state.camera.position))
      (assert (= (type position) :table) "Expected sanitized camera position table")
      (assert (= (. position 1) 0) "Sanitized camera x should reset to default")
      (assert (= (. position 2) 0) "Sanitized camera y should reset to default")
      (assert (= (. position 3) 30) "Sanitized camera z should reset to default")
      true)))

(fn home-world-loads-persisted-physics-containment []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :physics {:containment {:mode "manual-bounds"
                                                  :bounds {:min [-500 -1234 -500]
                                                           :max [500 500 500]}}}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local containment (and world.state world.state.physics world.state.physics.containment))
      (assert (= containment.mode "manual-bounds") "Expected persisted containment mode to load")
      (assert (= (. (. containment.bounds.min) 2) -1234)
              "Expected persisted containment min-y to load")
      true)))

(fn home-world-strips-legacy-persisted-containment-color []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :physics {:containment {:mode "manual-bounds"
                                                  :bounds {:min [-500 -1234 -500]
                                                           :max [500 500 500]}
                                                  :visualization {:enabled true
                                                                  :color [0.9 0.2 0.1 0.8]}}}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local containment (and world.state world.state.physics world.state.physics.containment))
      (assert (= containment.mode "manual-bounds") "Expected persisted containment mode to load")
      (assert (= (and containment.visualization containment.visualization.enabled) true)
              "Expected persisted containment visualization.enabled to load")
      (assert (= (and containment.visualization containment.visualization.color) nil)
              "Legacy persisted containment visualization.color should be stripped during load")
      true)))

(fn home-world-sanitizes-invalid-physics-containment []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :physics {:containment "invalid"}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local containment (and world.state world.state.physics world.state.physics.containment))
      (assert (= containment.mode PhysicsContainment.default-mode)
              "Invalid containment should reset to default mode")
      (assert (= (. (. containment.bounds.min) 2) -500)
              "Invalid containment should reset to default min-y")
      true)))

(fn home-world-update-drives-active-graph-view []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (var graph-view-updates [])
      (var drawing-render-updates 0)
      (CanvasModes.activate-mode "graph")
      (set world.runtime {:graph-view {:update (fn [_self delta]
                                                 (table.insert graph-view-updates delta))}
                          :drawing-render {:update (fn [_self]
                                                     (set drawing-render-updates
                                                          (+ drawing-render-updates 1)))}
                          :active-canvas-mode "graph"})
      (world:update 0.25 {:active? false})
      (world:update 0.5 {:active? true})
      (assert (= (length graph-view-updates) 1)
              "HomeWorld should only tick graph-view while active")
      (assert (= (. graph-view-updates 1) 0.5)
              "HomeWorld should pass the frame delta through to graph-view")
      (assert (= drawing-render-updates 0)
              "HomeWorld should skip drawing-render updates while graph is the active canvas mode")
      (CanvasModes.activate-mode "drawing")
      (world:update 0.6 {:active? false})
      (assert (= drawing-render-updates 0)
              "HomeWorld should skip drawing-render updates while inactive even if drawing was the last active canvas mode")
      (world:update 0.75 {:active? true})
      (assert (= drawing-render-updates 1)
              "HomeWorld should resume drawing-render updates when drawing becomes active")
      true)))

(fn home-world-activate-reapplies-runtime-containment []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :physics {:containment {:mode "manual-bounds"
                                                  :bounds {:min [-500 -1450 -500]
                                                           :max [500 500 500]}}}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.runtime {:physics-containment-config {:mode "manual-bounds"
                                                       :bounds {:min [-500 -1450 -500]
                                                                :max [500 500 500]}}})
      (set app.physics-containment-config {:mode "manual-bounds"
                                           :bounds {:min [-500 -777 -500]
                                                    :max [500 500 500]}})
      (world:activate {})
      (assert (= (. (. app.physics-containment-config.bounds.min) 2) -1450)
              "World activation should reapply runtime containment config")
      true)))

(fn home-world-captures-runtime-containment-on-drop []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.runtime {:physics-containment-config {:mode "manual-bounds"
                                                       :bounds {:min [-500 -1666 -500]
                                                                :max [500 500 500]}}
                          :unload-canvas-runtime (fn [_self] true)})
      (world:drop {} "test")
      (local containment (and world.state world.state.physics world.state.physics.containment))
      (assert (= (. (. containment.bounds.min) 2) -1666)
              "World drop should capture runtime containment into persisted state")
      true)))

(fn home-world-deactivate-queues-canvas-and-hud-restore-state []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.runtime
           {:camera {:position [0 0 0]
                     :rotation [1 0 0 0]}
            :canvas {:capture-state (fn [_self]
                                      {:panels [{:kind "graph-node-view"
                                                 :node-key "node-a"}]})}})
      (world:deactivate {:hud {:capture-state (fn [_self]
                                                {:panels [{:kind "dialog/demo"}]})}
                         :canvas {:capture-state (fn [_self]
                                                   {:panels [{:kind "graph-node-view"
                                                              :node-key "node-a"}]})}}
                        "switch")
      (assert (= (. (. world.runtime.pending-canvas-state.panels 1) :node-key) "node-a")
              "World deactivate should queue canvas panel state for restore")
      (assert (= (. (. world.runtime.pending-hud-state.panels 1) :kind) "dialog/demo")
              "World deactivate should queue hud panel state for restore")
      true)))

(fn home-world-deactivate-persists-preferred-interaction-surface []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.runtime
           {:camera {:position [0 0 0]
                     :rotation [1 0 0 0]}
            :preferred-interaction-surface :canvas
            :active-canvas-mode "drawing"
            :requested-canvas-mode-id "drawing"
            :requested-canvas-mode-known? true
            :canvas {:capture-state (fn [_self]
                                      {:panels []})}})
      (world:deactivate {:canvas {:capture-state (fn [_self]
                                                   {:panels []})}}
                        "switch")
      (local canvas-state (and world.state world.state.canvas))
      (assert (= canvas-state.preferred_interaction_surface "canvas")
              "World deactivate should persist preferred interaction surface")
      (assert (= canvas-state.active_mode "drawing")
              "World deactivate should keep active canvas mode alongside interaction surface")
      true)))

(fn home-world-preserves-unregistered-persisted-canvas-mode []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :canvas {:active_mode "bogus"
                                   :preferred_interaction_surface "canvas"}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)
                                  :background (make-background-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local canvas-state (and world.state world.state.canvas))
      (assert (= canvas-state.active_mode "bogus")
              "HomeWorld should preserve unregistered persisted canvas mode ids")
      (local persisted (json.loads (fs.read-file (fs.join-path world-dir "world.json"))))
      (local persisted-canvas-state (and persisted.canvas persisted.canvas))
      (assert (= persisted-canvas-state.active_mode "bogus")
              "HomeWorld should not rewrite unregistered persisted canvas mode ids during load")
      true)))

(fn home-world-new-state-seeds-default-terrain []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local terrains (and world.state world.state.scene world.state.scene.terrains))
      (assert (= (type terrains) :table) "Expected world scene terrains table")
      (assert (= (length terrains) 1) "Expected exactly one default terrain for new world")
      (assert (= (. (. terrains 1) :kind) "heightfield-terrain") "Default terrain should be heightfield-terrain")
      true)))

(fn home-world-new-state-seeds-default-lights []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local lights (and world.state world.state.scene world.state.scene.lights))
      (assert (= (type lights) :table) "Expected world scene lights table")
      (assert (= (type lights.ambient) :table) "Expected ambient light record")
      (assert (= (length lights.directional) 1) "Expected exactly one default directional light")
      (assert (= (length lights.point) 0) "Expected no default point lights")
      (assert (= (length lights.spot) 0) "Expected no default spot lights")
      true)))

(fn home-world-new-state-seeds-default-skybox []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local skybox (and world.state world.state.scene world.state.scene.skybox))
      (assert (= (type skybox) :table) "Expected world scene skybox table")
      (assert (= skybox.enabled? true) "Expected default skybox to start enabled")
      (assert (= skybox.default.name "lake") "Expected default skybox name")
      (assert (= skybox.default.brightness 0.1) "Expected default skybox brightness")
      true)))

(fn home-world-new-state-seeds-default-background []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local background (and world.state world.state.scene world.state.scene.background))
      (assert (= (type background) :table) "Expected world scene background table")
      (assert (= (length background.color) 3) "Expected default background to have rgb color")
      (assert (= (. background.color 1) 0.0) "Expected default background red")
      (assert (= (. background.color 2) 0.0) "Expected default background green")
      (assert (= (. background.color 3) 0.0) "Expected default background blue")
      true)))

(fn home-world-loads-persisted-lights []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights {:ambient {:id "ambient"
                                                     :color [0.1 0.2 0.3]
                                                     :enabled? true}
                                           :directional []
                                           :point [{:id "point-1"
                                                    :position [1 2 3]
                                                    :ambient [0 0 0]
                                                    :diffuse [1 1 1]
                                                    :specular [1 1 1]
                                                    :specular-power 8
                                                    :constant 1
                                                    :linear 0.2
                                                    :quadratic 0.05
                                                    :enabled? true}]
                                           :spot []}
                                  :skybox (make-skybox-state {:enabled? false
                                                              :name "lake"
                                                              :brightness 0.25})}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local lights (and world.state world.state.scene world.state.scene.lights))
      (assert (= (. (. lights.ambient.color) 2) 0.2) "Expected persisted ambient light to load")
      (assert (= (length lights.point) 1) "Expected persisted point light to load")
      (assert (= (. (. lights.point 1) :linear) 0.2) "Expected persisted point attenuation to load")
      true)))

(fn home-world-loads-persisted-skybox []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state {:enabled? false
                                                              :name "lake"
                                                              :brightness 0.25})
                                  :background (make-background-state {:color [0.1 0.2 0.3]})}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local skybox (and world.state world.state.scene world.state.scene.skybox))
      (assert (= skybox.enabled? false) "Expected persisted skybox enabled flag to load")
      (assert (= skybox.default.name "lake") "Expected persisted skybox name to load")
      (assert (= skybox.default.brightness 0.25) "Expected persisted skybox brightness to load")
      true)))

(fn home-world-loads-persisted-background []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)
                                  :background (make-background-state {:color [0.1 0.2 0.3]})}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local background (and world.state world.state.scene world.state.scene.background))
      (assert (= (. background.color 1) 0.1) "Expected persisted background red to load")
      (assert (= (. background.color 2) 0.2) "Expected persisted background green to load")
      (assert (= (. background.color 3) 0.3) "Expected persisted background blue to load")
      true)))

(fn home-world-repairs-missing-persisted-lights-with-default []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (fs.write-file (fs.join-path world-dir "world.json")
                     "{\"camera\":{\"position\":[0,0,30],\"rotation\":[1,0,0,0]},\"graph\":{\"graph\":{\"nodes\":[],\"edges\":[]},\"views\":{\"open-node-keys\":[]}},\"scene\":{\"panels\":[],\"terrains\":[]},\"hud\":{\"panels\":[]}}")
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local lights (and world.state world.state.scene world.state.scene.lights))
      (local expected-defaults (LightSystemModule.default-state))
      (assert lights "HomeWorld should seed missing persisted scene lights")
      (assert lights.ambient "HomeWorld should repair missing ambient light with default state")
      (assert (= (json.dumps lights) (json.dumps expected-defaults))
              "HomeWorld should repair missing lights with the canonical default light state")
      (local persisted (json.loads (fs.read-file (fs.join-path world-dir "world.json"))))
      (local persisted-lights (and persisted.scene persisted.scene.lights))
      (assert persisted-lights "HomeWorld should immediately persist repaired lights during load")
      (assert (= (json.dumps persisted-lights) (json.dumps expected-defaults))
              "Persisted repaired lights should use the canonical default light state")
      true)))

(fn home-world-repairs-missing-persisted-skybox-with-default []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :background (make-background-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local skybox (and world.state world.state.scene world.state.scene.skybox))
      (assert skybox "HomeWorld should seed missing persisted scene skybox")
      (assert (= skybox.enabled? true) "HomeWorld should repair missing skybox with default enabled flag")
      (assert (= skybox.default.name "lake") "HomeWorld should repair missing skybox with default name")
      (assert (= skybox.default.brightness 0.1) "HomeWorld should repair missing skybox with default brightness")
      (local persisted (json.loads (fs.read-file (fs.join-path world-dir "world.json"))))
      (local persisted-skybox (and persisted.scene persisted.scene.skybox))
      (assert persisted-skybox "HomeWorld should immediately persist repaired skybox during load")
      (assert (= persisted-skybox.default.name "lake") "Persisted repaired skybox should use default name")
      true)))

(fn home-world-repairs-missing-persisted-background-with-default []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local background (and world.state world.state.scene world.state.scene.background))
      (assert background "HomeWorld should seed missing persisted scene background")
      (assert (= (. background.color 1) 0.0) "HomeWorld should repair missing background with default red")
      (assert (= (. background.color 2) 0.0) "HomeWorld should repair missing background with default green")
      (assert (= (. background.color 3) 0.0) "HomeWorld should repair missing background with default blue")
      (local persisted (json.loads (fs.read-file (fs.join-path world-dir "world.json"))))
      (local persisted-background (and persisted.scene persisted.scene.background))
      (assert persisted-background "HomeWorld should immediately persist repaired background during load")
      (assert (= (. persisted-background.color 1) 0.0) "Persisted repaired background should use default red")
      true)))

(fn home-world-persists-updated-ambient-light-across-reload []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.state.scene.lights
           (LightSystemModule.normalize-state
             {:ambient {:id "ambient" :color [0.25 0.5 0.75] :enabled? true}
              :directional world.state.scene.lights.directional
              :point world.state.scene.lights.point
              :spot world.state.scene.lights.spot}))
      (world:save-state)
      (local reloaded (HomeWorld {:id "world-a"
                                  :name "home"
                                  :type "home"
                                  :dir world-dir}))
      (reloaded:init {})
      (local ambient (and reloaded.state reloaded.state.scene reloaded.state.scene.lights reloaded.state.scene.lights.ambient))
      (assert ambient "Expected ambient light after reload")
      (assert (= (. ambient.color 1) 0.25) "Expected persisted ambient x value after reload")
      (assert (= (. ambient.color 2) 0.5) "Expected persisted ambient y value after reload")
      (assert (= (. ambient.color 3) 0.75) "Expected persisted ambient z value after reload")
      true)))

(fn home-world-persists-updated-non-ambient-lights-across-reload []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.state.scene.lights
           (LightSystemModule.normalize-state
             {:ambient {:id "ambient" :color [0.0 0.0 1.0] :enabled? true}
              :directional [{:id "directional-1"
                             :direction [0.0 -1.0 0.0]
                             :ambient [0.1 0.2 0.3]
                             :diffuse [0.9 0.8 0.7]
                             :specular [1.0 0.75 0.5]
                             :specular-power 16
                             :enabled? true}]
              :point [{:id "point-1"
                       :position [1.0 2.0 3.0]
                       :ambient [0.1 0.1 0.1]
                       :diffuse [0.9 0.8 0.7]
                       :specular [1.0 1.0 0.9]
                       :specular-power 18
                       :constant 1.2
                       :linear 0.3
                       :quadratic 0.07
                       :enabled? true}]
              :spot [{:id "spot-1"
                      :position [4.0 5.0 6.0]
                      :direction [0.0 -1.0 0.0]
                      :ambient [0.2 0.1 0.0]
                      :diffuse [0.8 0.7 0.6]
                      :specular [1.0 0.9 0.8]
                      :specular-power 22
                      :cutoff 0.9
                      :outer-cutoff 0.8
                      :constant 1.1
                      :linear 0.2
                      :quadratic 0.03
                      :enabled? true}]}))
      (world:save-state)
      (local reloaded (HomeWorld {:id "world-a"
                                  :name "home"
                                  :type "home"
                                  :dir world-dir}))
      (reloaded:init {})
      (local lights (and reloaded.state reloaded.state.scene reloaded.state.scene.lights))
      (assert (= (length lights.directional) 1) "Expected persisted directional light after reload")
      (assert (= (. (. lights.directional 1) :direction 2) -1.0)
              "Expected persisted directional direction after reload")
      (assert (= (length lights.point) 1) "Expected persisted point light after reload")
      (assert (= (. (. lights.point 1) :linear) 0.3)
              "Expected persisted point attenuation after reload")
      (assert (= (length lights.spot) 1) "Expected persisted spot light after reload")
      (assert (= (. (. lights.spot 1) :outer-cutoff) 0.8)
              "Expected persisted spot cutoff after reload")
      true)))

(fn home-world-activate-reapplies-runtime-light-state []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.state.scene.lights
           (LightSystemModule.normalize-state
             {:ambient {:id "ambient" :color [0.25 0.5 0.75] :enabled? true}
              :directional []
              :point [{:id "point-1"
                       :position [4 5 6]
                       :ambient [0 0 0]
                       :diffuse [1 1 1]
                       :specular [1 1 1]
                       :specular-power 8
                       :constant 1
                       :linear 0.3
                       :quadratic 0.07
                       :enabled? true}]
              :spot []}))
      (var applied nil)
      (set world.runtime {:scene {:set-light-state (fn [_self lights]
                                                     (set applied lights)
                                                     true)}})
      (world:activate {})
      (assert applied "World activation should reapply persisted light state to runtime scene")
      (assert (= (. (. applied.ambient.color) 3) 0.75) "Applied ambient light should match world state")
      (assert (= (. (. applied.point 1) :linear) 0.3) "Applied point light should match world state")
      true)))

(fn home-world-activate-reapplies-runtime-skybox-state []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.state.scene.skybox
           (make-skybox-state {:enabled? false
                               :name "lake"
                               :brightness 0.25}))
      (var applied nil)
      (set world.runtime {:scene {:set-skybox-state (fn [_self skybox]
                                                      (set applied skybox)
                                                      true)}})
      (world:activate {})
      (assert applied "World activation should reapply persisted skybox state to runtime scene")
      (assert (= applied.enabled? false) "Applied skybox enabled flag should match world state")
      (assert (= applied.name "lake") "Applied skybox name should match world state")
      (assert (= applied.brightness 0.25) "Applied skybox brightness should match world state")
      true)))

(fn home-world-activate-reapplies-runtime-background-state []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.state.scene.background
           (make-background-state {:color [0.1 0.2 0.3]}))
      (var applied nil)
      (set world.runtime {:scene {:set-background-state (fn [_self background]
                                                          (set applied background)
                                                          true)}})
      (world:activate {})
      (assert applied "World activation should reapply persisted background state to runtime scene")
      (assert (= (. applied.color 1) 0.1) "Applied background red should match world state")
      (assert (= (. applied.color 2) 0.2) "Applied background green should match world state")
      (assert (= (. applied.color 3) 0.3) "Applied background blue should match world state")
      true)))

(fn home-world-resume-reapplies-runtime-light-and-skybox-state []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.state.scene.lights
           (LightSystemModule.normalize-state
             {:ambient {:id "ambient" :color [0.25 0.5 0.75] :enabled? true}
              :directional []
              :point []
              :spot []}))
      (set world.state.scene.skybox
           (make-skybox-state {:enabled? false
                               :name "lake"
                               :brightness 0.25}))
      (set world.state.scene.background
           (make-background-state {:color [0.1 0.2 0.3]}))
      (var applied-lights nil)
      (var applied-skybox nil)
      (var applied-background nil)
      (set world.runtime {:scene {:set-light-state (fn [_self lights]
                                                     (set applied-lights lights)
                                                     true)
                                  :set-skybox-state (fn [_self skybox]
                                                      (set applied-skybox skybox)
                                                      true)
                                  :set-background-state (fn [_self background]
                                                         (set applied-background background)
                                                      true)}})
      (world:resume {})
      (assert applied-lights "World resume should reapply persisted light state to runtime scene")
      (assert applied-skybox "World resume should reapply persisted skybox state to runtime scene")
      (assert applied-background "World resume should reapply persisted background state to runtime scene")
      (assert (= (. (. applied-lights.ambient.color) 2) 0.5) "Resumed ambient light should match world state")
      (assert (= applied-skybox.enabled? false) "Resumed skybox enabled flag should match world state")
      (assert (= applied-skybox.brightness 0.25) "Resumed skybox brightness should match world state")
      (assert (= (. applied-background.color 2) 0.2) "Resumed background should match world state")
      true)))

(fn home-world-deactivate-requires-scene-lights []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.runtime
           {:scene {:capture-state (fn [_self]
                                     {:panels []
                                      :terrains []})}})
      (local (ok err)
        (pcall (fn []
                 (world:deactivate {} "switch"))))
      (assert (not ok) "World deactivate should fail when scene capture omits lights")
      (assert (string.find (tostring err) "requires scene lights")
              "Expected missing lights failure during world capture")
      true)))

(fn home-world-deactivate-requires-scene-skybox []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.runtime
           {:scene {:capture-state (fn [_self]
                                     {:panels []
                                      :terrains []
                                      :lights (LightSystemModule.default-state)
                                      :background (make-background-state)})}})
      (local (ok err)
        (pcall (fn []
                 (world:deactivate {} "switch"))))
      (assert (not ok) "World deactivate should fail when scene capture omits skybox")
      (assert (string.find (tostring err) "requires scene skybox" 1 true)
              "Expected missing skybox failure during world capture")
      true)))

(fn home-world-deactivate-requires-scene-background []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.runtime
           {:scene {:capture-state (fn [_self]
                                     {:panels []
                                      :terrains []
                                      :lights (LightSystemModule.default-state)
                                      :skybox (make-skybox-state)})}})
      (local (ok err)
        (pcall (fn []
                 (world:deactivate {} "switch"))))
      (assert (not ok) "World deactivate should fail when scene capture omits background")
      (assert (string.find (tostring err) "requires scene background" 1 true)
              "Expected missing background failure during world capture")
      true)))

(fn home-world-preserves-explicit-empty-terrain-list []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local terrains (and world.state world.state.scene world.state.scene.terrains))
      (assert (= (type terrains) :table) "Expected terrain list to remain a table")
      (assert (= (length terrains) 0) "Expected explicit empty terrain list to be preserved")
      true)))

(fn home-world-preserves-unknown-terrain-kind-state []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains [{:id "t-1"
                                              :kind "voxel-terrain"
                                              :options {:chunk-size 32}}]
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local terrains (and world.state world.state.scene world.state.scene.terrains))
      (assert (= (type terrains) :table) "Expected terrain list table")
      (assert (= (length terrains) 1) "Expected unknown terrain record to be preserved")
      (local terrain (. terrains 1))
      (assert (= terrain.kind "voxel-terrain") "Expected unknown terrain kind to remain unchanged")
      (assert (= terrain.id "t-1") "Expected unknown terrain id to remain unchanged")
      true)))

(fn home-world-preserves-unsupported-terrain-on-deactivate []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains [{:id "t-1"
                                              :kind "legacy-terrain"
                                              :options {:width 64}}]
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)
                                  :background (make-background-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.runtime
           {:scene {:capture-state (fn [_self]
                                     {:panels []
                                      :terrains []
                                      :lights (LightSystemModule.default-state)
                                      :skybox (make-skybox-state)
                                      :background (make-background-state)})}})
      (world:deactivate {} "switch")
      (local terrains (and world.state world.state.scene world.state.scene.terrains))
      (assert (= (type terrains) :table) "Expected terrain list table after deactivate")
      (assert (= (length terrains) 1)
              "Unsupported terrain should remain in world state after runtime capture")
      (local terrain (. terrains 1))
      (assert (= terrain.kind "legacy-terrain")
              "Expected unsupported terrain kind to be preserved after deactivate")
      (assert (= terrain.id "t-1")
              "Expected unsupported terrain id to remain unchanged after deactivate")
      true)))

(fn home-world-preserves-supported-terrain-when-runtime-capture-misses-terrains []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes []
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains [{:id "terrain-1"
                                              :kind "heightfield-terrain"
                                              :options {:position [-160 -100 -160]
                                                        :rotation [1 0 0 0]
                                                        :opacity 1.0
                                                        :physics true
                                                        :sample-spacing [20 20]
                                                        :chunk-samples [17 17]
                                                        :default-height 0.0}
                                              :chunks [{:coord [0 0]}]}]
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)
                                  :background (make-background-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.runtime
           {:scene {:capture-state (fn [_self]
                                     {:panels []
                                      :terrains nil
                                      :lights (LightSystemModule.default-state)
                                      :skybox (make-skybox-state)
                                      :background (make-background-state)})}})
      (world:deactivate {} "switch")
      (local terrains (and world.state world.state.scene world.state.scene.terrains))
      (assert (= (type terrains) :table) "Expected terrain list table after deactivate")
      (assert (= (length terrains) 1)
              "Supported terrain should remain in world state when runtime capture omits terrains")
      (local terrain (. terrains 1))
      (assert (= terrain.kind "heightfield-terrain")
              "Expected supported terrain kind to remain unchanged after missing runtime capture")
      (assert (= terrain.id "terrain-1")
              "Expected supported terrain id to remain unchanged after missing runtime capture")
      true)))

(fn home-world-preserves-unsupported-graph-nodes-on-deactivate []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes ["mystery-node:world-1:node-a"]
                                          :edges [{:source "mystery-node:world-1:node-a"
                                                   :target "start"}]}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local graph-state {:graph {:nodes ["start"]
                                  :edges []}
                          :views {:open-node-keys []}})
      (set world.runtime
           {:graph {:has-key-loader-for-key (fn [_self key]
                                             (= key "start"))
                    :capture-state (fn [_self]
                                     (. graph-state :graph))}})
      (world:deactivate {} "switch")
      (local nodes (and world.state world.state.graph world.state.graph.graph world.state.graph.graph.nodes))
      (local edges (and world.state world.state.graph world.state.graph.graph world.state.graph.graph.edges))
      (assert (= (type nodes) :table) "Expected graph nodes table after deactivate")
      (assert (= (length nodes) 2)
              "Unsupported graph node should remain alongside captured supported nodes")
      (assert (= (. nodes 1) "start")
              "Captured supported graph node should be preserved")
      (assert (= (. nodes 2) "mystery-node:world-1:node-a")
              "Unsupported graph node should be preserved after deactivate")
      (assert (= (length edges) 1)
              "Unsupported graph edge should be preserved after deactivate")
      (local edge (. edges 1))
      (assert (= edge.source "mystery-node:world-1:node-a")
              "Unsupported graph edge source should be preserved")
      (assert (= edge.target "start")
              "Unsupported graph edge target should be preserved")
      true)))

(fn home-world-load-state-errors-on-stale-terrain-persistence-refs []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes ["start"
                                                  "legacy:keep"
                                                  "terrain:world-a:terrain-stale"
                                                  "terrain-editor:world-a:terrain-stale"
                                                  "terrain-tool:world-a:terrain-stale:resize-terrain"]
                                          :edges [{:source "legacy:keep"
                                                   :target "start"}
                                                  {:source "terrain:world-a:terrain-stale"
                                                   :target "terrain-tool:world-a:terrain-stale:resize-terrain"}
                                                  {:source "terrain:world-a:terrain-stale"
                                                   :target "terrain-editor:world-a:terrain-stale"}]}
                                  :views {:open-node-keys ["legacy:keep"
                                                           "terrain-tool:world-a:terrain-stale:resize-terrain"]}}
                          :canvas {:camera {:position [0 0 100]}
                                   :scale_factor 1.0
                                   :panels [{:kind "graph-node-view"
                                             :node-key "terrain-tool:world-a:terrain-canvas:resize-terrain"}]}
                          :scene {:panels [{:kind "graph-node-cube"
                                            :node-key "terrain:world-a:terrain-scene"}]
                                  :terrains [{:id "terrain-live"
                                              :kind "heightfield-terrain"
                                              :options {:position [-160 -100 -160]
                                                        :rotation [1 0 0 0]
                                                        :opacity 1.0
                                                        :physics true
                                                        :sample-spacing [20 20]
                                                        :chunk-samples [17 17]
                                                        :default-height 0.0}
                                              :chunks [{:coord [0 0]}]}]
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)
                                  :background (make-background-state)}
                          :hud {:panels [{:kind "graph-node-view"
                                          :node-key "terrain-editor:world-a:terrain-hud"}]}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (local (ok err) (pcall (fn [] (world:init {}))))
      (local err-text (tostring err))
      (assert (not ok)
              "Expected load-state to fail fast on stale terrain persistence refs")
      (assert (string.find err-text "HomeWorld.load%-state world%-a found stale terrain graph refs")
              (.. "Expected load-state stale terrain persistence error prefix, got: " err-text))
      (assert (string.find err-text "terrain:world%-a:terrain%-stale")
              (.. "Expected load-state stale terrain graph error to include terrain node key, got: "
                  err-text))
      (assert (string.find err-text "terrain%-editor:world%-a:terrain%-stale")
              "Expected load-state stale terrain graph error to include terrain editor key")
      (assert (string.find err-text "terrain%-tool:world%-a:terrain%-stale:resize%-terrain")
              "Expected load-state stale terrain graph error to include terrain tool key")
      (assert (string.find err-text "terrain%-tool:world%-a:terrain%-canvas:resize%-terrain")
              "Expected load-state stale terrain graph error to include canvas graph-node-view key")
      (assert (string.find err-text "terrain%-editor:world%-a:terrain%-hud")
              "Expected load-state stale terrain graph error to include hud graph-node-view key")
      (assert (string.find err-text "terrain:world%-a:terrain%-scene")
              "Expected load-state stale terrain graph error to include scene graph-node-cube key")
      true)))

(fn home-world-load-state-errors-on-cross-world-terrain-refs []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes ["terrain:world-b:terrain-live"]
                                          :edges []}
                                  :views {:open-node-keys []}}
                          :scene {:panels []
                                  :terrains [{:id "terrain-live"
                                              :kind "heightfield-terrain"
                                              :options {:position [-160 -100 -160]
                                                        :rotation [1 0 0 0]
                                                        :opacity 1.0
                                                        :physics true
                                                        :sample-spacing [20 20]
                                                        :chunk-samples [17 17]
                                                        :default-height 0.0}
                                              :chunks [{:coord [0 0]}]}]
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)
                                  :background (make-background-state)}
                          :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (local (ok err) (pcall (fn [] (world:init {}))))
      (local err-text (tostring err))
      (assert (not ok)
              "Expected load-state to fail fast on cross-world terrain refs")
      (assert (string.find err-text "terrain:world%-b:terrain%-live")
              (.. "Expected load-state cross-world terrain ref error to include offending key, got: "
                  err-text))
      true)))

(fn home-world-persists-graph-node-views-on-targets-instead-of-graph-state []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (write-world-json! world-dir
                         {:camera {:position [0 0 30]
                                   :rotation [1 0 0 0]}
                          :graph {:graph {:nodes []
                                          :edges []}}
                          :scene {:panels []
                                  :terrains []
                                  :lights (LightSystemModule.default-state)
                                  :skybox (make-skybox-state)}
                          :hud {:panels []}
                          :canvas {:camera {:position [0 0 100]}
                                   :scale_factor 1.0
                                   :panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.runtime
           {:graph {:has-key-loader-for-key (fn [_self key]
                                             (= key "start"))}
            :canvas {:capture-state (fn [_self]
                                      {:panels [{:kind "graph-node-view"
                                                 :node-key "start"
                                                 :layer "float"
                                                 :position [1 2 3]
                                                 :rotation [1 0 0 0]
                                                 :size [7 8 9]}]})}})
      (world:deactivate {:canvas {:capture-state (fn [_self]
                                                   {:panels [{:kind "graph-node-view"
                                                              :node-key "start"
                                                              :layer "float"
                                                              :position [1 2 3]
                                                              :rotation [1 0 0 0]
                                                              :size [7 8 9]}]})}}
                        "switch")
      (assert (= (and world.state.graph world.state.graph.views) nil)
              "Graph node views should no longer persist through graph state")
      (local panels (and world.state world.state.canvas world.state.canvas.panels))
      (assert (= (type panels) :table)
              "Canvas should capture graph node view panels")
      (assert (= (length panels) 1)
              "Canvas should persist the captured graph node view panel")
      (assert (= (. (. panels 1) :node-key) "start")
              "Canvas should persist graph node view placement by node key")
      true)))

(table.insert tests {:name "WorldManager creates and activates default home world"
                     :fn manager-creates-and-activates-default-home})
(table.insert tests {:name "WorldManager adds and switches home tabs"
                     :fn manager-adds-and-switches-home-tabs})
(table.insert tests {:name "WorldManager closing last world signals empty"
                     :fn manager-closing-last-world-signals-empty})
(table.insert tests {:name "WorldManager colon activate-index regression"
                     :fn manager-colon-activate-index-regression})
(table.insert tests {:name "WorldManager errors on corrupt index"
                     :fn manager-errors-on-corrupt-index})
(table.insert tests {:name "WorldManager switch suspends inactive world in physics"
                     :fn manager-switch-suspends-inactive-world-in-physics})
(table.insert tests {:name "HomeWorld errors on corrupt state"
                     :fn home-world-errors-on-corrupt-state})
(table.insert tests {:name "HomeWorld sanitizes poisoned camera position"
                     :fn home-world-sanitizes-poisoned-camera-position})
(table.insert tests {:name "HomeWorld loads persisted physics containment"
                     :fn home-world-loads-persisted-physics-containment})
(table.insert tests {:name "HomeWorld strips legacy persisted containment color"
                     :fn home-world-strips-legacy-persisted-containment-color})
(table.insert tests {:name "HomeWorld sanitizes invalid physics containment"
                     :fn home-world-sanitizes-invalid-physics-containment})
(table.insert tests {:name "HomeWorld update drives active graph-view"
                     :fn home-world-update-drives-active-graph-view})
(table.insert tests {:name "HomeWorld activate reapplies runtime containment"
                     :fn home-world-activate-reapplies-runtime-containment})
(table.insert tests {:name "HomeWorld captures runtime containment on drop"
                     :fn home-world-captures-runtime-containment-on-drop})
(table.insert tests {:name "HomeWorld deactivate queues canvas and hud restore state"
                     :fn home-world-deactivate-queues-canvas-and-hud-restore-state})
(table.insert tests {:name "HomeWorld deactivate persists preferred interaction surface"
                     :fn home-world-deactivate-persists-preferred-interaction-surface})
(table.insert tests {:name "HomeWorld preserves unregistered persisted canvas mode"
                     :fn home-world-preserves-unregistered-persisted-canvas-mode})
(table.insert tests {:name "HomeWorld new state seeds default terrain"
                     :fn home-world-new-state-seeds-default-terrain})
(table.insert tests {:name "HomeWorld new state seeds default lights"
                     :fn home-world-new-state-seeds-default-lights})
(table.insert tests {:name "HomeWorld new state seeds default skybox"
                     :fn home-world-new-state-seeds-default-skybox})
(table.insert tests {:name "HomeWorld new state seeds default background"
                     :fn home-world-new-state-seeds-default-background})
(table.insert tests {:name "HomeWorld loads persisted lights"
                     :fn home-world-loads-persisted-lights})
(table.insert tests {:name "HomeWorld loads persisted skybox"
                     :fn home-world-loads-persisted-skybox})
(table.insert tests {:name "HomeWorld loads persisted background"
                     :fn home-world-loads-persisted-background})
(table.insert tests {:name "HomeWorld repairs missing persisted lights with default"
                     :fn home-world-repairs-missing-persisted-lights-with-default})
(table.insert tests {:name "HomeWorld repairs missing persisted skybox with default"
                     :fn home-world-repairs-missing-persisted-skybox-with-default})
(table.insert tests {:name "HomeWorld repairs missing persisted background with default"
                     :fn home-world-repairs-missing-persisted-background-with-default})
(table.insert tests {:name "HomeWorld persists updated ambient light across reload"
                     :fn home-world-persists-updated-ambient-light-across-reload})
(table.insert tests {:name "HomeWorld persists updated non-ambient lights across reload"
                     :fn home-world-persists-updated-non-ambient-lights-across-reload})
(table.insert tests {:name "HomeWorld activate reapplies runtime light state"
                     :fn home-world-activate-reapplies-runtime-light-state})
(table.insert tests {:name "HomeWorld activate reapplies runtime skybox state"
                     :fn home-world-activate-reapplies-runtime-skybox-state})
(table.insert tests {:name "HomeWorld activate reapplies runtime background state"
                     :fn home-world-activate-reapplies-runtime-background-state})
(table.insert tests {:name "HomeWorld resume reapplies runtime light and skybox state"
                     :fn home-world-resume-reapplies-runtime-light-and-skybox-state})
(table.insert tests {:name "HomeWorld deactivate requires scene lights"
                     :fn home-world-deactivate-requires-scene-lights})
(table.insert tests {:name "HomeWorld deactivate requires scene skybox"
                     :fn home-world-deactivate-requires-scene-skybox})
(table.insert tests {:name "HomeWorld deactivate requires scene background"
                     :fn home-world-deactivate-requires-scene-background})
(table.insert tests {:name "HomeWorld preserves explicit empty terrain list"
                     :fn home-world-preserves-explicit-empty-terrain-list})
(table.insert tests {:name "HomeWorld preserves unknown terrain kind state"
                     :fn home-world-preserves-unknown-terrain-kind-state})
(table.insert tests {:name "HomeWorld preserves unsupported terrain on deactivate"
                     :fn home-world-preserves-unsupported-terrain-on-deactivate})
(table.insert tests {:name "HomeWorld preserves supported terrain when runtime capture misses terrains"
                     :fn home-world-preserves-supported-terrain-when-runtime-capture-misses-terrains})
(table.insert tests {:name "HomeWorld preserves unsupported graph nodes on deactivate"
                     :fn home-world-preserves-unsupported-graph-nodes-on-deactivate})
(table.insert tests {:name "HomeWorld load-state errors on stale terrain persistence refs"
                     :fn home-world-load-state-errors-on-stale-terrain-persistence-refs})
(table.insert tests {:name "HomeWorld load-state errors on cross-world terrain refs"
                     :fn home-world-load-state-errors-on-cross-world-terrain-refs})
(table.insert tests {:name "HomeWorld persists graph node views on targets instead of graph state"
                     :fn home-world-persists-graph-node-views-on-targets-instead-of-graph-state})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "world-manager"
                       :tests tests})))

{:name "world-manager"
 :tests tests
 :main main}
