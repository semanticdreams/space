(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphView (require :graph/view))
(local BuildContext (require :build-context))
(local ObjectSelector (require :object-selector))
(local GraphViewLayout (require :graph/view/layout))
(local GraphViewPersistence (require :graph/view/persistence))
(local GraphViewNodeViews (require :graph/view/node-views))
(local {:FsNode FsNode} (require :graph/nodes/fs))
(local CodeDirNode (require :graph/nodes/code-dir))
(local FnlModuleNode (require :graph/nodes/fnl-module))
(local TextModuleNode (require :graph/nodes/text-module))
(local LlmConversationNode (require :graph/nodes/llm-conversation))
(local LlmConversationsNode (require :graph/nodes/llm-conversations))
(local LlmMessageNode (require :graph/nodes/llm-message))
(local LlmNode (require :graph/nodes/llm))
(local {:TableNode TableNode} (require :graph/nodes/table))
(local Movables (require :movables))
(local Intersectables (require :intersectables))
(local {:FocusManager FocusManager} (require :focus))
(local Signal (require :signal))
(local LightSystemModule (require :light-system))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local fs (require :fs))
(local PathUtils (require :tests.path-utils))
(local TestSupport (require :tests/test-support))

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

(local paths-eq PathUtils.paths-eq)

(fn find-fs-node-by-path [graph target-path]
    (var matched nil)
    (each [_ node (pairs (or graph.nodes {}))]
        (when (and (not matched)
                   node
                   node.path
                   (paths-eq node.path target-path))
            (set matched node)))
    matched)

(fn make-icons-stub []
    (local glyph {:advance 1})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {65533 glyph
                             4242 glyph}})
    (local stub {:font font
                 :codepoints {:refresh 4242
                              :table 4242
                              :code 4242
                              :edit 4242
                              :close 4242
                              :cancel 4242
                              :move_item 4242
                              :select 4242
                              :arrow_drop_down 4242
                              :terminal 4242
                              :settings 4242
                              :contrast 4242
                              :apps 4242
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

(fn make-heightfield-terrain-record [opts]
    (local options (or opts {}))
    (local chunk-samples (or options.chunk-samples [5 5]))
    {:id (or options.id "terrain-a")
     :kind "heightfield-terrain"
     :options {:position (or options.position [0 0 0])
               :rotation (or options.rotation [1 0 0 0])
               :opacity 1.0
               :physics true
               :sample-spacing (or options.sample-spacing [1 1])
               :chunk-samples chunk-samples
               :default-height (or options.default-height 0.0)}
     :chunks (or options.chunks
                 [{:coord [0 0]
                   :size chunk-samples
                   :heights [0 0 0 0 0
                             0 0 0 0 0
                             0 0 0 0 0
                             0 0 0 0 0
                             0 0 0 0 0]}])})

(fn make-world-entry [opts]
    (local options (or opts {}))
    {:id (or options.id "world-a")
     :name (or options.name "World A")
     :world {:state (or options.state {:scene {:panels [] :terrains [] :lights (LightSystemModule.default-state)}
                                       :hud {:panels []}})
             :get-runtime (fn [_self] options.runtime)
             :save-state (fn [_self] true)}})

(fn make-world-manager [opts]
    (local options (or opts {}))
    (local entry (assert options.entry "make-world-manager requires :entry"))
    {:changed (or options.changed (Signal))
     :get-world-entry (fn [_self world-id]
                        (if (= world-id entry.id) entry nil))
     :active-world-id (fn [_self] (or options.active-world-id entry.id))
     :active-world (fn [_self] entry)})

(fn unwrap-element [item]
    (or (and item item.element) item))

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

(fn code-dir-node-view-adds-subdir-and-module-nodes []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local subdir (fs.join-path root "sub"))
                    (local fnl-file (fs.join-path root "main.fnl"))
                    (local cpp-file (fs.join-path root "main.cpp"))
                    (local txt-file (fs.join-path root "ignore.txt"))
                    (fs.create-dirs subdir)
                    (fs.write-file fnl-file "(local x 1)\n")
                    (fs.write-file cpp-file "#include \"sub/dep.h\"\n")
                    (fs.write-file txt-file "skip")
                    (local ctx (make-ctx))
                    (local graph (Graph {:with-start false}))
                    (local node (CodeDirNode {:path root :root root}))
                    (graph:add-node node {:position (glm.vec3 0 0 0)})
                    (local builder (node.view node))
                    (local view (builder ctx))
                    (view:refresh-items)
                    (var dir-entry nil)
                    (var fnl-entry nil)
                    (var cpp-entry nil)
                    (var txt-entry nil)
                    (each [_ pair (ipairs view.search.items)]
                        (local entry (. pair 1))
                        (when (paths-eq entry.path subdir)
                            (set dir-entry entry))
                        (when (paths-eq entry.path fnl-file)
                            (set fnl-entry entry))
                        (when (paths-eq entry.path cpp-file)
                            (set cpp-entry entry))
                        (when (paths-eq entry.path txt-file)
                            (set txt-entry entry)))
                    (assert dir-entry "CodeDir should include subdirectories")
                    (assert fnl-entry "CodeDir should include .fnl files")
                    (assert cpp-entry "CodeDir should include cpp files")
                    (assert txt-entry "CodeDir should include text files")
                    (view:open-entry dir-entry)
                    (view:open-entry fnl-entry)
                    (view:open-entry cpp-entry)
                    (view:open-entry txt-entry)
                    (local subdir-key (.. "code-dir:" (fs.absolute subdir)))
                    (local fnl-key (.. "fnl-module:" (fs.absolute fnl-file)))
                    (local cpp-key (.. "cpp-module:" (fs.absolute cpp-file)))
                    (local text-key (.. "text-module:" (fs.absolute txt-file)))
                    (assert (graph:lookup subdir-key) "Opening dir entry should add code-dir child")
                    (assert (graph:lookup fnl-key) "Opening fnl entry should add fnl-module child")
                    (assert (graph:lookup cpp-key) "Opening cpp entry should add cpp-module child")
                    (assert (graph:lookup text-key) "Opening text entry should add text-module child")
                    (assert (= (graph:edge-count) 4))
                    (view:drop)
                    (graph:drop))))))

(fn fs-node-actions-open-code-dir-for-directories []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local child-dir (fs.join-path root "sub"))
                    (fs.create-dirs child-dir)
                    (local graph (Graph {:with-start false}))
                    (local node (FsNode {:path root}))
                    (graph:add-node node {:position (glm.vec3 0 0 0)})
                    (local actions (node:actions))
                    (var code-action nil)
                    (each [_ action (ipairs actions)]
                        (when (= action.name "Open as Code Graph")
                            (set code-action action)))
                    (assert code-action
                            "FsNode directory actions should include Open as Code Graph")
                    (code-action.fn nil {})
                    (local code-key (.. "code-dir:" (fs.absolute root)))
                    (assert (graph:lookup code-key)
                            "Open as Code Graph should add a code-dir node")
                    (assert (= (graph:edge-count) 1))
                    (graph:drop))))))

(fn fs-node-actions-open-fnl-module-for-fnl-files []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local path (fs.join-path root "main.fnl"))
                    (fs.write-file path "(local x 1)\n")
                    (local graph (Graph {:with-start false}))
                    (local node (FsNode {:path path}))
                    (graph:add-node node {:position (glm.vec3 0 0 0)})
                    (local actions (node:actions))
                    (var module-action nil)
                    (each [_ action (ipairs actions)]
                        (when (= action.name "Open as Fennel Module")
                            (set module-action action)))
                    (assert module-action
                            "FsNode .fnl actions should include Open as Fennel Module")
                    (module-action.fn nil {})
                    (local module-key (.. "fnl-module:" (fs.absolute path)))
                    (assert (graph:lookup module-key)
                            "Open as Fennel Module should add fnl-module node")
                    (assert (= (graph:edge-count) 1))
                    (graph:drop))))))

(fn fnl-module-node-view-adds-required-module-node []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local subdir (fs.join-path root "sub"))
                    (local main-file (fs.join-path root "main.fnl"))
                    (local dep-file (fs.join-path subdir "dep.fnl"))
                    (fs.create-dirs subdir)
                    (fs.write-file main-file "(local dep (require :sub/dep))\n")
                    (fs.write-file dep-file "(local x 1)\n")
                    (local ctx (make-ctx))
                    (local graph (Graph {:with-start false}))
                    (local node (FnlModuleNode {:path main-file :lua-root root}))
                    (graph:add-node node {:position (glm.vec3 0 0 0)})
                    (local actions (node:actions))
                    (var has-edit false)
                    (each [_ action (ipairs actions)]
                        (when (= action.name "Edit")
                            (set has-edit true)))
                    (assert has-edit "FnlModuleNode should expose Edit action")
                    (local builder (node.view node))
                    (local view (builder ctx))
                    (view:refresh-items)
                    (assert (> (length view.search.items) 0)
                            "FnlModule should list resolvable requires")
                    (local entry (. (. view.search.items 1) 1))
                    (view.search.submitted:emit [entry "sub/dep"])
                    (local dep-key (.. "fnl-module:" (fs.absolute dep-file)))
                    (assert (graph:lookup dep-key)
                            "Submitting dependency should add fnl-module node")
                    (assert (= (graph:edge-count) 1))
                    (view:drop)
                    (graph:drop))))))

(fn cpp-module-node-view-adds-included-module-node []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local subdir (fs.join-path root "sub"))
                    (local main-file (fs.join-path root "main.cpp"))
                    (local dep-file (fs.join-path subdir "dep.h"))
                    (fs.create-dirs subdir)
                    (fs.write-file main-file "#include \"sub/dep.h\"\n")
                    (fs.write-file dep-file "#pragma once\n")
                    (local ctx (make-ctx))
                    (local graph (Graph {:with-start false}))
                    (local code-dir (CodeDirNode {:path root :root root}))
                    (graph:add-node code-dir {:position (glm.vec3 0 0 0)})
                    (local code-dir-view ((code-dir.view code-dir) ctx))
                    (code-dir-view:refresh-items)
                    (var cpp-entry nil)
                    (each [_ pair (ipairs code-dir-view.search.items)]
                        (local entry (. pair 1))
                        (when (paths-eq entry.path main-file)
                            (set cpp-entry entry)))
                    (assert cpp-entry "CodeDir should include cpp module entries")
                    (code-dir-view:open-entry cpp-entry)
                    (local main-key (.. "cpp-module:" (fs.absolute main-file)))
                    (local main-node (graph:lookup main-key))
                    (assert main-node "Opening cpp entry should add cpp-module node")
                    (local actions (main-node:actions))
                    (var has-edit false)
                    (each [_ action (ipairs actions)]
                        (when (= action.name "Edit")
                            (set has-edit true)))
                    (assert has-edit "CppModuleNode should expose Edit action")
                    (local main-view ((main-node.view main-node) ctx))
                    (main-view:refresh-items)
                    (assert (> (length main-view.search.items) 0)
                            "CppModule should list resolvable includes")
                    (local include-entry (. (. main-view.search.items 1) 1))
                    (main-view:open-entry include-entry)
                    (local dep-key (.. "cpp-module:" (fs.absolute dep-file)))
                    (assert (graph:lookup dep-key)
                            "Opening include should add included cpp-module node")
                    (main-view:drop)
                    (code-dir-view:drop)
                    (graph:drop))))))

(fn text-module-node-view-exposes-edit-and-open-parent-actions []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local docs (fs.join-path root "docs"))
                    (local path (fs.join-path docs "note.txt"))
                    (fs.create-dirs docs)
                    (fs.write-file path "See [README](../README.md)\n")
                    (fs.write-file (fs.join-path root "README.md") "# title\n")
                    (local ctx (make-ctx))
                    (local graph (Graph {:with-start false}))
                    (local node (TextModuleNode {:path path :project-root root}))
                    (graph:add-node node {:position (glm.vec3 0 0 0)})
                    (local view ((node.view node) ctx))
                    (view:refresh-items)
                    (assert (= (length view.search.items) 1)
                            "TextModule should list local text references")
                    (local ref-entry (. (. view.search.items 1) 1))
                    (view:open-entry ref-entry)
                    (local ref-key (.. "text-module:" (fs.absolute (fs.join-path root "README.md"))))
                    (assert (graph:lookup ref-key)
                            "Opening text reference should add text-module node")
                    (local actions (node:actions))
                    (var has-edit false)
                    (var has-open-parent false)
                    (each [_ action (ipairs actions)]
                        (when (= action.name "Edit")
                            (set has-edit true))
                        (when (= action.name "Open Parent Dir")
                            (set has-open-parent true)))
                    (assert has-edit "TextModuleNode should expose Edit action")
                    (assert has-open-parent "TextModuleNode should expose Open Parent Dir action")
                    (var open-parent-action nil)
                    (each [_ action (ipairs actions)]
                        (when (= action.name "Open Parent Dir")
                            (set open-parent-action action)))
                    (assert open-parent-action "TextModuleNode should provide Open Parent Dir action")
                    (open-parent-action.fn nil {})
                    (local parent-key (.. "code-dir:" (fs.absolute docs)))
                    (local parent-node (graph:lookup parent-key))
                    (assert parent-node "Open Parent Dir should add parent code-dir node")
                    (assert (= (graph:edge-count) 2)
                            "Open Parent Dir should add one more graph edge")
                    (var saw-parent-edge false)
                    (each [_ edge (ipairs graph.edges)]
                        (when (and (= edge.source parent-node)
                                   (= edge.target node))
                            (set saw-parent-edge true)))
                    (assert saw-parent-edge
                            "Open Parent Dir edge should flow downward from parent code-dir to module")
                    (view:drop)
                    (graph:drop))))))

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
                        (when (paths-eq entry.path child-dir)
                            (set dir-entry entry))
                        (when (paths-eq entry.path file)
                            (set file-entry entry)))
                    (assert dir-entry "Fs node view should list directories")
                    (assert file-entry "Fs node view should list files")
                    (view:open-entry dir-entry)
                    (assert (= (graph:edge-count) 1)
                            (string.format "Fs node should create one edge after opening dir (got %s)"
                                           (graph:edge-count)))
                    (view:open-entry file-entry)
                    (assert (find-fs-node-by-path graph child-dir)
                            "Dir node should be added to graph")
                    (assert (find-fs-node-by-path graph file)
                            "File node should be added to graph")
                    (local edge-count (graph:edge-count))
                    (assert (= edge-count 2)
                            (string.format "Fs node edges should match spawned children (got %s)"
                                           edge-count))
                    (view:drop)
                    (graph:drop))))))

(fn fs-node-view-ripgrep-button-opens-ripgrep-view-with-prefilled-path []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local original-hud app.hud)
                    (local added-opts [])
                    (set app.hud
                         {:add-panel-child (fn [_self opts]
                                             (table.insert added-opts opts)
                                             {:layout {:position (glm.vec3 0 0 0)}
                                              :drop (fn [_] nil)})})
                    (local (ok err)
                          (pcall
                            (fn []
                                (local ctx (make-ctx))
                                (local graph (Graph {:with-start false}))
                                (local node (FsNode {:path root}))
                                (graph:add-node node {:position (glm.vec3 0 0 0)})
                                (local builder (node.view node))
                                (local view (builder ctx))
                                (local ripgrep-button view.ripgrep-button)
                                (assert ripgrep-button "Fs node view should expose a ripgrep-button handle")
                                (ripgrep-button:on-click {:button 1})
                                (assert (= (length added-opts) 1)
                                        "Ripgrep button should open one panel child")
                                (local opts (. added-opts 1))
                                (assert (and opts opts.builder) "Ripgrep panel add should include a builder")
                                (assert (= (and opts.builder-options opts.builder-options.path)
                                           (fs.absolute root))
                                        "Ripgrep panel should prefill FsNode absolute path")
                                (view:drop)
                                (graph:drop))))
                    (set app.hud original-hud)
                    (when (not ok)
                        (error err)))))))

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

(fn graph-point-right-click-opens-node-actions-menu []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (var opened nil)
            (var custom-invoked 0)
            (var cube-invoked 0)
            (local original-menu-manager app.menu-manager)
            (local original-scene app.scene)
            (set app.menu-manager {:open (fn [_self opts]
                                           (set opened opts))})
            (set app.scene {:add-graph-node-cube (fn [_self opts]
                                                   (set cube-invoked (+ cube-invoked 1))
                                                   (assert (and opts opts.node
                                                                (= opts.node.key "menu-node"))
                                                           "Cube action should forward the selected graph node"))})
            (local node (Graph.GraphNode {:key "menu-node"
                                          :actions [{:name "Custom Action"
                                                     :icon "build"
                                                     :fn (fn [_button _event]
                                                             (set custom-invoked (+ custom-invoked 1)))}]}))
            (local view (GraphView {:graph graph
                                    :ctx ctx}))
            (graph:add-node node {:position (glm.vec3 10 12 0)})
            (local point (. view.points node))
            (assert point.on-right-click "GraphView should attach right click handler to node point")
            (point:on-right-click {:point (glm.vec3 3 4 0)})
            (assert opened "Right click should open a menu")
            (assert (= (length opened.actions) 4)
                    "Node menu should include Open, cube, custom actions, and Remove")
            (assert (= (. opened.actions 1 :name) "Open"))
            (assert (= (. opened.actions 2 :name) "cube"))
            (assert (= (. opened.actions 3 :name) "Custom Action"))
            (assert (= (. opened.actions 4 :name) "Remove"))
            ((. opened.actions 2 :fn) nil {})
            (assert (= cube-invoked 1)
                    "Cube action should create one scene graph-node cube")
            ((. opened.actions 3 :fn) nil {})
            (assert (= custom-invoked 1)
                    "Custom node action should be callable from the context menu")
            ((. opened.actions 4 :fn) nil {})
            (assert (not (graph:lookup "menu-node"))
                    "Remove action should remove the node from the graph")
            (view:drop)
            (graph:drop)
            (set app.menu-manager original-menu-manager)
            (set app.scene original-scene))))

(fn graph-point-right-click-uses-menu-manager-created-later []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (var opened nil)
            (local original-menu-manager app.menu-manager)
            (set app.menu-manager nil)
            (local node (Graph.GraphNode {:key "late-menu-node"}))
            (local view (GraphView {:graph graph
                                    :ctx ctx}))
            (graph:add-node node {:position (glm.vec3 1 1 0)})
            (set app.menu-manager {:open (fn [_self opts]
                                           (set opened opts))})
            (local point (. view.points node))
            (point:on-right-click {:point (glm.vec3 7 8 0)})
            (assert opened
                    "GraphView should resolve app.menu-manager at click time")
            (view:drop)
            (graph:drop)
            (set app.menu-manager original-menu-manager))))

(fn fs-node-actions-include-edit-only-for-files []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local file-path (fs.join-path root "note.txt"))
                    (local dir-path (fs.join-path root "child"))
                    (fs.create-dirs dir-path)
                    (fs.write-file file-path "hello")
                    (local file-node (FsNode {:path file-path}))
                    (local dir-node (FsNode {:path dir-path}))
                    (local file-actions (file-node:actions))
                    (local dir-actions (dir-node:actions))
                    (local has-edit
                           (fn [actions]
                               (var found false)
                               (each [_ action (ipairs (or actions []))]
                                   (when (= action.name "Edit")
                                       (set found true)))
                               found))
                    (assert (has-edit file-actions)
                            "FsNode actions should include Edit for files")
                    (assert (not (has-edit dir-actions))
                            "FsNode actions should omit Edit for directories"))))))

(fn graph-node-view-dialog-table-action-adds-table-node []
    (with-temp-data-dir
        (fn [_root]
            (local unwrap-element
                   (fn [item]
                       (or (and item item.element) item)))
            (local ctx (make-ctx))
            (local target {:build-context ctx
                           :children []
                           :add-panel-child (fn [self opts]
                                              (local builder (and opts opts.builder))
                                              (assert builder "builder required")
                                              (local dialog (builder self.build-context {}))
                                              (table.insert self.children dialog)
                                              dialog)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))})
            (local graph (Graph {}))
            (local node graph.start)
            (local views (GraphViewNodeViews {:ctx ctx
                                              :view-target target}))
            (views:open node)
            (assert (= (length target.children) 1)
                    "Node view should attach a dialog")
            (local dialog (. target.children 1))
            (local titlebar (unwrap-element (. dialog.children 1)))
            (local title-flex (unwrap-element (. titlebar.children 2)))
            (local action-row (unwrap-element (. title-flex.children (length title-flex.children))))
            (assert (= (length action-row.children) 3)
                    "Node view dialog should include table, code, and close actions")
            (local table-button (unwrap-element (. action-row.children 1)))
            (local code-button (unwrap-element (. action-row.children 2)))
            (assert (= table-button.icon "table")
                    "Table action should be first")
            (assert (= code-button.icon "code")
                    "Code action should be second")
            (table-button:on-click {:button 1})
            (local table-key (.. "table:node-view-dialog:" (tostring dialog)))
            (local table-node (graph:lookup table-key))
            (assert table-node
                    "Table action should add a table node for the node view module")
            (assert (= table-node.table dialog)
                    "Table action should use the actual node view dialog table")
            (assert (= (graph:edge-count) 1)
                    "Table action should add one edge")
            (views:drop-all)
            (graph:drop))))

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

(fn graph-view-node-views-hosts-heightfield-perlin-tool-dialog []
    (with-temp-data-dir
        (fn [_root]
            (local {:HeightfieldPerlinToolNode HeightfieldPerlinToolNode}
                   (require :graph/nodes/heightfield-perlin-tool))
            (local States (require :states))
            (local TerrainRectPickState (require :terrain-rect-pick-state))
            (local Clickables (require :clickables))
            (local Hoverables (require :hoverables))
            (local original-hud app.hud)
            (local original-scene app.scene)
            (local original-clickables app.clickables)
            (local original-hoverables app.hoverables)
            (local original-intersectables app.intersectables)
            (local original-screen-pos-ray app.screen-pos-ray)
            (local original-movables app.movables)
            (local original-resizables app.resizables)
            (local original-fpc app.first-person-controls)
            (local original-terrain-rect-pick-session app.terrain-rect-pick-session)
            (local original-states app.states)
            (var suspended-state nil)
            (local terrain-record (make-heightfield-terrain-record))
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
            (local runtime {:scene scene})
            (local entry (make-world-entry {:id "world-a"
                                            :runtime runtime
                                            :state {:scene {:panels []
                                                            :terrains [terrain-record]}
                                                    :hud {:panels []}}}))
            (local manager (make-world-manager {:entry entry}))
            (set app.intersectables (Intersectables))
            (set app.clickables (Clickables {:intersectables app.intersectables}))
            (set app.hoverables (Hoverables {:intersectables app.intersectables}))
            (set app.screen-pos-ray
                 (fn [pointer]
                     {:origin (glm.vec3 (or pointer.x 0) (or pointer.y 0) 10)
                      :direction (glm.vec3 0 0 -1)}))
            (set app.movables {:on-mouse-button-down (fn [_self _payload] nil)
                               :on-mouse-button-up (fn [_self _payload] nil)
                               :on-mouse-motion (fn [_self _payload] nil)
                               :drag-active? (fn [_self] false)})
            (set app.resizables {:on-mouse-button-down (fn [_self _payload] false)
                                 :on-mouse-button-up (fn [_self _payload] nil)
                                 :on-mouse-motion (fn [_self _payload] nil)
                                 :drag-active? (fn [_self] false)})
            (set app.first-person-controls {:on-mouse-button-down (fn [_self _payload] nil)
                                            :on-mouse-button-up (fn [_self _payload] nil)
                                            :on-mouse-motion (fn [_self _payload] nil)
                                            :drag-active? (fn [_self] false)})
            (local ctx (make-ctx))
            (local target {:build-context ctx
                           :world-units-per-pixel 1
                           :children []
                           :add-panel-child (fn [self opts]
                                              (local builder (and opts opts.builder))
                                              (assert builder "builder required")
                                              (local dialog (builder self.build-context {}))
                                              (table.insert self.children dialog)
                                              dialog)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))})
            (set app.hud target)
            (set app.scene scene)
            (local states (States))
            (states.add-state :normal {})
            (states.add-state :terrain-rect-pick (TerrainRectPickState))
            (states.set-state :normal)
            (set suspended-state (TestSupport.suspend-active-state original-states))
            (set app.states states)
            (local graph (Graph {:with-start false}))
            (local node (HeightfieldPerlinToolNode {:world-id "world-a"
                                                    :world-manager manager
                                                    :terrain-id "terrain-a"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local views (GraphViewNodeViews {:graph graph
                                              :ctx ctx
                                              :view-target target}))
            (views:open node)
            (assert (= (length target.children) 1)
                    "GraphViewNodeViews should host the terrain tool in a dialog")
            (local dialog (. target.children 1))
            (local body-card (unwrap-element (. dialog.children 2)))
            (local body-content (unwrap-element (. body-card.children 2)))
            (local tool-view (or (and body-content body-content.child) body-content))
            (assert tool-view "Expected terrain tool view inside hosted dialog")
            (assert tool-view.pick-button "Hosted terrain tool should expose pick button")
            (tool-view.pick-button:on-click {})
            (assert (= (app.states.active-name) :terrain-rect-pick)
                    "Hosted terrain tool pick should enter the terrain rectangle pick state")
            (assert app.terrain-rect-pick-session
                    "Hosted terrain tool pick should register the active terrain rectangle pick session")
            (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
            (app.engine.events.mouse-motion.emit {:x 40 :y 60})
            (app.engine.events.mouse-button-up.emit {:button 1 :x 40 :y 60})
            (local draft (and tool-view.form (tool-view.form:get-draft)))
            (local picked-target (and draft draft.picked-target))
            (assert picked-target)
            (assert (= picked-target.x0 1))
            (assert (= picked-target.z0 2))
            (assert (= picked-target.x1 3))
            (assert (= picked-target.z1 4))
            (assert-codepoints-eq (tool-view.selection-label:get-codepoints)
                                  (TextUtils.codepoints-from-text "12 samples across [1, 2] to [3, 4]"))
            (assert (= (app.states.active-name) :normal)
                    "Hosted terrain tool pick should restore the previous state after completion")
            (views:drop-all)
            (graph:drop)
            (set app.hud original-hud)
            (set app.scene original-scene)
            (set app.clickables original-clickables)
            (set app.hoverables original-hoverables)
            (set app.intersectables original-intersectables)
            (set app.screen-pos-ray original-screen-pos-ray)
            (set app.movables original-movables)
            (set app.resizables original-resizables)
            (set app.first-person-controls original-fpc)
            (set app.states original-states)
            (TestSupport.resume-active-state suspended-state)
            (set app.terrain-rect-pick-session original-terrain-rect-pick-session))))


(fn graph-view-node-views-clickables-drive-heightfield-perlin-tool-pick []
    (with-temp-data-dir
        (fn [_root]
            (local {:HeightfieldPerlinToolNode HeightfieldPerlinToolNode}
                   (require :graph/nodes/heightfield-perlin-tool))
            (local States (require :states))
            (local TerrainRectPickState (require :terrain-rect-pick-state))
            (local Clickables (require :clickables))
            (local Hoverables (require :hoverables))
            (local original-hud app.hud)
            (local original-scene app.scene)
            (local original-clickables app.clickables)
            (local original-hoverables app.hoverables)
            (local original-intersectables app.intersectables)
            (local original-screen-pos-ray app.screen-pos-ray)
            (local original-movables app.movables)
            (local original-resizables app.resizables)
            (local original-fpc app.first-person-controls)
            (local original-terrain-rect-pick-session app.terrain-rect-pick-session)
            (local original-states app.states)
            (var suspended-state nil)
            (local terrain-record (make-heightfield-terrain-record))
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
            (local runtime {:scene scene})
            (local entry (make-world-entry {:id "world-a"
                                            :runtime runtime
                                            :state {:scene {:panels []
                                                            :terrains [terrain-record]}
                                                    :hud {:panels []}}}))
            (local manager (make-world-manager {:entry entry}))
            (set app.intersectables (Intersectables))
            (set app.clickables (Clickables {:intersectables app.intersectables}))
            (set app.hoverables (Hoverables {:intersectables app.intersectables}))
            (set app.screen-pos-ray
                 (fn [pointer]
                     {:origin (glm.vec3 (or pointer.x 0) (or pointer.y 0) 10)
                      :direction (glm.vec3 0 0 -1)}))
            (set app.movables {:on-mouse-button-down (fn [_self _payload] nil)
                               :on-mouse-button-up (fn [_self _payload] nil)
                               :on-mouse-motion (fn [_self _payload] nil)
                               :drag-active? (fn [_self] false)})
            (set app.resizables {:on-mouse-button-down (fn [_self _payload] false)
                                 :on-mouse-button-up (fn [_self _payload] nil)
                                 :on-mouse-motion (fn [_self _payload] nil)
                                 :drag-active? (fn [_self] false)})
            (set app.first-person-controls {:on-mouse-button-down (fn [_self _payload] nil)
                                            :on-mouse-button-up (fn [_self _payload] nil)
                                            :on-mouse-motion (fn [_self _payload] nil)
                                            :drag-active? (fn [_self] false)})
            (local ctx (make-ctx))
            (local target {:build-context ctx
                           :world-units-per-pixel 1
                           :children []
                           :add-panel-child (fn [self opts]
                                              (local builder (and opts opts.builder))
                                              (assert builder "builder required")
                                              (local dialog (builder self.build-context {}))
                                              (table.insert self.children dialog)
                                              dialog)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))})
            (set app.hud target)
            (set app.scene scene)
            (local states (States))
            (states.add-state :normal {})
            (states.add-state :terrain-rect-pick (TerrainRectPickState))
            (states.set-state :normal)
            (set suspended-state (TestSupport.suspend-active-state original-states))
            (set app.states states)
            (local graph (Graph {:with-start false}))
            (local node (HeightfieldPerlinToolNode {:world-id "world-a"
                                                    :world-manager manager
                                                    :terrain-id "terrain-a"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local views (GraphViewNodeViews {:graph graph
                                              :ctx ctx
                                              :view-target target}))
            (views:open node)
            (local dialog (. target.children 1))
            (local body-card (unwrap-element (. dialog.children 2)))
            (local body-content (unwrap-element (. body-card.children 2)))
            (local tool-view (or (and body-content body-content.child) body-content))
            (local button tool-view.pick-button)
            (assert button "Expected terrain tool pick button")
            (local original-intersect button.intersect)
            (set button.intersect
                 (fn [_self _ray]
                     (values true (glm.vec3 0 0 0) 0.0)))
            (app.clickables:on-mouse-button-down {:button 1 :x 5 :y 5 :timestamp 10})
            (app.clickables:on-mouse-button-up {:button 1 :x 5 :y 5 :timestamp 10})
            (assert (= (app.states.active-name) :terrain-rect-pick)
                    "clickables-driven pick button should enter the terrain rectangle pick state")
            (assert app.terrain-rect-pick-session
                    "clickables-driven pick button should register the active terrain rectangle pick session")
            (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
            (app.engine.events.mouse-motion.emit {:x 40 :y 60})
            (app.engine.events.mouse-button-up.emit {:button 1 :x 40 :y 60})
            (local draft (and tool-view.form (tool-view.form:get-draft)))
            (local picked-target (and draft draft.picked-target))
            (assert picked-target)
            (assert (= picked-target.x0 1))
            (assert (= picked-target.z0 2))
            (assert (= picked-target.x1 3))
            (assert (= picked-target.z1 4))
            (assert-codepoints-eq (tool-view.selection-label:get-codepoints)
                                  (TextUtils.codepoints-from-text "12 samples across [1, 2] to [3, 4]"))
            (set button.intersect original-intersect)
            (views:drop-all)
            (graph:drop)
            (set app.hud original-hud)
            (set app.scene original-scene)
            (set app.clickables original-clickables)
            (set app.hoverables original-hoverables)
            (set app.intersectables original-intersectables)
            (set app.screen-pos-ray original-screen-pos-ray)
            (set app.movables original-movables)
            (set app.resizables original-resizables)
            (set app.first-person-controls original-fpc)
            (set app.states original-states)
            (TestSupport.resume-active-state suspended-state)
            (set app.terrain-rect-pick-session original-terrain-rect-pick-session))))


(fn graph-view-node-views-engine-events-drive-heightfield-perlin-tool-pick []
    (with-temp-data-dir
        (fn [_root]
            (local {:HeightfieldPerlinToolNode HeightfieldPerlinToolNode}
                   (require :graph/nodes/heightfield-perlin-tool))
            (local States (require :states))
            (local TerrainRectPickState (require :terrain-rect-pick-state))
            (local NormalState (require :normal-state))
            (local Clickables (require :clickables))
            (local Hoverables (require :hoverables))
            (local original-hud app.hud)
            (local original-scene app.scene)
            (local original-clickables app.clickables)
            (local original-hoverables app.hoverables)
            (local original-intersectables app.intersectables)
            (local original-screen-pos-ray app.screen-pos-ray)
            (local original-movables app.movables)
            (local original-resizables app.resizables)
            (local original-fpc app.first-person-controls)
            (local original-terrain-rect-pick-session app.terrain-rect-pick-session)
            (local original-states app.states)
            (var suspended-state nil)
            (local terrain-record (make-heightfield-terrain-record))
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
            (local runtime {:scene scene})
            (local entry (make-world-entry {:id "world-a"
                                            :runtime runtime
                                            :state {:scene {:panels []
                                                            :terrains [terrain-record]}
                                                    :hud {:panels []}}}))
            (local manager (make-world-manager {:entry entry}))
            (set app.intersectables (Intersectables))
            (set app.clickables (Clickables {:intersectables app.intersectables}))
            (set app.hoverables (Hoverables {:intersectables app.intersectables}))
            (set app.screen-pos-ray
                 (fn [pointer]
                     {:origin (glm.vec3 (or pointer.x 0) (or pointer.y 0) 10)
                      :direction (glm.vec3 0 0 -1)}))
            (set app.movables {:on-mouse-button-down (fn [_self _payload] nil)
                               :on-mouse-button-up (fn [_self _payload] nil)
                               :on-mouse-motion (fn [_self _payload] nil)
                               :drag-active? (fn [_self] false)})
            (set app.resizables {:on-mouse-button-down (fn [_self _payload] false)
                                 :on-mouse-button-up (fn [_self _payload] nil)
                                 :on-mouse-motion (fn [_self _payload] nil)
                                 :drag-active? (fn [_self] false)})
            (set app.first-person-controls {:on-mouse-button-down (fn [_self _payload] nil)
                                            :on-mouse-button-up (fn [_self _payload] nil)
                                            :on-mouse-motion (fn [_self _payload] nil)
                                            :drag-active? (fn [_self] false)})
            (local ctx (make-ctx))
            (local target {:build-context ctx
                           :world-units-per-pixel 1
                           :children []
                           :add-panel-child (fn [self opts]
                                              (local builder (and opts opts.builder))
                                              (assert builder "builder required")
                                              (local dialog (builder self.build-context {}))
                                              (table.insert self.children dialog)
                                              dialog)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))})
            (set app.hud target)
            (set app.scene scene)
            (local states (States))
            (states.add-state :normal (NormalState))
            (states.add-state :terrain-rect-pick (TerrainRectPickState))
            (states.set-state :normal)
            (set suspended-state (TestSupport.suspend-active-state original-states))
            (set app.states states)
            (local graph (Graph {:with-start false}))
            (local node (HeightfieldPerlinToolNode {:world-id "world-a"
                                                    :world-manager manager
                                                    :terrain-id "terrain-a"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local views (GraphViewNodeViews {:graph graph
                                              :ctx ctx
                                              :view-target target}))
            (views:open node)
            (local dialog (. target.children 1))
            (local body-card (unwrap-element (. dialog.children 2)))
            (local body-content (unwrap-element (. body-card.children 2)))
            (local tool-view (or (and body-content body-content.child) body-content))
            (local button tool-view.pick-button)
            (assert button "Expected terrain tool pick button")
            (local original-intersect button.intersect)
            (set button.intersect
                 (fn [_self _ray]
                     (values true (glm.vec3 0 0 0) 0.0)))
            (app.engine.events.mouse-button-down.emit {:button 1 :x 5 :y 5 :timestamp 10})
            (app.engine.events.mouse-button-up.emit {:button 1 :x 5 :y 5 :timestamp 10})
            (assert (= (app.states.active-name) :terrain-rect-pick)
                    "engine-event click should enter terrain rect pick state")
            (assert app.terrain-rect-pick-session
                    "engine-event click should register active terrain pick session")
            (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
            (app.engine.events.mouse-motion.emit {:x 40 :y 60})
            (app.engine.events.mouse-button-up.emit {:button 1 :x 40 :y 60})
            (local draft (and tool-view.form (tool-view.form:get-draft)))
            (local picked-target (and draft draft.picked-target))
            (assert picked-target)
            (assert (= picked-target.x0 1))
            (assert (= picked-target.z0 2))
            (assert (= picked-target.x1 3))
            (assert (= picked-target.z1 4))
            (assert-codepoints-eq (tool-view.selection-label:get-codepoints)
                                  (TextUtils.codepoints-from-text "12 samples across [1, 2] to [3, 4]"))
            (set button.intersect original-intersect)
            (views:drop-all)
            (graph:drop)
            (set app.hud original-hud)
            (set app.scene original-scene)
            (set app.clickables original-clickables)
            (set app.hoverables original-hoverables)
            (set app.intersectables original-intersectables)
            (set app.screen-pos-ray original-screen-pos-ray)
            (set app.movables original-movables)
            (set app.resizables original-resizables)
            (set app.first-person-controls original-fpc)
            (set app.states original-states)
            (TestSupport.resume-active-state suspended-state)
            (set app.terrain-rect-pick-session original-terrain-rect-pick-session))))

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
(table.insert tests {:name "Fs node view ripgrep button opens prefilled view"
                     :fn fs-node-view-ripgrep-button-opens-ripgrep-view-with-prefilled-path})
(table.insert tests {:name "Fs node actions open code-dir for directories"
                     :fn fs-node-actions-open-code-dir-for-directories})
(table.insert tests {:name "Fs node actions open fnl-module for .fnl files"
                     :fn fs-node-actions-open-fnl-module-for-fnl-files})
(table.insert tests {:name "Code dir node view adds edges for dir and module entries"
                     :fn code-dir-node-view-adds-subdir-and-module-nodes})
(table.insert tests {:name "Fnl module node view adds dependency module edge"
                     :fn fnl-module-node-view-adds-required-module-node})
(table.insert tests {:name "Cpp module node view adds included module edge"
                     :fn cpp-module-node-view-adds-included-module-node})
(table.insert tests {:name "Text module node view exposes actions and references"
                     :fn text-module-node-view-exposes-edit-and-open-parent-actions})
(table.insert tests {:name "Table node view adds edges for entries" :fn table-node-view-adds-child-nodes})
(table.insert tests {:name "GraphView removes selected nodes and related edges" :fn graph-removes-selected-nodes-and-edges})
(table.insert tests {:name "GraphView opens node view in HUD on double click" :fn graph-opens-node-view-in-hud-on-double-click})
(table.insert tests {:name "GraphView node point right-click opens node actions"
                     :fn graph-point-right-click-opens-node-actions-menu})
(table.insert tests {:name "GraphView right-click resolves late menu manager"
                     :fn graph-point-right-click-uses-menu-manager-created-later})
(table.insert tests {:name "FsNode actions include edit only for files"
                     :fn fs-node-actions-include-edit-only-for-files})
(table.insert tests {:name "Graph node view dialog table action adds table node"
                     :fn graph-node-view-dialog-table-action-adds-table-node})
(table.insert tests {:name "GraphView emits selection changes" :fn graph-selection-emits-changed})
(table.insert tests {:name "GraphView updates selection and focus borders" :fn graph-view-updates-selection-and-focus-borders})
(table.insert tests {:name "GraphView auto-focus updates focus ring" :fn graph-view-autofocus-updates-focus-ring})
(table.insert tests {:name "Graph view rebuilds views from double click" :fn graph-view-rebuilds-from-double-click})
(table.insert tests {:name "GraphView node views host heightfield perlin tool dialog"
                     :fn graph-view-node-views-hosts-heightfield-perlin-tool-dialog})
(table.insert tests {:name "GraphView node views clickables drive heightfield perlin tool pick"
                     :fn graph-view-node-views-clickables-drive-heightfield-perlin-tool-pick})
(table.insert tests {:name "GraphView node views engine events drive heightfield perlin tool pick"
                     :fn graph-view-node-views-engine-events-drive-heightfield-perlin-tool-pick})
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
