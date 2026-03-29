(local fs (require :fs))
(local Signal (require :signal))
(local Graph (require :graph/init))
(local GraphKeyLoaders (require :graph/key-loaders))
(local LightSystemModule (require :light-system))
(local SkyboxState (require :skybox-state))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "world-skybox-node"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "world-skybox-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok result (error result)))

(fn make-skybox-state [opts]
  (local options (or opts {}))
  (SkyboxState.normalize-complete-state
    {:enabled? (if (= options.enabled? nil) true options.enabled?)
     :name (or options.name "lake")
     :brightness (or options.brightness 0.1)}
    "test-world-skybox-node skybox state"))

(fn make-world-entry [opts]
  (local options (or opts {}))
  (local runtime (or options.runtime nil))
  (local state (or options.state {:scene {:panels []
                                          :terrains []
                                          :lights (LightSystemModule.default-state)
                                          :skybox (make-skybox-state)}
                                  :hud {:panels []}}))
  {:id (or options.id "test-world")
   :name (or options.name "Test World")
   :active? (or options.active? false)
   :world {:state state
           :get-runtime (fn [_self] runtime)
           :save-state (fn [_self]
                         (when options.on-save
                           (options.on-save state))
                         true)}})

(fn make-scene-runtime [opts]
  (local options (or opts {}))
  (var lights (or options.lights (LightSystemModule.default-state)))
  (var skybox (or options.skybox (make-skybox-state)))
  {:scene {:capture-state (fn [_self]
                            {:panels []
                             :terrains []
                             :lights lights
                             :skybox skybox})
           :build-default (fn [_self _payload] true)
           :restore-state (fn [_self payload]
                            (assert (and payload payload.lights)
                                    "test scene runtime restore-state requires lights")
                            (assert (and payload payload.skybox)
                                    "test scene runtime restore-state requires skybox")
                            (set lights payload.lights)
                            (set skybox payload.skybox)
                            true)
           :set-light-state (fn [_self value]
                              (set lights value)
                              true)
           :get-light-state (fn [_self]
                              lights)
           :set-skybox-state (fn [_self value]
                               (set skybox value)
                               (when options.on-set-skybox-state
                                 (options.on-set-skybox-state value))
                               true)
           :get-skybox-state (fn [_self]
                               skybox)}})

(fn make-world-manager [opts]
  (local options (or opts {}))
  (local changed (or options.changed (Signal)))
  (local entry (or options.entry (make-world-entry options)))
  (local active-world-id
    (or options.active-world-id
        (and (or options.active? entry.active?) entry.id)
        nil))
  {:changed changed
   :get-world-entry (fn [_self world-id]
                      (if (= world-id entry.id)
                          entry
                          nil))
   :active-world (fn [_self]
                   (if (= active-world-id entry.id) entry nil))
   :active-world-id (fn [_self] active-world-id)})

(fn with-skybox-assets [cb]
  (local previous-app app)
  (local previous-engine (and app app.engine))
  (when (not app)
    (global app {}))
  (set app.engine {:get-asset-path (fn [path]
                                     (.. (assert (os.getenv "SPACE_ASSETS_PATH")
                                                 "SPACE_ASSETS_PATH is required for skybox node tests")
                                         "/"
                                         path))})
  (local (ok result) (pcall cb))
  (if previous-app
      (set app.engine previous-engine)
      (global app nil))
  (if ok result (error result)))

(fn asset-path-resolver [path]
  (.. (assert (os.getenv "SPACE_ASSETS_PATH")
              "SPACE_ASSETS_PATH is required for skybox node tests")
      "/"
      path))

(fn make-icons-stub []
  {:get (fn [_self _name] 4242)
   :resolve (fn [_self _name]
              {:type :font
               :codepoint 4242
               :font {:metadata {:metrics {:ascender 1 :descender -1}
                                 :atlas {:width 1 :height 1}}
                      :glyph-map {65533 {:advance 1}
                                  4242 {:advance 1}}}})})

(fn make-skybox-node-view-harness [opts]
  (local options (or opts {}))
  (local SkyboxNodeView (require :graph/view/views/skybox))
  (local BuildContext (require :build-context))
  (local Intersectables (require :intersectables))
  (local Clickables (require :clickables))
  (local Hoverables (require :hoverables))
  (local intersectables (or app.intersectables (Intersectables)))
  (local clickables (or app.clickables (Clickables {:intersectables intersectables})))
  (local hoverables (or app.hoverables (Hoverables {:intersectables intersectables})))
  (local ctx (BuildContext {:clickables clickables
                            :hoverables hoverables}))
  (set ctx.icons (make-icons-stub))
  (local state {:scene {:panels []
                        :terrains []
                        :lights (LightSystemModule.default-state)
                        :skybox (or options.skybox (make-skybox-state))}
                :hud {:panels []}})
  (var saved-skybox nil)
  (var synced-skybox nil)
  (local runtime (make-scene-runtime {:lights state.scene.lights
                                      :skybox state.scene.skybox
                                      :on-set-skybox-state (fn [value]
                                                             (set synced-skybox value))}))
  (local entry (make-world-entry {:id "test-world"
                                  :state state
                                  :runtime runtime
                                  :active? true
                                  :on-save (fn [saved-state]
                                             (set saved-skybox
                                                  (and saved-state
                                                       saved-state.scene
                                                       saved-state.scene.skybox)))}))
  (local manager (make-world-manager {:id "test-world"
                                      :entry entry
                                      :active-world-id "test-world"}))
  (local {:SkyboxNode SkyboxNode} (require :graph/nodes/skybox))
  (local node (SkyboxNode {:world-id "test-world"
                           :world-manager manager
                           :asset-path-resolver asset-path-resolver}))
  (local builder (SkyboxNodeView node))
  (local view (builder ctx))
  {:state state
   :node node
   :view view
   :synced-skybox (fn [_self] synced-skybox)
   :saved-skybox (fn [_self] saved-skybox)
   :drop (fn [self]
           (self.view:drop)
           (self.node:drop))})

(fn skybox-node-module-exports []
  (local {:SkyboxNode SkyboxNode} (require :graph/nodes/skybox))
  (assert SkyboxNode "skybox module should export SkyboxNode")
  (assert (= (type SkyboxNode) "function") "SkyboxNode should be a function"))

(fn skybox-node-has-correct-key []
  (local {:SkyboxNode SkyboxNode} (require :graph/nodes/skybox))
  (local node (SkyboxNode {:world-id "test-world-123"
                           :world-manager (make-world-manager {:id "test-world-123"})
                           :asset-path-resolver asset-path-resolver}))
  (assert (= node.key "skybox:test-world-123") "SkyboxNode key should include world-id")
  (assert (= node.label "skybox") "SkyboxNode label should be 'skybox'")
  (node:drop))

(fn graph-key-loaders-load-skybox-node []
  (with-temp-dir
    (fn [_dir]
      (local graph (Graph {:with-start false}))
      (GraphKeyLoaders.register graph {:world-manager (make-world-manager {:id "test-world"})
                                       :asset-path-resolver asset-path-resolver})
      (local result (graph:load-by-key "skybox:test-world"))
      (assert result "skybox loader should create node")
      (assert (= result.key "skybox:test-world") "skybox key should match")
      (result:drop)
      (graph:drop))))

(fn skybox-node-available-items-use-injected-resolver []
  (local previous-app app)
  (global app nil)
  (local (ok result)
    (pcall
      (fn []
        (local {:SkyboxNode SkyboxNode} (require :graph/nodes/skybox))
        (local node (SkyboxNode {:world-id "test-world"
                                 :world-manager (make-world-manager {:id "test-world"})
                                 :asset-path-resolver asset-path-resolver}))
        (local items (node:available-items))
        (assert (> (length items) 0) "SkyboxNode should discover skybox choices through injected resolver")
        (node:drop)
        true)))
  (global app previous-app)
  (if ok result (error result)))

(fn skybox-node-view-builds []
  (with-skybox-assets
    (fn []
      (local harness (make-skybox-node-view-harness))
      (assert harness.view.layout "SkyboxNodeView should have layout")
      (assert harness.view.fields "SkyboxNodeView should expose fields")
      (assert harness.view.apply-button "SkyboxNodeView should expose apply button")
      (assert (= (harness.view.fields.name:get-value) "lake")
              "SkyboxNodeView should default to the current skybox name")
      (harness:drop))))

(fn skybox-node-view-applies-changes []
  (with-skybox-assets
    (fn []
      (local harness
        (make-skybox-node-view-harness {:skybox (make-skybox-state {:enabled? true
                                                                    :name "lake"
                                                                    :brightness 0.1})}))
      (local skybox-items (harness.node:available-items))
      (local next-name
        (if (> (length skybox-items) 1)
            (. (. skybox-items 2) 1)
            (. (. skybox-items 1) 1)))
      (harness.view.fields.enabled:set-value "false")
      (harness.view.fields.name:set-value next-name)
      (harness.view.fields.brightness:set-text "0.25")
      (harness.view.apply-button:on-click {})
      (assert (= harness.state.scene.skybox.enabled? false) "Skybox apply should persist enabled flag")
      (assert (= harness.state.scene.skybox.name next-name) "Skybox apply should persist name")
      (assert (= harness.state.scene.skybox.brightness 0.25) "Skybox apply should persist brightness")
      (local synced-skybox (harness:synced-skybox))
      (assert synced-skybox "Skybox apply should sync the active scene")
      (assert (= synced-skybox.name next-name) "Synced skybox should include updated name")
      (local saved-skybox (harness:saved-skybox))
      (assert saved-skybox "Skybox apply should persist world state")
      (assert (= saved-skybox.brightness 0.25) "Saved skybox should include updated brightness")
      (harness:drop))))

(table.insert tests {:name "skybox node module exports"
                     :fn skybox-node-module-exports})
(table.insert tests {:name "skybox node has correct key"
                     :fn skybox-node-has-correct-key})
(table.insert tests {:name "graph key loaders load skybox node"
                     :fn graph-key-loaders-load-skybox-node})
(table.insert tests {:name "skybox node available items use injected resolver"
                     :fn skybox-node-available-items-use-injected-resolver})
(table.insert tests {:name "skybox node view builds"
                     :fn skybox-node-view-builds})
(table.insert tests {:name "skybox node view applies changes"
                     :fn skybox-node-view-applies-changes})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "world-skybox-node"
                       :tests tests})))

{:name "world-skybox-node"
 :tests tests
 :main main}
