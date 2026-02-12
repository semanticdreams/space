(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode :node-id node-id} (require :graph/node-base))
(local StartNodeView (require :graph/view/views/start))
(local {:FsNode FsNode :resolve-path fs-resolve-path} (require :graph/nodes/fs))
(local LlmNode (require :graph/nodes/llm))
(local QuitNode (require :graph/nodes/quit))
(local HackerNewsRootNode (require :graph/nodes/hackernews-root))
(local {:TableNode TableNode} (require :graph/nodes/table))
(local EntitiesNode (require :graph/nodes/entities))
(local CodeDirNode (require :graph/nodes/code-dir))
(local Signal (require :signal))
(local fs (require :fs))

(fn StartNode []
    (local node
        (GraphNode {:key "start"
                        :label "start"
                        :color (glm.vec4 0 1 0 1)
                        :sub-color (glm.vec4 0 0.8 0 1)
                        :size 9.0
                        :view StartNodeView}))
    (set node.targets-changed (Signal))

    (set node.resolve-fs-path
         (fn [_self]
             (assert (and fs fs.cwd) "StartNode fs entry requires fs.cwd")
             (if fs-resolve-path
                 (fs-resolve-path (fs.cwd))
                 (fs.cwd))))

    (set node.resolve-code-path
         (fn [_self]
             (if (and app app.engine app.engine.get-asset-path)
                 (app.engine.get-asset-path "lua")
                 (if (and fs fs.cwd fs.join-path)
                     (fs.join-path (fs.cwd) "assets" "lua")
                     "assets/lua"))))

    (set node.collect-targets
         (fn [self]
             (local produced [])
             (local fs-node (FsNode {:path (self:resolve-fs-path)}))
             (table.insert produced [fs-node (or fs-node.label fs-node.key)])
             (local table-node (TableNode {:table _G
                                           :label "_G"
                                           :key "table:_G"}))
             (table.insert produced [table-node (or table-node.label table-node.key)])
            (local llm-node (LlmNode))
            (table.insert produced [llm-node (or llm-node.label llm-node.key)])
            (local quit-node (QuitNode {:on-quit (and app.engine app.engine.quit)}))
             (table.insert produced [quit-node (or quit-node.label quit-node.key (node-id quit-node))])
             (local hn-node (HackerNewsRootNode))
             (table.insert produced [hn-node (or hn-node.label hn-node.key (node-id hn-node))])
             (local entities-node (EntitiesNode))
             (table.insert produced [entities-node (or entities-node.label entities-node.key)])
             (local code-node (CodeDirNode {:path (self:resolve-code-path)}))
             (table.insert produced [code-node (or code-node.label "code")])
             produced))

    (set node.emit-targets
         (fn [self]
             (local targets (self:collect-targets))
             (when self.targets-changed
                 (self.targets-changed:emit targets))
             targets))

    (set node.add-target
         (fn [self target]
             (local graph self.graph)
             (when (and graph target)
                (local node
                    (if (= (type target) "function")
                        (target)
                        target))
                (assert node "StartNode requires a node to add")
                (graph:add-edge (GraphEdge {:source self
                                                :target node})))))

    (fn add-target-by-key [self target-key]
        (each [_ pair (ipairs (self:collect-targets))]
            (local target (. pair 1))
            (local key (or (and target target.key) ""))
            (if (= target-key :fs-prefix)
                (when (= (string.sub key 1 3) "fs:")
                    (self:add-target target))
                (= target-key :code-prefix)
                (when (= (string.sub key 1 9) "code-dir:")
                    (self:add-target target))
                (when (= key target-key)
                    (self:add-target target)))))

    (set node.actions
         [{:name "Add Filesystem"
           :icon "folder"
           :fn (fn [_button _event]
                   (add-target-by-key node :fs-prefix))}
          {:name "Add Globals Table"
           :icon "table"
           :fn (fn [_button _event]
                   (add-target-by-key node "table:_G"))}
          {:name "Add LLM"
           :icon "chat"
           :fn (fn [_button _event]
                   (add-target-by-key node "llm"))}
          {:name "Add HackerNews"
           :icon "public"
           :fn (fn [_button _event]
                   (add-target-by-key node "hackernews-root"))}
          {:name "Add Entities"
           :icon "apps"
           :fn (fn [_button _event]
                   (add-target-by-key node "entities"))}
          {:name "Add Quit"
           :icon "exit_to_app"
           :fn (fn [_button _event]
                   (add-target-by-key node "quit"))}
          {:name "Add Code (assets/lua)"
           :icon "code"
           :fn (fn [_button _event]
                   (add-target-by-key node :code-prefix))}])

    (set node.drop
         (fn [self]
             (when self.targets-changed
                 (self.targets-changed:clear))))

    node)

StartNode
