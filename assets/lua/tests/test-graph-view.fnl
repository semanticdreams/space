(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphView (require :graph/view))
(local BuildContext (require :build-context))
(local ObjectSelector (require :object-selector))
(local GraphViewLayout (require :graph/view/layout))
(local GraphViewPersistence (require :graph/view/persistence))
(local {:FsNode FsNode} (require :graph/nodes/fs))
(local LlmConversationNode (require :graph/nodes/llm-conversation))
(local LlmConversationsNode (require :graph/nodes/llm-conversations))
(local LlmMessageNode (require :graph/nodes/llm-message))
(local LlmNode (require :graph/nodes/llm))
(local {:TableNode TableNode} (require :graph/nodes/table))
(local Movables (require :movables))
(local Intersectables (require :intersectables))
(local {:FocusManager FocusManager} (require :focus))
(local Signal (require :signal))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local fs (require :fs))

(local tests [])
(local appdirs (require :appdirs))
(local MathUtils (require :math-utils))
(local TextUtils (require :text-utils))

(local {:ForceLayout ForceLayout :ForceLayoutSignal ForceLayoutSignal} (require :force-layout))
(fn assert-codepoints-eq [actual expected message]
    (assert (= (# actual) (# expected))
            (or message "codepoints length mismatch"))
    (for [i 1 (# expected)]
        (assert (= (. actual i) (. expected i))
                (or message "codepoints mismatch"))))

(fn make-icons-stub []
    (local glyph {:advance 1})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {65533 glyph
                             4242 glyph}})
    (local stub {:font font
                 :codepoints {:refresh 4242
                              :close 4242
                              :cancel 4242
                              :move_item 4242
                              :select 4242
                              :arrow_drop_down 4242
                              :terminal 4242
                              :settings 4242
                              :contrast 4242
                              :wallet 4242
                              :volume_mute 4242
                              :volume_down 4242
                              :volume_up 4242
                              :volume_off 4242}})
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

(local default-icons (make-icons-stub))

(fn make-ctx [opts]
    (local options (or opts {}))
    (local focus-manager (FocusManager {:root-name "test-graph"}))
    (local focus-scope (focus-manager:create-scope {:name "test-graph-view"}))
    (local theme {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
                          :label-color (glm.vec4 1 1 1 1)
                          :edge-color (glm.vec4 0.6 0.6 0.6 1)}
                  :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}})
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (assert app.hoverables "test requires app.hoverables")
                              :theme theme
                              :focus-manager focus-manager
                              :focus-scope focus-scope}))
    (set ctx.icons (or options.icons default-icons))
    ctx)

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "graph-fs-node-tmp"))

(fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "fs-node-" (os.time) "-" temp-counter)))

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

(fn with-data-dir [dir f]
    (assert appdirs "appdirs module must be available")
    (local original appdirs.user-data-dir)
    (set appdirs.user-data-dir (fn [_appname] (fs.absolute dir)))
    (local (ok result) (pcall f))
    (set appdirs.user-data-dir original)
    (if ok
        result
        (error result)))

(fn with-temp-data-dir [f]
    (with-temp-dir
        (fn [root]
            (with-data-dir root
                (fn [] (f root))))))

(fn edge-produces-triangles []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph :ctx ctx}))
            (local a (Graph.GraphNode {:key "a" :color (glm.vec4 0.2 0.6 1.0 1)}))
            (local b (Graph.GraphNode {:key "b" :color (glm.vec4 1 0.4 0.2 1)}))
            (graph:add-node a {:position (glm.vec3 0 0 0)})
            (graph:add-node b {:position (glm.vec3 50 0 0)})
            (graph:add-edge (Graph.GraphEdge {:source a :target b}))
            (view:update 0.016)
            (assert (= (graph:node-count) 2))
            (assert (= (graph:edge-count) 1))
            (assert (= (ctx.triangle-vector:length) (* 3 8))
                    "Triangle edge should emit exactly one wedge (3 vertices)")
            (view:drop)
            (graph:drop))))

(fn start-node-view-adds-quit-node []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {}))
            (local start graph.start)
            (local builder (start.view start))
            (local view (builder ctx))
            (view:refresh-items)
            (var quit-node nil)
            (each [_ pair (ipairs view.search.items)]
                (when (= (. pair 2) "quit")
                    (set quit-node (. pair 1))))
            (assert quit-node "Start view should list quit node")
            (view:add-edge quit-node)
            (assert (graph:lookup "quit"))
            (assert (= (graph:edge-count) 1))
            (view:drop)
            (graph:drop))))

(fn start-node-view-adds-fs-node []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {}))
            (local start graph.start)
            (local builder (start.view start))
            (local view (builder ctx))
            (view:refresh-items)
            (local cwd (fs.cwd))
            (local expected-key (.. "fs:" cwd))
            (var fs-node nil)
            (each [_ pair (ipairs view.search.items)]
                (local candidate (. pair 1))
                (when (and candidate (= candidate.key expected-key))
                    (set fs-node candidate)))
            (assert fs-node "Start view should list fs node")
            (view:add-edge fs-node)
            (assert (graph:lookup expected-key))
            (assert (= (graph:edge-count) 1))
            (view:drop)
            (graph:drop))))

(fn start-node-view-adds-table-node []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {}))
            (local start graph.start)
            (local builder (start.view start))
            (local view (builder ctx))
            (view:refresh-items)
            (var table-node nil)
            (each [_ pair (ipairs view.search.items)]
                (local candidate (. pair 1))
                (when (and candidate (= candidate.key "table:_G"))
                    (set table-node candidate)))
            (assert table-node "Start view should list table node for _G")
            (view:add-edge table-node)
            (assert (graph:lookup "table:_G"))
            (assert (= (graph:edge-count) 1))
            (view:drop)
            (graph:drop))))

(fn nodes-default-to-center-position []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph :ctx ctx}))
            (local center (glm.vec3 15 25 0))
            (view.layout:set-center-position center)
            (local node (Graph.GraphNode {:key "centered"}))
            (graph:add-node node {})
            (local pos (view:get-position node))
            (assert pos "GraphView should expose node position after add-node")
            (local dx (- pos.x center.x))
            (local dy (- pos.y center.y))
            (assert (and (>= dx 0) (<= dx 100))
                    (string.format "Default X offset should be in [0, 100] (got %.3f)" dx))
            (assert (and (>= dy 0) (<= dy 100))
                    (string.format "Default Y offset should be in [0, 100] (got %.3f)" dy))
            (assert (= pos.z center.z))
            (view:drop)
            (graph:drop))))

(fn fs-node-view-adds-child-nodes-for-entries []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local ctx (make-ctx))
                    (local graph (Graph {:with-start false}))
                    (local child-dir (fs.join-path root "child"))
                    (local file (fs.join-path root "note.txt"))
                    (fs.create-dirs child-dir)
                    (fs.write-file file "hello")
                    (local node (FsNode {:path root}))
                    (graph:add-node node {:position (glm.vec3 0 0 0)})
                    (local builder (node.view node))
                    (local view (builder ctx))
                    (view:refresh-items)
                    (var dir-entry nil)
                    (var file-entry nil)
                    (each [_ item (ipairs view.search.items)]
                        (local entry (. item 1))
                        (when (= entry.path child-dir)
                            (set dir-entry entry))
                        (when (= entry.path file)
                            (set file-entry entry)))
                    (assert dir-entry "Fs node view should list directories")
                    (assert file-entry "Fs node view should list files")
                    (view:open-entry dir-entry)
                    (assert (= (graph:edge-count) 1)
                            (string.format "Fs node should create one edge after opening dir (got %s)"
                                           (graph:edge-count)))
                    (view:open-entry file-entry)
                    (local resolved-dir (node:resolve-path child-dir))
                    (local resolved-file (node:resolve-path file))
                    (assert (graph:lookup (.. "fs:" resolved-dir))
                            "Dir node should be added to graph")
                    (assert (graph:lookup (.. "fs:" resolved-file))
                            "File node should be added to graph")
                    (local edge-count (graph:edge-count))
                    (assert (= edge-count 2)
                            (string.format "Fs node edges should match spawned children (got %s)"
                                           edge-count))
                    (view:drop)
                    (graph:drop))))))

(fn table-node-view-adds-child-nodes []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local target {:one 1 :nested {:two 2}})
            (local node (TableNode {:table target
                                    :label "root"
                                    :key "table:root"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local builder (node.view node))
            (local view (builder ctx))
            (view:refresh-items)
            (var nested-entry nil)
            (var value-entry nil)
            (each [_ pair (ipairs view.search.items)]
                (local entry (. pair 1))
                (when (= entry.key :nested)
                    (set nested-entry entry))
                (when (= entry.key :one)
                    (set value-entry entry)))
            (assert nested-entry "Table view should include nested table entry")
            (assert value-entry "Table view should include value entry")
            (view:open-entry nested-entry)
            (view:open-entry value-entry)
            (local nested-key (node:child-key nested-entry))
            (local value-key (node:child-key value-entry))
            (assert (graph:lookup nested-key) "Nested table node should be added")
            (assert (graph:lookup value-key) "Value node should be added")
            (local edge-count (graph:edge-count))
            (assert (= edge-count 2)
                    (string.format "Table node edges should match spawned entries (got %s)"
                                   edge-count))
            (view:drop)
            (graph:drop))))

(fn graph-removes-selected-nodes-and-edges []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph
                                    :ctx ctx
                                    :selector selector}))
            (local a (Graph.GraphNode {:key "a"}))
            (local b (Graph.GraphNode {:key "b"}))
            (local c (Graph.GraphNode {:key "c"}))
            (graph:add-node a {:position (glm.vec3 0 0 0)})
            (graph:add-node b {:position (glm.vec3 10 0 0)})
            (graph:add-node c {:position (glm.vec3 20 0 0)})
            (graph:add-edge (Graph.GraphEdge {:source a :target b}))
            (graph:add-edge (Graph.GraphEdge {:source b :target c}))
            (selector:set-selected [(. view.points b)])
            (local removed (view:remove-selected-nodes))
            (assert (= removed 1) "GraphView should report the number of removed nodes")
            (assert (not (graph:lookup "b")) "Removed node should be cleared from lookup")
            (assert (= (graph:edge-count) 0) "Edges connected to removed nodes should be dropped")
            (local remaining-points (icollect [_ point (pairs view.points)] point))
            (assert (= (length remaining-points) 2)
                    (string.format "GraphView should retain two point records (got %s)"
                                   (length remaining-points)))
            (assert (= (length selector.selectables) 2)
                    (string.format "Selector should retain only remaining points (got %s)"
                                   (length selector.selectables)))
            (assert (= (length view.selected-nodes) 0) "Graph selection should clear after removal")
            (view:drop)
            (graph:drop)
            (selector:drop))))

(fn quit-node-view-invokes-handler []
    (local ctx (make-ctx))
    (local original-quit app.engine.quit)
    (var quit-calls 0)
    (set app.engine.quit (fn [] (set quit-calls (+ quit-calls 1))))
    (local quit-node (Graph.QuitNode {}))
    (local builder (quit-node.view quit-node))
    (local view (builder ctx))
    (view:perform-quit)
    (assert (= quit-calls 1) "Quit view should call app.engine.quit")
    (view:drop)
    (set app.engine.quit original-quit))

(fn llm-conversation-view-adds-message-node []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local conversation (LlmConversationNode {}))
            (graph:add-node conversation {:position (glm.vec3 0 0 0)})
            (local builder (conversation.view conversation))
            (local view (builder ctx))
            (local message (view:add-message))
            (assert message "LlmConversationView should create a message node")
            (assert message.llm-id "Llm conversation should assign an llm id")
            (local expected-key (.. "llm-message:" message.llm-id))
            (assert (= message.key expected-key)
                    "Llm conversation should key messages by llm id")
            (assert (graph:lookup message.key)
                    "Graph should register message node created from conversation")
            (assert (= (graph:edge-count) 1)
                    "Conversation should add an edge for new message")
            (view:drop)
            (graph:drop))))

(fn llm-message-view-updates-node-fields []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local node (LlmMessageNode {:key "llm-message:test"
                                         :role "assistant"
                                         :content "Hello"
                                         :tool-name "picker"
                                         :tool-call-id "call-1"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local builder (node.view node))
            (local view (builder ctx))
            (local inputs view.inputs)
            (assert inputs "LlmMessageView should expose inputs")
            (local tool-name-input (. inputs :tool-name))
            (local tool-call-input (. inputs :tool-call-id))
            (assert (= (inputs.role:get-value) "assistant"))
            (assert (= (inputs.content:get-text) "Hello"))
            (assert (= (tool-name-input:get-text) "picker"))
            (assert (= (tool-call-input:get-text) "call-1"))
            (inputs.role:set-value "user")
            (inputs.content:set-text "Updated")
            (tool-name-input:set-text "search")
            (tool-call-input:set-text "call-2")
            (assert (= node.role "user"))
            (assert (= node.content "Updated"))
            (assert (= (. node :tool-name) "search"))
            (assert (= (. node :tool-call-id) "call-2"))
            (view:drop)
            (graph:drop))))

(fn llm-node-view-adds-conversations []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local node (LlmNode))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local builder (node.view node))
            (local view (builder ctx))
            (view:refresh-items)
            (var conversations-node nil)
            (each [_ pair (ipairs view.search.items)]
                (when (= (. pair 2) "llm conversations")
                    (set conversations-node (. pair 1))))
            (assert conversations-node "Llm node view should list conversations")
            (view:add-edge conversations-node)
            (assert (graph:lookup "llm-conversations"))
            (assert (= (graph:edge-count) 1))
            (view:drop)
            (graph:drop))))

(fn llm-conversations-view-builds []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local node (LlmConversationsNode {}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local builder (node.view node))
            (local view (builder ctx))
            (assert view "LlmConversationsView should build")
            (view:drop)
            (graph:drop))))

(fn graph-opens-node-view-in-hud-on-double-click []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local original-hud app.hud)
            (when (not original-hud)
                (local Hud (require :hud))
                (set app.hud (Hud {:scene app.scene
                                   :icons default-icons}))
                (when app.hud
                    (app.hud:build-default)))
            (local hud app.hud)
            (assert hud "Graph node view test requires app.hud")
            (local graph (Graph {}))
            (local view-controller (GraphView {:graph graph
                                               :ctx ctx
                                               :selector selector
                                               :view-target hud}))
            (local tiles hud.tiles)
            (assert tiles "HUD tiles should exist for node views")
            (local initial-count (length tiles.children))
            (local start graph.start)
            (local point (. view-controller.points start))
            (assert point.on-double-click "GraphView should attach double click handler to node point")
            (point:on-double-click {})
            (local after-count (length tiles.children))
            (assert (> after-count initial-count)
                    "Double-clicking node should add its view to HUD tiles")
            (view-controller.views:drop-node start)
            (assert (= (length tiles.children) initial-count)
                    "Closing node view should remove node view dialog from HUD")
            (view-controller:drop)
            (graph:drop)
            (selector:drop)
            (when (and (not original-hud) app.hud)
                (app.hud:drop)
                (set app.hud nil)))))

(fn graph-selection-emits-changed []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph
                                    :ctx ctx
                                    :selector selector}))
            (local node (Graph.GraphNode {:key "n"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local point (. view.points node))
            (var changes 0)
            (local handler (view.selected-nodes-changed:connect (fn [_]
                                                                    (set changes (+ changes 1)))))
            (selector:set-selected [point])
            (assert (= (length view.selected-nodes) 1)
                    "GraphView should mirror selector selection")
            (assert (= changes 1)
                    "Selection change should emit through selected-nodes-changed")
            (selector:set-selected [])
            (view.selected-nodes-changed:disconnect handler true)
            (view:drop)
            (graph:drop)
            (selector:drop))))

(fn graph-view-rebuilds-from-double-click []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local target {:children []
                           :add-panel-child (fn [self opts]
                                              (table.insert self.children opts)
                                              opts)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))})
            (local graph (Graph {:with-start false}))
            (local view-controller (GraphView {:graph graph
                                               :view-target target
                                               :ctx ctx
                                               :selector selector}))
            (local node (Graph.GraphNode {:key "n"
                                          :view (fn [_node]
                                                    (fn [_ctx]
                                                        {:layout {:position (glm.vec3 0 0 0)
                                                                  :size (glm.vec2 0 0)
                                                                  :rotation (glm.quat 1 0 0 0)}}))}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local point (. view-controller.points node))
            (assert point.on-double-click "GraphView should attach double click handler to node point")
            (point:on-double-click {})
            (assert (= (length target.children) 1)
                    "View controller should build a node view from double click")
            (view-controller:drop)
            (assert (= (length target.children) 0)
                    "Dropping the view controller should remove views")
            (local view-controller-2 (GraphView {:graph graph
                                                 :view-target target
                                                 :ctx ctx
                                                 :selector selector}))
            (local point-2 (. view-controller-2.points node))
            (assert point-2.on-double-click "GraphView should attach double click handler on rebuild")
            (point-2:on-double-click {})
            (assert (= (length target.children) 1)
                    "Recreating view controller should build views for double click")
            (view-controller-2:drop)
            (graph:drop)
            (selector:drop))))

(fn graph-layout-module-updates-lines-and-labels []
    (with-temp-data-dir
        (fn [_root]
            (local a (Graph.GraphNode {:key "a"}))
            (local b (Graph.GraphNode {:key "b"}))
            (local point-a {:position (glm.vec3 0 0 0)})
            (local point-b {:position (glm.vec3 10 0 0)})
            (local points {})
            (set (. points a) point-a)
            (set (. points b) point-b)
            (local nodes {})
            (set (. nodes a.key) a)
            (set (. nodes b.key) b)
            (local layout (ForceLayout))
            (local nodes-by-index [])
            (local indices {})
            (local edges [])
            (local edge-map {})
            (var line-updates 0)
            (var last-line nil)
            (local make-line
                  (fn [_ctx _opts]
                      {:update (fn [_self start end]
                                    (set line-updates (+ line-updates 1))
                                    (set last-line {:start start :end end}))}))
            (var set-point-calls 0)
            (local set-point-position
                  (fn [node pos]
                      (set set-point-calls (+ set-point-calls 1))
                      (local point (. points node))
                      (assert point "GraphViewLayout test missing point")
                      (set point.position pos)))
            (var label-updates 0)
            (var label-refreshes 0)
            (local layout-module
                  (GraphViewLayout {:layout layout
                                          :nodes-by-index nodes-by-index
                                          :indices indices
                                          :nodes nodes
                                          :points points
                                          :edges edges
                                          :edge-map edge-map
                                          :make-line make-line
                                          :set-point-position set-point-position
                                          :update-labels (fn [_nodes _opts]
                                                             (set label-updates (+ label-updates 1)))
                                          :refresh-label-positions (fn [_nodes]
                                                                        (set label-refreshes (+ label-refreshes 1)))
                                          :get-position (fn [_self node]
                                                            (local point (. points node))
                                                            (and point point.position))}))
            (layout-module:add-node a (glm.vec3 0 0 0) false)
            (layout-module:add-node b (glm.vec3 10 0 0) false)
            (layout-module:add-edge (Graph.GraphEdge {:source a :target b}))
            (assert (= line-updates 1)
                    "GraphViewLayout should update lines after adding edge")
            (layout-module:set-node-position a (glm.vec3 5 0 0))
            (assert (= set-point-calls 1)
                    "GraphViewLayout should set point position when moving node")
            (assert (= line-updates 2)
                    "GraphViewLayout should update lines after moving node")
            (assert (= label-updates 1)
                    "GraphViewLayout should refresh labels when moving node")
            (assert (= label-refreshes 1)
                    "GraphViewLayout should refresh label positions when moving node")
            (assert last-line "GraphViewLayout should capture line updates")
            (assert (= (. last-line.start.x) 5)
                    "Line start should reflect moved node position")
            (layout:clear))))

(local approx (. MathUtils :approx))

(fn graph-view-updates-selection-and-focus-borders []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph :ctx ctx}))
            (local node (Graph.GraphNode {:key "border-node" :size 8}))
            (graph:add-node node {:position (glm.vec3 0 0 0) :run-force? false})
            (local point (. view.points node))
            (assert point "GraphView should create a point for node")
            (local focus-layer (. point.layers 1))
            (local selection-layer (. point.layers 2))
            (local base-layer (. point.layers 3))
            (assert (approx focus-layer.size 0) "Focus border should start hidden")
            (assert (approx selection-layer.size 0) "Selection border should start hidden")
            (view.selection:set-selection [node])
            (assert (> selection-layer.size base-layer.size)
                    "Selection border should be larger than the base point")
            (local focus-node (. view.focus-nodes node))
            (assert focus-node "GraphView should create a focus node for each point")
            (focus-node:request-focus)
            (assert (> focus-layer.size selection-layer.size)
                    "Focus border should be outside selection border when both are active")
            (view:drop)
            (graph:drop))))

(fn graph-view-autofocus-updates-focus-ring []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local focus-manager (. ctx.focus :manager))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph :ctx ctx}))
            (local node (Graph.GraphNode {:key "auto-focus-node" :size 6}))
            (focus-manager:arm-auto-focus {:event {:mod 0}})
            (graph:add-node node {:position (glm.vec3 0 0 0) :run-force? false})
            (local point (. view.points node))
            (assert point "GraphView should create a point for auto-focused node")
            (local focus-layer (. point.layers 1))
            (assert (> focus-layer.size 0) "Auto-focused node should show focus ring")
            (local focus-node (. view.focus-nodes node))
            (assert focus-node "GraphView should create a focus node for auto-focused node")
            (assert (= (focus-manager:get-focused-node) focus-node)
                    "Auto-focused node should be the focused node")
            (view:drop)
            (graph:drop))))

(fn graph-movables-module-registers-and-cleans-up []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local registered [])
            (local unregistered [])
            (var scheduled 0)
            (local persistence {:saved-position (fn [_self _node] nil)
                                :persist (fn [_self _points _force?] nil)
                                :schedule-save (fn [_self]
                                                    (set scheduled (+ scheduled 1)))})
            (local movables {:register (fn [_self point opts]
                                          (table.insert registered {:point point :opts opts}))
                             :unregister (fn [_self node]
                                             (table.insert unregistered node))})
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph
                                    :ctx ctx
                                    :movables movables
                                    :persistence persistence}))
            (local node (Graph.GraphNode {:key "movable"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (assert (= (length registered) 1)
                    "GraphView should register nodes with GraphViewMovables")
            (local opts (. (. registered 1) :opts))
            (assert opts "Movables registration should include options")
            (local on-drag-end (and opts opts.on-drag-end))
            (assert on-drag-end "Movables registration should include drag end handler")
            (on-drag-end {})
            (assert (= scheduled 1) "Drag end should schedule persistence save")
            (graph:remove-nodes [node])
            (assert (= (length unregistered) 1)
                    "GraphView should unregister movables when removing nodes")
            (assert (not (. view.movable-targets node))
                    "GraphView should clear movable targets after removal")
            (view:drop)
            (graph:drop))))

(fn graph-nodes-are-movable []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local intersector (Intersectables))
            (local movables (Movables {:intersectables intersector}))
            (local original-movables app.movables)
            (local original-ray app.screen-pos-ray)
            (local original-camera app.camera)
            (set app.movables movables)
            (set app.screen-pos-ray
                 (fn [pointer]
                     {:origin (glm.vec3 (or (and pointer pointer.x) 0) 0 10)
                      :direction (glm.vec3 0 0 -1)}))
            (set app.camera nil)
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph
                                    :ctx ctx
                                    :movables movables}))
            (local node (Graph.GraphNode {:key "drag"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (movables:on-mouse-button-down {:button 1 :x 0 :y 0})
            (movables:on-mouse-motion {:x 20 :y 0})
            (assert (movables:drag-active?) "Drag should start when clicking a graph node")
            (movables:on-mouse-button-up {:button 1 :x 20 :y 0})
            (local position (view:get-position node))
            (assert position "GraphView should expose node position after drag")
            (assert (> position.x 1.5) "Graph node should follow drag ray")
            (local idx (. view.indices node))
            (local positions (view.layout:get-positions))
            (when (and positions idx)
                (local layout-pos (. positions (+ idx 1)))
                (assert layout-pos "Force layout should store node position")
                (assert (approx layout-pos.x position.x)
                        "Force layout position should match dragged position"))
            (view:drop)
            (graph:drop)
            (movables:drop)
            (set app.movables original-movables)
            (set app.screen-pos-ray original-ray)
            (set app.camera original-camera))))

(fn graph-drag-respects-force-layout-position []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local intersector (Intersectables))
            (local movables (Movables {:intersectables intersector}))
            (local original-movables app.movables)
            (local original-ray app.screen-pos-ray)
            (set app.movables movables)
            (set app.screen-pos-ray
                 (fn [pointer]
                     {:origin (glm.vec3 (or (and pointer pointer.x) 0)
                                    (or (and pointer pointer.y) 0)
                                    10)
                      :direction (glm.vec3 0 0 -1)}))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph
                                    :ctx ctx
                                    :movables movables}))
            (local a (Graph.GraphNode {:key "a"}))
            (local b (Graph.GraphNode {:key "b"}))
            (view.layout:set-bounds (glm.vec3 -200 -200 0) (glm.vec3 200 200 0))
            (graph:add-node a {:position (glm.vec3 -120 0 0)})
            (graph:add-node b {:position (glm.vec3 120 0 0)})
            (graph:add-edge (Graph.GraphEdge {:source a :target b}))
            (view:update 40)
            (local before (view:get-position a))
            (assert before "GraphView should expose node position after layout update")
            (movables:on-mouse-button-down {:button 1 :x before.x :y before.y})
            (movables:on-mouse-motion {:x (+ before.x 20) :y before.y})
            (movables:on-mouse-button-up {:button 1 :x (+ before.x 20) :y before.y})
            (local after (view:get-position a))
            (assert after "GraphView should expose node position after drag")
            (assert (> after.x before.x) "Drag should move node forward from its current layout position")
            (movables:drop)
            (view:drop)
            (graph:drop)
            (set app.movables original-movables)
            (set app.screen-pos-ray original-ray))))

(fn graph-persistence-class-saves-and-restores []
    (with-temp-data-dir
        (fn [root]
            (local persistence (GraphViewPersistence {:data-dir root}))
            (local node {:key "persist-me"})
            (local point {:position (glm.vec3 5 6 7)})
            (persistence:schedule-save)
            (persistence:persist {node point} false)
            (local reloaded (GraphViewPersistence {:data-dir root}))
            (local restored (reloaded:saved-position node))
            (assert restored "GraphViewPersistence should restore saved position")
            (assert (= restored.x 5))
            (assert (= restored.y 6))
            (assert (= restored.z 7))
            (set point.position (glm.vec3 8 9 10))
            (persistence:persist {node point} false)
            (local stale (GraphViewPersistence {:data-dir root}))
            (local stale-pos (stale:saved-position node))
            (assert (= stale-pos.x 5) "Persist should wait for schedule or force")
            (persistence:persist {node point} true)
            (local updated (GraphViewPersistence {:data-dir root}))
            (local updated-pos (updated:saved-position node))
            (assert (= updated-pos.x 8))
            (assert (= updated-pos.y 9))
            (assert (= updated-pos.z 10)))))


(fn graph-restores-saved-node-position []
    (with-temp-data-dir
        (fn [root]
            (local graph-dir (fs.join-path root "graph-view"))
            (fs.create-dirs graph-dir)
            (local metadata-path (fs.join-path graph-dir "metadata.json"))
            (JsonUtils.write-json! metadata-path {:positions {:persisted [12 34 0]}})
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph :ctx ctx}))
            (local node (Graph.GraphNode {:key "persisted"}))
            (graph:add-node node {})
            (local pos (view:get-position node))
            (assert pos "GraphView should expose restored node position")
            (assert (= pos.x 12))
            (assert (= pos.y 34))
            (assert (= pos.z 0))
            (view:drop)
            (graph:drop))))

(fn graph-saves-positions-after-stabilizing []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph :ctx ctx}))
            (local a (Graph.GraphNode {:key "a"}))
            (local b (Graph.GraphNode {:key "b"}))
            (graph:add-node a {:position (glm.vec3 -60 0 0)})
            (graph:add-node b {:position (glm.vec3 60 0 0)})
            (graph:add-edge (Graph.GraphEdge {:source a :target b}))
            (local graph-dir (fs.join-path (appdirs.user-data-dir "space") "graph-view"))
            (local metadata-path (fs.join-path graph-dir "metadata.json"))
            (for [i 1 200]
                (view:update 0.016))
            (assert (fs.exists metadata-path)
                    "GraphView should persist positions after stabilizing force layout")
            (local saved (json.loads (fs.read-file metadata-path)))
            (assert (and saved saved.positions)
                    "Graph metadata should include positions table")
            (assert (. saved.positions "a")
                    "GraphView should save positions keyed by node key")
            (view:drop)
            (graph:drop))))

(fn graph-keeps-saved-positions-when-rebuilt []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph :ctx ctx}))
            (local node (Graph.GraphNode {:key "sticky"}))
            (graph:add-node node {:position (glm.vec3 7 9 0)})
            (view:drop)
            (graph:drop)
            (local graph2 (Graph {:with-start false}))
            (local view2 (GraphView {:graph graph2 :ctx (make-ctx)}))
            (local node2 (Graph.GraphNode {:key "sticky"}))
            (graph2:add-node node2 {})
            (local pos (view2:get-position node2))
            (assert pos "GraphView should restore position for rebuilt node")
            (assert (= pos.x 7))
            (assert (= pos.y 9))
            (assert (= pos.z 0))
            (view2:drop)
            (graph2:drop))))

(fn graph-view-updates-node-labels-without-lod-change []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local camera {:position (glm.vec3 0 0 0)})
            (local view (GraphView {:graph graph
                                    :ctx ctx
                                    :camera camera}))
            (local node (Graph.GraphNode {:key "label-node"
                                          :label "first"}))
            (set node.changed (Signal))
            (graph:add-node node {:position (glm.vec3 0 0 0)
                                  :run-force? false})
            (local span (. view.labels.labels node))
            (assert span "GraphView should create a label for each node")
            (assert-codepoints-eq (span:get-codepoints)
                                  (TextUtils.codepoints-from-text "first")
                                  "Initial label should reflect node label")
            (set node.label "second")
            (node.changed:emit node)
            (local span-after (. view.labels.labels node))
            (assert (= span-after span) "GraphView should reuse the existing label widget")
            (assert-codepoints-eq (span-after:get-codepoints)
                                  (TextUtils.codepoints-from-text "second")
                                  "GraphView should update labels when node label changes")
            (view:drop)
            (graph:drop))))

(table.insert tests {:name "GraphView draws triangle edge between nodes" :fn edge-produces-triangles})
(table.insert tests {:name "Start node view adds quit node edge" :fn start-node-view-adds-quit-node})
(table.insert tests {:name "Start node view adds fs node edge" :fn start-node-view-adds-fs-node})
(table.insert tests {:name "Start node view adds table node edge" :fn start-node-view-adds-table-node})
(table.insert tests {:name "GraphView seeds new nodes at layout center" :fn nodes-default-to-center-position})
(table.insert tests {:name "Quit node view invokes handler" :fn quit-node-view-invokes-handler})
(table.insert tests {:name "Llm conversation view adds message node" :fn llm-conversation-view-adds-message-node})
(table.insert tests {:name "Llm message view updates node fields" :fn llm-message-view-updates-node-fields})
(table.insert tests {:name "Llm conversations view builds" :fn llm-conversations-view-builds})
(table.insert tests {:name "Llm node view adds conversations" :fn llm-node-view-adds-conversations})
(table.insert tests {:name "Fs node view adds edges for entries" :fn fs-node-view-adds-child-nodes-for-entries})
(table.insert tests {:name "Table node view adds edges for entries" :fn table-node-view-adds-child-nodes})
(table.insert tests {:name "GraphView removes selected nodes and related edges" :fn graph-removes-selected-nodes-and-edges})
(table.insert tests {:name "GraphView opens node view in HUD on double click" :fn graph-opens-node-view-in-hud-on-double-click})
(table.insert tests {:name "GraphView emits selection changes" :fn graph-selection-emits-changed})
(table.insert tests {:name "GraphView updates selection and focus borders" :fn graph-view-updates-selection-and-focus-borders})
(table.insert tests {:name "GraphView auto-focus updates focus ring" :fn graph-view-autofocus-updates-focus-ring})
(table.insert tests {:name "Graph view rebuilds views from double click" :fn graph-view-rebuilds-from-double-click})
(table.insert tests {:name "GraphViewLayout updates lines and labels" :fn graph-layout-module-updates-lines-and-labels})
(table.insert tests {:name "Graph movables register and clean up drag targets" :fn graph-movables-module-registers-and-cleans-up})
(table.insert tests {:name "Graph nodes register with movables for dragging" :fn graph-nodes-are-movable})
(table.insert tests {:name "Graph drag respects latest force layout position" :fn graph-drag-respects-force-layout-position})
(table.insert tests {:name "GraphViewPersistence saves and restores positions" :fn graph-persistence-class-saves-and-restores})
(table.insert tests {:name "Graph restores saved node position" :fn graph-restores-saved-node-position})
(table.insert tests {:name "GraphView saves positions after force layout stabilizes" :fn graph-saves-positions-after-stabilizing})
(table.insert tests {:name "GraphView keeps saved positions when rebuilt" :fn graph-keeps-saved-positions-when-rebuilt})
(table.insert tests {:name "GraphView updates node labels without LOD change" :fn graph-view-updates-node-labels-without-lod-change})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-view"
                       :tests tests})))

{:name "graph-view"
 :tests tests
 :main main}
