(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local HackerNewsRootView (require :graph/view/views/hackernews-root))
(local HackerNewsStoryListNode (require :graph/nodes/hackernews-story-list))
(local Signal (require :signal))

(fn HackerNewsRootNode [opts]
    (local options (or opts {}))
    (local node
        (GraphNode
            {:key "hackernews-root"
             :label "hackernews"
             :color (glm.vec4 1 0.4 0 1)
             :sub-color (glm.vec4 1 0.25 0 1)
             :size 9.0
             :view HackerNewsRootView}))

    (set node.ensure-client options.ensure-client)
    (set node.feeds [{:label "Top stories" :kind "topstories"}
                     {:label "New stories" :kind "newstories"}
                     {:label "Best stories" :kind "beststories"}])
    (set node.feeds-changed (Signal))
    (set node.emit-feeds
         (fn [self]
             (when self.feeds-changed
                 (self.feeds-changed:emit self.feeds))
             self.feeds))

    (set node.make-list-node
         (fn [_self kind label]
             (HackerNewsStoryListNode {:kind kind
                                       :label label
                                       :ensure-client node.ensure-client})))

    (set node.add-feed
         (fn [self entry]
             (local graph self.graph)
             (when (and graph entry entry.kind)
                 (local child (self:make-list-node entry.kind entry.label))
                 (graph:add-edge
                     (GraphEdge {:source self
                                     :target child})))))

    (set node.drop
         (fn [self]
             (when self.feeds-changed
                 (self.feeds-changed:clear))))

    node)

HackerNewsRootNode
