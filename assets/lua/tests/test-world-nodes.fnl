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

(fn test-worlds-node-has-correct-key []
  (local {:WorldsNode WorldsNode} (require :graph/nodes/worlds))
  (local mock-manager {:changed (Signal) :list-tabs (fn [] [])})
  (local node (WorldsNode {:world-manager mock-manager}))
  (assert (= node.key "worlds") "WorldsNode key should be 'worlds'")
  (assert (= node.label "worlds") "WorldsNode label should be 'worlds'")
  (node:drop))

(fn test-world-node-has-correct-key []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (local mock-manager {:changed (Signal) :list-tabs (fn [] []) :active-world (fn [] nil)})
  (local node (WorldNode {:world-id "test-world-123" :world-manager mock-manager}))
  (assert (= node.key "world:test-world-123") "WorldNode key should include world-id")
  (node:drop))

(fn test-scene-panels-node-has-correct-key []
  (local {:ScenePanelsNode ScenePanelsNode} (require :graph/nodes/scene-panels))
  (local node (ScenePanelsNode {:world-id "test-world-123"}))
  (assert (= node.key "scene-panels:test-world-123") "ScenePanelsNode key should include world-id")
  (assert (= node.label "scene panels") "ScenePanelsNode label should be 'scene panels'")
  (node:drop))

(fn test-hud-panels-node-has-correct-key []
  (local {:HudPanelsNode HudPanelsNode} (require :graph/nodes/hud-panels))
  (local node (HudPanelsNode {:world-id "test-world-123"}))
  (assert (= node.key "hud-panels:test-world-123") "HudPanelsNode key should include world-id")
  (assert (= node.label "hud panels") "HudPanelsNode label should be 'hud panels'")
  (node:drop))

(fn test-terrains-node-has-correct-key []
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (local node (TerrainsNode {:world-id "test-world-123"}))
  (assert (= node.key "terrains:test-world-123") "TerrainsNode key should include world-id")
  (assert (= node.label "terrains") "TerrainsNode label should be 'terrains'")
  (node:drop))

(fn test-scene-panel-node-has-correct-key []
  (local {:ScenePanelNode ScenePanelNode} (require :graph/nodes/scene-panel))
  (local node (ScenePanelNode {:world-id "test-world-123" :panel-index 5}))
  (assert (= node.key "scene-panel:test-world-123:5") "ScenePanelNode key should include world-id and index")
  (node:drop))

(fn test-hud-panel-node-has-correct-key []
  (local {:HudPanelNode HudPanelNode} (require :graph/nodes/hud-panel))
  (local node (HudPanelNode {:world-id "test-world-123" :layer "float" :panel-index 3}))
  (assert (= node.key "hud-panel:test-world-123:float:3") "HudPanelNode key should include world-id, layer, and index")
  (node:drop))

(fn test-terrain-node-has-correct-key []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local node (TerrainNode {:world-id "test-world-123" :terrain-id "terrain-abc"}))
  (assert (= node.key "terrain:test-world-123:terrain-abc") "TerrainNode key should include world-id and terrain-id")
  (node:drop))

(fn test-world-node-has-emit-categories []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (local mock-manager {:changed (Signal) :list-tabs (fn [] []) :active-world (fn [] nil)})
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
  (local mock-manager {:changed (Signal) :list-tabs (fn [] []) :active-world (fn [] nil)})
  (local node (WorldNode {:world-id "test-world-123" :world-manager mock-manager}))
  (graph:add-node node {})
  (local categories (node:emit-categories))
  (node:add-category-node (. categories 1))
  (assert (= (graph:edge-count) 1) "WorldNode add-category-node should create 1 edge")
  (node:drop)
  (graph:drop))

(fn test-worlds-node-has-emit-items []
  (local {:WorldsNode WorldsNode} (require :graph/nodes/worlds))
  (local mock-manager {:changed (Signal) :list-tabs (fn [] [{:index 1 :id "w1" :name "home" :active? true}])})
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
  (local node (ScenePanelsNode {:world-id "test-world"}))
  (assert node.emit-items "ScenePanelsNode should have emit-items method")
  (local items (node:emit-items))
  (assert (= (type items) :table) "emit-items should return a table")
  (node:drop))

(fn test-hud-panels-node-has-emit-items []
  (local {:HudPanelsNode HudPanelsNode} (require :graph/nodes/hud-panels))
  (local node (HudPanelsNode {:world-id "test-world"}))
  (assert node.emit-items "HudPanelsNode should have emit-items method")
  (local items (node:emit-items))
  (assert (= (type items) :table) "emit-items should return a table")
  (node:drop))

(fn test-terrains-node-has-emit-items []
  (local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
  (local node (TerrainsNode {:world-id "test-world"}))
  (assert node.emit-items "TerrainsNode should have emit-items method")
  (local items (node:emit-items))
  (assert (= (type items) :table) "emit-items should return a table")
  (node:drop))

(fn test-world-node-has-actions []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (local mock-manager {:changed (Signal) :list-tabs (fn [] []) :active-world (fn [] nil)})
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
  (local node (ScenePanelNode {:world-id "test-world" :panel-index 1}))
  (assert node.actions "ScenePanelNode should have actions")
  (assert (= (length node.actions) 1) "ScenePanelNode should have one action")
  (local action (. node.actions 1))
  (assert (= action.name "Remove") "action should be Remove")
  (node:drop))

(fn test-hud-panel-node-has-remove-action []
  (local {:HudPanelNode HudPanelNode} (require :graph/nodes/hud-panel))
  (local node (HudPanelNode {:world-id "test-world" :layer "float" :panel-index 1}))
  (assert node.actions "HudPanelNode should have actions")
  (assert (= (length node.actions) 1) "HudPanelNode should have one action")
  (local action (. node.actions 1))
  (assert (= action.name "Remove") "action should be Remove")
  (node:drop))

(fn test-terrain-node-has-no-actions []
  (local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
  (local node (TerrainNode {:world-id "test-world" :terrain-id "t1"}))
  (assert node.actions "TerrainNode should have actions")
  (assert (= (length node.actions) 0) "TerrainNode should have no actions (read-only)")
  (node:drop))

(fn test-worlds-node-has-create-world []
  (local {:WorldsNode WorldsNode} (require :graph/nodes/worlds))
  (var created nil)
  (local mock-manager {:changed (Signal)
                       :list-tabs (fn [] [])
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
  (local mock-manager {:changed (Signal)
                       :list-tabs (fn []
                                    [{:index 1 :id "other-world" :name "other" :active? false}
                                     {:index 2 :id "target-world" :name "target" :active? false}])
                       :activate-index (fn [self idx] (set activated-idx idx))
                       :active-world (fn [self] nil)})
  (local node (WorldNode {:world-id "target-world" :world-manager mock-manager}))
  (node:activate)
  (assert (= activated-idx 2) "activate should find correct index")
  (node:drop))

(fn test-world-node-close-finds-index []
  (local {:WorldNode WorldNode} (require :graph/nodes/world))
  (var closed-idx nil)
  (local mock-manager {:changed (Signal)
                       :list-tabs (fn []
                                    [{:index 1 :id "other-world" :name "other" :active? false}
                                     {:index 2 :id "target-world" :name "target" :active? false}])
                       :close-world-index (fn [self idx] (set closed-idx idx))
                       :active-world (fn [self] nil)})
  (local node (WorldNode {:world-id "target-world" :world-manager mock-manager}))
  (node:close)
  (assert (= closed-idx 2) "close should find correct index")
  (node:drop))

(fn test-graph-key-loaders-loads-scene-panels-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (GraphKeyLoaders.register graph {})
      (local result (graph:load-by-key "scene-panels:test-world"))
      (assert result "scene-panels loader should create node")
      (assert (= result.key "scene-panels:test-world") "scene-panels key should match")
      (result:drop)
      (graph:drop))))

(fn test-graph-key-loaders-loads-hud-panels-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (GraphKeyLoaders.register graph {})
      (local result (graph:load-by-key "hud-panels:test-world"))
      (assert result "hud-panels loader should create node")
      (assert (= result.key "hud-panels:test-world") "hud-panels key should match")
      (result:drop)
      (graph:drop))))

(fn test-graph-key-loaders-loads-terrains-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (GraphKeyLoaders.register graph {})
      (local result (graph:load-by-key "terrains:test-world"))
      (assert result "terrains loader should create node")
      (assert (= result.key "terrains:test-world") "terrains key should match")
      (result:drop)
      (graph:drop))))

(fn test-graph-key-loaders-loads-scene-panel-node []
  (with-temp-dir
    (fn [dir]
      (local graph (Graph {:with-start false}))
      (GraphKeyLoaders.register graph {})
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
      (GraphKeyLoaders.register graph {})
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
      (GraphKeyLoaders.register graph {})
      (local result (graph:load-by-key "terrain:test-world:terrain-abc"))
      (assert result "terrain loader should create node")
      (assert (= result.key "terrain:test-world:terrain-abc") "terrain key should match")
      (assert (= result.terrain-id "terrain-abc") "terrain-id should be parsed")
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
(table.insert tests {:name "worlds node requires world-manager" :fn test-worlds-node-requires-world-manager})
(table.insert tests {:name "world node requires world-id" :fn test-world-node-requires-world-id})
(table.insert tests {:name "scene panels node requires world-id" :fn test-scene-panels-node-requires-world-id})
(table.insert tests {:name "hud panels node requires world-id" :fn test-hud-panels-node-requires-world-id})
(table.insert tests {:name "terrains node requires world-id" :fn test-terrains-node-requires-world-id})
(table.insert tests {:name "scene panel node requires world-id" :fn test-scene-panel-node-requires-world-id})
(table.insert tests {:name "hud panel node requires world-id" :fn test-hud-panel-node-requires-world-id})
(table.insert tests {:name "terrain node requires world-id" :fn test-terrain-node-requires-world-id})
(table.insert tests {:name "worlds node has correct key" :fn test-worlds-node-has-correct-key})
(table.insert tests {:name "world node has correct key" :fn test-world-node-has-correct-key})
(table.insert tests {:name "scene panels node has correct key" :fn test-scene-panels-node-has-correct-key})
(table.insert tests {:name "hud panels node has correct key" :fn test-hud-panels-node-has-correct-key})
(table.insert tests {:name "terrains node has correct key" :fn test-terrains-node-has-correct-key})
(table.insert tests {:name "scene panel node has correct key" :fn test-scene-panel-node-has-correct-key})
(table.insert tests {:name "hud panel node has correct key" :fn test-hud-panel-node-has-correct-key})
(table.insert tests {:name "terrain node has correct key" :fn test-terrain-node-has-correct-key})
(table.insert tests {:name "world node has emit categories" :fn test-world-node-has-emit-categories})
(table.insert tests {:name "world node add category node" :fn test-world-node-add-category-node})
(table.insert tests {:name "worlds node has emit items" :fn test-worlds-node-has-emit-items})
(table.insert tests {:name "scene panels node has emit items" :fn test-scene-panels-node-has-emit-items})
(table.insert tests {:name "hud panels node has emit items" :fn test-hud-panels-node-has-emit-items})
(table.insert tests {:name "terrains node has emit items" :fn test-terrains-node-has-emit-items})
(table.insert tests {:name "world node has actions" :fn test-world-node-has-actions})
(table.insert tests {:name "scene panel node has remove action" :fn test-scene-panel-node-has-remove-action})
(table.insert tests {:name "hud panel node has remove action" :fn test-hud-panel-node-has-remove-action})
(table.insert tests {:name "terrain node has no actions" :fn test-terrain-node-has-no-actions})
(table.insert tests {:name "worlds node has create world" :fn test-worlds-node-has-create-world})
(table.insert tests {:name "world node activate finds index" :fn test-world-node-activate-finds-index})
(table.insert tests {:name "world node close finds index" :fn test-world-node-close-finds-index})
(table.insert tests {:name "graph key loaders loads scene panels node" :fn test-graph-key-loaders-loads-scene-panels-node})
(table.insert tests {:name "graph key loaders loads hud panels node" :fn test-graph-key-loaders-loads-hud-panels-node})
(table.insert tests {:name "graph key loaders loads terrains node" :fn test-graph-key-loaders-loads-terrains-node})
(table.insert tests {:name "graph key loaders loads scene panel node" :fn test-graph-key-loaders-loads-scene-panel-node})
(table.insert tests {:name "graph key loaders loads hud panel node" :fn test-graph-key-loaders-loads-hud-panel-node})
(table.insert tests {:name "graph key loaders loads terrain node" :fn test-graph-key-loaders-loads-terrain-node})

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

(table.insert tests {:name "world node view builds" :fn test-world-node-view-builds})
(table.insert tests {:name "world node view set categories" :fn test-world-node-view-set-categories})
(table.insert tests {:name "world node view refresh categories" :fn test-world-node-view-refresh-categories})
(table.insert tests {:name "world node view search submitted" :fn test-world-node-view-search-submitted})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "world-nodes"
                       :tests tests})))

{:name "world-nodes"
 :tests tests
 :main main}
