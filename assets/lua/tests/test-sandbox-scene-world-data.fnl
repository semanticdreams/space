;; Tests verifying that world-data consumers resolve scene data from the
;; canonical sandbox activity session state, not from legacy scene.* paths.
;; Each test builds a world state where scene.* is empty and all data lives
;; under activity.sessions.sandbox.scene.

(local Signal (require :signal))
(local LightSystemModule (require :light-system))
(local SkyboxState (require :skybox-state))
(local BackgroundState (require :background-state))

(local tests [])

;; ── Minimal test helpers ────────────────────────────────────────────

(fn make-skybox-state [opts]
  (local options (or opts {}))
  (SkyboxState.normalize-complete-state
    {:enabled? (if (= options.enabled? nil) true options.enabled?)
     :default {:name (or options.name "lake")
               :brightness (or options.brightness 0.1)}
     :by-theme (or options.by-theme {})}
    "test-sandbox-scene skybox state"))

(fn make-background-state [opts]
  (local options (or opts {}))
  (BackgroundState.normalize-complete-state
    {:color (or options.color [0.0 0.0 0.0])}
    "test-sandbox-scene background state"))

(fn make-light-state [opts]
  (local options (or opts {}))
  (local state (LightSystemModule.default-state))
  (when (not (= options.ambient nil))
    (set state.ambient options.ambient))
  (when (not (= options.directional nil))
    (set state.directional options.directional))
  (when (not (= options.point nil))
    (set state.point options.point))
  (when (not (= options.spot nil))
    (set state.spot options.spot))
  state)

(fn make-light-record [type-key opts]
  (local options (or opts {}))
  (LightSystemModule.default-record-for-type type-key
                                             {:id options.id
                                              :index options.index}))

(fn make-flat-terrain-record [opts]
  (local options (or opts {}))
  {:id (or options.id "flat-1")
   :kind "flat-terrain"
   :options {:width (or options.width 50)
             :length (or options.length 50)
             :scale (or options.scale [20 1 20])
             :position (or options.position [-500 -100 -500])
             :rotation (or options.rotation [1 0 0 0])
             :opacity (or options.opacity 1.0)
             :physics-thickness (or options.physics-thickness 2.0)}})

(fn make-heightfield-terrain-record [opts]
  (local options (or opts {}))
  (local chunk-samples (or options.chunk-samples [17 17]))
  (local default-height (or options.default-height 0.0))
  (local heights [])
  (for [_ 1 (* (. chunk-samples 1) (. chunk-samples 2))]
    (table.insert heights default-height))
  {:id (or options.id "heightfield-1")
   :name options.name
   :kind "heightfield-terrain"
   :options {:position (or options.position [-160 -100 -160])
             :rotation (or options.rotation [1 0 0 0])
             :opacity (or options.opacity 1.0)
             :physics (if (= options.physics nil) true options.physics)
             :sample-spacing (or options.sample-spacing [20 20])
             :chunk-samples chunk-samples
             :default-height default-height}
   :chunks (or options.chunks [{:coord [0 0]
                                :size chunk-samples
                                 :heights heights}])})

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (tset out k (clone-table v)))
        out)
      value))

(fn same-table? [left right]
  (if (not (= (type left) (type right)))
      false
      (if (not (= (type left) :table))
          (= left right)
          (do
            (var same? true)
            (each [k v (pairs left)]
              (when (not (same-table? v (. right k)))
                (set same? false)))
            (each [k _ (pairs right)]
              (when (= (. left k) nil)
                (set same? false)))
            same?))))

(fn make-world-entry [opts]
  (local options (or opts {}))
  (local runtime (or options.runtime nil))
  (local state (or options.state {:scene {:panels []
                                          :terrains []
                                          :lights (LightSystemModule.default-state)
                                          :skybox (make-skybox-state)
                                          :background (make-background-state)}
                                  :hud {:panels []}}))
  ;; Populate sandbox session state (legacy scene.* may be empty).
  (when (not (= (type state.activity) :table))
    (local sandbox-lights (or state.scene.lights
                              (LightSystemModule.default-state)))
    (local sandbox-skybox (or state.scene.skybox
                              (make-skybox-state)))
    (local sandbox-background (or state.scene.background
                                  (make-background-state)))
    (set state.activity
         {:active_id "sandbox"
          :sessions {:sandbox
                     {:scene
                      {:panels state.scene.panels
                       :terrains state.scene.terrains
                       :lights sandbox-lights
                       :skybox sandbox-skybox
                       :background sandbox-background
                       :containment {:enabled? false}}}}}))
  {:id (or options.id "test-world")
   :name (or options.name "Test World")
   :active? (or options.active? false)
   :world {:state state
           :get-runtime (fn [_self] runtime)
           :save-state (fn [_self]
                         (when options.on-save
                           (options.on-save state))
                         true)}})

(fn make-world-manager [opts]
  (local options (or opts {}))
  (local changed (or options.changed (Signal)))
  (local entry (or options.entry (make-world-entry options)))
  (local active-world-id
    (or options.active-world-id
        (and (or options.active? entry.active?) entry.id)
        nil))
  {:changed changed
   :list-tabs (fn [_self]
                (or options.tabs
                    [{:index 1 :id entry.id :name entry.name :active? (or options.active? false)}]))
   :get-world-entry (fn [_self world-id]
                      (if (= world-id entry.id) entry nil))
   :active-world (fn [_self]
                   (if (= active-world-id entry.id) entry nil))
   :active-world-id (fn [_self] active-world-id)
   :activate-index (or options.activate-index (fn [_self _idx] true))
   :close-world-index (or options.close-world-index (fn [_self _idx] true))
   :create-home-world (or options.create-home-world (fn [_self _opts] {:id "created-world"}))})

;; ── State builder for canonical-owner tests ─────────────────────────

(fn make-canonical-sandbox-state [opts]
  "Build a world state with empty legacy scene.* and sandbox session scene
  populated from opts."
  (local options (or opts {}))
  (local scene-state
    {:panels (or options.panels [])
     :terrains (or options.terrains [])
     :lights (or options.lights (LightSystemModule.default-state))
     :skybox (or options.skybox (make-skybox-state))
     :background (or options.background (make-background-state))
     :containment {:enabled? false}})
  (local activity-state
    {:active_id "sandbox"
     :sessions {:sandbox {:scene scene-state}}})
  {:scene {:panels [] :terrains []}
    :hud {:panels []}
    :activity activity-state})

(fn make-activity-aware-state []
  (local sandbox-scene {:panels [{:kind "sandbox-panel"}]
                        :terrains [(make-flat-terrain-record {:id "sandbox-terrain" :width 30})]
                        :lights (make-light-state {:point [(make-light-record "point" {:id "sandbox-light"})]})
                        :skybox (make-skybox-state {:name "sandbox-sky"})
                        :background (make-background-state {:color [0.1 0.2 0.3]})
                        :containment {:enabled? false}})
  (local graph-scene {:panels [{:kind "graph-panel"}]
                      :terrains [(make-flat-terrain-record {:id "graph-terrain" :width 60})]
                      :lights (make-light-state {:point [(make-light-record "point" {:id "graph-light"})]})
                      :skybox (make-skybox-state {:name "graph-sky"})
                      :background (make-background-state {:color [0.4 0.5 0.6]})
                      :containment {:enabled? false}})
  {:scene {:panels [] :terrains []}
   :hud {:panels []}
   :activity {:active_id "sandbox"
              :sessions {:sandbox {:scene sandbox-scene
                                    :hud {:panels [{:kind "sandbox-hud"}]}}
                         :graph {:scene graph-scene
                                 :hud {:panels [{:kind "graph-hud"}]}
                                 :canvas {:layers [{:id "graph-canvas"}]}}}}})

;; ── Canonical-owner tests ───────────────────────────────────────────

(fn test-sandbox-scene-panels-enumerate-from-sandbox-session []
  (local {:ScenePanelsNode ScenePanelsNode} (require :graph/nodes/scene-panels))
  (local state (make-canonical-sandbox-state {:panels [{:kind "alpha"} {:kind "beta"}]}))
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (ScenePanelsNode {:world-id "test-world" :world-manager manager}))
  (local items (node:emit-items))
  (assert (= (length items) 2) "ScenePanelsNode should enumerate sandbox session panels")
  (assert (= (. (. items 1) 2) "alpha [1]") "first panel should come from sandbox session")
  (assert (= (. (. items 2) 2) "beta [2]") "second panel should come from sandbox session")
  (node:drop))

(fn test-sandbox-terrains-enumerate-from-sandbox-session []
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (local state (make-canonical-sandbox-state
                 {:terrains [(make-heightfield-terrain-record {:id "t1" :name "lava"})
                             (make-flat-terrain-record {:id "t2"})]}))
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (TerrainsNode {:world-id "test-world" :world-manager manager}))
  (local items (node:emit-items))
  (assert (= (length items) 2) "TerrainsNode should enumerate sandbox session terrains")
  (assert (= (. (. items 1) 2) "lava") "first terrain should come from sandbox session")
  (node:drop))

(fn test-sandbox-terrain-edit-persists-to-sandbox-session []
  (local {:FlatTerrainNode FlatTerrainNode} (require :graph/nodes/flat-terrain))
  (local terrain-record (make-flat-terrain-record {:id "terrain-a" :width 50}))
  (local state (make-canonical-sandbox-state {:terrains [terrain-record]}))
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (FlatTerrainNode {:world-id "test-world"
                                :world-manager manager
                                :terrain-id "terrain-a"}))
  (node:apply-values {:width 64 :length 50 :scale [20 1 20]
                      :position [-500 -100 -500] :rotation [1 0 0 0]
                      :opacity 1.0 :physics-thickness 2.0})
  (local sandbox-terrains state.activity.sessions.sandbox.scene.terrains)
  (assert (= (. (. sandbox-terrains 1) :options :width) 64)
          "terrain edit should persist to sandbox session")
  (assert (= (length state.scene.terrains) 0)
          "legacy scene terrains should remain empty")
  (node:drop))

(fn test-sandbox-lights-enumerate-from-sandbox-session []
  (local {:LightsNode LightsNode} (require :graph/nodes/lights))
  (local lights-state (make-light-state {:point [(make-light-record "point" {:id "point-1"})]}))
  (local state (make-canonical-sandbox-state {:lights lights-state}))
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (LightsNode {:world-id "test-world" :world-manager manager}))
  (local items (node:emit-items))
  (assert (= (length items) 4) "lights node should expose four light types from sandbox session")
  (assert (= (. (. items 1) 1 :type-key) "ambient") "ambient type should enumerate")
  (assert (= (. (. items 2) 1 :type-key) "directional") "directional type should enumerate")
  (node:drop))

(fn test-sandbox-light-edit-persists-to-sandbox-session []
  (local {:LightNode LightNode} (require :graph/nodes/light))
  (local lights-state (make-light-state {:point [(make-light-record "point" {:id "point-1"})]}))
  (local state (make-canonical-sandbox-state {:lights lights-state}))
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (LightNode {:world-id "test-world" :world-manager manager
                          :type-key "point" :light-id "point-1"}))
  (node:apply-values {:enabled true :position [1 2 3]
                      :ambient [0.1 0.1 0.1] :diffuse [0.9 0.8 0.7]
                      :specular [1 1 1] :specular-power 16
                      :constant 1.0 :linear 0.2 :quadratic 0.05})
  (local sandbox-lights state.activity.sessions.sandbox.scene.lights)
  (assert (= (. (. sandbox-lights.point 1) :linear) 0.2)
          "light edit should persist to sandbox session")
  (node:drop))

(fn test-explicit-graph-activity-scene-access []
  "WorldData scene reads must use the requested activity session, not sandbox."
  (local WorldData (require :graph/world-data))
  (local state (make-activity-aware-state))
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local scene-panels (WorldData.list-scene-panels manager "test-world" "graph"))
  (assert (= (length scene-panels) 1) "graph activity should expose one scene panel")
  (assert (= (. (. scene-panels 1) 1 :kind) "graph-panel")
          "scene panels should come from graph activity")
  (local terrains (WorldData.list-terrains manager "test-world" "graph"))
  (assert (= (length terrains) 1) "graph activity should expose one terrain")
  (assert (= (. (. terrains 1) 1 :terrain-id) "graph-terrain")
          "terrains should come from graph activity")
  (local background (WorldData.get-background manager "test-world" "graph"))
  (assert (= (. background.color 1) 0.4) "background red should come from graph activity")
  (assert (= (. background.color 3) 0.6) "background blue should come from graph activity"))

(fn test-explicit-graph-activity_mutations_are_isolated []
  "Mutating one activity session must not rewrite sandbox session state."
  (local WorldData (require :graph/world-data))
  (local state (make-activity-aware-state))
  (local sandbox-before (clone-table state.activity.sessions.sandbox.scene))
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (WorldData.update-background manager "test-world" "graph"
    (make-background-state {:color [0.7 0.8 0.9]}))
  (WorldData.update-terrain-record manager "test-world" "graph" "graph-terrain"
    (fn [record]
      (set record.name "graph terrain updated")
      (set record.options.width 90)))
  (WorldData.update-light-record manager "test-world" "graph" "point" "graph-light"
    (fn [record]
      (set record.linear 0.42)))
  (local graph-scene state.activity.sessions.graph.scene)
  (assert (= (. graph-scene.background.color 1) 0.7)
          "graph background should be updated")
  (assert (= (. graph-scene.terrains 1 :name) "graph terrain updated")
          "graph terrain should be updated")
  (assert (= (. graph-scene.lights.point 1 :linear) 0.42)
          "graph light should be updated")
  (assert (same-table? sandbox-before state.activity.sessions.sandbox.scene)
          "sandbox scene state should remain byte-for-byte unchanged"))

(fn test-activity-scene-access-fails-on-missing-requested-activity []
  "Missing requested activity ids must fail instead of returning sandbox data."
  (local WorldData (require :graph/world-data))
  (local state (make-activity-aware-state))
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local (ok err) (pcall WorldData.list-terrains manager "test-world" "missing-activity"))
  (assert (not ok) "missing requested activity should fail loudly")
  (assert (string.find (tostring err) "missing-activity" 1 true)
          "missing activity failure should include requested id")
  (local (panel-ok panel-err)
    (pcall WorldData.list-scene-panels manager "test-world" "missing-activity"))
  (assert (not panel-ok) "scene panels must not fall back to sandbox")
  (assert (string.find (tostring panel-err) "missing-activity" 1 true)
          "scene panel failure should include requested id")
  (local (background-ok background-err)
    (pcall WorldData.get-background manager "test-world" "missing-activity"))
  (assert (not background-ok) "background must not fall back to sandbox")
  (assert (string.find (tostring background-err) "missing-activity" 1 true)
          "background failure should include requested id"))

(fn test-graph-activity-slot-scene-not-treated-as-sandbox-world-content []
  "WorldData must not treat another activity's scene state as sandbox world content."
  (local WorldData (require :graph/world-data))
  (local graph-scene {:panels [{:kind "graph-panel"}]
                      :terrains [(make-heightfield-terrain-record {:id "graph-terrain"})]
                      :lights (LightSystemModule.default-state)
                      :skybox (make-skybox-state)
                      :background (make-background-state)
                      :containment {:enabled? false}})
  (local sandbox-scene {:panels [{:kind "sandbox-panel"}]
                        :terrains [(make-flat-terrain-record {:id "sandbox-terrain"})]
                        :lights (LightSystemModule.default-state)
                        :skybox (make-skybox-state)
                        :background (make-background-state)
                        :containment {:enabled? false}})
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}
                :activity {:active_id "sandbox"
                           :sessions {:sandbox {:scene sandbox-scene}
                                      :graph {:scene graph-scene}}}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local scene-panels (WorldData.list-scene-panels manager "test-world" "sandbox"))
  (assert (= (length scene-panels) 1) "should enumerate only sandbox scene panels")
  (assert (= (. (. scene-panels 1) 1 :kind) "sandbox-panel")
          "scene panels should be from sandbox session")
  (local terrains (WorldData.list-terrains manager "test-world" "sandbox"))
  (assert (= (length terrains) 1) "should enumerate only sandbox terrains")
  (assert (= (. (. terrains 1) 1 :terrain-id) "sandbox-terrain")
          "terrains should be from sandbox session")
  (local skybox (WorldData.get-skybox manager "test-world" "sandbox"))
  (assert skybox "should read skybox from sandbox session")
  (local background (WorldData.get-background manager "test-world" "sandbox"))
  (assert background "should read background from sandbox session"))

(fn test-sandbox-skybox-reads-from-sandbox-session []
  "Skybox reads from sandbox session when legacy scene.skybox is absent."
  (local WorldData (require :graph/world-data))
  (local sandbox-skybox (make-skybox-state {:enabled? false :name "night" :brightness 0.5}))
  ;; Legacy scene has NO skybox key; sandbox session has the real data.
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}
                :activity {:active_id "sandbox"
                           :sessions {:sandbox
                                      {:scene {:panels []
                                               :terrains []
                                               :lights (LightSystemModule.default-state)
                                               :skybox sandbox-skybox
                                               :background (make-background-state)
                                               :containment {:enabled? false}}}}}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local skybox (WorldData.get-skybox manager "test-world" "sandbox"))
  (assert skybox "should read skybox from sandbox session")
  (assert (= skybox.enabled? false) "sandbox skybox should report disabled")
  (assert (= skybox.default.name "night") "sandbox skybox should use custom name"))

(fn test-sandbox-skybox-edit-persists-to-sandbox-session []
  "Skybox edits persist to sandbox session, not to legacy scene."
  (local {:SkyboxNode SkyboxNode} (require :graph/nodes/skybox))
  (local sandbox-skybox (make-skybox-state {:enabled? true :name "lake" :brightness 0.1}))
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}
                :activity {:active_id "sandbox"
                           :sessions {:sandbox
                                      {:scene {:panels []
                                               :terrains []
                                               :lights (LightSystemModule.default-state)
                                               :skybox sandbox-skybox
                                               :background (make-background-state)
                                               :containment {:enabled? false}}}}}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (SkyboxNode {:world-id "test-world"
                           :world-manager manager
                           :asset-path-resolver (fn [path] (.. (assert (os.getenv "SPACE_ASSETS_PATH") "SPACE_ASSETS_PATH required") "/" path))}))
  (node:apply-values {:enabled? false
                      :default {:name "night"
                                :brightness 0.5
                                :tint-color [0.8 0.8 1.0]}
                      :by-theme {}})
  (local sandbox-scene state.activity.sessions.sandbox.scene)
  (assert (= sandbox-scene.skybox.enabled? false)
          "skybox edit should persist to sandbox session")
  (assert (= sandbox-scene.skybox.default.brightness 0.5)
          "skybox edit should update brightness in sandbox session")
  (node:drop))

(fn test-sandbox-background-reads-from-sandbox-session []
  "Background reads from sandbox session when legacy scene.background is absent."
  (local WorldData (require :graph/world-data))
  (local sandbox-bg (make-background-state {:color [0.1 0.2 0.3]}))
  ;; Legacy scene has NO background key; sandbox session has the real data.
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}
                :activity {:active_id "sandbox"
                           :sessions {:sandbox
                                      {:scene {:panels []
                                               :terrains []
                                               :lights (LightSystemModule.default-state)
                                               :skybox (make-skybox-state)
                                               :background sandbox-bg
                                               :containment {:enabled? false}}}}}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local background (WorldData.get-background manager "test-world" "sandbox"))
  (assert background "should read background from sandbox session")
  (assert (= (. background.color 1) 0.1) "sandbox background should use custom red")
  (assert (= (. background.color 2) 0.2) "sandbox background should use custom green"))

(fn test-sandbox-background-edit-persists-to-sandbox-session []
  "Background edits persist to sandbox session, not to legacy scene."
  (local {:BackgroundNode BackgroundNode} (require :graph/nodes/background))
  (local sandbox-bg (make-background-state {:color [0.0 0.0 0.0]}))
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}
                :activity {:active_id "sandbox"
                           :sessions {:sandbox
                                      {:scene {:panels []
                                               :terrains []
                                               :lights (LightSystemModule.default-state)
                                               :skybox (make-skybox-state)
                                               :background sandbox-bg
                                               :containment {:enabled? false}}}}}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (BackgroundNode {:world-id "test-world"
                               :world-manager manager}))
  (node:apply-values {:color [0.4 0.5 0.6]})
  (local sandbox-scene state.activity.sessions.sandbox.scene)
  (assert (= (. sandbox-scene.background.color 1) 0.4)
          "background edit should persist to sandbox session")
  (assert (= (. sandbox-scene.background.color 3) 0.6)
          "background edit should update blue in sandbox session")
  (node:drop))

(fn test-runtime-sync-ignores-non-sandbox-active-slot []
  "When a non-sandbox activity slot is active, sandbox world-data mutations
  must not contaminate the runtime scene. They persist to canonical state only."
  (local WorldData (require :graph/world-data))
  ;; Build a mock runtime Scene with Graph as the active slot.
  ;; The sandbox sync functions must detect this and skip direct scene mutation.
  (var call-log [])
  (local mock-scene
    {:active-activity-slot-id "graph"
     :activity-slot (fn [_self activity-id]
                      (when (= activity-id "sandbox")
                        {:scene-state {:panels [] :terrains [] :lights {}
                                       :skybox {} :background {} :containment {}}}))
     :set-light-state (fn [_self _lights]
                        (table.insert call-log "set-light-state-called"))
     :set-skybox-state (fn [_self _skybox]
                         (table.insert call-log "set-skybox-state-called"))
     :set-background-state (fn [_self _bg]
                            (table.insert call-log "set-background-state-called"))
     :replace-terrain-record (fn [_self _tid _rec]
                               (table.insert call-log "replace-terrain-record-called"))
     :add-terrain-record (fn [_self _rec]
                           (table.insert call-log "add-terrain-record-called"))
     :remove-terrain (fn [_self _tid]
                       (table.insert call-log "remove-terrain-called"))})
  (local runtime {:scene mock-scene})
  (local terrain-record (make-heightfield-terrain-record {:id "t1"}))
  (local state {:scene {:panels [{:kind "alpha"}] :terrains [terrain-record]}
                :hud {:panels []}
                :activity {:active_id "sandbox"
                           :sessions {:sandbox
                                      {:scene {:panels [{:kind "alpha"}]
                                               :terrains [terrain-record]
                                               :lights (LightSystemModule.default-state)
                                               :skybox (make-skybox-state)
                                               :background (make-background-state)
                                               :containment {:enabled? false}}}}}})
  (local entry {:id "test-world"
                :name "Test World"
                :active? true
                :world {:state state
                        :get-runtime (fn [_self] runtime)
                        :save-state (fn [_self] true)}})
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  ;; Mutate terrain: should NOT call runtime scene methods when graph is active.
  (WorldData.add-terrain manager "test-world" "sandbox" "heightfield-terrain")
  (assert (= (length call-log) 0)
          "add-terrain should not touch runtime scene when sandbox is inactive")
  (WorldData.update-terrain-record manager "test-world" "sandbox" "t1"
    (fn [record] (set record.name "updated")))
  (assert (= (length call-log) 0)
          "update-terrain should not touch runtime scene when sandbox is inactive")
  ;; Mutate light: should NOT call runtime scene.
  (WorldData.add-light manager "test-world" "sandbox" "point")
  (assert (= (length call-log) 0)
          "add-light should not touch runtime scene when sandbox is inactive")
  ;; Mutate skybox: should NOT call runtime scene.
  (WorldData.update-skybox manager "test-world" "sandbox"
    (make-skybox-state {:enabled? false :name "night" :brightness 0.5}))
  (assert (= (length call-log) 0)
          "update-skybox should not touch runtime scene when sandbox is inactive")
  ;; Mutate background: should NOT call runtime scene.
  (WorldData.update-background manager "test-world" "sandbox"
    (make-background-state {:color [0.1 0.2 0.3]}))
  (assert (= (length call-log) 0)
          "update-background should not touch runtime scene when sandbox is inactive"))

(table.insert tests {:name "sandbox scene panels enumerate from sandbox session"
                     :fn test-sandbox-scene-panels-enumerate-from-sandbox-session})
(table.insert tests {:name "sandbox terrains enumerate from sandbox session"
                     :fn test-sandbox-terrains-enumerate-from-sandbox-session})
(table.insert tests {:name "sandbox terrain edit persists to sandbox session"
                     :fn test-sandbox-terrain-edit-persists-to-sandbox-session})
(table.insert tests {:name "sandbox lights enumerate from sandbox session"
                     :fn test-sandbox-lights-enumerate-from-sandbox-session})
(table.insert tests {:name "sandbox light edit persists to sandbox session"
                      :fn test-sandbox-light-edit-persists-to-sandbox-session})
(table.insert tests {:name "explicit graph activity scene access"
                     :fn test-explicit-graph-activity-scene-access})
(table.insert tests {:name "explicit graph activity mutations are isolated"
                     :fn test-explicit-graph-activity_mutations_are_isolated})
(table.insert tests {:name "activity scene access fails on missing requested activity"
                     :fn test-activity-scene-access-fails-on-missing-requested-activity})
(table.insert tests {:name "graph activity slot scene not treated as sandbox world content"
                     :fn test-graph-activity-slot-scene-not-treated-as-sandbox-world-content})
(table.insert tests {:name "sandbox skybox reads from sandbox session"
                     :fn test-sandbox-skybox-reads-from-sandbox-session})
(table.insert tests {:name "sandbox skybox edit persists to sandbox session"
                     :fn test-sandbox-skybox-edit-persists-to-sandbox-session})
(table.insert tests {:name "sandbox background reads from sandbox session"
                     :fn test-sandbox-background-reads-from-sandbox-session})
(table.insert tests {:name "sandbox background edit persists to sandbox session"
                     :fn test-sandbox-background-edit-persists-to-sandbox-session})
(table.insert tests {:name "runtime sync ignores non-sandbox active slot"
                     :fn test-runtime-sync-ignores-non-sandbox-active-slot})

(fn test-runtime-reads-ignore-non-sandbox-active-slot []
  "When Graph is the active slot, list-scene-panels, list-terrains, and
  remove-scene-panel must ignore runtime scene data and use canonical sandbox
  session state instead."
  (local WorldData (require :graph/world-data))
  ;; Build a mock runtime Scene with Graph active and populated runtime data
  ;; that differs from sandbox session data.
  (local mock-scene
    {:active-activity-slot-id "graph"
     ;; Runtime scene has different panels/terrains than sandbox session.
     :scene-children [{:persistence {:kind "graph-runtime-panel"}}]
     :scene-terrains [{:record {:id "graph-terrain" :kind "heightfield-terrain"}}]
     :remove-panel-child (fn [_self _element] true)})
  (local runtime {:scene mock-scene})
  ;; Sandbox session has its own distinct data.
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}
                :activity {:active_id "sandbox"
                           :sessions {:sandbox
                                      {:scene {:panels [{:kind "sandbox-panel"}]
                                               :terrains [(make-heightfield-terrain-record {:id "sandbox-terrain" :name "lava"})]
                                               :lights (LightSystemModule.default-state)
                                               :skybox (make-skybox-state)
                                               :background (make-background-state)
                                               :containment {:enabled? false}}}}}})
  (local entry {:id "test-world"
                :name "Test World"
                :active? true
                :world {:state state
                        :get-runtime (fn [_self] runtime)
                        :save-state (fn [_self] true)}})
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  ;; list-scene-panels must NOT use runtime scene-children when graph is active.
  (local panels (WorldData.list-scene-panels manager "test-world" "sandbox"))
  (assert (= (length panels) 1) "should list only sandbox session panels")
  (assert (= (. (. panels 1) 1 :kind) "sandbox-panel")
          "panel should come from sandbox session, not graph runtime")
  ;; list-terrains must NOT use runtime scene-terrains when graph is active.
  (local terrains (WorldData.list-terrains manager "test-world" "sandbox"))
  (assert (= (length terrains) 1) "should list only sandbox session terrains")
  (assert (= (. (. terrains 1) 1 :label) "lava")
          "terrain should come from sandbox session, not graph runtime")
  ;; remove-scene-panel must NOT remove from runtime scene when graph is active;
  ;; it should fall through to canonical state path and remove from session.
  (assert (= (length (. state.activity.sessions.sandbox.scene :panels)) 1)
          "sandbox session should start with one panel")
  (WorldData.remove-scene-panel manager "test-world" "sandbox" 1)
  (assert (= (length (. state.activity.sessions.sandbox.scene :panels)) 0)
          "remove-scene-panel should remove from sandbox session when graph is active"))

(fn test-terrain-mutators-fail-on-missing-sandbox-session []
  "Terrain mutators must fail loudly when activity.sessions.sandbox.scene
  is absent rather than silently creating it."
  (local WorldData (require :graph/world-data))
  ;; World with state but no sandbox session scene.
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}})
  ;; Intentionally no activity or sessions — sandbox scene missing.
  (local entry {:id "test-world"
                :name "Test World"
                :active? false
                :world {:state state
                        :get-runtime (fn [_self] nil)
                        :save-state (fn [_self] true)}})
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  ;; add-terrain should assert
  (local (ok-add err-add)
    (pcall (fn []
              (WorldData.add-terrain manager "test-world" "sandbox" "heightfield-terrain"))))
  (assert (not ok-add) "add-terrain should fail on missing sandbox session")
  (assert (string.find (tostring err-add) "requires world.state.activity" 1 true)
          "add-terrain failure should mention missing activity state")
  ;; update-terrain-record should assert
  (local (ok-upd err-upd)
    (pcall (fn []
              (WorldData.update-terrain-record manager "test-world" "sandbox" "t1"
               (fn [r] (set r.name "x"))))))
  (assert (not ok-upd) "update-terrain-record should fail on missing sandbox session")
  (assert (string.find (tostring err-upd) "requires world.state.activity" 1 true)
          "update-terrain-record failure should mention missing activity state")
  ;; remove-terrain should assert
  (local (ok-rem err-rem)
    (pcall (fn []
              (WorldData.remove-terrain manager "test-world" "sandbox" "t1"))))
  (assert (not ok-rem) "remove-terrain should fail on missing sandbox session")
  (assert (string.find (tostring err-rem) "requires world.state.activity" 1 true)
          "remove-terrain failure should mention missing activity state"))

(table.insert tests {:name "runtime reads ignore non-sandbox active slot"
                      :fn test-runtime-reads-ignore-non-sandbox-active-slot})
(table.insert tests {:name "terrain mutators fail on missing sandbox session"
                      :fn test-terrain-mutators-fail-on-missing-sandbox-session})

;; ── R5-1: WorldData mutations update runtime.activity-session-state ────

(fn test-worlddata-mutation-updates-activity-session-state-when-inactive []
  "R5-1: When WorldData mutates canonical Sandbox scene state while an active
  runtime exists and Sandbox is inactive, the runtime's activity-session-state
  sandbox.scene must be updated so that Activities.snapshot-activity-sessions
  cannot save stale pending data over the mutation."
  (local WorldData (require :graph/world-data))
  (local SkyboxState (require :skybox-state))
  (local BackgroundState (require :background-state))
  (local LightSystemModule (require :light-system))
  ;; Build a runtime where Graph is the active slot and sandbox was never activated.
  ;; The runtime has activity-session-state with stale sandbox scene data.
  (var call-log [])
  (var slot-skybox nil)
  (local mock-scene
    {:active-activity-slot-id "graph"
     :activity-slot (fn [_self activity-id]
                      (when (= activity-id "sandbox")
                        ;; Sandbox slot exists but has stale scene-state
                        {:scene-state {:panels [{:kind "stale-panel"}]
                                       :terrains []
                                       :lights (LightSystemModule.default-state)
                                       :skybox (make-skybox-state {:enabled? true :name "stale" :brightness 0.99})
                                       :background (make-background-state {:color [0.99 0.99 0.99]})
                                       :containment {:enabled? false}}}))
     :set-light-state (fn [_self _lights]
                        (table.insert call-log "set-light-state-called"))
     :set-skybox-state (fn [_self _skybox]
                         (table.insert call-log "set-skybox-state-called"))
     :set-background-state (fn [_self _bg]
                            (table.insert call-log "set-background-state-called"))
     :replace-terrain-record (fn [_self _tid _rec]
                               (table.insert call-log "replace-terrain-record-called"))
     :add-terrain-record (fn [_self _rec]
                           (table.insert call-log "add-terrain-record-called"))
     :remove-terrain (fn [_self _tid]
                       (table.insert call-log "remove-terrain-called"))
     :remove-panel-child (fn [_self _element] true)})
  ;; activity-session-state holds stale sandbox scene that should be updated.
  (local stale-sandbox-scene
    {:panels [{:kind "stale-panel"}]
     :terrains []
     :lights (LightSystemModule.default-state)
     :skybox (make-skybox-state {:enabled? true :name "stale" :brightness 0.99})
     :background (make-background-state {:color [0.99 0.99 0.99]})
     :containment {:enabled? false}})
  (local runtime {:scene mock-scene
                  :activity-session-state {:sandbox {:scene stale-sandbox-scene}
                                          :graph {:scene {:panels []}}}})
  (local terrain-record (make-heightfield-terrain-record {:id "r5-1-terrain"}))
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}
                :activity {:active_id "sandbox"
                           :sessions {:sandbox
                                      {:scene {:panels [{:kind "removable-panel"}]
                                               :terrains [terrain-record]
                                               :lights (LightSystemModule.default-state)
                                               :skybox (make-skybox-state {:enabled? true :name "lake" :brightness 0.1})
                                               :background (make-background-state {:color [0.1 0.2 0.3]})
                                               :containment {:enabled? false}}}}}})
  (local entry {:id "test-world"
                :name "Test World"
                :active? true
                :world {:state state
                        :get-runtime (fn [_self] runtime)
                        :save-state (fn [_self] true)}})
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  ;; R5-1: Remove a canonical panel while Sandbox is inactive.
  ;; The stale pending scene has its own panel; removal + refresh must update
  ;; activity-session-state so the stale panel does not come back on save.
  (assert (= (length (. state.activity.sessions.sandbox.scene :panels)) 1)
          "canonical sandbox scene should start with one panel")
  (WorldData.remove-scene-panel manager "test-world" "sandbox" 1)
  (assert (= (length (. state.activity.sessions.sandbox.scene :panels)) 0)
          "remove-scene-panel should remove from canonical session")
  ;; R5-1: The runtime's activity-session-state sandbox scene must be refreshed
  ;; so it reflects the removal (not the stale panel that was pending).
  (local pending-scene runtime.activity-session-state.sandbox.scene)
  (assert pending-scene "activity-session-state sandbox must exist")
  (assert (not (= pending-scene stale-sandbox-scene))
          "activity-session-state sandbox must not be the stale object after removal")
  (assert (= (length (or pending-scene.panels [])) 0)
          "pending sandbox scene panels must be empty after removal and refresh")
  ;; Mutate skybox via WorldData.update-skybox
  (WorldData.update-skybox manager "test-world" "sandbox"
    (make-skybox-state {:enabled? false :name "night" :brightness 0.5}))
  (assert (= (length call-log) 0)
          "update-skybox should not touch runtime scene when sandbox is inactive")
  ;; R5-1: The runtime's activity-session-state sandbox scene must be updated.
  (assert (= pending-scene.skybox.enabled? false)
          "pending sandbox scene skybox.enabled? must reflect mutation")
  (assert (= pending-scene.skybox.default.name "night")
          "pending sandbox scene skybox.name must reflect mutation")
  (assert (= pending-scene.skybox.default.brightness 0.5)
          "pending sandbox scene skybox.brightness must reflect mutation")
  ;; Mutate background
  (WorldData.update-background manager "test-world" "sandbox"
    (make-background-state {:color [0.4 0.5 0.6]}))
  (assert (= (. pending-scene.background.color 1) 0.4)
          "pending sandbox scene background must reflect mutation")
  ;; Mutate terrain
  (WorldData.update-terrain-record manager "test-world" "sandbox" "r5-1-terrain"
    (fn [record] (set record.name "mutated-terrain")))
  (assert (= (. pending-scene.terrains 1 :name) "mutated-terrain")
          "pending sandbox scene terrain must reflect mutation")
  ;; Mutate lights
  (WorldData.add-light manager "test-world" "sandbox" "point")
  (assert (= (length pending-scene.lights.point) 1)
          "pending sandbox scene lights must reflect added point light"))

(table.insert tests {:name "R5-1 WorldData mutation updates activity-session-state when inactive"
                     :fn test-worlddata-mutation-updates-activity-session-state-when-inactive})

;; ── R5-2: WorldData.update-skybox updates active slot scene-state.skybox ──

(fn test-worlddata-update-skybox-updates-active-slot-scene-state []
  "R5-2: With Sandbox active, WorldData.update-skybox must update the active
  sandbox slot's scene-state.skybox with the normalized complete skybox
  before applying the resolved renderer state."
  (local WorldData (require :graph/world-data))
  (local SkyboxState (require :skybox-state))
  (var resolved-skybox nil)
  (var slot-skybox nil)
  (local sandbox-slot
    {:scene-state {:panels []
                   :terrains []
                   :lights {}
                   :skybox (make-skybox-state {:enabled? true :name "lake" :brightness 0.1})
                   :background {}
                   :containment {}}})
  (local mock-scene
    {:active-activity-slot-id "sandbox"
     :activity-slot (fn [_self activity-id]
                      (when (= activity-id "sandbox")
                        sandbox-slot))
     :set-skybox-state (fn [_self skybox]
                        (set resolved-skybox skybox)
                        true)})
  (local runtime {:scene mock-scene
                  :activity-session-state {}})
  (local terrain-record (make-heightfield-terrain-record {:id "r5-2-terrain"}))
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}
                :activity {:active_id "sandbox"
                           :sessions {:sandbox
                                      {:scene {:panels []
                                               :terrains [terrain-record]
                                               :lights (LightSystemModule.default-state)
                                               :skybox (make-skybox-state {:enabled? true :name "lake" :brightness 0.1})
                                               :background (make-background-state {:color [0 0 0]})
                                               :containment {:enabled? false}}}}}})
  (local entry {:id "test-world"
                :name "Test World"
                :active? true
                :world {:state state
                        :get-runtime (fn [_self] runtime)
                        :save-state (fn [_self] true)}})
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  ;; update-skybox with a complete-by-theme-policy skybox
  (WorldData.update-skybox manager "test-world" "sandbox"
    (SkyboxState.normalize-complete-state
      {:enabled? true
       :default {:name "desert"
                 :brightness 0.35
                 :tint-color [1.0 1.0 1.0]}
       :by-theme {:dark {:name "night"
                          :brightness 0.6
                          :tint-color [0.8 0.8 1.0]}}}
      "R5-2 test skybox"))
  ;; R5-2: The active sandbox slot's scene-state.skybox must be the
  ;; complete policy (not the resolved renderer format).
  (assert (= (type sandbox-slot.scene-state.skybox.default) :table)
          "slot scene-state skybox must have :default policy")
  (assert (= sandbox-slot.scene-state.skybox.default.name "desert")
          "slot scene-state skybox default name must be updated")
  (assert (= sandbox-slot.scene-state.skybox.default.brightness 0.35)
          "slot scene-state skybox default brightness must be updated")
  (assert (= (type sandbox-slot.scene-state.skybox.by-theme) :table)
          "slot scene-state skybox must have :by-theme overrides")
  (assert (= sandbox-slot.scene-state.skybox.by-theme.dark.name "night")
          "slot scene-state skybox dark override must be updated")
  ;; The renderer should receive the resolved skybox (for active theme).
  (assert resolved-skybox "renderer should receive resolved skybox")
  (assert (= (type resolved-skybox.name) :string)
          "resolved skybox should have a :name field"))

(table.insert tests {:name "R5-2 WorldData.update-skybox updates active slot scene-state skybox"
                     :fn test-worlddata-update-skybox-updates-active-slot-scene-state})

;; ── R6-3: Active Sandbox remove-scene-panel updates canonical state ────

(fn test-active-sandbox-remove-panel-updates-canonical-session []
  "R6-3: When Sandbox is the active slot, WorldData.remove-scene-panel must
  update both the canonical activity.sessions.sandbox.scene.panels AND the
  runtime.activity-session-state.sandbox.scene so capture/save/pending
  sessions no longer contain the removed panel."
  (local WorldData (require :graph/world-data))
  (local LightSystemModule (require :light-system))
  ;; Build a runtime where Sandbox IS the active slot.
  (var removed-element nil)
  (local mock-scene
    {:active-activity-slot-id "sandbox"
     :scene-children [{:element {:drop (fn [_])}
                        ;; Persistence data that matches the canonical panel
                        :persistence {:kind "test-panel"
                                      :graph-map-id "gm-1"
                                      :node-key "nk-1"
                                      :label "Test Panel"}}]
     :remove-panel-child (fn [_self element]
                           (set removed-element element)
                           true)})
  (local runtime {:scene mock-scene
                  :activity-session-state {:sandbox {:scene {:panels []}}}})
  ;; Canonical sandbox session has matching panel
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}
                :activity {:active_id "sandbox"
                           :sessions {:sandbox
                                      {:scene {:panels [{:kind "test-panel"
                                                         :graph-map-id "gm-1"
                                                         :node-key "nk-1"
                                                         :label "Test Panel"}]
                                               :terrains []
                                               :lights (LightSystemModule.default-state)
                                               :skybox (make-skybox-state)
                                               :background (make-background-state)
                                               :containment {:enabled? false}}}}}})
  (local entry {:id "test-world"
                :name "Test World"
                :active? true
                :world {:state state
                        :get-runtime (fn [_self] runtime)
                        :save-state (fn [_self] true)}})
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  ;; Precondition: canonical has one panel
  (assert (= (length (. state.activity.sessions.sandbox.scene :panels)) 1)
          "canonical sandbox session should start with one panel")
  ;; Remove panel through WorldData (Sandbox active)
  (WorldData.remove-scene-panel manager "test-world" "sandbox" 1)
  ;; R6-3: The canonical session panels must be empty
  (assert (= (length (. state.activity.sessions.sandbox.scene :panels)) 0)
          "remove-scene-panel with active sandbox must remove from canonical session")
  ;; R6-3: runtime.activity-session-state.sandbox.scene must reflect removal
  (local pending-scene runtime.activity-session-state.sandbox.scene)
  (assert pending-scene "activity-session-state sandbox must exist")
  (assert (= (length (or pending-scene.panels [])) 0)
          "pending sandbox scene panels must be empty after removal")
  ;; The runtime panel was actually removed
  (assert removed-element
          "remove-panel-child must have been called on the runtime scene"))

(table.insert tests {:name "R6-3 active sandbox remove-scene-panel updates canonical and pending"
                      :fn test-active-sandbox-remove-panel-updates-canonical-session})

;; ── R6-3 duplicate-panel regression ──────────────────────────────────

;; Helper: shallow clone a table
(fn shallow-clone-table [tbl]
  (local out {})
  (each [k v (pairs tbl)]
    (tset out k v))
  out)

(fn test-active-sandbox-remove-panel-duplicates-uses-index-not-persistence []
  "R6-3: When two panels have identical persistence except position/rotation,
  removing the first panel through the active runtime must remove the
  corresponding canonical panel (by index/order), not the wrong duplicate.
  Persistence matching must not cause the wrong duplicate panel to be removed."
  (local WorldData (require :graph/world-data))
  (local LightSystemModule (require :light-system))
  ;; Build a runtime where Sandbox IS the active slot with two panels that
  ;; share the same persistence data but differ only in position.
  (var removed-element nil)
  (local runtime-panel-1-element {:drop (fn [_])})
  (local runtime-panel-2-element {:drop (fn [_])})
  (local base-persistence {:kind "test-panel"
                           :graph-map-id "gm-1"
                           :node-key "nk-1"
                           :label "Test Panel"})
  (local mock-scene
    {:active-activity-slot-id "sandbox"
      :scene-children [{:element runtime-panel-1-element
                         :persistence (doto (shallow-clone-table base-persistence)
                                        (tset :position [0 0 0]))}
                        {:element runtime-panel-2-element
                         :persistence (doto (shallow-clone-table base-persistence)
                                        (tset :position [5 5 5]))}]
     :remove-panel-child (fn [_self element]
                           (set removed-element element)
                           true)})
  (local runtime {:scene mock-scene
                  :activity-session-state {:sandbox {:scene {:panels []}}}})
  ;; Canonical sandbox session has two panels with same persistence but
  ;; different positions. Order matches runtime.
  (local canonical-panel-1 {:kind "test-panel"
                            :graph-map-id "gm-1"
                            :node-key "nk-1"
                            :label "Test Panel"
                            :position [0 0 0]})
  (local canonical-panel-2 {:kind "test-panel"
                            :graph-map-id "gm-1"
                            :node-key "nk-1"
                            :label "Test Panel"
                            :position [5 5 5]})
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}
                :activity {:active_id "sandbox"
                           :sessions {:sandbox
                                      {:scene {:panels [canonical-panel-1 canonical-panel-2]
                                               :terrains []
                                               :lights (LightSystemModule.default-state)
                                               :skybox (make-skybox-state)
                                               :background (make-background-state)
                                               :containment {:enabled? false}}}}}})
  (local entry {:id "test-world"
                :name "Test World"
                :active? true
                :world {:state state
                        :get-runtime (fn [_self] runtime)
                        :save-state (fn [_self] true)}})
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  ;; Precondition: canonical has two panels
  (local canonical-panels (. state.activity.sessions.sandbox.scene :panels))
  (assert (= (length canonical-panels) 2)
          "canonical sandbox session should start with two panels")
  ;; Remove the FIRST panel (index 1)
  (WorldData.remove-scene-panel manager "test-world" "sandbox" 1)
  ;; R6-3: Canonical should have ONE panel remaining — the second one
  (assert (= (length canonical-panels) 1)
          "canonical panels should have one remaining after removal")
  (assert (= (. canonical-panels 1 :position 1) 5)
          "remaining canonical panel must be the second panel (position x=5), not the first (x=0)")
  ;; Pending session must also reflect removal of first panel, leaving the second
  (local pending-scene runtime.activity-session-state.sandbox.scene)
  (assert pending-scene "activity-session-state sandbox must exist")
  (assert (= (length (or pending-scene.panels [])) 1)
          "pending scene panels should have one remaining after removal")
  (assert (= (. pending-scene.panels 1 :position 1) 5)
          "remaining pending panel must be the second panel (position x=5), not the first (x=0)")
  ;; The runtime removal was called with the FIRST panel's element
  (assert removed-element
          "remove-panel-child must have been called on the runtime scene")
  (assert (= removed-element runtime-panel-1-element)
          "remove-panel-child must receive the first panel's element, not the second"))

(table.insert tests {:name "R6-3 duplicate panels use index-based removal not persistence matching"
                      :fn test-active-sandbox-remove-panel-duplicates-uses-index-not-persistence})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "sandbox-scene-world-data"
                       :tests tests})))

{:name "sandbox-scene-world-data"
 :tests tests
 :main main}
