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

    (set node.drop
         (fn [self]
             (when self.targets-changed
                 (self.targets-changed:clear))))

    node)

StartNode
