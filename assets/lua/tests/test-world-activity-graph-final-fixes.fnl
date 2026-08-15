(local Graph (require :graph/init))
(local Signal (require :signal))
(local LightSystem (require :light-system))
(local SkyboxState (require :skybox-state))
(local BackgroundState (require :background-state))

(local tests [])

(fn make-icons-stub []
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {65533 {:advance 1}
                           4242 {:advance 1}}})
  {:font font
   :get (fn [_self _name] 4242)
   :resolve (fn [self name]
              {:type :font
               :codepoint (self:get name)
               :font font})})

(fn make-build-ctx []
  (local BuildContext (require :build-context))
  (local Intersectables (require :intersectables))
  (local Clickables (require :clickables))
  (local Hoverables (require :hoverables))
  (local intersectables (if app.intersectables app.intersectables (Intersectables)))
  (local clickables (if app.clickables app.clickables (Clickables {:intersectables intersectables})))
  (local hoverables (if app.hoverables app.hoverables (Hoverables {:intersectables intersectables})))
  (local ctx (BuildContext {:clickables clickables
                            :hoverables hoverables}))
  (set ctx.icons (make-icons-stub))
  ctx)

(fn make-background-state []
  (BackgroundState.normalize-complete-state {:color [0.0 0.0 0.0]}
                                            "world activity graph final fixes"))

(fn make-skybox-state []
  (SkyboxState.normalize-complete-state {:enabled? true
                                         :default {:name "lake" :brightness 0.1}
                                         :by-theme {}}
                                        "world activity graph final fixes"))

(fn make-scene-state [opts]
  (local options (if opts opts {}))
  {:panels (if options.panels options.panels [])
   :terrains (if options.terrains options.terrains [])
   :lights (if options.lights options.lights (LightSystem.default-state))
   :skybox (if options.skybox options.skybox (make-skybox-state))
   :background (if options.background options.background (make-background-state))
   :containment {:enabled? false}})

(fn make-heightfield-terrain [id]
  {:id id
   :kind "heightfield-terrain"
   :options {:position [-160 -100 -160]
             :rotation [1 0 0 0]
             :opacity 1.0
             :physics true
             :sample-spacing [20 20]
             :chunk-samples [17 17]
             :default-height 0.0}
   :chunks [{:coord [0 0]
             :size [17 17]
             :heights []}]})

(fn save-state [] true)

(fn make-manager [state]
  (local changed (Signal))
  (local entry {:id "test-world"
                :name "Test World"
                :world {:state state
                        :save-state save-state}})
  (fn get-world-entry [_self world-id]
    (if (= world-id "test-world") entry nil))
  {:changed changed
   :get-world-entry get-world-entry})

(fn activity-session [scene]
  {:scene scene})

(fn find-activity-item [items activity-id]
  (var found nil)
  (each [_ item (ipairs items)]
    (when (= (. item 1 :id) activity-id)
      (set found item)))
  found)

(fn make-hierarchy-state []
  (local graph-scene (make-scene-state {:panels [{:kind "graph-panel"}]
                                        :terrains [(make-heightfield-terrain "graph-terrain")]}))
  {:scene {:panels [] :terrains []}
   :activity {:active_id "sandbox"
              :sessions {:sandbox (activity-session (make-scene-state))
                         :graph (activity-session graph-scene)}}})

(fn make-stale-category-state []
  (local graph-scene (make-scene-state {:panels [{:kind "graph-panel"}]
                                        :terrains [(make-heightfield-terrain "graph-terrain")]}))
  {:scene {:panels [] :terrains []}
   :activity {:active_id "graph"
              :sessions {:graph (activity-session graph-scene)}}})

(fn asset-path-resolver [_name]
  "/tmp/space/tests/skybox")

(fn make-remove-nodes-recorder [removed]
  (fn remove-nodes [_self nodes opts]
    (table.insert removed {:nodes nodes :opts opts})))

(fn world-activity-hierarchy-views-navigate-to-scene-category []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (local ctx (make-build-ctx))
  (local graph-map (Graph {:with-start false}))
  (local state (make-hierarchy-state))
  (local manager (make-manager state))
  (local world-node (WorldNode {:world-id "test-world" :world-manager manager}))
  (graph-map:add-node world-node {})
  (world-node:add-category-node (. (world-node:emit-categories) 1))
  (local activities-node (assert (graph-map:lookup "world-activities:test-world")
                                 "world view path should add activities node"))
  (assert activities-node.view "activities collection should expose a node view")
  (local activities-view ((activities-node.view activities-node) ctx))
  (activities-view.search.submitted:emit (assert (find-activity-item (activities-node:emit-items) "graph")
                                                 "activities should include graph session"))
  (local activity-node (assert (graph-map:lookup "world-activity:test-world:graph")
                               "activities view should add selected activity node"))
  (activity-node:open-surfaces)
  (local surfaces-node (assert (graph-map:lookup "activity-surfaces:test-world:graph")
                               "activity node should open surfaces node"))
  (assert surfaces-node.view "surfaces collection should expose a node view")
  (local surfaces-view ((surfaces-node.view surfaces-node) ctx))
  (surfaces-view.search.submitted:emit (. (surfaces-node:emit-items) 1))
  (local scene-node (assert (graph-map:lookup "activity-scene:test-world:graph")
                            "surfaces view should add selected scene surface node"))
  (assert scene-node.view "activity scene surface should expose a node view")
  (local scene-view ((scene-node.view scene-node) ctx))
  (scene-view.search.submitted:emit (. scene-view.search.items 1))
  (assert (graph-map:lookup "activity-scene-panels:test-world:graph")
          "scene surface view should add selected scene category node")
  (scene-view:drop)
  (surfaces-view:drop)
  (activities-view:drop)
  (world-node:drop)
  (graph-map:drop))

(fn world-activity-view-opens-surfaces []
  (local {:WorldActivityNode WorldActivityNode} (require :graph/nodes/world-activity))
  (local ctx (make-build-ctx))
  (local graph-map (Graph {:with-start false}))
  (local state (make-hierarchy-state))
  (local manager (make-manager state))
  (local activity-node (WorldActivityNode {:world-id "test-world"
                                           :activity-id "sandbox"
                                           :world-manager manager}))
  (graph-map:add-node activity-node {})
  (assert activity-node.view "world activity should expose a node view")
  (local activity-view ((activity-node.view activity-node) ctx))
  (local surfaces-item (assert (. activity-view.search.items 1)
                               "world activity view should expose surfaces item"))
  (assert (= (. surfaces-item 1 :id) "surfaces")
          "world activity view first item should be surfaces")
  (activity-view.search.submitted:emit surfaces-item)
  (assert (graph-map:lookup "activity-surfaces:test-world:sandbox")
          "submitting surfaces item should create activity surfaces node")
  (activity-view:drop)
  (graph-map:drop))

(fn stale-scene-category-nodes-remove-when-activity-session-disappears []
  (local {:BackgroundNode BackgroundNode} (require :graph/nodes/background))
  (local {:SkyboxNode SkyboxNode} (require :graph/nodes/skybox))
  (local {:LightsNode LightsNode} (require :graph/nodes/lights))
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (local {:ScenePanelsNode ScenePanelsNode} (require :graph/nodes/scene-panels))
  (local state (make-stale-category-state))
  (local manager (make-manager state))
  (local removed {})
  (local graph-stub {:remove-nodes (make-remove-nodes-recorder removed)})
  (local nodes [(BackgroundNode {:world-id "test-world" :activity-id "graph" :world-manager manager})
                (SkyboxNode {:world-id "test-world" :activity-id "graph" :world-manager manager :asset-path-resolver asset-path-resolver})
                (LightsNode {:world-id "test-world" :activity-id "graph" :world-manager manager})
                (TerrainsNode {:world-id "test-world" :activity-id "graph" :world-manager manager})
                (ScenePanelsNode {:world-id "test-world" :activity-id "graph" :world-manager manager})])
  (each [_ node (ipairs nodes)]
    (set node.graph graph-stub))
  (set state.activity.sessions.graph nil)
  (local (ok err) (pcall (fn []
                           (manager.changed:emit {:world-id "test-world"}))))
  (assert ok (.. "stale category changed handlers should not throw: " (tostring err)))
  (assert (= (length removed) (length nodes))
          "each stale category node should remove itself when activity scene is absent")
  (each [_ node (ipairs nodes)]
    (node:drop)))

(table.insert tests {:name "world activity hierarchy views navigate to scene category"
                     :fn world-activity-hierarchy-views-navigate-to-scene-category})
(table.insert tests {:name "world activity view opens surfaces"
                     :fn world-activity-view-opens-surfaces})
(table.insert tests {:name "stale scene category nodes remove when activity session disappears"
                     :fn stale-scene-category-nodes-remove-when-activity-session-disappears})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "world-activity-graph-final-fixes"
                     :tests tests}))

{:name "world-activity-graph-final-fixes"
 :tests tests
 :main main}
