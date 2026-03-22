(local fs (require :fs))
(local glm (require :glm))
(local Signal (require :signal))
(local Graph (require :graph/init))
(local GraphKeyLoaders (require :graph/key-loaders))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "world-nodes"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "world-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok result (error result)))

(fn make-world-entry [opts]
  (local options (or opts {}))
  (local runtime (or options.runtime nil))
  (local state (or options.state {:scene {:panels [] :terrains []}
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

(fn make-scene-runtime [opts]
  (local options (or opts {}))
  (local scene {:capture-state (fn [_self]
                                 {:panels (or options.panels [])
                                  :terrains (or options.terrains [])})
                :build-default (fn [_self payload]
                                 (when options.on-build-default
                                   (options.on-build-default payload))
                                 true)
                 :restore-state (fn [_self payload]
                                  (when options.on-restore-state
                                    (options.on-restore-state payload))
                                  true)
                :replace-terrain-record (fn [_self terrain-id record]
                                          (when options.on-replace-terrain-record
                                            (options.on-replace-terrain-record terrain-id record))
                                          true)
                :remove-terrain (fn [_self terrain-id]
                                  (when options.on-remove-terrain
                                    (options.on-remove-terrain terrain-id))
                                  true)})
  {:scene scene})

(fn make-world-manager [opts]
  (local options (or opts {}))
  (local changed (or options.changed (Signal)))
  (local entry (or options.entry (make-world-entry options)))
  (local tabs (or options.tabs [{:index 1
                                 :id entry.id
                                 :name entry.name
                                 :active? (or options.active? false)}]))
  {:changed changed
   :list-tabs (fn [_self] tabs)
   :get-world-entry (fn [_self world-id]
                      (if (= world-id entry.id)
                          entry
                          nil))
   :active-world (fn [_self]
                   (if (or options.active? entry.active?) entry nil))
   :activate-index (or options.activate-index (fn [_self _idx] true))
   :close-world-index (or options.close-world-index (fn [_self _idx] true))
   :create-home-world (or options.create-home-world (fn [_self _opts] {:id "created-world"}))})

(fn test-worlds-node-module-exports []
  (local {:WorldsNode WorldsNode} (require :graph/nodes/worlds))
  (assert WorldsNode "worlds module should export WorldsNode")
  (assert (= (type WorldsNode) "function") "WorldsNode should be a function"))

(fn test-world-node-module-exports []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (assert WorldNode "world module should export WorldNode")
  (assert (= (type WorldNode) "function") "WorldNode should be a function"))

(fn test-scene-panels-node-module-exports []
  (local {:ScenePanelsNode ScenePanelsNode} (require :graph/nodes/scene-panels))
  (assert ScenePanelsNode "scene-panels module should export ScenePanelsNode")
  (assert (= (type ScenePanelsNode) "function") "ScenePanelsNode should be a function"))

(fn test-hud-panels-node-module-exports []
  (local {:HudPanelsNode HudPanelsNode} (require :graph/nodes/hud-panels))
  (assert HudPanelsNode "hud-panels module should export HudPanelsNode")
  (assert (= (type HudPanelsNode) "function") "HudPanelsNode should be a function"))

(fn test-terrains-node-module-exports []
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (assert TerrainsNode "terrains module should export TerrainsNode")
  (assert (= (type TerrainsNode) "function") "TerrainsNode should be a function"))

(fn test-scene-panel-node-module-exports []
  (local {:ScenePanelNode ScenePanelNode} (require :graph/nodes/scene-panel))
  (assert ScenePanelNode "scene-panel module should export ScenePanelNode")
  (assert (= (type ScenePanelNode) "function") "ScenePanelNode should be a function"))

(fn test-hud-panel-node-module-exports []
  (local {:HudPanelNode HudPanelNode} (require :graph/nodes/hud-panel))
  (assert HudPanelNode "hud-panel module should export HudPanelNode")
  (assert (= (type HudPanelNode) "function") "HudPanelNode should be a function"))

(fn test-terrain-node-module-exports []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (assert TerrainNode "terrain module should export TerrainNode")
  (assert (= (type TerrainNode) "function") "TerrainNode should be a function"))

(fn test-flat-terrain-node-module-exports []
  (local {:FlatTerrainNode FlatTerrainNode} (require :graph/nodes/flat-terrain))
  (assert FlatTerrainNode "flat-terrain module should export FlatTerrainNode")
  (assert (= (type FlatTerrainNode) "function") "FlatTerrainNode should be a function"))

(fn test-worlds-node-requires-world-manager []
  (local {:WorldsNode WorldsNode} (require :graph/nodes/worlds))
  (local (ok err) (pcall (fn [] (WorldsNode {}))))
  (assert (not ok) "WorldsNode should require world-manager"))

(fn test-world-node-requires-world-id []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (local (ok err) (pcall (fn [] (WorldNode {}))))
  (assert (not ok) "WorldNode should require world-id"))

(fn test-scene-panels-node-requires-world-id []
  (local {:ScenePanelsNode ScenePanelsNode} (require :graph/nodes/scene-panels))
  (local (ok err) (pcall (fn [] (ScenePanelsNode {}))))
  (assert (not ok) "ScenePanelsNode should require world-id"))

(fn test-hud-panels-node-requires-world-id []
  (local {:HudPanelsNode HudPanelsNode} (require :graph/nodes/hud-panels))
  (local (ok err) (pcall (fn [] (HudPanelsNode {}))))
  (assert (not ok) "HudPanelsNode should require world-id"))

(fn test-terrains-node-requires-world-id []
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (local (ok err) (pcall (fn [] (TerrainsNode {}))))
  (assert (not ok) "TerrainsNode should require world-id"))

(fn test-scene-panel-node-requires-world-id []
  (local {:ScenePanelNode ScenePanelNode} (require :graph/nodes/scene-panel))
  (local (ok err) (pcall (fn [] (ScenePanelNode {}))))
  (assert (not ok) "ScenePanelNode should require world-id"))

(fn test-hud-panel-node-requires-world-id []
  (local {:HudPanelNode HudPanelNode} (require :graph/nodes/hud-panel))
  (local (ok err) (pcall (fn [] (HudPanelNode {}))))
  (assert (not ok) "HudPanelNode should require world-id"))

(fn test-terrain-node-requires-world-id []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local (ok err) (pcall (fn [] (TerrainNode {}))))
  (assert (not ok) "TerrainNode should require world-id"))

(fn test-flat-terrain-node-requires-world-id []
  (local {:FlatTerrainNode FlatTerrainNode} (require :graph/nodes/flat-terrain))
  (local (ok err) (pcall (fn [] (FlatTerrainNode {}))))
  (assert (not ok) "FlatTerrainNode should require world-id"))

(fn test-worlds-node-has-correct-key []
  (local {:WorldsNode WorldsNode} (require :graph/nodes/worlds))
  (local mock-manager {:changed (Signal) :list-tabs (fn [] []) :get-world-entry (fn [_self _id] nil)})
  (local node (WorldsNode {:world-manager mock-manager}))
  (assert (= node.key "worlds") "WorldsNode key should be 'worlds'")
  (assert (= node.label "worlds") "WorldsNode label should be 'worlds'")
  (node:drop))

(fn test-world-node-has-correct-key []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (local mock-manager (make-world-manager {:id "test-world-123"}))
  (local node (WorldNode {:world-id "test-world-123" :world-manager mock-manager}))
  (assert (= node.key "world:test-world-123") "WorldNode key should include world-id")
  (node:drop))

(fn test-scene-panels-node-has-correct-key []
  (local {:ScenePanelsNode ScenePanelsNode} (require :graph/nodes/scene-panels))
  (local node (ScenePanelsNode {:world-id "test-world-123"
                                :world-manager (make-world-manager {:id "test-world-123"})}))
  (assert (= node.key "scene-panels:test-world-123") "ScenePanelsNode key should include world-id")
  (assert (= node.label "scene panels") "ScenePanelsNode label should be 'scene panels'")
  (node:drop))

(fn test-hud-panels-node-has-correct-key []
  (local {:HudPanelsNode HudPanelsNode} (require :graph/nodes/hud-panels))
  (local node (HudPanelsNode {:world-id "test-world-123"
                              :world-manager (make-world-manager {:id "test-world-123"})}))
  (assert (= node.key "hud-panels:test-world-123") "HudPanelsNode key should include world-id")
  (assert (= node.label "hud panels") "HudPanelsNode label should be 'hud panels'")
  (node:drop))

(fn test-terrains-node-has-correct-key []
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (local node (TerrainsNode {:world-id "test-world-123"
                             :world-manager (make-world-manager {:id "test-world-123"})}))
  (assert (= node.key "terrains:test-world-123") "TerrainsNode key should include world-id")
  (assert (= node.label "terrains") "TerrainsNode label should be 'terrains'")
  (node:drop))

(fn test-scene-panel-node-has-correct-key []
  (local {:ScenePanelNode ScenePanelNode} (require :graph/nodes/scene-panel))
  (local node (ScenePanelNode {:world-id "test-world-123"
                               :world-manager (make-world-manager {:id "test-world-123"})
                               :panel-index 5}))
  (assert (= node.key "scene-panel:test-world-123:5") "ScenePanelNode key should include world-id and index")
  (node:drop))

(fn test-hud-panel-node-has-correct-key []
  (local {:HudPanelNode HudPanelNode} (require :graph/nodes/hud-panel))
  (local node (HudPanelNode {:world-id "test-world-123"
                             :world-manager (make-world-manager {:id "test-world-123"})
                             :layer "float"
                             :panel-index 3}))
  (assert (= node.key "hud-panel:test-world-123:float:3") "HudPanelNode key should include world-id, layer, and index")
  (node:drop))

(fn test-terrain-node-has-correct-key []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local node (TerrainNode {:world-id "test-world-123"
                            :world-manager (make-world-manager {:id "test-world-123"})
                            :terrain-id "terrain-abc"}))
  (assert (= node.key "terrain:test-world-123:terrain-abc") "TerrainNode key should include world-id and terrain-id")
  (node:drop))

(fn test-flat-terrain-node-has-correct-key []
  (local {:FlatTerrainNode FlatTerrainNode} (require :graph/nodes/flat-terrain))
  (local entry (make-world-entry {:id "test-world-123"
                                  :state {:scene {:panels []
                                                  :terrains [(make-flat-terrain-record {:id "terrain-abc"})]}
                                          :hud {:panels []}}}))
  (local node (FlatTerrainNode {:world-id "test-world-123"
                                :world-manager (make-world-manager {:id "test-world-123" :entry entry})
                                :terrain-id "terrain-abc"}))
  (assert (= node.key "terrain-editor:test-world-123:terrain-abc") "FlatTerrainNode key should include world-id and terrain-id")
  (node:drop))

(fn test-world-node-has-emit-categories []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (local mock-manager (make-world-manager {:id "test-world-123"}))
  (local node (WorldNode {:world-id "test-world-123" :world-manager mock-manager}))
  (assert node.emit-categories "WorldNode should have emit-categories method")
  (local categories (node:emit-categories))
  (assert (= (length categories) 3) "WorldNode should have 3 categories")
  (local cat1 (. categories 1))
  (local cat2 (. categories 2))
  (local cat3 (. categories 3))
  (assert (= cat1.key "scene-panels") "first category should be scene-panels")
  (assert (= cat2.key "hud-panels") "second category should be hud-panels")
  (assert (= cat3.key "terrains") "third category should be terrains")
  (node:drop))

(fn test-world-node-add-category-node []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (local graph (Graph {:with-start false}))
  (local mock-manager (make-world-manager {:id "test-world-123"}))
  (local node (WorldNode {:world-id "test-world-123" :world-manager mock-manager}))
  (graph:add-node node {})
  (local categories (node:emit-categories))
  (node:add-category-node (. categories 1))
  (assert (= (graph:edge-count) 1) "WorldNode add-category-node should create 1 edge")
  (node:drop)
  (graph:drop))

(fn test-worlds-node-has-emit-items []
  (local {:WorldsNode WorldsNode} (require :graph/nodes/worlds))
  (local mock-manager {:changed (Signal)
                       :list-tabs (fn [] [{:index 1 :id "w1" :name "home" :active? true}])
                       :get-world-entry (fn [_self _id] nil)})
  (local node (WorldsNode {:world-manager mock-manager}))
  (assert node.emit-items "WorldsNode should have emit-items method")
  (local items (node:emit-items))
  (assert (= (length items) 1) "WorldsNode should list one world")
  (local entry (. (. items 1) 1))
  (local label (. (. items 1) 2))
  (assert (= entry.id "w1") "WorldsNode item should have world id")
  (assert (string.find label "home") "WorldsNode label should include world name")
  (node:drop))

(fn test-scene-panels-node-has-emit-items []
  (local {:ScenePanelsNode ScenePanelsNode} (require :graph/nodes/scene-panels))
  (local node (ScenePanelsNode {:world-id "test-world"
                                :world-manager (make-world-manager {:id "test-world"})}))
  (assert node.emit-items "ScenePanelsNode should have emit-items method")
  (local items (node:emit-items))
  (assert (= (type items) :table) "emit-items should return a table")
  (node:drop))

(fn test-hud-panels-node-has-emit-items []
  (local {:HudPanelsNode HudPanelsNode} (require :graph/nodes/hud-panels))
  (local node (HudPanelsNode {:world-id "test-world"
                              :world-manager (make-world-manager {:id "test-world"})}))
  (assert node.emit-items "HudPanelsNode should have emit-items method")
  (local items (node:emit-items))
  (assert (= (type items) :table) "emit-items should return a table")
  (node:drop))

(fn test-terrains-node-has-emit-items []
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (local node (TerrainsNode {:world-id "test-world"
                             :world-manager (make-world-manager {:id "test-world"})}))
  (assert node.emit-items "TerrainsNode should have emit-items method")
  (local items (node:emit-items))
  (assert (= (type items) :table) "emit-items should return a table")
  (node:drop))

(fn test-world-node-has-actions []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (local mock-manager (make-world-manager {:id "test-world-123"}))
  (local node (WorldNode {:world-id "test-world-123" :world-manager mock-manager}))
  (assert node.actions "WorldNode should have actions")
  (assert (= (type node.actions) :table) "actions should be a table")
  (assert (= (length node.actions) 2) "WorldNode should have 2 actions")
  (local act1 (. node.actions 1))
  (local act2 (. node.actions 2))
  (assert (= act1.name "Activate") "first action should be Activate")
  (assert (= act2.name "Close") "second action should be Close")
  (node:drop))

(fn test-scene-panel-node-has-remove-action []
  (local {:ScenePanelNode ScenePanelNode} (require :graph/nodes/scene-panel))
  (local node (ScenePanelNode {:world-id "test-world"
                               :world-manager (make-world-manager {:id "test-world"})
                               :panel-index 1}))
  (assert node.actions "ScenePanelNode should have actions")
  (assert (= (length node.actions) 1) "ScenePanelNode should have one action")
  (local action (. node.actions 1))
  (assert (= action.name "Remove") "action should be Remove")
  (node:drop))

(fn test-hud-panel-node-has-remove-action []
  (local {:HudPanelNode HudPanelNode} (require :graph/nodes/hud-panel))
  (local node (HudPanelNode {:world-id "test-world"
                             :world-manager (make-world-manager {:id "test-world"})
                             :layer "float"
                             :panel-index 1}))
  (assert node.actions "HudPanelNode should have actions")
  (assert (= (length node.actions) 1) "HudPanelNode should have one action")
  (local action (. node.actions 1))
  (assert (= action.name "Remove") "action should be Remove")
  (node:drop))

(fn test-terrain-node-has-actions []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local entry (make-world-entry {:id "test-world"
                                  :state {:scene {:panels []
                                                  :terrains [(make-flat-terrain-record {:id "t1"})]}
                                          :hud {:panels []}}}))
  (local node (TerrainNode {:world-id "test-world"
                            :world-manager (make-world-manager {:id "test-world" :entry entry})
                            :terrain-id "t1"}))
  (assert (= node.label "terrain") "generic terrain node label should stay generic")
  (assert node.actions "TerrainNode should have actions")
  (assert (= (length node.actions) 2) "TerrainNode should have editor and remove actions")
  (assert (= (. (. node.actions 1) :name) "Open Editor") "first terrain action should open editor")
  (assert (= (. (. node.actions 2) :name) "Remove") "second terrain action should remove terrain")
  (node:drop))

(fn test-flat-terrain-node-updates-world-state []
  (local {:FlatTerrainNode FlatTerrainNode} (require :graph/nodes/flat-terrain))
  (local terrain-record (make-flat-terrain-record {:id "terrain-a" :width 50}))
  (local state {:scene {:panels []
                        :terrains [terrain-record]}
                :hud {:panels []}})
  (var save-count 0)
  (local entry (make-world-entry {:id "test-world"
                                  :state state
                                  :on-save (fn [_state]
                                             (set save-count (+ save-count 1)))}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (FlatTerrainNode {:world-id "test-world"
                                :world-manager manager
                                :terrain-id "terrain-a"}))
  (node:apply-values {:width 64
                      :length 50
                      :scale [20 1 20]
                      :position [-500 -100 -500]
                      :rotation [1 0 0 0]
                      :opacity 1.0
                      :physics-thickness 2.0})
  (assert (= (. (. (. state.scene.terrains 1) :options) :width) 64)
          "FlatTerrainNode should update the persisted terrain width")
  (assert (> save-count 0) "FlatTerrainNode should persist terrain edits")
  (node:drop))

(fn test-flat-terrain-node-updates-active-scene-in-place []
  (local {:FlatTerrainNode FlatTerrainNode} (require :graph/nodes/flat-terrain))
  (local terrain-record (make-flat-terrain-record {:id "terrain-a" :width 50}))
  (local state {:scene {:panels [{:kind "graph-node-cube" :node-key "start" :position [0 0 0] :rotation [1 0 0 0] :size [4 4 4]}]
                        :terrains [terrain-record]}
                :hud {:panels []}})
  (var built-count 0)
  (var restored-count 0)
  (var replaced nil)
  (local runtime (make-scene-runtime {:panels state.scene.panels
                                      :terrains state.scene.terrains
                                      :on-build-default (fn [_payload] (set built-count (+ built-count 1)))
                                      :on-restore-state (fn [_payload] (set restored-count (+ restored-count 1)))
                                      :on-replace-terrain-record (fn [terrain-id record]
                                                                  (set replaced {:terrain-id terrain-id
                                                                                 :record record}))}))
  (local entry (make-world-entry {:id "test-world"
                                  :active? true
                                  :runtime runtime
                                  :state state}))
  (local manager (make-world-manager {:id "test-world"
                                      :active? true
                                      :entry entry}))
  (local node (FlatTerrainNode {:world-id "test-world"
                                :world-manager manager
                                :terrain-id "terrain-a"}))
  (node:apply-values {:width 72
                      :length 50
                      :scale [20 1 20]
                      :position [-500 -100 -500]
                      :rotation [1 0 0 0]
                      :opacity 1.0
                      :physics-thickness 2.0})
  (assert replaced "editing an active terrain should replace only that terrain runtime")
  (assert (= replaced.terrain-id "terrain-a") "active terrain update should target the same terrain id")
  (assert (= (. (. replaced.record :options) :width) 72)
          "replaced runtime terrain should include the edited width")
  (assert (= built-count 0) "editing an active terrain should not rebuild scene defaults")
  (assert (= restored-count 0) "editing an active terrain should not restore scene panels")
  (node:drop))

(fn test-flat-terrain-node-errors-when-active-runtime-update-fails []
  (local {:FlatTerrainNode FlatTerrainNode} (require :graph/nodes/flat-terrain))
  (local terrain-record (make-flat-terrain-record {:id "terrain-a" :width 50}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (local runtime {:scene {:replace-terrain-record (fn [_self _terrain-id _record] false)}})
  (local entry (make-world-entry {:id "test-world"
                                  :active? true
                                  :runtime runtime
                                  :state state}))
  (local manager (make-world-manager {:id "test-world"
                                      :active? true
                                      :entry entry}))
  (local node (FlatTerrainNode {:world-id "test-world"
                                :world-manager manager
                                :terrain-id "terrain-a"}))
  (local (ok err)
    (pcall (fn []
             (node:apply-values {:width 72
                                 :length 50
                                 :scale [20 1 20]
                                 :position [-500 -100 -500]
                                 :rotation [1 0 0 0]
                                 :opacity 1.0
                                 :physics-thickness 2.0}))))
  (assert (not ok) "active terrain update should fail loudly when runtime sync fails")
  (assert (string.find err "failed to replace terrain") "runtime sync failure should mention replace terrain")
  (node:drop))

(fn test-terrain-node-open-editor-adds-edge []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local graph (Graph {:with-start false}))
  (local entry (make-world-entry {:id "test-world"
                                  :state {:scene {:panels []
                                                  :terrains [(make-flat-terrain-record {:id "terrain-a"})]}
                                          :hud {:panels []}}}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (TerrainNode {:world-id "test-world"
                            :world-manager manager
                            :terrain-id "terrain-a"}))
  (graph:add-node node {})
  (local editor (node:open-editor))
  (assert editor "TerrainNode should create a type-specific editor")
  (assert (= editor.key "terrain-editor:test-world:terrain-a") "editor key should be stable")
  (assert (= (graph:edge-count) 1) "opening terrain editor should add one edge")
  (graph:drop))

(fn test-flat-terrain-node-remove-updates-world-state []
  (local {:FlatTerrainNode FlatTerrainNode} (require :graph/nodes/flat-terrain))
  (local state {:scene {:panels []
                        :terrains [(make-flat-terrain-record {:id "terrain-a"})
                                   (make-flat-terrain-record {:id "terrain-b"})]}
                :hud {:panels []}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (FlatTerrainNode {:world-id "test-world"
                                :world-manager manager
                                :terrain-id "terrain-a"}))
  (assert (node:remove-terrain) "flat terrain removal should succeed")
  (assert (= (length state.scene.terrains) 1) "flat terrain removal should mutate world state")
  (assert (= (. (. state.scene.terrains 1) :id) "terrain-b") "flat terrain removal should target the correct record")
  (node:drop))

(fn test-flat-terrain-node-removes-active-scene-in-place []
  (local {:FlatTerrainNode FlatTerrainNode} (require :graph/nodes/flat-terrain))
  (local state {:scene {:panels []
                        :terrains [(make-flat-terrain-record {:id "terrain-a"})
                                   (make-flat-terrain-record {:id "terrain-b"})]}
                :hud {:panels []}})
  (var removed-terrain-id nil)
  (var built-count 0)
  (local runtime (make-scene-runtime {:panels state.scene.panels
                                      :terrains state.scene.terrains
                                      :on-build-default (fn [_payload] (set built-count (+ built-count 1)))
                                      :on-remove-terrain (fn [terrain-id]
                                                           (set removed-terrain-id terrain-id))}))
  (local entry (make-world-entry {:id "test-world"
                                  :active? true
                                  :runtime runtime
                                  :state state}))
  (local manager (make-world-manager {:id "test-world"
                                      :active? true
                                      :entry entry}))
  (local node (FlatTerrainNode {:world-id "test-world"
                                :world-manager manager
                                :terrain-id "terrain-a"}))
  (assert (node:remove-terrain) "active flat terrain removal should succeed")
  (assert (= removed-terrain-id "terrain-a") "active terrain removal should target only that terrain")
  (assert (= built-count 0) "active terrain removal should not rebuild scene defaults")
  (node:drop))

(fn test-flat-terrain-node-errors-when-active-runtime-remove-fails []
  (local {:FlatTerrainNode FlatTerrainNode} (require :graph/nodes/flat-terrain))
  (local state {:scene {:panels []
                        :terrains [(make-flat-terrain-record {:id "terrain-a"})]}
                :hud {:panels []}})
  (local runtime {:scene {:remove-terrain (fn [_self _terrain-id] false)}})
  (local entry (make-world-entry {:id "test-world"
                                  :active? true
                                  :runtime runtime
                                  :state state}))
  (local manager (make-world-manager {:id "test-world"
                                      :active? true
                                      :entry entry}))
  (local node (FlatTerrainNode {:world-id "test-world"
                                :world-manager manager
                                :terrain-id "terrain-a"}))
  (local (ok err) (pcall (fn [] (node:remove-terrain))))
  (assert (not ok) "active terrain removal should fail loudly when runtime sync fails")
  (assert (string.find err "failed to remove terrain") "runtime removal failure should mention remove terrain")
  (node:drop))

(fn test-worlds-node-has-create-world []
  (local {:WorldsNode WorldsNode} (require :graph/nodes/worlds))
  (var created nil)
  (local mock-manager {:changed (Signal)
                       :list-tabs (fn [] [])
                       :get-world-entry (fn [_self _id] nil)
                       :create-home-world (fn [self opts]
                                            (set created opts)
                                            {:id "new-world"})})
  (local node (WorldsNode {:world-manager mock-manager}))
  (assert node.create-world "WorldsNode should have create-world method")
  (node:create-world {:name "my world"})
  (assert created "create-world should call world-manager")
  (assert (= created.name "my world") "create-world should pass options")
  (node:drop))

(fn test-world-node-activate-finds-index []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (var activated-idx nil)
  (local mock-manager (make-world-manager {:id "target-world"
                                           :name "target"
                                           :tabs [{:index 1 :id "other-world" :name "other" :active? false}
                                                  {:index 2 :id "target-world" :name "target" :active? false}]
                                           :activate-index (fn [self idx] (set activated-idx idx))}))
  (local node (WorldNode {:world-id "target-world" :world-manager mock-manager}))
  (node:activate)
  (assert (= activated-idx 2) "activate should find correct index")
  (node:drop))

(fn test-world-node-close-finds-index []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (var closed-idx nil)
  (local mock-manager (make-world-manager {:id "target-world"
                                           :name "target"
                                           :tabs [{:index 1 :id "other-world" :name "other" :active? false}
                                                  {:index 2 :id "target-world" :name "target" :active? false}]
                                           :close-world-index (fn [self idx] (set closed-idx idx))}))
  (local node (WorldNode {:world-id "target-world" :world-manager mock-manager}))
  (node:close)
  (assert (= closed-idx 2) "close should find correct index")
  (node:drop))

(fn with-app [app-value f]
  (local previous-app app)
  (set app app-value)
  (local (ok result) (pcall f))
  (set app previous-app)
  (if ok result (error result)))

(fn test-world-node-uses-target-world-entry []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (local target-entry (make-world-entry {:id "target-world" :name "Target World"}))
  (local mock-manager (make-world-manager {:id "target-world"
                                           :name "Target World"
                                           :entry target-entry}))
  (local node (WorldNode {:world-id "target-world" :world-manager mock-manager}))
  (assert (= node.label "Target World") "WorldNode should use the requested world entry")
  (node:drop))

(fn test-scene-panels-node-uses-world-state-when-inactive []
  (local {:ScenePanelsNode ScenePanelsNode} (require :graph/nodes/scene-panels))
  (local entry (make-world-entry {:id "test-world"
                                  :state {:scene {:panels [{:kind "alpha"}
                                                           {:kind "beta"}]
                                                  :terrains []}
                                          :hud {:panels []}}}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (ScenePanelsNode {:world-id "test-world" :world-manager manager}))
  (local items (node:emit-items))
  (assert (= (length items) 2) "ScenePanelsNode should read inactive world scene state")
  (assert (= (. (. items 1) 2) "alpha [1]") "first scene panel label should come from world state")
  (node:drop))

(fn test-hud-panels-node-uses-world-state-when-inactive []
  (local {:HudPanelsNode HudPanelsNode} (require :graph/nodes/hud-panels))
  (local entry (make-world-entry {:id "test-world"
                                  :state {:scene {:panels [] :terrains []}
                                          :hud {:panels [{:layer "tiles" :kind "control"}
                                                         {:layer "float" :kind "chat"}
                                                         {:layer "tiles" :kind "status"}]}}}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (with-app {:active-world-entry {:id "other-world"}
             :hud {:tiles {:children [{:persistence {:kind "wrong"}}]}
                   :float {:children []}}}
    (fn []
      (local node (HudPanelsNode {:world-id "test-world" :world-manager manager}))
      (local items (node:emit-items))
      (assert (= (length items) 3) "HudPanelsNode should read inactive world hud state")
      (assert (= (. (. items 1) 2) "control [tiles:1]") "tiles index should be layer-relative")
      (assert (= (. (. items 3) 2) "status [tiles:2]") "second tiles panel should keep layer-relative index")
      (node:drop))))

(fn test-scene-panel-remove-updates-world-state []
  (local {:ScenePanelNode ScenePanelNode} (require :graph/nodes/scene-panel))
  (local state {:scene {:panels [{:kind "alpha"}
                                 {:kind "beta"}]
                        :terrains []}
                :hud {:panels []}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (ScenePanelNode {:world-id "test-world"
                               :world-manager manager
                               :panel-index 1}))
  (assert (node:remove-panel) "scene panel removal should succeed")
  (assert (= (length state.scene.panels) 1) "scene panel removal should mutate world state")
  (assert (= (. (. state.scene.panels 1) :kind) "beta") "scene panel removal should target the requested world")
  (node:drop))

(fn test-scene-panel-removal-drops-shifted-siblings []
  (local {:ScenePanelNode ScenePanelNode} (require :graph/nodes/scene-panel))
  (local graph (Graph {:with-start false}))
  (local changed (Signal))
  (local state {:scene {:panels [{:kind "alpha"}
                                 {:kind "beta"}]
                        :terrains []}
                :hud {:panels []}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager {:changed changed
                  :list-tabs (fn [_self]
                               [{:index 1 :id "test-world" :name "Test World" :active? false}])
                  :get-world-entry (fn [_self world-id]
                                     (if (= world-id "test-world")
                                         entry
                                         nil))})
  (local node-a (ScenePanelNode {:world-id "test-world"
                                 :world-manager manager
                                 :panel-index 1}))
  (local node-b (ScenePanelNode {:world-id "test-world"
                                 :world-manager manager
                                 :panel-index 2}))
  (graph:add-node node-a {})
  (graph:add-node node-b {})
  (assert (node-a:remove-panel) "scene panel removal should succeed")
  (assert (= (graph:lookup "scene-panel:test-world:2") nil)
          "shifted sibling nodes should be removed after panel deletion")
  (graph:drop))

(fn test-hud-panel-remove-uses-layer-relative-state-index []
  (local {:HudPanelNode HudPanelNode} (require :graph/nodes/hud-panel))
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels [{:layer "tiles" :kind "control"}
                               {:layer "float" :kind "chat"}
                               {:layer "tiles" :kind "status"}]}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (HudPanelNode {:world-id "test-world"
                             :world-manager manager
                             :layer "tiles"
                             :panel-index 2}))
  (assert (node:remove-panel) "hud panel removal should succeed")
  (assert (= (length state.hud.panels) 2) "hud panel removal should mutate world state")
  (assert (= (. (. state.hud.panels 1) :kind) "control") "first tiles panel should remain")
  (assert (= (. (. state.hud.panels 2) :kind) "chat") "layer-relative removal should not remove float panels")
  (node:drop))

(fn test-world-node-removes-itself-when-world-disappears []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (local graph (Graph {:with-start false}))
  (local changed (Signal))
  (var entry (make-world-entry {:id "test-world"}))
  (local manager {:changed changed
                  :list-tabs (fn [_self]
                               (if entry
                                   [{:index 1 :id entry.id :name entry.name :active? false}]
                                   []))
                  :get-world-entry (fn [_self world-id]
                                     (if (and entry (= world-id entry.id))
                                         entry
                                         nil))
                  :activate-index (fn [_self _idx] true)
                  :close-world-index (fn [_self _idx] true)})
  (local node (WorldNode {:world-id "test-world" :world-manager manager}))
  (graph:add-node node {})
  (set entry nil)
  (changed:emit {})
  (assert (= (graph:lookup "world:test-world") nil) "WorldNode should remove itself when the world disappears")
  (graph:drop))

(fn test-scene-panel-node-removes-itself-when-world-disappears []
  (local {:ScenePanelNode ScenePanelNode} (require :graph/nodes/scene-panel))
  (local graph (Graph {:with-start false}))
  (local changed (Signal))
  (var entry (make-world-entry {:id "test-world"
                                :state {:scene {:panels [{:kind "alpha"}] :terrains []}
                                        :hud {:panels []}}}))
  (local manager {:changed changed
                  :list-tabs (fn [_self]
                               (if entry
                                   [{:index 1 :id entry.id :name entry.name :active? false}]
                                   []))
                  :get-world-entry (fn [_self world-id]
                                     (if (and entry (= world-id entry.id))
                                         entry
                                         nil))})
  (local node (ScenePanelNode {:world-id "test-world"
                               :world-manager manager
                               :panel-index 1}))
  (graph:add-node node {})
  (set entry nil)
  (changed:emit {})
  (assert (= (graph:lookup "scene-panel:test-world:1") nil)
          "ScenePanelNode should remove itself when its world disappears")
  (graph:drop))

(fn test-graph-key-loaders-loads-scene-panels-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (GraphKeyLoaders.register graph {:world-manager (make-world-manager {:id "test-world"})})
      (local result (graph:load-by-key "scene-panels:test-world"))
      (assert result "scene-panels loader should create node")
      (assert (= result.key "scene-panels:test-world") "scene-panels key should match")
      (result:drop)
      (graph:drop))))

(fn test-graph-key-loaders-loads-hud-panels-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (GraphKeyLoaders.register graph {:world-manager (make-world-manager {:id "test-world"})})
      (local result (graph:load-by-key "hud-panels:test-world"))
      (assert result "hud-panels loader should create node")
      (assert (= result.key "hud-panels:test-world") "hud-panels key should match")
      (result:drop)
      (graph:drop))))

(fn test-graph-key-loaders-loads-terrains-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (GraphKeyLoaders.register graph {:world-manager (make-world-manager {:id "test-world"})})
      (local result (graph:load-by-key "terrains:test-world"))
      (assert result "terrains loader should create node")
      (assert (= result.key "terrains:test-world") "terrains key should match")
      (result:drop)
      (graph:drop))))

(fn test-graph-key-loaders-loads-scene-panel-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (GraphKeyLoaders.register graph {:world-manager (make-world-manager {:id "test-world"})})
      (local result (graph:load-by-key "scene-panel:test-world:5"))
      (assert result "scene-panel loader should create node")
      (assert (= result.key "scene-panel:test-world:5") "scene-panel key should match")
      (assert (= result.panel-index 5) "scene-panel index should be parsed")
      (result:drop)
      (graph:drop))))

(fn test-graph-key-loaders-loads-hud-panel-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (GraphKeyLoaders.register graph {:world-manager (make-world-manager {:id "test-world"})})
      (local result (graph:load-by-key "hud-panel:test-world:float:3"))
      (assert result "hud-panel loader should create node")
      (assert (= result.key "hud-panel:test-world:float:3") "hud-panel key should match")
      (assert (= result.layer "float") "hud-panel layer should be parsed")
      (assert (= result.panel-index 3) "hud-panel index should be parsed")
      (result:drop)
      (graph:drop))))

(fn test-graph-key-loaders-loads-terrain-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (local entry (make-world-entry {:id "test-world"
                                      :state {:scene {:panels []
                                                      :terrains [(make-flat-terrain-record {:id "terrain-abc"})]}
                                              :hud {:panels []}}}))
      (GraphKeyLoaders.register graph {:world-manager (make-world-manager {:id "test-world" :entry entry})})
      (local result (graph:load-by-key "terrain:test-world:terrain-abc"))
      (assert result "terrain loader should create node")
      (assert (= result.key "terrain:test-world:terrain-abc") "terrain key should match")
      (assert (= result.terrain-id "terrain-abc") "terrain-id should be parsed")
      (result:drop)
      (graph:drop))))

(fn test-graph-key-loaders-loads-terrain-editor-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (local entry (make-world-entry {:id "test-world"
                                      :state {:scene {:panels []
                                                      :terrains [(make-flat-terrain-record {:id "terrain-abc"})]}
                                              :hud {:panels []}}}))
      (GraphKeyLoaders.register graph {:world-manager (make-world-manager {:id "test-world" :entry entry})})
      (local result (graph:load-by-key "terrain-editor:test-world:terrain-abc"))
      (assert result "terrain editor loader should create node")
      (assert (= result.key "terrain-editor:test-world:terrain-abc") "terrain editor key should match")
      (assert (= result.terrain-id "terrain-abc") "terrain editor terrain-id should be parsed")
      (result:drop)
      (graph:drop))))

(table.insert tests {:name "worlds node module exports" :fn test-worlds-node-module-exports})
(table.insert tests {:name "world node module exports" :fn test-world-node-module-exports})
(table.insert tests {:name "scene panels node module exports" :fn test-scene-panels-node-module-exports})
(table.insert tests {:name "hud panels node module exports" :fn test-hud-panels-node-module-exports})
(table.insert tests {:name "terrains node module exports" :fn test-terrains-node-module-exports})
(table.insert tests {:name "scene panel node module exports" :fn test-scene-panel-node-module-exports})
(table.insert tests {:name "hud panel node module exports" :fn test-hud-panel-node-module-exports})
(table.insert tests {:name "terrain node module exports" :fn test-terrain-node-module-exports})
(table.insert tests {:name "flat terrain node module exports" :fn test-flat-terrain-node-module-exports})
(table.insert tests {:name "worlds node requires world-manager" :fn test-worlds-node-requires-world-manager})
(table.insert tests {:name "world node requires world-id" :fn test-world-node-requires-world-id})
(table.insert tests {:name "scene panels node requires world-id" :fn test-scene-panels-node-requires-world-id})
(table.insert tests {:name "hud panels node requires world-id" :fn test-hud-panels-node-requires-world-id})
(table.insert tests {:name "terrains node requires world-id" :fn test-terrains-node-requires-world-id})
(table.insert tests {:name "scene panel node requires world-id" :fn test-scene-panel-node-requires-world-id})
(table.insert tests {:name "hud panel node requires world-id" :fn test-hud-panel-node-requires-world-id})
(table.insert tests {:name "terrain node requires world-id" :fn test-terrain-node-requires-world-id})
(table.insert tests {:name "flat terrain node requires world-id" :fn test-flat-terrain-node-requires-world-id})
(table.insert tests {:name "worlds node has correct key" :fn test-worlds-node-has-correct-key})
(table.insert tests {:name "world node has correct key" :fn test-world-node-has-correct-key})
(table.insert tests {:name "scene panels node has correct key" :fn test-scene-panels-node-has-correct-key})
(table.insert tests {:name "hud panels node has correct key" :fn test-hud-panels-node-has-correct-key})
(table.insert tests {:name "terrains node has correct key" :fn test-terrains-node-has-correct-key})
(table.insert tests {:name "scene panel node has correct key" :fn test-scene-panel-node-has-correct-key})
(table.insert tests {:name "hud panel node has correct key" :fn test-hud-panel-node-has-correct-key})
(table.insert tests {:name "terrain node has correct key" :fn test-terrain-node-has-correct-key})
(table.insert tests {:name "flat terrain node has correct key" :fn test-flat-terrain-node-has-correct-key})
(table.insert tests {:name "world node has emit categories" :fn test-world-node-has-emit-categories})
(table.insert tests {:name "world node add category node" :fn test-world-node-add-category-node})
(table.insert tests {:name "worlds node has emit items" :fn test-worlds-node-has-emit-items})
(table.insert tests {:name "scene panels node has emit items" :fn test-scene-panels-node-has-emit-items})
(table.insert tests {:name "hud panels node has emit items" :fn test-hud-panels-node-has-emit-items})
(table.insert tests {:name "terrains node has emit items" :fn test-terrains-node-has-emit-items})
(table.insert tests {:name "world node has actions" :fn test-world-node-has-actions})
(table.insert tests {:name "scene panel node has remove action" :fn test-scene-panel-node-has-remove-action})
(table.insert tests {:name "hud panel node has remove action" :fn test-hud-panel-node-has-remove-action})
(table.insert tests {:name "terrain node has actions" :fn test-terrain-node-has-actions})
(table.insert tests {:name "flat terrain node updates world state" :fn test-flat-terrain-node-updates-world-state})
(table.insert tests {:name "flat terrain node updates active scene in place" :fn test-flat-terrain-node-updates-active-scene-in-place})
(table.insert tests {:name "flat terrain node errors when active runtime update fails" :fn test-flat-terrain-node-errors-when-active-runtime-update-fails})
(table.insert tests {:name "terrain node open editor adds edge" :fn test-terrain-node-open-editor-adds-edge})
(table.insert tests {:name "flat terrain node remove updates world state" :fn test-flat-terrain-node-remove-updates-world-state})
(table.insert tests {:name "flat terrain node removes active scene in place" :fn test-flat-terrain-node-removes-active-scene-in-place})
(table.insert tests {:name "flat terrain node errors when active runtime remove fails" :fn test-flat-terrain-node-errors-when-active-runtime-remove-fails})
(table.insert tests {:name "worlds node has create world" :fn test-worlds-node-has-create-world})
(table.insert tests {:name "world node activate finds index" :fn test-world-node-activate-finds-index})
(table.insert tests {:name "world node close finds index" :fn test-world-node-close-finds-index})
(table.insert tests {:name "world node uses target world entry" :fn test-world-node-uses-target-world-entry})
(table.insert tests {:name "scene panels node uses world state when inactive" :fn test-scene-panels-node-uses-world-state-when-inactive})
(table.insert tests {:name "hud panels node uses world state when inactive" :fn test-hud-panels-node-uses-world-state-when-inactive})
(table.insert tests {:name "scene panel remove updates world state" :fn test-scene-panel-remove-updates-world-state})
(table.insert tests {:name "scene panel removal drops shifted siblings" :fn test-scene-panel-removal-drops-shifted-siblings})
(table.insert tests {:name "hud panel remove uses layer relative state index" :fn test-hud-panel-remove-uses-layer-relative-state-index})
(table.insert tests {:name "world node removes itself when world disappears" :fn test-world-node-removes-itself-when-world-disappears})
(table.insert tests {:name "scene panel node removes itself when world disappears" :fn test-scene-panel-node-removes-itself-when-world-disappears})
(table.insert tests {:name "graph key loaders loads scene panels node" :fn test-graph-key-loaders-loads-scene-panels-node})
(table.insert tests {:name "graph key loaders loads hud panels node" :fn test-graph-key-loaders-loads-hud-panels-node})
(table.insert tests {:name "graph key loaders loads terrains node" :fn test-graph-key-loaders-loads-terrains-node})
(table.insert tests {:name "graph key loaders loads scene panel node" :fn test-graph-key-loaders-loads-scene-panel-node})
(table.insert tests {:name "graph key loaders loads hud panel node" :fn test-graph-key-loaders-loads-hud-panel-node})
(table.insert tests {:name "graph key loaders loads terrain node" :fn test-graph-key-loaders-loads-terrain-node})
(table.insert tests {:name "graph key loaders loads terrain editor node" :fn test-graph-key-loaders-loads-terrain-editor-node})

(fn make-icons-stub []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {65533 glyph
                           4242 glyph}})
  (local stub {:font font
               :codepoints {:close 4242
                            :play_arrow 4242}})
  (set stub.get
       (fn [self name]
         (local value (. self.codepoints name))
         (assert value (.. "Missing icon " name))
         value))
  (set stub.resolve
       (fn [self name]
         (local code (self:get name))
         {:type :font
          :codepoint code
          :font self.font}))
  stub)

(fn make-build-ctx []
  (local BuildContext (require :build-context))
  (local ctx (BuildContext {:clickables app.clickables
                            :hoverables app.hoverables}))
  (set ctx.icons (make-icons-stub))
  ctx)

(fn codepoints->text [codepoints]
  (table.concat
    (icollect [_ codepoint (ipairs (or codepoints []))]
      (utf8.char codepoint))))

(fn text-entity-value [entity]
  (codepoints->text (entity:get-codepoints)))

(fn test-world-node-view-builds []
  (local WorldNodeView (require :graph/view/views/world))
  (local ctx (make-build-ctx))
  (local mock-node {:world-id "test-world"
                    :label "Test World"
                    :emit-categories (fn [] [])})
  (local builder (WorldNodeView mock-node))
  (local view (builder ctx))
  (assert view "WorldNodeView should build a view")
  (assert view.layout "WorldNodeView should have layout")
  (assert view.search "WorldNodeView should have search")
  (view:drop))

(fn test-world-node-view-set-categories []
  (local WorldNodeView (require :graph/view/views/world))
  (local ctx (make-build-ctx))
  (local mock-node {:world-id "test-world"
                    :label "Test World"
                    :emit-categories (fn [] [])})
  (local builder (WorldNodeView mock-node))
  (local view (builder ctx))
  (view:set-categories [{:key "scene-panels" :label "scene panels"}
                       {:key "hud-panels" :label "hud panels"}
                       {:key "terrains" :label "terrains"}])
  (assert view.search "WorldNodeView should have search after set-categories")
  (assert (= (length (or view.search.items [])) 3) "search should have 3 items")
  (view:drop))

(fn test-world-node-view-refresh-categories []
  (local WorldNodeView (require :graph/view/views/world))
  (local ctx (make-build-ctx))
  (var categories-called false)
  (local mock-node {:world-id "test-world"
                    :label "Test World"
                    :emit-categories (fn []
                                       (set categories-called true)
                                       [{:key "scene-panels" :label "scene panels"}])})
  (local builder (WorldNodeView mock-node))
  (local view (builder ctx))
  (view:refresh-categories)
  (assert categories-called "refresh-categories should call emit-categories")
  (assert (= (length (or view.search.items [])) 1) "search should have 1 item after refresh")
  (view:drop))

(fn test-world-node-view-search-submitted []
  (local WorldNodeView (require :graph/view/views/world))
  (local ctx (make-build-ctx))
  (var added-category nil)
  (local mock-node {:world-id "test-world"
                    :label "Test World"
                    :emit-categories (fn [] [{:key "scene-panels" :label "scene panels"}])
                    :add-category-node (fn [_self cat] (set added-category cat))})
  (local builder (WorldNodeView mock-node))
  (local view (builder ctx))
  (view:refresh-categories)
  (view.search.submitted:emit (. view.search.items 1))
  (assert added-category "add-category-node should be called on search submit")
  (view:drop))

(fn test-flat-terrain-node-view-builds []
  (local Validation (require :graph/terrain-editor-validation))
  (local FlatTerrainNodeView (require :graph/view/views/flat-terrain))
  (local ctx (make-build-ctx))
  (local mock-node {:terrain-id "terrain-a"
                    :changed (Signal)
                    :get-record (fn [] (make-flat-terrain-record {:id "terrain-a"}))
                    :apply-values (fn [_self _values] true)})
  (local builder (FlatTerrainNodeView mock-node))
  (local view (builder ctx))
  (assert view "FlatTerrainNodeView should build a view")
  (assert view.layout "FlatTerrainNodeView should have layout")
  (assert view.fields "FlatTerrainNodeView should expose fields")
  (assert view.error-labels "FlatTerrainNodeView should expose field error labels")
  (assert view.status-label "FlatTerrainNodeView should expose status label")
  (assert view.apply-button "FlatTerrainNodeView should expose apply button")
  (assert (= (length Validation.field-specs) 7) "validation should expose flat terrain field specs")
  (assert (not view.apply-button.enabled?) "Apply should start disabled when nothing changed")
  (view:drop))

(fn test-terrain-node-view-builds-scrollable-summary []
  (local TerrainNodeView (require :graph/view/views/terrain))
  (local ctx (make-build-ctx))
  (local mock-node {:terrain-id "terrain-a"
                    :terrain-kind "flat-terrain"
                    :has-editor? true
                    :open-editor (fn [_self] nil)
                    :remove-terrain (fn [_self] nil)
                    :terrain-record (make-flat-terrain-record {:id "terrain-a"})
                    :changed (Signal)})
  (local builder (TerrainNodeView mock-node))
  (local view (builder ctx))
  (assert view.layout "TerrainNodeView should have layout")
  (assert view.scroll-view "TerrainNodeView should use a scroll view for long summaries")
  (view:drop))

(fn test-flat-terrain-node-view-defers-updates-until-apply []
  (local FlatTerrainNodeView (require :graph/view/views/flat-terrain))
  (local ctx (make-build-ctx))
  (var updates 0)
  (local record (make-flat-terrain-record {:id "terrain-a" :width 50}))
  (local changed (Signal))
  (local mock-node {:terrain-id "terrain-a"
                    :changed changed
                    :get-record (fn [] record)
                    :apply-values (fn [_self validated]
                                      (set updates (+ updates 1))
                                      (local options (. record :options))
                                      (set options.width validated.width)
                                      (changed:emit record)
                                      record)})
  (local builder (FlatTerrainNodeView mock-node))
  (local view (builder ctx))
  (view.fields.width:set-text "72")
  (assert (= updates 0) "editing input text should not update terrain immediately")
  (assert view.apply-button.enabled? "Apply should enable when the draft is dirty")
  (view.apply-button:on-click {})
  (assert (= updates 1) "Apply should trigger a single terrain update")
  (assert (= (. (. record :options) :width) 72) "Apply should write edited width")
  (assert (not view.apply-button.enabled?) "Apply should disable again after commit")
  (assert (= (text-entity-value view.status-label) "Applied") "successful apply should show applied status")
  (view:drop))

(fn test-flat-terrain-node-view-shows-validation-errors []
  (local FlatTerrainNodeView (require :graph/view/views/flat-terrain))
  (local ctx (make-build-ctx))
  (var updates 0)
  (local mock-node {:terrain-id "terrain-a"
                    :changed (Signal)
                    :get-record (fn [] (make-flat-terrain-record {:id "terrain-a"}))
                    :apply-values (fn [_self _values]
                                    (set updates (+ updates 1))
                                    true)})
  (local builder (FlatTerrainNodeView mock-node))
  (local view (builder ctx))
  (view.fields.opacity:set-text "2")
  (view.apply-button:on-click {})
  (assert (= updates 0) "invalid apply should not update terrain")
  (assert (= (text-entity-value (. (. view :error-labels) :opacity)) "Opacity must be between 0 and 1")
          "invalid opacity should show an inline error")
  (assert (= (text-entity-value view.status-label) "Fix 1 invalid field before applying")
          "invalid apply should show summary feedback")
  (view.fields.opacity:set-text "0.5")
  (assert (= (text-entity-value (. (. view :error-labels) :opacity)) "")
          "fixing a field should clear its inline error")
  (assert (= (text-entity-value view.status-label) "Unsaved changes")
          "fixing the field should return to unsaved status")
  (view:drop))

(fn test-terrain-editor-validation-validates-draft []
  (local Validation (require :graph/terrain-editor-validation))
  (local draft (Validation.draft-from-record (make-flat-terrain-record {:id "terrain-a"})))
  (set (. draft :width) "4.5")
  (local result (Validation.validate-draft draft))
  (assert (not result.ok?) "validation should reject invalid draft values")
  (assert (= (. (. result :errors) :width) "Width must be an integer") "width validation should require integers"))

(table.insert tests {:name "world node view builds" :fn test-world-node-view-builds})
(table.insert tests {:name "world node view set categories" :fn test-world-node-view-set-categories})
(table.insert tests {:name "world node view refresh categories" :fn test-world-node-view-refresh-categories})
(table.insert tests {:name "world node view search submitted" :fn test-world-node-view-search-submitted})
(table.insert tests {:name "terrain node view builds scrollable summary" :fn test-terrain-node-view-builds-scrollable-summary})
(table.insert tests {:name "flat terrain node view builds" :fn test-flat-terrain-node-view-builds})
(table.insert tests {:name "flat terrain node view defers updates until apply" :fn test-flat-terrain-node-view-defers-updates-until-apply})
(table.insert tests {:name "flat terrain node view shows validation errors" :fn test-flat-terrain-node-view-shows-validation-errors})
(table.insert tests {:name "terrain editor validation validates draft" :fn test-terrain-editor-validation-validates-draft})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "world-nodes"
                       :tests tests})))

{:name "world-nodes"
 :tests tests
 :main main}
