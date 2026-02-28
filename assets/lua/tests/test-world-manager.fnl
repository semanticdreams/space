(local tests [])
(local fs (require :fs))
(local WorldManager (require :world-manager))
(local HomeWorld (require :home-world))
(local PhysicsFloor (require :physics-floor))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "world-manager-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "world-manager-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

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
      (fs.write-file (fs.join-path world-dir "world.json")
                     "{\"camera\":{\"position\":[1001000,0,0],\"rotation\":[1,0,0,0]},\"graph\":{\"graph\":{\"nodes\":[],\"edges\":[]},\"views\":{\"open-node-keys\":[]}},\"scene\":{\"panels\":[]},\"hud\":{\"panels\":[]}}")
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

(fn home-world-loads-persisted-physics-floor []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (fs.write-file (fs.join-path world-dir "world.json")
                     "{\"camera\":{\"position\":[0,0,30],\"rotation\":[1,0,0,0]},\"physics\":{\"floor-y\":-1234},\"graph\":{\"graph\":{\"nodes\":[],\"edges\":[]},\"views\":{\"open-node-keys\":[]}},\"scene\":{\"panels\":[]},\"hud\":{\"panels\":[]}}")
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local floor-y (and world.state world.state.physics world.state.physics.floor-y))
      (assert (= floor-y -1234) "Expected persisted physics.floor-y to load")
      true)))

(fn home-world-sanitizes-invalid-physics-floor []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (fs.write-file (fs.join-path world-dir "world.json")
                     "{\"camera\":{\"position\":[0,0,30],\"rotation\":[1,0,0,0]},\"physics\":{\"floor-y\":\"invalid\"},\"graph\":{\"graph\":{\"nodes\":[],\"edges\":[]},\"views\":{\"open-node-keys\":[]}},\"scene\":{\"panels\":[]},\"hud\":{\"panels\":[]}}")
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local floor-y (and world.state world.state.physics world.state.physics.floor-y))
      (assert (= floor-y PhysicsFloor.default-floor-y)
              "Invalid physics.floor-y should reset to default")
      true)))

(fn home-world-activate-reapplies-runtime-floor []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (fs.write-file (fs.join-path world-dir "world.json")
                     "{\"camera\":{\"position\":[0,0,30],\"rotation\":[1,0,0,0]},\"physics\":{\"floor-y\":-1450},\"graph\":{\"graph\":{\"nodes\":[],\"edges\":[]},\"views\":{\"open-node-keys\":[]}},\"scene\":{\"panels\":[]},\"hud\":{\"panels\":[]}}")
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.runtime {:physics-floor-y -1450})
      (set app.physics-floor-y -777)
      (world:activate {})
      (assert (= app.physics-floor-y -1450)
              "World activation should reapply runtime floor to app.physics-floor-y")
      true)))

(fn home-world-captures-runtime-floor-on-drop []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (set world.runtime {:physics-floor-y -1666})
      (world:drop {} "test")
      (local floor-y (and world.state world.state.physics world.state.physics.floor-y))
      (assert (= floor-y -1666)
              "World drop should capture runtime floor into persisted state")
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
(table.insert tests {:name "HomeWorld errors on corrupt state"
                     :fn home-world-errors-on-corrupt-state})
(table.insert tests {:name "HomeWorld sanitizes poisoned camera position"
                     :fn home-world-sanitizes-poisoned-camera-position})
(table.insert tests {:name "HomeWorld loads persisted physics floor"
                     :fn home-world-loads-persisted-physics-floor})
(table.insert tests {:name "HomeWorld sanitizes invalid physics floor"
                     :fn home-world-sanitizes-invalid-physics-floor})
(table.insert tests {:name "HomeWorld activate reapplies runtime floor"
                     :fn home-world-activate-reapplies-runtime-floor})
(table.insert tests {:name "HomeWorld captures runtime floor on drop"
                     :fn home-world-captures-runtime-floor-on-drop})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "world-manager"
                       :tests tests})))

{:name "world-manager"
 :tests tests
 :main main}
