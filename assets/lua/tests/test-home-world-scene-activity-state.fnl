(local tests [])
(local fs (require :fs))
(local json (require :json))
(local HomeWorld (require :home-world))
(local Activities (require :activities))
(local ActivitySceneState (require :activity-scene-state))
(local LightSystemModule (require :light-system))
(local SkyboxState (require :skybox-state))
(local BackgroundState (require :background-state))
(local PhysicsContainment (require :physics-containment))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "home-world-scene-activity-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "hw-scene-activity-" (os.time) "-" temp-counter)))

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
    "test-home-world-scene-activity skybox state"))

(fn make-background-state [opts]
  (local options (or opts {}))
  (BackgroundState.normalize-complete-state
    {:color (or options.color [0.0 0.0 0.0])}
    "test-home-world-scene-activity background state"))

(fn ensure-built-in-activities! []
  (local registry (Activities.ensure-registry))
  (when (not (. registry.activities "sandbox"))
    (Activities.register-activity
      {:id "sandbox"
       :label "Sandbox"
       :icon "toys"
       :button-name "sandbox-activity"
       :show-in-switcher? true
       :activate (fn [_ctx] {:activity-id "sandbox"})
       :deactivate (fn [_ctx _session] true)}))
  (when (not (. registry.activities "graph"))
    (Activities.register-activity
      {:id "graph"
       :label "Graph"
       :icon "account_tree"
       :button-name "graph-activity"
       :show-in-switcher? true
       :activate (fn [_ctx] {:activity-id "graph"})
       :deactivate (fn [_ctx _session] true)}))
  (when (not (. registry.activities "drawing"))
    (Activities.register-activity
      {:id "drawing"
       :label "Draw"
       :icon "draw"
       :button-name "drawing-activity"
       :show-in-switcher? true
       :activate (fn [_ctx] {:activity-id "drawing"})
       :deactivate (fn [_ctx _session] true)}))
  (when (not (. registry.activities "board"))
    (Activities.register-activity
      {:id "board"
       :label "Board"
       :icon "grid_view"
       :button-name "board-activity"
       :show-in-switcher? true
       :activate (fn [_ctx] {:activity-id "board"})
       :deactivate (fn [_ctx _session] true)}))
  true)

(fn with-temp-dir [f]
  (ensure-built-in-activities!)
  (local dir (make-temp-dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn fresh-home-world-has-canonical-activity-session-state []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local activity-state (and world.state world.state.activity))
      ;; Default activity should be "sandbox"
      (assert (= activity-state.active_id "sandbox")
              (.. "Expected sandbox as default active activity, got " (tostring activity-state.active_id)))
      ;; Sessions must exist
      (assert (= (type activity-state.sessions) :table)
              "Expected activity.sessions table")
      ;; Sandbox session must exist with scene state
      (local sandbox-session (and activity-state.sessions activity-state.sessions.sandbox))
      (assert (= (type sandbox-session) :table)
              "Expected activity.sessions.sandbox table")
      (local sandbox-scene (and sandbox-session sandbox-session.scene))
      (assert (= (type sandbox-scene) :table)
              "Expected activity.sessions.sandbox.scene table")
      ;; Sandbox scene should have default content
      (assert (= (type sandbox-scene.panels) :table) "Expected sandbox scene panels")
      (assert (= (type sandbox-scene.terrains) :table) "Expected sandbox scene terrains")
      (assert (= (type sandbox-scene.lights) :table) "Expected sandbox scene lights")
      (assert (= (type sandbox-scene.skybox) :table) "Expected sandbox scene skybox")
      (assert (= (type sandbox-scene.background) :table) "Expected sandbox scene background")
      (assert (= (type sandbox-scene.containment) :table) "Expected sandbox scene containment")
      (assert (= (length sandbox-scene.terrains) 1)
              "Expected one default terrain in sandbox scene")
      (assert (= sandbox-scene.lights.ambient.enabled? true)
              "Expected sandbox default ambient light enabled")
      (assert (= sandbox-scene.skybox.enabled? true)
              "Expected sandbox default skybox enabled")
      ;; Top-level scene should not have canonical content fields
      (local top-scene world.state.scene)
      (assert (or (= top-scene nil) (= (type top-scene) :table))
              "Expected top-level scene to be nil or empty table")
      (when (= (type top-scene) :table)
        (assert (= top-scene.panels nil)
                "Top-level scene.panels should be nil after migration")
        (assert (= top-scene.terrains nil)
                "Top-level scene.terrains should be nil after migration")
        (assert (= top-scene.lights nil)
                "Top-level scene.lights should be nil after migration")
        (assert (= top-scene.skybox nil)
                "Top-level scene.skybox should be nil after migration")
        (assert (= top-scene.background nil)
                "Top-level scene.background should be nil after migration"))
      ;; Top-level physics.containment should not have canonical content
      (local physics-state (and world.state world.state.physics))
      (when physics-state
        (assert (= physics-state.containment nil)
                "Top-level physics.containment should be nil after migration"))
      ;; Graph, Drawing, Board should have empty scene sessions
      (local graph-session (and activity-state.sessions activity-state.sessions.graph))
      (when graph-session
        (assert (= (type graph-session.scene) :table)
                "Expected graph session scene table")
        (assert (= (length graph-session.scene.terrains) 0)
                "Expected graph scene to have empty terrains"))
      ;; Drawing session
      (local drawing-session (and activity-state.sessions activity-state.sessions.drawing))
      (when drawing-session
        (assert (= (type drawing-session.scene) :table)
                "Expected drawing session scene table")
        (assert (= drawing-session.scene.skybox.enabled? false)
                "Expected drawing scene to have disabled skybox"))
      ;; Board session
      (local board-session (and activity-state.sessions activity-state.sessions.board))
      (when board-session
        (assert (= (type board-session.scene) :table)
                "Expected board session scene table")
        (assert (= board-session.scene.containment.enabled? false)
                "Expected board scene to have disabled containment"))
      true)))

(fn legacy-world-migrates-scene-state-to-activity-sessions []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      ;; Write a legacy world.json with top-level scene content and physics containment
      (write-world-json! world-dir
        {:camera {:position [0 0 30]
                  :rotation [1 0 0 0]}
         :graph {:graph {:nodes []
                         :edges []}
                 :views {:open-node-keys []}}
         :scene {:panels [{:kind "test-panel"
                           :node-key "test:a"
                           :position [1 2 3]
                           :rotation [1 0 0 0]
                           :size [8 4 0]}]
                 :terrains [{:id "terrain-legacy"
                             :kind "heightfield-terrain"
                             :options {:position [-160 -100 -160]
                                       :rotation [1 0 0 0]
                                       :opacity 1.0
                                       :physics true
                                       :sample-spacing [20 20]
                                       :chunk-samples [17 17]
                                       :default-height 0.0}
                             :chunks [{:coord [0 0]}]}]
                 :lights {:ambient {:id "ambient"
                                    :color [0.1 0.2 0.3]
                                    :enabled? true}
                          :directional []
                          :point []
                          :spot []}
                 :skybox (make-skybox-state {:enabled? false
                                             :name "ocean"
                                             :brightness 0.5})
                 :background (make-background-state {:color [0.1 0.2 0.3]})}
         :physics {:containment {:mode "manual-bounds"
                                 :bounds {:min [-500 -2000 -500]
                                          :max [500 500 500]}}}
         :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      ;; Verify migration: sandbox session contains the legacy values
      (local sandbox-scene (and world.state world.state.activity
                                world.state.activity.sessions
                                world.state.activity.sessions.sandbox
                                world.state.activity.sessions.sandbox.scene))
      (assert sandbox-scene "Expected migrated sandbox scene state")
      ;; Panels
      (assert (= (length sandbox-scene.panels) 1)
              "Expected one migrated panel")
      (assert (= (. sandbox-scene.panels 1 :kind) "test-panel")
              "Expected migrated panel kind")
      ;; Terrains
      (assert (= (length sandbox-scene.terrains) 1)
              "Expected one migrated terrain")
      (assert (= (. sandbox-scene.terrains 1 :id) "terrain-legacy")
              "Expected migrated terrain id")
      ;; Lights
      (assert (= (. sandbox-scene.lights.ambient.color 1) 0.1)
              "Expected migrated ambient light red")
      (assert (= (. sandbox-scene.lights.ambient.color 2) 0.2)
              "Expected migrated ambient light green")
      (assert (= (. sandbox-scene.lights.ambient.color 3) 0.3)
              "Expected migrated ambient light blue")
      ;; Skybox
      (assert (= sandbox-scene.skybox.enabled? false)
              "Expected migrated skybox disabled flag")
      (assert (= sandbox-scene.skybox.name "ocean")
              "Expected migrated skybox name")
      (assert (= sandbox-scene.skybox.brightness 0.5)
              "Expected migrated skybox brightness")
      ;; Background
      (assert (= (. sandbox-scene.background.color 1) 0.1)
              "Expected migrated background red")
      (assert (= (. sandbox-scene.background.color 2) 0.2)
              "Expected migrated background green")
      (assert (= (. sandbox-scene.background.color 3) 0.3)
              "Expected migrated background blue")
      ;; Containment
      (assert (= sandbox-scene.containment.mode "manual-bounds")
              "Expected migrated containment mode")
      (assert (= (. sandbox-scene.containment.bounds.min 2) -2000)
              "Expected migrated containment min-y")
      ;; Top-level scene should be cleaned
      (local top-scene world.state.scene)
      (when (= (type top-scene) :table)
        (assert (= top-scene.panels nil) "Top-level scene.panels should be removed")
        (assert (= top-scene.terrains nil) "Top-level scene.terrains should be removed")
        (assert (= top-scene.lights nil) "Top-level scene.lights should be removed")
        (assert (= top-scene.skybox nil) "Top-level scene.skybox should be removed")
        (assert (= top-scene.background nil) "Top-level scene.background should be removed"))
      ;; Top-level physics.containment should be removed
      (local physics-state world.state.physics)
      (when physics-state
        (assert (= physics-state.containment nil)
                "Top-level physics.containment should be removed"))
      true)))

(fn migrated-world-preserves-canonical-on-reload []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      ;; Write a legacy world.json
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
      ;; Force save to persist the migrated state
      (world:save-state)
      ;; Reload and verify canonical structure is unchanged
      (local reloaded (HomeWorld {:id "world-a"
                                  :name "home"
                                  :type "home"
                                  :dir world-dir}))
      (reloaded:init {})
      (local sandbox-scene (and reloaded.state reloaded.state.activity
                                reloaded.state.activity.sessions
                                reloaded.state.activity.sessions.sandbox
                                reloaded.state.activity.sessions.sandbox.scene))
      (assert sandbox-scene "Expected sandbox scene after reload")
      (assert (= (length sandbox-scene.terrains) 1)
              "Expected one terrain after reload")
      (assert (= (. sandbox-scene.terrains 1 :id) "terrain-1")
              "Expected terrain id after reload")
      ;; Check the JSON file directly for legacy content
      (local persisted (json.loads (fs.read-file (fs.join-path world-dir "world.json"))))
      (when (= (type persisted.scene) :table)
        (assert (= persisted.scene.panels nil)
                "Persisted JSON should not have legacy scene.panels")
        (assert (= persisted.scene.terrains nil)
                "Persisted JSON should not have legacy scene.terrains")
        (assert (= persisted.scene.lights nil)
                "Persisted JSON should not have legacy scene.lights")
        (assert (= persisted.scene.skybox nil)
                "Persisted JSON should not have legacy scene.skybox")
        (assert (= persisted.scene.background nil)
                "Persisted JSON should not have legacy scene.background"))
      (when (= (type persisted.physics) :table)
        (assert (= persisted.physics.containment nil)
                "Persisted JSON should not have legacy physics.containment"))
      ;; But activity.sessions.sandbox.scene should exist
      (local persisted-sandbox-scene (and persisted.activity
                                         persisted.activity.sessions
                                         persisted.activity.sessions.sandbox
                                         persisted.activity.sessions.sandbox.scene))
      (assert persisted-sandbox-scene
              "Persisted JSON should have activity.sessions.sandbox.scene")
      (assert (= (length persisted-sandbox-scene.terrains) 1)
              "Persisted sandbox scene should have terrain")
      true)))

(fn canonical-sandbox-state-wins-over-legacy []
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      ;; Write a world.json with BOTH legacy scene content AND canonical activity sessions
      (write-world-json! world-dir
        {:camera {:position [0 0 30]
                  :rotation [1 0 0 0]}
         :activity {:active_id "sandbox"
                    :preferred_interaction_surface "scene"
                    :sessions {:sandbox {:scene {:panels [{:kind "canonical-panel"
                                                           :node-key "canonical:a"
                                                           :position [10 20 30]
                                                           :rotation [1 0 0 0]
                                                           :size [16 8 0]}]
                                                 :terrains [{:id "canonical-terrain"
                                                             :kind "heightfield-terrain"
                                                             :options {:position [0 -100 0]
                                                                       :rotation [1 0 0 0]
                                                                       :opacity 1.0
                                                                       :physics true
                                                                       :sample-spacing [20 20]
                                                                       :chunk-samples [17 17]
                                                                       :default-height 0.0}
                                                             :chunks [{:coord [0 0]}]}]
                                                 :lights {:ambient {:id "ambient"
                                                                    :color [0.9 0.8 0.7]
                                                                    :enabled? false}
                                                          :directional []
                                                          :point []
                                                          :spot []}
                                                 :skybox (make-skybox-state {:enabled? true
                                                                             :name "desert"
                                                                             :brightness 0.75})
                                                 :background (make-background-state {:color [0.5 0.5 0.5]})
                                                 :containment {:mode "manual-bounds"
                                                               :bounds {:min [-500 -999 -500]
                                                                        :max [500 500 500]}
                                                               :enabled? true}}}}}
         :graph {:graph {:nodes []
                         :edges []}
                 :views {:open-node-keys []}}
         ;; Legacy content that should NOT win
         :scene {:panels [{:kind "legacy-panel"
                           :node-key "legacy:a"
                           :position [99 99 99]
                           :rotation [1 0 0 0]
                           :size [1 1 0]}]
                 :terrains [{:id "legacy-terrain"
                             :kind "heightfield-terrain"
                             :options {:position [-999 -999 -999]
                                       :rotation [1 0 0 0]
                                       :opacity 1.0
                                       :physics true
                                       :sample-spacing [20 20]
                                       :chunk-samples [17 17]
                                       :default-height 0.0}
                             :chunks [{:coord [0 0]}]}]
                 :lights {:ambient {:id "ambient"
                                    :color [0.1 0.1 0.1]
                                    :enabled? true}
                          :directional []
                          :point []
                          :spot []}
                 :skybox (make-skybox-state {:enabled? false
                                             :name "legacy-skybox"
                                             :brightness 0.01})
                 :background (make-background-state {:color [0.01 0.01 0.01]})}
         :physics {:containment {:mode "manual-bounds"
                                 :bounds {:min [-500 -888 -500]
                                          :max [500 500 500]}}}
         :hud {:panels []}})
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      ;; Canonical state should win over legacy
      (local sandbox-scene (and world.state world.state.activity
                                world.state.activity.sessions
                                world.state.activity.sessions.sandbox
                                world.state.activity.sessions.sandbox.scene))
      (assert sandbox-scene "Expected sandbox scene state")
      ;; Panels: canonical wins
      (assert (= (length sandbox-scene.panels) 1)
              "Expected canonical panel count (1, not legacy)")
      (assert (= (. sandbox-scene.panels 1 :kind) "canonical-panel")
              "Expected canonical panel kind, not legacy")
      ;; Terrains: canonical wins
      (assert (= (length sandbox-scene.terrains) 1)
              "Expected canonical terrain count (1, not legacy)")
      (assert (= (. sandbox-scene.terrains 1 :id) "canonical-terrain")
              "Expected canonical terrain id, not legacy")
      ;; Lights: canonical wins
      (assert (= sandbox-scene.lights.ambient.enabled? false)
              "Expected canonical ambient enabled? (false, not legacy true)")
      (assert (= (. sandbox-scene.lights.ambient.color 1) 0.9)
              "Expected canonical ambient red (0.9, not legacy 0.1)")
      ;; Skybox: canonical wins
      (assert (= sandbox-scene.skybox.enabled? true)
              "Expected canonical skybox enabled (true, not legacy false)")
      (assert (= sandbox-scene.skybox.name "desert")
              "Expected canonical skybox name (desert, not legacy)")
      (assert (= sandbox-scene.skybox.brightness 0.75)
              "Expected canonical skybox brightness (0.75, not legacy 0.01)")
      ;; Background: canonical wins
      (assert (= (. sandbox-scene.background.color 1) 0.5)
              "Expected canonical background red (0.5, not legacy 0.01)")
      ;; Containment: canonical wins
      (assert (= (. sandbox-scene.containment.bounds.min 2) -999)
              "Expected canonical containment min-y (-999, not legacy -888)")
      ;; Legacy top-level scene content should be removed
      (local top-scene world.state.scene)
      (when (= (type top-scene) :table)
        (assert (= top-scene.panels nil) "Legacy scene.panels should be removed")
        (assert (= top-scene.terrains nil) "Legacy scene.terrains should be removed")
        (assert (= top-scene.lights nil) "Legacy scene.lights should be removed")
        (assert (= top-scene.skybox nil) "Legacy scene.skybox should be removed")
        (assert (= top-scene.background nil) "Legacy scene.background should be removed"))
      (local physics-state world.state.physics)
      (when physics-state
        (assert (= physics-state.containment nil)
                "Legacy physics.containment should be removed when canonical exists"))
      true)))

(fn fresh-world-can-resolve-default-sandbox-activity []
  ;; Test that a new world's default activity can be resolved by the registry
  (with-temp-dir
    (fn [root]
      (local world-dir (fs.join-path root "world-a"))
      (fs.create-dirs world-dir)
      (local world (HomeWorld {:id "world-a"
                               :name "home"
                               :type "home"
                               :dir world-dir}))
      (world:init {})
      (local active-id (and world.state world.state.activity world.state.activity.active_id))
      (assert active-id "Expected a default active activity id")
      ;; The sandbox activity should be registered and resolvable
      (local spec (Activities.spec "sandbox"))
      (assert spec "Expected sandbox activity to be registered")
      (assert (= (. spec :id) "sandbox")
              "Expected sandbox activity to resolve")
      (assert (= active-id "sandbox")
              (.. "Expected default activity to be sandbox, got " (tostring active-id)))
      true)))

(table.insert tests {:name "fresh HomeWorld has canonical activity session state"
                     :fn fresh-home-world-has-canonical-activity-session-state})
(table.insert tests {:name "legacy world migrates scene state to activity sessions"
                     :fn legacy-world-migrates-scene-state-to-activity-sessions})
(table.insert tests {:name "migrated world preserves canonical structure on reload"
                     :fn migrated-world-preserves-canonical-on-reload})
(table.insert tests {:name "canonical Sandbox state wins over legacy coexistence"
                     :fn canonical-sandbox-state-wins-over-legacy})
(table.insert tests {:name "fresh world can resolve default sandbox activity"
                     :fn fresh-world-can-resolve-default-sandbox-activity})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "home-world-scene-activity-state"
                       :tests tests})))

{:name "home-world-scene-activity-state"
 :tests tests
 :main main}
