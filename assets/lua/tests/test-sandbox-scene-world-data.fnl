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
  (local scene-panels (WorldData.list-scene-panels manager "test-world"))
  (assert (= (length scene-panels) 1) "should enumerate only sandbox scene panels")
  (assert (= (. (. scene-panels 1) 1 :kind) "sandbox-panel")
          "scene panels should be from sandbox session")
  (local terrains (WorldData.list-terrains manager "test-world"))
  (assert (= (length terrains) 1) "should enumerate only sandbox terrains")
  (assert (= (. (. terrains 1) 1 :terrain-id) "sandbox-terrain")
          "terrains should be from sandbox session")
  (local skybox (WorldData.get-skybox manager "test-world"))
  (assert skybox "should read skybox from sandbox session")
  (local background (WorldData.get-background manager "test-world"))
  (assert background "should read background from sandbox session"))

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
(table.insert tests {:name "graph activity slot scene not treated as sandbox world content"
                     :fn test-graph-activity-slot-scene-not-treated-as-sandbox-world-content})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "sandbox-scene-world-data"
                       :tests tests})))

{:name "sandbox-scene-world-data"
 :tests tests
 :main main}
