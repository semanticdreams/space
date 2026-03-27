(local fs (require :fs))
(local glm (require :glm))
(local Signal (require :signal))
(local Graph (require :graph/init))
(local GraphKeyLoaders (require :graph/key-loaders))
(local TestSupport (require :tests/test-support))

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

(fn make-perlin-terrain-record [opts]
  (local options (or opts {}))
  {:id (or options.id "perlin-1")
   :kind "perlin-terrain"
   :options {:width (or options.width 50)
             :length (or options.length 50)
             :seed (or options.seed 1337)
             :scale (or options.scale [20 1 20])
             :position (or options.position [500 -100 -500])
             :rotation (or options.rotation [1 0 0 0])
             :opacity (or options.opacity 1.0)
             :physics true
             :n1div (or options.n1div 30)
             :n2div (or options.n2div 4)
             :n3div (or options.n3div 1)
             :n1scale (or options.n1scale 20)
             :n2scale (or options.n2scale 2)
             :n3scale (or options.n3scale 1)
             :zroot (or options.zroot 2)
             :zpower (or options.zpower 2.5)}})

(fn make-heightfield-terrain-record [opts]
  (local options (or opts {}))
  (local chunk-samples (or options.chunk-samples [17 17]))
  (local chunk-width (. chunk-samples 1))
  (local chunk-length (. chunk-samples 2))
  (local default-height (or options.default-height 0.0))
  (local heights [])
  (for [_ 1 (* chunk-width chunk-length)]
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
                                :heights heights}] )})

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
                :add-terrain-record (fn [_self record]
                                      (when options.on-add-terrain-record
                                        (options.on-add-terrain-record record))
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
  (local active-world-id
    (or options.active-world-id
        (and (or options.active? entry.active?) entry.id)
        nil))
  {:changed changed
   :list-tabs (fn [_self] tabs)
   :get-world-entry (fn [_self world-id]
                      (if (= world-id entry.id)
                          entry
                          nil))
   :active-world (fn [_self]
                   (if (= active-world-id entry.id) entry nil))
   :active-world-id (fn [_self] active-world-id)
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

(fn test-perlin-terrain-node-module-exports []
  (local {:PerlinTerrainNode PerlinTerrainNode} (require :graph/nodes/perlin-terrain))
  (assert PerlinTerrainNode "perlin-terrain module should export PerlinTerrainNode")
  (assert (= (type PerlinTerrainNode) "function") "PerlinTerrainNode should be a function"))

(fn test-heightfield-terrain-node-module-exports []
  (local {:HeightfieldTerrainNode HeightfieldTerrainNode} (require :graph/nodes/heightfield-terrain))
  (assert HeightfieldTerrainNode "heightfield-terrain module should export HeightfieldTerrainNode")
  (assert (= (type HeightfieldTerrainNode) "function") "HeightfieldTerrainNode should be a function"))

(fn test-world-data-resolve-active-scene-uses-active-world-id []
  (local WorldData (require :graph/world-data))
  (local runtime (make-scene-runtime {:terrains []}))
  (local entry (make-world-entry {:id "test-world"
                                  :runtime runtime
                                  :active? false}))
  (local manager (make-world-manager {:id "test-world"
                                      :entry entry
                                      :active-world-id "test-world"}))
  (local scene (WorldData.resolve-active-scene manager "test-world"))
  (assert (= scene runtime.scene)
          "resolve-active-scene should use the manager active-world-id, not stub-only entry.active?"))

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

(fn test-perlin-terrain-node-requires-world-id []
  (local {:PerlinTerrainNode PerlinTerrainNode} (require :graph/nodes/perlin-terrain))
  (local (ok err) (pcall (fn [] (PerlinTerrainNode {}))))
  (assert (not ok) "PerlinTerrainNode should require world-id"))

(fn test-heightfield-terrain-node-requires-world-id []
  (local {:HeightfieldTerrainNode HeightfieldTerrainNode} (require :graph/nodes/heightfield-terrain))
  (local (ok err) (pcall (fn [] (HeightfieldTerrainNode {}))))
  (assert (not ok) "HeightfieldTerrainNode should require world-id"))

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

(fn test-terrain-node-default-label-is-generic []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local entry (make-world-entry {:id "test-world-123"
                                  :state {:scene {:panels []
                                                  :terrains [{:id "terrain-abc"
                                                              :kind "heightfield-terrain"
                                                              :options {}}]}
                                          :hud {:panels []}}}))
  (local node (TerrainNode {:world-id "test-world-123"
                            :world-manager (make-world-manager {:id "test-world-123"
                                                                :entry entry})
                            :terrain-id "terrain-abc"}))
  (assert (= node.label "terrain") "TerrainNode should stay generic by default")
  (node:drop))

(fn test-terrain-node-uses-name-as-label []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local entry (make-world-entry {:id "test-world-123"
                                  :state {:scene {:panels []
                                                  :terrains [(make-heightfield-terrain-record {:id "terrain-abc"
                                                                                               :name "mesa"})]}
                                          :hud {:panels []}}}))
  (local node (TerrainNode {:world-id "test-world-123"
                            :world-manager (make-world-manager {:id "test-world-123"
                                                                :entry entry})
                            :terrain-id "terrain-abc"}))
  (assert (= node.label "mesa") "TerrainNode should prefer terrain name for its label")
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

(fn test-perlin-terrain-node-has-correct-key []
  (local {:PerlinTerrainNode PerlinTerrainNode} (require :graph/nodes/perlin-terrain))
  (local entry (make-world-entry {:id "test-world-123"
                                  :state {:scene {:panels []
                                                  :terrains [(make-perlin-terrain-record {:id "terrain-abc"})]}
                                          :hud {:panels []}}}))
  (local node (PerlinTerrainNode {:world-id "test-world-123"
                                  :world-manager (make-world-manager {:id "test-world-123" :entry entry})
                                  :terrain-id "terrain-abc"}))
  (assert (= node.key "terrain-editor:test-world-123:terrain-abc") "PerlinTerrainNode key should include world-id and terrain-id")
  (node:drop))

(fn test-heightfield-terrain-node-has-correct-key []
  (local {:HeightfieldTerrainNode HeightfieldTerrainNode} (require :graph/nodes/heightfield-terrain))
  (local entry (make-world-entry {:id "test-world-123"
                                  :state {:scene {:panels []
                                                  :terrains [(make-heightfield-terrain-record {:id "terrain-abc"})]}
                                          :hud {:panels []}}}))
  (local node (HeightfieldTerrainNode {:world-id "test-world-123"
                                       :world-manager (make-world-manager {:id "test-world-123" :entry entry})
                                       :terrain-id "terrain-abc"}))
  (assert (= node.key "terrain-editor:test-world-123:terrain-abc") "HeightfieldTerrainNode key should include world-id and terrain-id")
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
                                                  :terrains [(make-heightfield-terrain-record {:id "t1"})]}
                                          :hud {:panels []}}}))
  (local node (TerrainNode {:world-id "test-world"
                            :world-manager (make-world-manager {:id "test-world" :entry entry})
                            :terrain-id "t1"}))
  (assert (= node.label "terrain") "terrain node should stay generic")
  (assert node.actions "TerrainNode should have actions")
  (assert (= (length node.actions) 2) "TerrainNode should have editor and remove actions")
  (assert (= (. (. node.actions 1) :name) "Open Editor") "first terrain action should open properties")
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

(fn test-perlin-terrain-node-updates-world-state []
  (local {:PerlinTerrainNode PerlinTerrainNode} (require :graph/nodes/perlin-terrain))
  (local terrain-record (make-perlin-terrain-record {:id "terrain-a" :seed 7}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (PerlinTerrainNode {:world-id "test-world"
                                  :world-manager manager
                                  :terrain-id "terrain-a"}))
  (node:apply-values {:width 72
                      :length 60
                      :seed 99
                      :scale [30 2 30]
                      :position [10 -90 12]
                      :rotation [1 0 0 0]
                      :opacity 0.8
                      :n1div 31
                      :n2div 5
                      :n3div 2
                      :n1scale 18
                      :n2scale 3
                      :n3scale 1.5
                      :zroot 2.2
                      :zpower 3.1})
  (assert (= (. (. (. state.scene.terrains 1) :options) :seed) 99)
          "PerlinTerrainNode should update the persisted terrain seed")
  (assert (= (. (. (. state.scene.terrains 1) :options) :n3div) 2)
          "PerlinTerrainNode should update perlin-specific noise parameters")
  (assert (= (. (. (. state.scene.terrains 1) :options) :physics) true)
          "PerlinTerrainNode should keep physics enabled")
  (node:drop))

(fn test-perlin-terrain-node-updates-active-scene-in-place []
  (local {:PerlinTerrainNode PerlinTerrainNode} (require :graph/nodes/perlin-terrain))
  (local terrain-record (make-perlin-terrain-record {:id "terrain-a" :seed 7}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (var replaced nil)
  (local runtime (make-scene-runtime {:terrains state.scene.terrains
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
  (local node (PerlinTerrainNode {:world-id "test-world"
                                  :world-manager manager
                                  :terrain-id "terrain-a"}))
  (node:apply-values {:width 72
                      :length 60
                      :seed 99
                      :scale [30 2 30]
                      :position [10 -90 12]
                      :rotation [1 0 0 0]
                      :opacity 0.8
                      :n1div 31
                      :n2div 5
                      :n3div 2
                      :n1scale 18
                      :n2scale 3
                      :n3scale 1.5
                      :zroot 2.2
                      :zpower 3.1})
  (assert replaced "editing an active perlin terrain should replace only that terrain runtime")
  (assert (= replaced.terrain-id "terrain-a") "active perlin terrain update should target the same terrain id")
  (assert (= (. (. replaced.record :options) :seed) 99)
          "replaced runtime perlin terrain should include the edited seed")
  (node:drop))

(fn test-perlin-terrain-node-errors-when-active-runtime-update-fails []
  (local {:PerlinTerrainNode PerlinTerrainNode} (require :graph/nodes/perlin-terrain))
  (local terrain-record (make-perlin-terrain-record {:id "terrain-a" :seed 7}))
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
  (local node (PerlinTerrainNode {:world-id "test-world"
                                  :world-manager manager
                                  :terrain-id "terrain-a"}))
  (local (ok err)
    (pcall (fn []
             (node:apply-values {:width 72
                                 :length 60
                                 :seed 99
                                 :scale [30 2 30]
                                 :position [10 -90 12]
                                 :rotation [1 0 0 0]
                                 :opacity 0.8
                                 :n1div 31
                                 :n2div 5
                                 :n3div 2
                                 :n1scale 18
                                 :n2scale 3
                                 :n3scale 1.5
                                 :zroot 2.2
                                 :zpower 3.1}))))
  (assert (not ok) "active perlin terrain update should fail loudly when runtime sync fails")
  (assert (string.find err "failed to replace terrain") "runtime sync failure should mention replace terrain")
  (node:drop))

(fn test-heightfield-terrain-node-updates-world-state []
  (local {:HeightfieldTerrainNode HeightfieldTerrainNode} (require :graph/nodes/heightfield-terrain))
  (local terrain-record (make-heightfield-terrain-record {:id "terrain-a" :default-height 1.5}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (var save-count 0)
  (local entry (make-world-entry {:id "test-world"
                                  :state state
                                  :on-save (fn [_state]
                                             (set save-count (+ save-count 1)))}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (HeightfieldTerrainNode {:world-id "test-world"
                                       :world-manager manager
                                       :terrain-id "terrain-a"}))
  (node:apply-values {:name "mesa"
                      :position [10 -50 12]
                      :rotation [1 0 0 0]
                      :opacity 0.8
                      :physics false
                      :sample-spacing [8 8]})
  (assert (= (. (. state.scene.terrains 1) :name) "mesa")
          "HeightfieldTerrainNode should update the persisted terrain name")
  (assert (= (. (. (. state.scene.terrains 1) :options) :opacity) 0.8)
          "HeightfieldTerrainNode should update persisted terrain properties")
  (assert (= (. (. (. state.scene.terrains 1) :options) :physics) false)
          "HeightfieldTerrainNode should update persisted terrain physics")
  (assert (> save-count 0) "HeightfieldTerrainNode should persist terrain edits")
  (node:drop))

(fn test-heightfield-terrain-node-updates-active-scene-in-place []
  (local {:HeightfieldTerrainNode HeightfieldTerrainNode} (require :graph/nodes/heightfield-terrain))
  (local terrain-record (make-heightfield-terrain-record {:id "terrain-a" :default-height 0.0}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (var replaced nil)
  (local runtime (make-scene-runtime {:terrains state.scene.terrains
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
  (local node (HeightfieldTerrainNode {:world-id "test-world"
                                       :world-manager manager
                                       :terrain-id "terrain-a"}))
  (node:apply-values {:name "mesa"
                      :position [5 -75 0]
                      :rotation [1 0 0 0]
                      :opacity 0.9
                      :physics false
                      :sample-spacing [12 12]})
  (assert replaced "editing an active heightfield terrain should replace only that terrain runtime")
  (assert (= replaced.terrain-id "terrain-a") "active heightfield terrain update should target the same terrain id")
  (assert (= replaced.record.name "mesa") "replaced runtime terrain should include the edited terrain name")
  (assert (= (. (. replaced.record :options) :opacity) 0.9)
          "replaced runtime terrain should include updated terrain properties")
  (assert (= (. (. replaced.record :options) :physics) false)
          "replaced runtime terrain should include updated terrain physics")
  (node:drop))

(fn test-heightfield-terrain-node-errors-when-active-runtime-update-fails []
  (local {:HeightfieldTerrainNode HeightfieldTerrainNode} (require :graph/nodes/heightfield-terrain))
  (local terrain-record (make-heightfield-terrain-record {:id "terrain-a" :default-height 0.0}))
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
  (local node (HeightfieldTerrainNode {:world-id "test-world"
                                       :world-manager manager
                                       :terrain-id "terrain-a"}))
  (local (ok err)
    (pcall (fn []
             (node:apply-values {:name "mesa"
                                 :position [0 -100 0]
                                 :rotation [1 0 0 0]
                                 :opacity 1.0
                                 :physics true
                                 :sample-spacing [20 20]}))))
  (assert (not ok) "active heightfield terrain update should fail loudly when runtime sync fails")
  (assert (string.find err "failed to replace terrain") "runtime sync failure should mention replace terrain")
  (node:drop))

(fn test-heightfield-perlin-tool-node-applies-to-world-state []
  (local {:HeightfieldPerlinToolNode HeightfieldPerlinToolNode} (require :graph/nodes/heightfield-perlin-tool))
  (local terrain-record (make-heightfield-terrain-record {:id "terrain-a" :default-height 0.0}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (HeightfieldPerlinToolNode {:world-id "test-world"
                                          :world-manager manager
                                          :terrain-id "terrain-a"}))
  (node:apply-values {:seed 99
                      :target {:mode :whole}
                      :n1div 30
                      :n2div 4
                      :n3div 1
                      :n1scale 20
                      :n2scale 2
                      :n3scale 1
                      :zroot 2
                      :zpower 2.5})
  (local heights (. (. (. state.scene.terrains 1) :chunks 1) :heights))
  (assert (not (= (. heights 1) (. heights 2)))
          "Heightfield perlin apply should change canonical height samples")
  (node:drop))

(fn test-heightfield-flat-tool-node-applies-rectangle-to-world-state []
  (local {:HeightfieldFlatToolNode HeightfieldFlatToolNode} (require :graph/nodes/heightfield-flat-tool))
  (local terrain-record
    (make-heightfield-terrain-record {:id "terrain-a"
                                      :default-height 0.0
                                      :chunk-samples [5 5]}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (HeightfieldFlatToolNode {:world-id "test-world"
                                        :world-manager manager
                                        :terrain-id "terrain-a"}))
  (node:apply-values {:target {:mode :rect
                               :x0 1
                               :z0 1
                               :x1 2
                               :z1 2}
                      :height 6.0})
  (local heights (. (. (. state.scene.terrains 1) :chunks 1) :heights))
  (assert (= (. heights 1) 0.0) "flat rect apply should leave outside samples unchanged")
  (assert (= (. heights 7) 6.0) "flat rect apply should change targeted samples")
  (assert (= (. (. (. state.scene.terrains 1) :options) :default-height) 0.0)
          "flat rect apply should not rewrite default-height")
  (node:drop))

(fn test-heightfield-adjust-tool-node-applies-rectangle-to-world-state []
  (local {:HeightfieldAdjustToolNode HeightfieldAdjustToolNode} (require :graph/nodes/heightfield-adjust-tool))
  (local terrain-record
    (make-heightfield-terrain-record {:id "terrain-a"
                                      :default-height 1.0
                                      :chunk-samples [5 5]}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (HeightfieldAdjustToolNode {:world-id "test-world"
                                          :world-manager manager
                                          :terrain-id "terrain-a"}))
  (node:apply-values {:target {:mode :rect
                               :x0 1
                               :z0 1
                               :x1 2
                               :z1 2}
                      :delta 2.0})
  (local heights (. (. (. state.scene.terrains 1) :chunks 1) :heights))
  (assert (= (. heights 1) 1.0) "adjust rect apply should leave outside samples unchanged")
  (assert (= (. heights 7) 3.0) "adjust rect apply should change targeted samples")
  (assert (= (. (. (. state.scene.terrains 1) :options) :default-height) 1.0)
          "adjust rect apply should not rewrite default-height")
  (node:drop))

(fn test-heightfield-perlin-tool-node-applies-rectangle-to-world-state []
  (local {:HeightfieldPerlinToolNode HeightfieldPerlinToolNode} (require :graph/nodes/heightfield-perlin-tool))
  (local terrain-record
    (make-heightfield-terrain-record {:id "terrain-a"
                                      :default-height 0.0
                                      :chunk-samples [5 5]}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (HeightfieldPerlinToolNode {:world-id "test-world"
                                          :world-manager manager
                                          :terrain-id "terrain-a"}))
  (node:apply-values {:target {:mode :rect
                               :x0 1
                               :z0 1
                               :x1 3
                               :z1 3}
                      :seed 99
                      :n1div 30
                      :n2div 4
                      :n3div 1
                      :n1scale 20
                      :n2scale 2
                      :n3scale 1
                      :zroot 2
                      :zpower 2.5})
  (local heights (. (. (. state.scene.terrains 1) :chunks 1) :heights))
  (var changed-count 0)
  (each [_ value (ipairs heights)]
    (when (not (= value 0.0))
      (set changed-count (+ changed-count 1))))
  (assert (= (. heights 1) 0.0) "perlin rect apply should leave outside samples unchanged")
  (assert (> changed-count 0) "perlin rect apply should change targeted samples")
  (node:drop))

(fn test-heightfield-resize-tool-node-updates-world-state []
  (local {:HeightfieldResizeToolNode HeightfieldResizeToolNode} (require :graph/nodes/heightfield-resize-tool))
  (local terrain-record
    (make-heightfield-terrain-record {:id "terrain-a"
                                      :default-height 0.0
                                      :chunk-samples [5 5]}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (HeightfieldResizeToolNode {:world-id "test-world"
                                          :world-manager manager
                                          :terrain-id "terrain-a"}))
  (node:apply-values {:min-chunk-x -1
                      :min-chunk-z 0
                      :max-chunk-x 1
                      :max-chunk-z 0
                      :fill-height 2.5})
  (local chunks (. (. state.scene.terrains 1) :chunks))
  (assert (= (length chunks) 3) "resize tool should update persisted chunk coverage")
  (assert (= (. (. chunks 1) :coord 1) -1) "resize tool should extend chunk coverage left")
  (assert (= (. (. chunks 2) :coord 1) 0) "resize tool should preserve overlapping center chunk")
  (assert (= (. (. chunks 3) :coord 1) 1) "resize tool should extend chunk coverage right")
  (assert (= (. (. (. chunks 2) :heights) 1) 0.0) "resize tool should preserve overlapping chunk sample data")
  (assert (= (. (. (. chunks 1) :heights) 1) 2.5) "resize tool should fill new chunks with fill height")
  (node:drop))

(fn test-heightfield-perlin-tool-node-applies-to-active-scene-in-place []
  (local {:HeightfieldPerlinToolNode HeightfieldPerlinToolNode} (require :graph/nodes/heightfield-perlin-tool))
  (local terrain-record (make-heightfield-terrain-record {:id "terrain-a" :default-height 0.0}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (var replaced nil)
  (local runtime (make-scene-runtime {:terrains state.scene.terrains
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
  (local node (HeightfieldPerlinToolNode {:world-id "test-world"
                                          :world-manager manager
                                          :terrain-id "terrain-a"}))
  (node:apply-values {:seed 99
                      :target {:mode :whole}
                      :n1div 30
                      :n2div 4
                      :n3div 1
                      :n1scale 20
                      :n2scale 2
                      :n3scale 1
                      :zroot 2
                      :zpower 2.5})
  (assert replaced "active perlin tool apply should replace only that terrain runtime")
  (assert (= replaced.terrain-id "terrain-a") "active perlin tool apply should target the same terrain id")
  (assert (not (= (. (. (. replaced.record :chunks 1) :heights) 1)
                  (. (. (. replaced.record :chunks 1) :heights) 2)))
          "active perlin tool apply should update runtime chunk data")
  (node:drop))

(fn test-heightfield-resize-tool-node-updates-active-scene-in-place []
  (local {:HeightfieldResizeToolNode HeightfieldResizeToolNode} (require :graph/nodes/heightfield-resize-tool))
  (local terrain-record
    (make-heightfield-terrain-record {:id "terrain-a"
                                      :default-height 0.0
                                      :chunk-samples [5 5]}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (var replaced nil)
  (local runtime (make-scene-runtime {:terrains state.scene.terrains
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
  (local node (HeightfieldResizeToolNode {:world-id "test-world"
                                          :world-manager manager
                                          :terrain-id "terrain-a"}))
  (node:apply-values {:min-chunk-x 0
                      :min-chunk-z 0
                      :max-chunk-x 0
                      :max-chunk-z 1
                      :fill-height 4.0})
  (assert replaced "active resize tool apply should replace only that terrain runtime")
  (assert (= replaced.terrain-id "terrain-a") "active resize tool apply should target the same terrain id")
  (assert (= (length replaced.record.chunks) 2) "active resize tool apply should update runtime chunk coverage")
  (assert (= (. (. (. replaced.record.chunks 2) :coord) 2) 1) "active resize tool apply should include the new chunk")
  (assert (= (. (. (. replaced.record.chunks 2) :heights) 1) 4.0) "active resize tool apply should fill new runtime chunks")
  (node:drop))

(fn test-heightfield-adjust-tool-node-applies-to-active-scene-in-place []
  (local {:HeightfieldAdjustToolNode HeightfieldAdjustToolNode} (require :graph/nodes/heightfield-adjust-tool))
  (local terrain-record (make-heightfield-terrain-record {:id "terrain-a" :default-height 1.0}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (var replaced nil)
  (local runtime (make-scene-runtime {:terrains state.scene.terrains
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
  (local node (HeightfieldAdjustToolNode {:world-id "test-world"
                                          :world-manager manager
                                          :terrain-id "terrain-a"}))
  (node:apply-values {:target {:mode :whole}
                      :delta -0.5})
  (assert replaced "active adjust tool apply should replace only that terrain runtime")
  (assert (= replaced.terrain-id "terrain-a") "active adjust tool apply should target the same terrain id")
  (assert (= (. (. (. replaced.record :chunks 1) :heights) 1) 0.5) "active adjust tool apply should update runtime chunk data")
  (assert (= (. (. replaced.record :options) :default-height) 0.5) "active adjust tool apply should update default height")
  (node:drop))

(fn test-heightfield-adjust-tool-node-applies-stroke-batch-in-one-update []
  (local {:HeightfieldAdjustToolNode HeightfieldAdjustToolNode} (require :graph/nodes/heightfield-adjust-tool))
  (local terrain-record
    (make-heightfield-terrain-record {:id "terrain-a"
                                      :default-height 0.0
                                      :chunk-samples [5 5]}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (var replace-count 0)
  (var replaced nil)
  (local runtime
    (make-scene-runtime {:terrains state.scene.terrains
                         :on-replace-terrain-record (fn [terrain-id record]
                                                     (set replace-count (+ replace-count 1))
                                                     (set replaced {:terrain-id terrain-id
                                                                    :record record}))}))
  (local entry (make-world-entry {:id "test-world"
                                  :active? true
                                  :runtime runtime
                                  :state state}))
  (local manager (make-world-manager {:id "test-world"
                                      :active? true
                                      :entry entry}))
  (local node (HeightfieldAdjustToolNode {:world-id "test-world"
                                          :world-manager manager
                                          :terrain-id "terrain-a"}))
  (node:apply-stroke-values {:targets [{:mode :rect :x0 1 :z0 1 :x1 1 :z1 1}
                                       {:mode :rect :x0 2 :z0 1 :x1 2 :z1 1}
                                       {:mode :rect :x0 3 :z0 1 :x1 3 :z1 1}]
                             :delta 0.5})
  (assert (= replace-count 1) "stroke batch should replace the active terrain runtime once")
  (assert replaced "stroke batch should replace the active terrain runtime")
  (local heights (. (. replaced.record :chunks 1) :heights))
  (assert (= (. heights 7) 0.5) "stroke batch should update the first stamped sample")
  (assert (= (. heights 8) 0.5) "stroke batch should update intermediate stamped samples")
  (assert (= (. heights 9) 0.5) "stroke batch should update the last stamped sample")
  (node:drop))

(fn test-terrain-node-open-editor-adds-edge []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local graph (Graph {:with-start false}))
  (local entry (make-world-entry {:id "test-world"
                                  :state {:scene {:panels []
                                                  :terrains [(make-heightfield-terrain-record {:id "terrain-a"})]}
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

(fn test-terrain-node-open-editor-returns-nil-for-noneditable-kind []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local graph (Graph {:with-start false}))
  (local entry (make-world-entry {:id "test-world"
                                  :state {:scene {:panels []
                                                  :terrains [{:id "terrain-a"
                                                              :kind "voxel-terrain"
                                                              :options {}}]}
                                          :hud {:panels []}}}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (TerrainNode {:world-id "test-world"
                            :world-manager manager
                            :terrain-id "terrain-a"}))
  (graph:add-node node {})
  (local editor (node:open-editor))
  (assert (= editor nil) "TerrainNode should return nil when the terrain kind has no editor")
  (assert (= (graph:edge-count) 0) "noneditable terrain kinds should not add editor edges")
  (graph:drop))

(fn test-terrains-node-add-terrain-updates-world-state []
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}})
  (local node (TerrainsNode {:world-id "test-world"
                             :world-manager (make-world-manager {:id "test-world"
                                                                 :state state})}))
  (local added (node:add-terrain "heightfield-terrain"))
  (assert added "adding a heightfield terrain should return the created record")
  (assert (= (length state.scene.terrains) 1) "adding a terrain should append to world state")
  (assert (= (. (. state.scene.terrains 1) :kind) "heightfield-terrain") "added terrain should preserve kind")
  (assert (. added :id) "added terrain should have an id")
  (node:drop))

(fn test-terrains-node-add-terrain-supports-heightfield-kind []
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}})
  (local node (TerrainsNode {:world-id "test-world"
                             :world-manager (make-world-manager {:id "test-world"
                                                                 :state state})}))
  (local added (node:add-terrain "heightfield-terrain"))
  (assert added "adding a heightfield terrain should return the created record")
  (assert (= (. added :kind) "heightfield-terrain") "heightfield add should preserve terrain kind")
  (assert (= (length added.chunks) 1) "heightfield add should create a default chunk")
  (assert (= (length (. (. added.chunks 1) :heights)) (* 17 17))
          "heightfield add should seed default height samples")
  (assert (= (length state.scene.terrains) 1) "heightfield add should append to world state")
  (node:drop))

(fn test-terrain-node-heightfield-kind-opens-editor []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local graph (Graph {:with-start false}))
  (local entry (make-world-entry {:id "test-world"
                                  :state {:scene {:panels []
                                                  :terrains [(make-heightfield-terrain-record {:id "terrain-a"})]}
                                          :hud {:panels []}}}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (TerrainNode {:world-id "test-world"
                            :world-manager manager
                            :terrain-id "terrain-a"}))
  (graph:add-node node {})
  (assert (= node.label "terrain") "heightfield terrain node should stay generic without a name")
  (assert (= node.has-editor? true) "heightfield terrain should advertise its editor")
  (local editor (node:open-editor))
  (assert editor "heightfield terrain should open a type-specific editor")
  (assert (= editor.key "terrain-editor:test-world:terrain-a") "heightfield terrain editor key should be stable")
  (graph:drop))

(fn test-terrain-node-open-tool-adds-edge []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local graph (Graph {:with-start false}))
  (local entry (make-world-entry {:id "test-world"
                                  :state {:scene {:panels []
                                                  :terrains [(make-heightfield-terrain-record {:id "terrain-a"})]}
                                          :hud {:panels []}}}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (TerrainNode {:world-id "test-world"
                            :world-manager manager
                            :terrain-id "terrain-a"}))
  (graph:add-node node {})
  (local tool-node (node:open-tool "apply-perlin"))
  (assert tool-node "TerrainNode should create a dedicated terrain tool node")
  (assert (= tool-node.key "terrain-tool:test-world:terrain-a:apply-perlin") "terrain tool key should be stable")
  (assert (= (graph:edge-count) 1) "opening a terrain tool should add one edge")
  (graph:drop))

(fn test-terrain-node-open-resize-tool-adds-edge []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local graph (Graph {:with-start false}))
  (local entry (make-world-entry {:id "test-world"
                                  :state {:scene {:panels []
                                                  :terrains [(make-heightfield-terrain-record {:id "terrain-a"})]}
                                          :hud {:panels []}}}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (TerrainNode {:world-id "test-world"
                            :world-manager manager
                            :terrain-id "terrain-a"}))
  (graph:add-node node {})
  (local tool-node (node:open-tool "resize-terrain"))
  (assert tool-node "TerrainNode should create a resize terrain tool node")
  (assert (= tool-node.key "terrain-tool:test-world:terrain-a:resize-terrain") "resize terrain tool key should be stable")
  (assert (= (graph:edge-count) 1) "opening the resize terrain tool should add one edge")
  (graph:drop))

(fn test-terrain-node-open-adjust-tool-adds-edge []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local graph (Graph {:with-start false}))
  (local entry (make-world-entry {:id "test-world"
                                  :state {:scene {:panels []
                                                  :terrains [(make-heightfield-terrain-record {:id "terrain-a"})]}
                                          :hud {:panels []}}}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (TerrainNode {:world-id "test-world"
                            :world-manager manager
                            :terrain-id "terrain-a"}))
  (graph:add-node node {})
  (local tool-node (node:open-tool "adjust-height"))
  (assert tool-node "TerrainNode should create an adjust-height tool node")
  (assert (= tool-node.key "terrain-tool:test-world:terrain-a:adjust-height") "adjust-height tool key should be stable")
  (assert (= (graph:edge-count) 1) "opening the adjust-height tool should add one edge")
  (graph:drop))

(fn test-terrains-node-adds-active-scene-terrain-in-place []
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}})
  (var added-record nil)
  (var saved-count 0)
  (local runtime (make-scene-runtime {:terrains state.scene.terrains
                                      :on-add-terrain-record (fn [record]
                                                               (set added-record record))}))
  (local entry (make-world-entry {:id "test-world"
                                  :state state
                                  :runtime runtime
                                  :on-save (fn [_state]
                                             (set saved-count (+ saved-count 1)))}))
  (local node (TerrainsNode {:world-id "test-world"
                             :world-manager (make-world-manager {:id "test-world"
                                                                 :entry entry})}))
  (local added (node:add-terrain "heightfield-terrain"))
  (assert added "active terrain add should return the created record")
  (assert added-record "active terrain add should sync into the live scene")
  (assert (= added-record.id added.id) "active scene add should use the same terrain record")
  (assert (= saved-count 1) "adding a terrain should persist world state once")
  (node:drop))

(fn test-terrains-node-add-terrain-errors-on-unsupported-kind []
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}})
  (local node (TerrainsNode {:world-id "test-world"
                             :world-manager (make-world-manager {:id "test-world"
                                                                 :state state})}))
  (local (ok err) (pcall (fn []
                           (node:add-terrain "voxel-terrain"))))
  (assert (not ok) "unsupported terrain kinds should fail loudly")
  (assert (string.find err "Unsupported terrain kind")
          "unsupported terrain kind failure should mention the kind registry")
  (assert (= (length state.scene.terrains) 0) "unsupported terrain add should not mutate world state")
  (node:drop))

(fn test-terrains-node-adds-new-terrain-node-to-graph-when-present []
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (local graph (Graph {:with-start false}))
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}})
  (local node (TerrainsNode {:world-id "test-world"
                             :world-manager (make-world-manager {:id "test-world"
                                                                 :state state})}))
  (graph:add-node node {})
  (local added (node:add-terrain "heightfield-terrain"))
  (assert added "graph terrain add should return the created record")
  (local terrain-key (.. "terrain:test-world:" added.id))
  (local terrain-node (graph:lookup terrain-key))
  (assert terrain-node "new terrain should appear in the graph when parent node is mounted")
  (assert (= (graph:edge-count) 1) "new terrain graph attachment should add one edge from terrains node")
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

(fn test-perlin-terrain-node-remove-updates-world-state []
  (local {:PerlinTerrainNode PerlinTerrainNode} (require :graph/nodes/perlin-terrain))
  (local state {:scene {:panels []
                        :terrains [(make-perlin-terrain-record {:id "terrain-a"})
                                   (make-perlin-terrain-record {:id "terrain-b"})]}
                :hud {:panels []}})
  (local entry (make-world-entry {:id "test-world" :state state}))
  (local manager (make-world-manager {:id "test-world" :entry entry}))
  (local node (PerlinTerrainNode {:world-id "test-world"
                                  :world-manager manager
                                  :terrain-id "terrain-a"}))
  (assert (node:remove-terrain) "perlin terrain removal should succeed")
  (assert (= (length state.scene.terrains) 1) "perlin terrain removal should mutate world state")
  (assert (= (. (. state.scene.terrains 1) :id) "terrain-b") "perlin terrain removal should target the correct record")
  (node:drop))

(fn test-perlin-terrain-node-removes-active-scene-in-place []
  (local {:PerlinTerrainNode PerlinTerrainNode} (require :graph/nodes/perlin-terrain))
  (local state {:scene {:panels []
                        :terrains [(make-perlin-terrain-record {:id "terrain-a"})
                                   (make-perlin-terrain-record {:id "terrain-b"})]}
                :hud {:panels []}})
  (var removed-terrain-id nil)
  (local runtime (make-scene-runtime {:terrains state.scene.terrains
                                      :on-remove-terrain (fn [terrain-id]
                                                           (set removed-terrain-id terrain-id))}))
  (local entry (make-world-entry {:id "test-world"
                                  :active? true
                                  :runtime runtime
                                  :state state}))
  (local manager (make-world-manager {:id "test-world"
                                      :active? true
                                      :entry entry}))
  (local node (PerlinTerrainNode {:world-id "test-world"
                                  :world-manager manager
                                  :terrain-id "terrain-a"}))
  (assert (node:remove-terrain) "active perlin terrain removal should succeed")
  (assert (= removed-terrain-id "terrain-a") "active perlin terrain removal should target only that terrain")
  (node:drop))

(fn test-perlin-terrain-node-errors-when-active-runtime-remove-fails []
  (local {:PerlinTerrainNode PerlinTerrainNode} (require :graph/nodes/perlin-terrain))
  (local state {:scene {:panels []
                        :terrains [(make-perlin-terrain-record {:id "terrain-a"})]}
                :hud {:panels []}})
  (local runtime {:scene {:remove-terrain (fn [_self _terrain-id] false)}})
  (local entry (make-world-entry {:id "test-world"
                                  :active? true
                                  :runtime runtime
                                  :state state}))
  (local manager (make-world-manager {:id "test-world"
                                      :active? true
                                      :entry entry}))
  (local node (PerlinTerrainNode {:world-id "test-world"
                                  :world-manager manager
                                  :terrain-id "terrain-a"}))
  (local (ok err) (pcall (fn [] (node:remove-terrain))))
  (assert (not ok) "active perlin terrain removal should fail loudly when runtime sync fails")
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
                                                      :terrains [(make-heightfield-terrain-record {:id "terrain-abc"})]}
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
                                                      :terrains [(make-heightfield-terrain-record {:id "terrain-abc"})]}
                                              :hud {:panels []}}}))
      (GraphKeyLoaders.register graph {:world-manager (make-world-manager {:id "test-world" :entry entry})})
      (local result (graph:load-by-key "terrain-editor:test-world:terrain-abc"))
      (assert result "terrain editor loader should create node")
      (assert (= result.key "terrain-editor:test-world:terrain-abc") "terrain editor key should match")
      (assert (= result.terrain-id "terrain-abc") "terrain editor terrain-id should be parsed")
      (assert (= result.terrain-kind "heightfield-terrain") "terrain editor should preserve terrain kind")
      (result:drop)
      (graph:drop))))

(fn test-graph-key-loaders-loads-heightfield-terrain-editor-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (local entry (make-world-entry {:id "test-world"
                                      :state {:scene {:panels []
                                                      :terrains [(make-heightfield-terrain-record {:id "terrain-abc"})]}
                                              :hud {:panels []}}}))
      (GraphKeyLoaders.register graph {:world-manager (make-world-manager {:id "test-world" :entry entry})})
      (local result (graph:load-by-key "terrain-editor:test-world:terrain-abc"))
      (assert result "heightfield terrain editor loader should create node")
      (assert (= result.key "terrain-editor:test-world:terrain-abc") "heightfield terrain editor key should match")
      (assert (= result.terrain-id "terrain-abc") "heightfield terrain editor terrain-id should be parsed")
      (assert (= result.terrain-kind "heightfield-terrain") "heightfield terrain editor should preserve terrain kind")
      (result:drop)
      (graph:drop))))

(fn test-graph-key-loaders-loads-heightfield-terrain-tool-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (local entry (make-world-entry {:id "test-world"
                                      :state {:scene {:panels []
                                                      :terrains [(make-heightfield-terrain-record {:id "terrain-abc"})]}
                                              :hud {:panels []}}}))
      (GraphKeyLoaders.register graph {:world-manager (make-world-manager {:id "test-world" :entry entry})})
      (local result (graph:load-by-key "terrain-tool:test-world:terrain-abc:apply-perlin"))
      (assert result "terrain tool loader should create node")
      (assert (= result.key "terrain-tool:test-world:terrain-abc:apply-perlin") "terrain tool key should match")
      (assert (= result.terrain-id "terrain-abc") "terrain tool terrain-id should be parsed")
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
(table.insert tests {:name "perlin terrain node module exports" :fn test-perlin-terrain-node-module-exports})
(table.insert tests {:name "heightfield terrain node module exports" :fn test-heightfield-terrain-node-module-exports})
(table.insert tests {:name "world data resolve-active-scene uses active-world-id"
                     :fn test-world-data-resolve-active-scene-uses-active-world-id})
(table.insert tests {:name "worlds node requires world-manager" :fn test-worlds-node-requires-world-manager})
(table.insert tests {:name "world node requires world-id" :fn test-world-node-requires-world-id})
(table.insert tests {:name "scene panels node requires world-id" :fn test-scene-panels-node-requires-world-id})
(table.insert tests {:name "hud panels node requires world-id" :fn test-hud-panels-node-requires-world-id})
(table.insert tests {:name "terrains node requires world-id" :fn test-terrains-node-requires-world-id})
(table.insert tests {:name "scene panel node requires world-id" :fn test-scene-panel-node-requires-world-id})
(table.insert tests {:name "hud panel node requires world-id" :fn test-hud-panel-node-requires-world-id})
(table.insert tests {:name "terrain node requires world-id" :fn test-terrain-node-requires-world-id})
(table.insert tests {:name "flat terrain node requires world-id" :fn test-flat-terrain-node-requires-world-id})
(table.insert tests {:name "perlin terrain node requires world-id" :fn test-perlin-terrain-node-requires-world-id})
(table.insert tests {:name "heightfield terrain node requires world-id" :fn test-heightfield-terrain-node-requires-world-id})
(table.insert tests {:name "worlds node has correct key" :fn test-worlds-node-has-correct-key})
(table.insert tests {:name "world node has correct key" :fn test-world-node-has-correct-key})
(table.insert tests {:name "scene panels node has correct key" :fn test-scene-panels-node-has-correct-key})
(table.insert tests {:name "hud panels node has correct key" :fn test-hud-panels-node-has-correct-key})
(table.insert tests {:name "terrains node has correct key" :fn test-terrains-node-has-correct-key})
(table.insert tests {:name "scene panel node has correct key" :fn test-scene-panel-node-has-correct-key})
(table.insert tests {:name "hud panel node has correct key" :fn test-hud-panel-node-has-correct-key})
(table.insert tests {:name "terrain node has correct key" :fn test-terrain-node-has-correct-key})
(table.insert tests {:name "terrain node default label is generic" :fn test-terrain-node-default-label-is-generic})
(table.insert tests {:name "terrain node uses name as label" :fn test-terrain-node-uses-name-as-label})
(table.insert tests {:name "flat terrain node has correct key" :fn test-flat-terrain-node-has-correct-key})
(table.insert tests {:name "perlin terrain node has correct key" :fn test-perlin-terrain-node-has-correct-key})
(table.insert tests {:name "heightfield terrain node has correct key" :fn test-heightfield-terrain-node-has-correct-key})
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
(table.insert tests {:name "perlin terrain node updates world state" :fn test-perlin-terrain-node-updates-world-state})
(table.insert tests {:name "perlin terrain node updates active scene in place" :fn test-perlin-terrain-node-updates-active-scene-in-place})
(table.insert tests {:name "perlin terrain node errors when active runtime update fails" :fn test-perlin-terrain-node-errors-when-active-runtime-update-fails})
(table.insert tests {:name "heightfield terrain node updates world state" :fn test-heightfield-terrain-node-updates-world-state})
(table.insert tests {:name "heightfield terrain node updates active scene in place" :fn test-heightfield-terrain-node-updates-active-scene-in-place})
(table.insert tests {:name "heightfield terrain node errors when active runtime update fails" :fn test-heightfield-terrain-node-errors-when-active-runtime-update-fails})
(table.insert tests {:name "heightfield flat tool node applies rectangle to world state"
                     :fn test-heightfield-flat-tool-node-applies-rectangle-to-world-state})
(table.insert tests {:name "heightfield adjust tool node applies rectangle to world state"
                     :fn test-heightfield-adjust-tool-node-applies-rectangle-to-world-state})
(table.insert tests {:name "heightfield resize tool node updates world state"
                     :fn test-heightfield-resize-tool-node-updates-world-state})
(table.insert tests {:name "heightfield perlin tool node applies rectangle to world state"
                     :fn test-heightfield-perlin-tool-node-applies-rectangle-to-world-state})
(table.insert tests {:name "heightfield perlin tool node applies to world state" :fn test-heightfield-perlin-tool-node-applies-to-world-state})
(table.insert tests {:name "heightfield resize tool node updates active scene in place"
                     :fn test-heightfield-resize-tool-node-updates-active-scene-in-place})
(table.insert tests {:name "heightfield adjust tool node applies to active scene in place"
                     :fn test-heightfield-adjust-tool-node-applies-to-active-scene-in-place})
(table.insert tests {:name "heightfield adjust tool node applies stroke batch in one update"
                     :fn test-heightfield-adjust-tool-node-applies-stroke-batch-in-one-update})
(table.insert tests {:name "heightfield perlin tool node applies to active scene in place" :fn test-heightfield-perlin-tool-node-applies-to-active-scene-in-place})
(table.insert tests {:name "terrain node open editor adds edge" :fn test-terrain-node-open-editor-adds-edge})
(table.insert tests {:name "terrain node open editor returns nil for noneditable kind" :fn test-terrain-node-open-editor-returns-nil-for-noneditable-kind})
(table.insert tests {:name "terrain node heightfield kind opens editor" :fn test-terrain-node-heightfield-kind-opens-editor})
(table.insert tests {:name "terrain node open tool adds edge" :fn test-terrain-node-open-tool-adds-edge})
(table.insert tests {:name "terrain node open resize tool adds edge" :fn test-terrain-node-open-resize-tool-adds-edge})
(table.insert tests {:name "terrain node open adjust tool adds edge" :fn test-terrain-node-open-adjust-tool-adds-edge})
(table.insert tests {:name "terrains node add terrain updates world state" :fn test-terrains-node-add-terrain-updates-world-state})
(table.insert tests {:name "terrains node add terrain supports heightfield kind" :fn test-terrains-node-add-terrain-supports-heightfield-kind})
(table.insert tests {:name "terrains node adds active scene terrain in place" :fn test-terrains-node-adds-active-scene-terrain-in-place})
(table.insert tests {:name "terrains node add terrain errors on unsupported kind" :fn test-terrains-node-add-terrain-errors-on-unsupported-kind})
(table.insert tests {:name "terrains node adds new terrain node to graph when present" :fn test-terrains-node-adds-new-terrain-node-to-graph-when-present})
(table.insert tests {:name "flat terrain node remove updates world state" :fn test-flat-terrain-node-remove-updates-world-state})
(table.insert tests {:name "flat terrain node removes active scene in place" :fn test-flat-terrain-node-removes-active-scene-in-place})
(table.insert tests {:name "flat terrain node errors when active runtime remove fails" :fn test-flat-terrain-node-errors-when-active-runtime-remove-fails})
(table.insert tests {:name "perlin terrain node remove updates world state" :fn test-perlin-terrain-node-remove-updates-world-state})
(table.insert tests {:name "perlin terrain node removes active scene in place" :fn test-perlin-terrain-node-removes-active-scene-in-place})
(table.insert tests {:name "perlin terrain node errors when active runtime remove fails" :fn test-perlin-terrain-node-errors-when-active-runtime-remove-fails})
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
(table.insert tests {:name "graph key loaders loads heightfield terrain editor node" :fn test-graph-key-loaders-loads-heightfield-terrain-editor-node})
(table.insert tests {:name "graph key loaders loads heightfield terrain tool node" :fn test-graph-key-loaders-loads-heightfield-terrain-tool-node})

(fn make-icons-stub []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {65533 glyph
                           4242 glyph}})
  (local stub {:font font
               :codepoints {:close 4242
                            :play_arrow 4242
                            :arrow_drop_down 4242}})
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
  (local Intersectables (require :intersectables))
  (local Clickables (require :clickables))
  (local Hoverables (require :hoverables))
  (local intersectables (or app.intersectables (Intersectables)))
  (local clickables (or app.clickables (Clickables {:intersectables intersectables})))
  (local hoverables (or app.hoverables (Hoverables {:intersectables intersectables})))
  (local ctx (BuildContext {:clickables clickables
                            :hoverables hoverables}))
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

(fn test-terrains-node-view-builds-add-controls []
  (local TerrainsNodeView (require :graph/view/views/terrains))
  (local ctx (make-build-ctx))
  (local mock-node {:supported-terrain-kinds ["heightfield-terrain"]
                    :emit-items (fn [] [])
                    :items-changed (Signal)
                    :open-terrain-node (fn [_self _entry] nil)
                    :add-terrain (fn [_self _kind] nil)})
  (local builder (TerrainsNodeView mock-node))
  (local view (builder ctx))
  (assert view.layout "TerrainsNodeView should have layout")
  (assert view.kind-picker "TerrainsNodeView should expose a terrain kind picker")
  (assert view.add-button "TerrainsNodeView should expose an add button")
  (assert (= (view.kind-picker:get-value) "heightfield-terrain")
          "TerrainsNodeView should default to the first supported terrain kind")
  (view:drop))

(fn test-terrains-node-view-add-button-uses-selected-kind []
  (local TerrainsNodeView (require :graph/view/views/terrains))
  (local ctx (make-build-ctx))
  (var added-kind nil)
  (local mock-node {:supported-terrain-kinds ["heightfield-terrain"]
                    :emit-items (fn [] [])
                    :items-changed (Signal)
                    :open-terrain-node (fn [_self _entry] nil)
                    :add-terrain (fn [_self kind]
                                   (set added-kind kind))})
  (local builder (TerrainsNodeView mock-node))
  (local view (builder ctx))
  (view.kind-picker:set-value "heightfield-terrain")
  (view.add-button:on-click nil)
  (assert (= added-kind "heightfield-terrain")
          "TerrainsNodeView add button should use the selected terrain kind")
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
                    :terrain-kind "heightfield-terrain"
                    :has-editor? true
                    :open-editor (fn [_self] nil)
                    :open-tool (fn [_self _tool-id] nil)
                    :remove-terrain (fn [_self] nil)
                    :terrain-record (make-heightfield-terrain-record {:id "terrain-a" :name "mesa"})
                    :available-tools [{:id "resize-terrain" :label "Resize Terrain"}
                                      {:id "initialize-flat" :label "Initialize Flat"}
                                      {:id "adjust-height" :label "Raise/Lower"}
                                      {:id "apply-perlin" :label "Apply Perlin"}]
                    :changed (Signal)})
  (local builder (TerrainNodeView mock-node))
  (local view (builder ctx))
  (assert view.layout "TerrainNodeView should have layout")
  (assert view.scroll-view "TerrainNodeView should use a scroll view for long summaries")
  (assert view.tools-search "TerrainNodeView should expose a tools search list")
  (assert (= (length (or view.tools-search.items [])) 4) "TerrainNodeView should list terrain tools")
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

(fn test-perlin-terrain-node-view-builds []
  (local Validation (require :graph/perlin-terrain-editor-validation))
  (local PerlinTerrainNodeView (require :graph/view/views/perlin-terrain))
  (local ctx (make-build-ctx))
  (local mock-node {:terrain-id "terrain-a"
                    :changed (Signal)
                    :get-record (fn [] (make-perlin-terrain-record {:id "terrain-a"}))
                    :apply-values (fn [_self _values] true)})
  (local builder (PerlinTerrainNodeView mock-node))
  (local view (builder ctx))
  (assert view "PerlinTerrainNodeView should build a view")
  (assert view.layout "PerlinTerrainNodeView should have layout")
  (assert view.fields "PerlinTerrainNodeView should expose fields")
  (assert view.error-labels "PerlinTerrainNodeView should expose field error labels")
  (assert view.status-label "PerlinTerrainNodeView should expose status label")
  (assert view.apply-button "PerlinTerrainNodeView should expose apply button")
  (assert (= (length Validation.field-specs) 15) "validation should expose perlin terrain field specs")
  (assert (not view.apply-button.enabled?) "Apply should start disabled when nothing changed")
  (view:drop))

(fn test-perlin-terrain-node-view-defers-updates-until-apply []
  (local PerlinTerrainNodeView (require :graph/view/views/perlin-terrain))
  (local ctx (make-build-ctx))
  (var updates 0)
  (local record (make-perlin-terrain-record {:id "terrain-a" :seed 7}))
  (local changed (Signal))
  (local mock-node {:terrain-id "terrain-a"
                    :changed changed
                    :get-record (fn [] record)
                    :apply-values (fn [_self validated]
                                      (set updates (+ updates 1))
                                      (local options (. record :options))
                                      (set options.seed validated.seed)
                                      (changed:emit record)
                                      record)})
  (local builder (PerlinTerrainNodeView mock-node))
  (local view (builder ctx))
  (view.fields.seed:set-text "99")
  (assert (= updates 0) "editing input text should not update perlin terrain immediately")
  (assert view.apply-button.enabled? "Apply should enable when the perlin draft is dirty")
  (view.apply-button:on-click {})
  (assert (= updates 1) "Apply should trigger a single perlin terrain update")
  (assert (= (. (. record :options) :seed) 99) "Apply should write edited perlin seed")
  (assert (not view.apply-button.enabled?) "Apply should disable again after perlin commit")
  (assert (= (text-entity-value view.status-label) "Applied") "successful perlin apply should show applied status")
  (view:drop))

(fn test-perlin-terrain-node-view-shows-validation-errors []
  (local PerlinTerrainNodeView (require :graph/view/views/perlin-terrain))
  (local ctx (make-build-ctx))
  (var updates 0)
  (local mock-node {:terrain-id "terrain-a"
                    :changed (Signal)
                    :get-record (fn [] (make-perlin-terrain-record {:id "terrain-a"}))
                    :apply-values (fn [_self _values]
                                    (set updates (+ updates 1))
                                    true)})
  (local builder (PerlinTerrainNodeView mock-node))
  (local view (builder ctx))
  (view.fields.seed:set-text "-1")
  (view.apply-button:on-click {})
  (assert (= updates 0) "invalid perlin apply should not update terrain")
  (assert (= (text-entity-value (. (. view :error-labels) :seed)) "Seed must be between 0 and 4294967295")
          "invalid perlin seed should show an inline error")
  (assert (= (text-entity-value view.status-label) "Fix 1 invalid field before applying")
          "invalid perlin apply should show summary feedback")
  (view.fields.seed:set-text "99")
  (assert (= (text-entity-value (. (. view :error-labels) :seed)) "")
          "fixing a perlin field should clear its inline error")
  (assert (= (text-entity-value view.status-label) "Unsaved changes")
          "fixing the perlin field should return to unsaved status")
  (view:drop))

(fn test-perlin-terrain-editor-validation-validates-draft []
  (local Validation (require :graph/perlin-terrain-editor-validation))
  (local draft (Validation.draft-from-record (make-perlin-terrain-record {:id "terrain-a"})))
  (set (. draft :seed) "-1")
  (local result (Validation.validate-draft draft))
  (assert (not result.ok?) "perlin validation should reject invalid draft values")
  (assert (= (. (. result :errors) :seed) "Seed must be between 0 and 4294967295")
          "perlin seed validation should require the native uint32 range"))

(fn test-heightfield-terrain-node-view-builds []
  (local Validation (require :graph/heightfield-terrain-editor-validation))
  (local HeightfieldTerrainNodeView (require :graph/view/views/heightfield-terrain))
  (local ctx (make-build-ctx))
  (local mock-node {:terrain-id "terrain-a"
                    :changed (Signal)
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :apply-values (fn [_self _values] true)})
  (local builder (HeightfieldTerrainNodeView mock-node))
  (local view (builder ctx))
  (assert view "HeightfieldTerrainNodeView should build a view")
  (assert view.layout "HeightfieldTerrainNodeView should have layout")
  (assert view.fields "HeightfieldTerrainNodeView should expose property fields")
  (assert (= (length Validation.field-specs) 6) "validation should expose heightfield terrain property field specs")
  (assert (not view.apply-button.enabled?) "property apply should start disabled when nothing changed")
  (view:drop))

(fn test-heightfield-terrain-node-view-defers-updates-until-apply []
  (local HeightfieldTerrainNodeView (require :graph/view/views/heightfield-terrain))
  (local ctx (make-build-ctx))
  (var updates 0)
  (local record (make-heightfield-terrain-record {:id "terrain-a" :default-height 0.0}))
  (local changed (Signal))
  (local mock-node {:terrain-id "terrain-a"
                    :changed changed
                    :get-record (fn [] record)
                    :apply-values (fn [_self validated]
                                    (set updates (+ updates 1))
                                    (set record.name validated.name)
                                    (local options (. record :options))
                                    (set options.position validated.position)
                                    (set options.opacity validated.opacity)
                                    (set options.physics validated.physics)
                                    (changed:emit record)
                                    record)})
  (local builder (HeightfieldTerrainNodeView mock-node))
  (local view (builder ctx))
  (view.fields.name:set-text "mesa")
  (view.fields.physics:set-value "disabled")
  (assert (= updates 0) "editing input text should not update heightfield terrain immediately")
  (assert view.apply-button.enabled? "Apply should enable when the heightfield draft is dirty")
  (view.apply-button:on-click {})
  (assert (= updates 1) "Apply should trigger a single heightfield terrain update")
  (assert (= record.name "mesa") "Apply should write edited terrain name")
  (assert (= (. (. record :options) :physics) false) "Apply should write edited physics state")
  (assert (not view.apply-button.enabled?) "Apply should disable again after heightfield commit")
  (assert (= (text-entity-value view.status-label) "Applied") "successful heightfield apply should show applied status")
  (view:drop))

(fn test-heightfield-terrain-node-view-shows-validation-errors []
  (local HeightfieldTerrainNodeView (require :graph/view/views/heightfield-terrain))
  (local ctx (make-build-ctx))
  (var updates 0)
  (local mock-node {:terrain-id "terrain-a"
                    :changed (Signal)
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :apply-values (fn [_self _values]
                                    (set updates (+ updates 1))
                                    true)})
  (local builder (HeightfieldTerrainNodeView mock-node))
  (local view (builder ctx))
  (view.fields.opacity:set-text "2")
  (view.apply-button:on-click {})
  (assert (= updates 0) "invalid heightfield apply should not update terrain")
  (assert (= (text-entity-value (. (. view :error-labels) :opacity)) "Opacity must be between 0 and 1")
          "invalid heightfield value should show an inline error")
  (assert (= (text-entity-value view.status-label) "Fix 1 invalid field before applying")
          "invalid heightfield apply should show summary feedback")
  (view.fields.opacity:set-text "0.5")
  (assert (= (text-entity-value (. (. view :error-labels) :opacity)) "")
          "fixing the heightfield field should clear its inline error")
  (assert (= (text-entity-value view.status-label) "Unsaved changes")
          "fixing the heightfield field should return to unsaved status")
  (view:drop))

(fn test-heightfield-flat-tool-node-view-builds []
  (local Validation (require :graph/heightfield-flat-tool-validation))
  (local HeightfieldFlatToolNodeView (require :graph/view/views/heightfield-flat-tool))
  (local ctx (make-build-ctx))
  (local world-changed (Signal))
  (local mock-node {:terrain-id "terrain-a"
                    :world-id "world-a"
                    :world-manager {:changed world-changed}
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :get-live-scene (fn [] nil)
                    :apply-values (fn [_self _validated] true)})
  (local builder (HeightfieldFlatToolNodeView mock-node))
  (local view (builder ctx))
  (assert view.layout "HeightfieldFlatToolNodeView should have layout")
  (assert view.scroll-view "HeightfieldFlatToolNodeView should wrap controls in a scroll view")
  (assert view.fields "HeightfieldFlatToolNodeView should expose fields")
  (assert view.pick-button "HeightfieldFlatToolNodeView should expose the live pick button")
  (assert (not view.pick-button.enabled?) "flat tool live pick should be disabled without an active scene")
  (assert (= (length Validation.field-specs) 1) "flat tool validation should expose only the height field")
  (view:drop))

(fn test-heightfield-flat-tool-node-view-reacts-to-world-activation []
  (local HeightfieldFlatToolNodeView (require :graph/view/views/heightfield-flat-tool))
  (local ctx (make-build-ctx))
  (local world-changed (Signal))
  (var live-scene nil)
  (local mock-node {:terrain-id "terrain-a"
                    :world-id "world-a"
                    :world-manager {:changed world-changed}
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :get-live-scene (fn [] live-scene)
                    :apply-values (fn [_self _validated] true)})
  (local builder (HeightfieldFlatToolNodeView mock-node))
  (local view (builder ctx))
  (assert (not view.pick-button.enabled?) "flat tool live pick should start disabled without an active scene")
  (set live-scene {:id "scene-a"})
  (world-changed:emit {:active-index 1})
  (assert view.pick-button.enabled? "flat tool live pick should enable when its world becomes active")
  (set live-scene nil)
  (world-changed:emit {:active-index nil})
  (assert (not view.pick-button.enabled?) "flat tool live pick should disable when its world becomes inactive")
  (view:drop))

(fn test-heightfield-flat-tool-stays-applicable-after-apply []
  (local HeightfieldFlatToolNodeView (require :graph/view/views/heightfield-flat-tool))
  (local ctx (make-build-ctx))
  (var updates 0)
  (local mock-node {:terrain-id "terrain-a"
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :get-selection-target (fn [_self]
                                            {:mode :samples :shape :rect :x0 1 :z0 1 :x1 2 :z1 2
                                             :sample-count 4 :width 2 :length 2})
                    :apply-values (fn [_self _values]
                                           (set updates (+ updates 1))
                                           true)})
  (local builder (HeightfieldFlatToolNodeView mock-node))
  (local view (builder ctx))
  (view.fields.height:set-text "2")
  (assert view.apply-button.enabled? "flat tool should enable apply when valid")
  (view.apply-button:on-click {})
  (assert (= updates 1) "flat tool should apply once")
  (assert view.apply-button.enabled? "flat tool apply should remain enabled after apply")
  (assert (= (text-entity-value view.selection-label) "4 samples across [1, 1] to [2, 2]"))
  (assert (= (text-entity-value view.status-label) "Applied") "flat tool should show applied status")
  (view:drop))

(fn test-heightfield-perlin-tool-stays-applicable-after-apply []
  (local HeightfieldPerlinToolNodeView (require :graph/view/views/heightfield-perlin-tool))
  (local ctx (make-build-ctx))
  (var updates 0)
  (local mock-node {:terrain-id "terrain-a"
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :get-selection-target (fn [_self]
                                            {:mode :samples :shape :rect :x0 1 :z0 1 :x1 3 :z1 3
                                             :sample-count 9 :width 3 :length 3})
                    :apply-values (fn [_self _values]
                                    (set updates (+ updates 1))
                                    true)})
  (local builder (HeightfieldPerlinToolNodeView mock-node))
  (local view (builder ctx))
  (view.fields.seed:set-text "99")
  (assert view.apply-button.enabled? "perlin tool should enable apply when valid")
  (view.apply-button:on-click {})
  (assert (= updates 1) "perlin tool should apply once")
  (assert view.apply-button.enabled? "perlin tool apply should remain enabled after apply")
  (assert (= (text-entity-value view.selection-label) "9 samples across [1, 1] to [3, 3]"))
  (assert (= (view.fields.seed:get-text) "99") "perlin tool should keep last used params")
  (assert (= (text-entity-value view.status-label) "Applied") "perlin tool should show applied status")
  (view:drop))

(fn test-heightfield-perlin-tool-pick-rectangle-updates-fields []
  (local HeightfieldPerlinToolNodeView (require :graph/view/views/heightfield-perlin-tool))
  (local States (require :states))
  (local TerrainRectPickState (require :terrain-rect-pick-state))
  (local ctx (make-build-ctx))
  (local world-changed (Signal))
  (local original-terrain-rect-pick-session app.terrain-rect-pick-session)
  (local original-states app.states)
  (var suspended-state nil)
  (local original-hud app.hud)
  (local original-clickables app.clickables)
  (local terrain-record
    (make-heightfield-terrain-record {:id "terrain-a"
                                      :position [0 0 0]
                                      :rotation [1 0 0 0]
                                      :sample-spacing [1 1]
                                      :chunk-samples [5 5]
                                      :default-height 0.0
                                      :chunks [{:coord [0 0]
                                                :size [5 5]
                                                :heights [0 0 0 0 0
                                                          0 0 0 0 0
                                                          0 0 0 0 0
                                                          0 0 0 0 0
                                                          0 0 0 0 0]}]}))
  (local scene
    {:screen-pos-terrain-domain-hit
     (fn [_self pos _opts]
       (if (< pos.x 20)
           {:terrain-id "terrain-a"
            :terrain-kind "heightfield-terrain"
            :terrain-record terrain-record
            :local-point (glm.vec3 1 0 2)}
           {:terrain-id "terrain-a"
            :terrain-kind "heightfield-terrain"
            :terrain-record terrain-record
            :local-point (glm.vec3 3 0 4)}))
     :screen-rect-terrain-target
     (fn [_self _terrain-id start-pos end-pos _opts]
       (if (and (< start-pos.x 20) (< end-pos.x 20))
           {:terrain-id "terrain-a"
            :terrain-kind "heightfield-terrain"
            :terrain-record terrain-record
            :target {:mode :samples :shape :rect :x0 1 :z0 2 :x1 1 :z1 2 :sample-count 1 :width 1 :length 1}}
           {:terrain-id "terrain-a"
            :terrain-kind "heightfield-terrain"
            :terrain-record terrain-record
            :target {:mode :samples :shape :rect :x0 1 :z0 2 :x1 3 :z1 4 :sample-count 12 :width 3 :length 4}}))})
  (local mock-node
    {:terrain-id "terrain-a"
     :world-id "world-a"
     :world-manager {:changed world-changed}
     :get-record (fn [] terrain-record)
     :get-live-scene (fn [] scene)
     :apply-values (fn [_self _values] true)})
  (local states (States))
  (set app.hud {:build-context ctx
                :world-units-per-pixel 1})
  (states.add-state :normal {})
  (states.add-state :terrain-rect-pick (TerrainRectPickState))
  (states.set-state :normal)
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set app.states states)
  (set app.clickables {:on-mouse-button-down (fn [_self _payload] nil)
                       :on-mouse-button-up (fn [_self _payload] nil)
                       :active? true})
  (local builder (HeightfieldPerlinToolNodeView mock-node))
  (local view (builder ctx))
  (assert view.pick-button.enabled? "perlin tool live pick should enable when the terrain world is active")
  (for [_ 1 2]
    (view.pick-button:on-click {})
    (assert (= (app.states.active-name) :terrain-rect-pick)
            "clicking pick rectangle should enter the explicit terrain rectangle pick state")
    (assert app.terrain-rect-pick-session
            "clicking pick rectangle should register the active terrain rectangle pick session")
    (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
    (app.engine.events.mouse-motion.emit {:x 40 :y 60})
    (app.engine.events.updated.emit 0.016)
    (app.engine.events.mouse-button-up.emit {:button 1 :x 40 :y 60})
    (assert (= (app.states.active-name) :normal)
            "successful rectangle picking should restore the previous state"))
  (local draft (and view.form (view.form:get-draft)))
  (local picked-target (and draft draft.picked-target))
  (assert picked-target "successful pick should store the picked target in the form")
  (assert (= picked-target.x0 1))
  (assert (= picked-target.z0 2))
  (assert (= picked-target.x1 3))
  (assert (= picked-target.z1 4))
  (assert (= (text-entity-value view.selection-label) "12 samples across [1, 2] to [3, 4]"))
  (set app.terrain-rect-pick-session original-terrain-rect-pick-session)
  (set app.states original-states)
  (TestSupport.resume-active-state suspended-state)
  (set app.hud original-hud)
  (set app.clickables original-clickables)
  (view:drop))

(fn test-heightfield-perlin-tool-initializes-from-existing-selection-target []
  (local HeightfieldPerlinToolNodeView (require :graph/view/views/heightfield-perlin-tool))
  (local ctx (make-build-ctx))
  (local mock-node {:terrain-id "terrain-a"
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :get-selection-target (fn [_self]
                                            {:mode :samples
                                             :shape :rect
                                             :x0 2
                                             :z0 3
                                             :x1 5
                                             :z1 7
                                             :sample-count 20
                                             :width 4
                                             :length 5})
                    :apply-values (fn [_self _values] true)})
  (local builder (HeightfieldPerlinToolNodeView mock-node))
  (local view (builder ctx))
  (assert (= (text-entity-value view.selection-label) "20 samples across [2, 3] to [5, 7]"))
  (view:drop))

(fn test-heightfield-perlin-tool-initial-draft-preserves-selection-target []
  (local HeightfieldPerlinToolNodeView (require :graph/view/views/heightfield-perlin-tool))
  (local ctx (make-build-ctx))
  (local mock-node {:terrain-id "terrain-a"
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :get-selection-target (fn [_self]
                                            {:mode :samples
                                             :shape :rect
                                             :x0 7
                                             :z0 8
                                             :x1 9
                                             :z1 10
                                             :sample-count 9
                                             :width 3
                                             :length 3})
                    :apply-values (fn [_self _values] true)})
  (local builder (HeightfieldPerlinToolNodeView mock-node))
  (local view (builder ctx))
  (local draft (and view.form (view.form:get-draft)))
  (local picked-target (and draft draft.picked-target))
  (assert picked-target)
  (assert (= picked-target.x0 7))
  (assert (= picked-target.z0 8))
  (assert (= picked-target.x1 9))
  (assert (= picked-target.z1 10))
  (assert (= (text-entity-value view.selection-label) "9 samples across [7, 8] to [9, 10]"))
  (view:drop))

(fn test-heightfield-resize-tool-node-view-builds []
  (local Validation (require :graph/heightfield-resize-tool-validation))
  (local HeightfieldResizeToolNodeView (require :graph/view/views/heightfield-resize-tool))
  (local ctx (make-build-ctx))
  (local mock-node {:terrain-id "terrain-a"
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :apply-values (fn [_self _validated] true)})
  (local builder (HeightfieldResizeToolNodeView mock-node))
  (local view (builder ctx))
  (assert view.layout "HeightfieldResizeToolNodeView should have layout")
  (assert view.fields "HeightfieldResizeToolNodeView should expose fields")
  (assert view.center-on-origin-button "HeightfieldResizeToolNodeView should expose center-on-origin button")
  (assert (= (length Validation.field-specs) 5) "resize tool validation should expose chunk bounds and fill height")
  (view:drop))

(fn test-heightfield-resize-tool-node-center-on-origin-updates-world-state []
  (local {:HeightfieldResizeToolNode HeightfieldResizeToolNode} (require :graph/nodes/heightfield-resize-tool))
  (local terrain-record
    (make-heightfield-terrain-record {:id "terrain-a"
                                      :default-height 0.0
                                      :chunk-samples [5 5]
                                      :position [100 -20 50]}))
  (local state {:scene {:panels [] :terrains [terrain-record]}
                :hud {:panels []}})
  (local entry (make-world-entry {:id "test-world"
                                  :active? true
                                  :state state}))
  (local manager (make-world-manager {:id "test-world"
                                      :active? true
                                      :entry entry}))
  (local node (HeightfieldResizeToolNode {:world-id "test-world"
                                          :world-manager manager
                                          :terrain-id "terrain-a"}))
  (local updated
    (node:apply-values-centered-on-origin {:min-chunk-x -2
                                           :min-chunk-z 0
                                           :max-chunk-x 1
                                           :max-chunk-z 1
                                           :fill-height 4.0}))
  (assert updated "center-on-origin apply should update world state")
  (assert (= (. updated.options.position 1) 0)
          "center-on-origin apply should shift canonical terrain X so the resized footprint centers on world origin")
  (assert (= (. updated.options.position 2) -20)
          "center-on-origin apply should preserve terrain Y position")
  (assert (= (. updated.options.position 3) -80)
          "center-on-origin apply should shift canonical terrain Z so the resized footprint centers on world origin")
  (node:drop))

(fn test-heightfield-resize-tool-stays-applicable-after-apply []
  (local HeightfieldResizeToolNodeView (require :graph/view/views/heightfield-resize-tool))
  (local ctx (make-build-ctx))
  (var updates 0)
  (local mock-node {:terrain-id "terrain-a"
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :apply-values (fn [_self _values]
                                    (set updates (+ updates 1))
                                    true)})
  (local builder (HeightfieldResizeToolNodeView mock-node))
  (local view (builder ctx))
  (view.fields.min-chunk-x:set-text "-1")
  (view.fields.max-chunk-x:set-text "1")
  (view.fields.fill-height:set-text "3")
  (assert view.apply-button.enabled? "resize tool should enable apply when valid")
  (view.apply-button:on-click {})
  (assert (= updates 1) "resize tool should apply once")
  (assert view.apply-button.enabled? "resize tool apply should remain enabled after apply")
  (assert (= (view.fields.min-chunk-x:get-text) "-1") "resize tool should keep last used params")
  (assert (= (text-entity-value view.status-label) "Applied") "resize tool should show applied status")
  (view:drop))

(fn test-heightfield-resize-tool-center-on-origin-button-applies-centered-resize []
  (local HeightfieldResizeToolNodeView (require :graph/view/views/heightfield-resize-tool))
  (local ctx (make-build-ctx))
  (var centered-values nil)
  (local mock-node {:terrain-id "terrain-a"
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :apply-values (fn [_self _validated] true)
                    :apply-values-centered-on-origin (fn [_self validated]
                                                      (set centered-values validated)
                                                      true)})
  (local builder (HeightfieldResizeToolNodeView mock-node))
  (local view (builder ctx))
  (view.fields.min-chunk-x:set-text "2")
  (view.fields.max-chunk-x:set-text "5")
  (view.fields.min-chunk-z:set-text "-4")
  (view.fields.max-chunk-z:set-text "2")
  (view.center-on-origin-button:on-click {})
  (assert centered-values "center-on-origin button should invoke the centered apply path")
  (assert (= centered-values.min-chunk-x 2) "center-on-origin button should use current X min draft value")
  (assert (= centered-values.max-chunk-x 5) "center-on-origin button should use current X max draft value")
  (assert (= centered-values.min-chunk-z -4) "center-on-origin button should use current Z min draft value")
  (assert (= centered-values.max-chunk-z 2) "center-on-origin button should use current Z max draft value")
  (view:drop))

(fn test-heightfield-adjust-tool-node-view-builds []
  (local Validation (require :graph/heightfield-adjust-tool-validation))
  (local HeightfieldAdjustToolNodeView (require :graph/view/views/heightfield-adjust-tool))
  (local ctx (make-build-ctx))
  (local world-changed (Signal))
  (local mock-node {:terrain-id "terrain-a"
                    :world-id "world-a"
                    :world-manager {:changed world-changed}
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :get-live-scene (fn [] nil)
                    :apply-values (fn [_self _validated] true)})
  (local builder (HeightfieldAdjustToolNodeView mock-node))
  (local view (builder ctx))
  (assert view.layout "HeightfieldAdjustToolNodeView should have layout")
  (assert view.scroll-view "HeightfieldAdjustToolNodeView should wrap controls in a scroll view")
  (assert view.fields "HeightfieldAdjustToolNodeView should expose fields")
  (assert view.pick-button "HeightfieldAdjustToolNodeView should expose the live pick button")
  (assert view.paint-button "HeightfieldAdjustToolNodeView should expose the live paint button")
  (assert (not view.pick-button.enabled?) "adjust tool live pick should be disabled without an active scene")
  (assert (not view.paint-button.enabled?) "adjust tool live paint should be disabled without an active scene")
  (assert (= (length Validation.field-specs) 1) "adjust tool validation should expose only the delta field")
  (view:drop))

(fn test-heightfield-adjust-tool-node-view-reacts-to-world-activation []
  (local HeightfieldAdjustToolNodeView (require :graph/view/views/heightfield-adjust-tool))
  (local ctx (make-build-ctx))
  (local world-changed (Signal))
  (var live-scene nil)
  (local mock-node {:terrain-id "terrain-a"
                    :world-id "world-a"
                    :world-manager {:changed world-changed}
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :get-live-scene (fn [] live-scene)
                    :apply-values (fn [_self _validated] true)})
  (local builder (HeightfieldAdjustToolNodeView mock-node))
  (local view (builder ctx))
  (assert (not view.pick-button.enabled?) "adjust tool live pick should start disabled without an active scene")
  (assert (not view.paint-button.enabled?) "adjust tool live paint should start disabled without an active scene")
  (set live-scene {:id "scene-a"})
  (world-changed:emit {:active-index 1})
  (assert view.pick-button.enabled? "adjust tool live pick should enable when its world becomes active")
  (assert view.paint-button.enabled? "adjust tool live paint should enable when its world becomes active")
  (set live-scene nil)
  (world-changed:emit {:active-index nil})
  (assert (not view.pick-button.enabled?) "adjust tool live pick should disable when its world becomes inactive")
  (assert (not view.paint-button.enabled?) "adjust tool live paint should disable when its world becomes inactive")
  (view:drop))

(fn test-heightfield-adjust-tool-stays-applicable-after-apply []
  (local HeightfieldAdjustToolNodeView (require :graph/view/views/heightfield-adjust-tool))
  (local ctx (make-build-ctx))
  (var updates 0)
  (local mock-node {:terrain-id "terrain-a"
                    :get-record (fn [] (make-heightfield-terrain-record {:id "terrain-a"}))
                    :get-selection-target (fn [_self]
                                            {:mode :samples :shape :rect :x0 1 :z0 1 :x1 2 :z1 2
                                             :sample-count 4 :width 2 :length 2})
                    :apply-values (fn [_self _values]
                                    (set updates (+ updates 1))
                                    true)})
  (local builder (HeightfieldAdjustToolNodeView mock-node))
  (local view (builder ctx))
  (view.fields.delta:set-text "-0.5")
  (assert view.apply-button.enabled? "adjust tool should enable apply when valid")
  (view.apply-button:on-click {})
  (assert (= updates 1) "adjust tool should apply once")
  (assert view.apply-button.enabled? "adjust tool apply should remain enabled after apply")
  (assert (= (text-entity-value view.selection-label) "4 samples across [1, 1] to [2, 2]"))
  (assert (= (view.fields.delta:get-text) "-0.5") "adjust tool should keep last used params")
  (assert (= (text-entity-value view.status-label) "Applied") "adjust tool should show applied status")
  (view:drop))

(fn test-heightfield-adjust-tool-node-emits-lightweight-stroke-change []
  (local {:HeightfieldAdjustToolNode HeightfieldAdjustToolNode} (require :graph/nodes/heightfield-adjust-tool))
  (local entry
    (make-world-entry {:id "world-a"
                       :state {:scene {:panels []
                                       :terrains [(make-heightfield-terrain-record {:id "terrain-a"})]}
                               :hud {:panels []}}}))
  (local world-manager (make-world-manager {:id "world-a" :entry entry}))
  (local node (HeightfieldAdjustToolNode {:world-id "world-a"
                                          :world-manager world-manager
                                          :terrain-id "terrain-a"}))
  (var payload nil)
  (node.changed:connect (fn [next-payload]
                          (set payload next-payload)))
  (node:apply-stroke-values {:targets [{:mode :rect :x0 1 :z0 1 :x1 1 :z1 1}
                                       {:mode :rect :x0 2 :z0 1 :x1 2 :z1 1}]
                             :delta 0.25})
  (assert (= payload.reason :live-stroke-applied)
          "live stroke updates should emit a lightweight reason payload")
  (assert (= payload.terrain-id "terrain-a")
          "live stroke updates should identify the edited terrain")
  (assert (= payload.target-count 2)
          "live stroke updates should report the batch target count")
  (node:drop))

(table.insert tests {:name "world node view builds" :fn test-world-node-view-builds})
(table.insert tests {:name "world node view set categories" :fn test-world-node-view-set-categories})
(table.insert tests {:name "world node view refresh categories" :fn test-world-node-view-refresh-categories})
(table.insert tests {:name "world node view search submitted" :fn test-world-node-view-search-submitted})
(table.insert tests {:name "terrains node view builds add controls" :fn test-terrains-node-view-builds-add-controls})
(table.insert tests {:name "terrains node view add button uses selected kind" :fn test-terrains-node-view-add-button-uses-selected-kind})
(table.insert tests {:name "terrain node view builds scrollable summary" :fn test-terrain-node-view-builds-scrollable-summary})
(table.insert tests {:name "flat terrain node view builds" :fn test-flat-terrain-node-view-builds})
(table.insert tests {:name "flat terrain node view defers updates until apply" :fn test-flat-terrain-node-view-defers-updates-until-apply})
(table.insert tests {:name "flat terrain node view shows validation errors" :fn test-flat-terrain-node-view-shows-validation-errors})
(table.insert tests {:name "terrain editor validation validates draft" :fn test-terrain-editor-validation-validates-draft})
(table.insert tests {:name "perlin terrain node view builds" :fn test-perlin-terrain-node-view-builds})
(table.insert tests {:name "perlin terrain node view defers updates until apply" :fn test-perlin-terrain-node-view-defers-updates-until-apply})
(table.insert tests {:name "perlin terrain node view shows validation errors" :fn test-perlin-terrain-node-view-shows-validation-errors})
(table.insert tests {:name "perlin terrain editor validation validates draft" :fn test-perlin-terrain-editor-validation-validates-draft})
(table.insert tests {:name "heightfield terrain node view builds" :fn test-heightfield-terrain-node-view-builds})
(table.insert tests {:name "heightfield terrain node view defers updates until apply" :fn test-heightfield-terrain-node-view-defers-updates-until-apply})
(table.insert tests {:name "heightfield terrain node view shows validation errors" :fn test-heightfield-terrain-node-view-shows-validation-errors})
(table.insert tests {:name "heightfield flat tool node view builds" :fn test-heightfield-flat-tool-node-view-builds})
(table.insert tests {:name "heightfield flat tool node view reacts to world activation" :fn test-heightfield-flat-tool-node-view-reacts-to-world-activation})
(table.insert tests {:name "heightfield flat tool stays applicable after apply" :fn test-heightfield-flat-tool-stays-applicable-after-apply})
(table.insert tests {:name "heightfield perlin tool stays applicable after apply" :fn test-heightfield-perlin-tool-stays-applicable-after-apply})
(table.insert tests {:name "heightfield perlin tool pick rectangle updates fields"
                     :fn test-heightfield-perlin-tool-pick-rectangle-updates-fields})
(table.insert tests {:name "heightfield perlin tool initializes from existing selection target"
                     :fn test-heightfield-perlin-tool-initializes-from-existing-selection-target})
(table.insert tests {:name "heightfield perlin tool initial draft preserves selection target"
                     :fn test-heightfield-perlin-tool-initial-draft-preserves-selection-target})
(table.insert tests {:name "heightfield resize tool node view builds" :fn test-heightfield-resize-tool-node-view-builds})
(table.insert tests {:name "heightfield resize tool node center-on-origin updates world state"
                     :fn test-heightfield-resize-tool-node-center-on-origin-updates-world-state})
(table.insert tests {:name "heightfield resize tool stays applicable after apply" :fn test-heightfield-resize-tool-stays-applicable-after-apply})
(table.insert tests {:name "heightfield resize tool center-on-origin button applies centered resize"
                     :fn test-heightfield-resize-tool-center-on-origin-button-applies-centered-resize})
(table.insert tests {:name "heightfield adjust tool node view builds" :fn test-heightfield-adjust-tool-node-view-builds})
(table.insert tests {:name "heightfield adjust tool node view reacts to world activation" :fn test-heightfield-adjust-tool-node-view-reacts-to-world-activation})
(table.insert tests {:name "heightfield adjust tool stays applicable after apply" :fn test-heightfield-adjust-tool-stays-applicable-after-apply})
(table.insert tests {:name "heightfield adjust tool node emits lightweight stroke change" :fn test-heightfield-adjust-tool-node-emits-lightweight-stroke-change})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "world-nodes"
                       :tests tests})))

{:name "world-nodes"
 :tests tests
 :main main}
