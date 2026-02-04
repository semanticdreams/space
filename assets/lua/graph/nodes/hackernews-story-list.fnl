(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local HackerNewsStoryListView (require :graph/view/views/hackernews-story-list))
(local HackerNewsStoryNode (require :graph/nodes/hackernews-story))
(local {:ensure-client default-ensure-client
        :next-list-key next-list-key} (require :graph/nodes/hackernews-common))
(local Signal (require :signal))

(fn HackerNewsStoryListNode [opts]
    (local options (or opts {}))
    (local ensure (or options.ensure-client default-ensure-client))
    (local kind (or options.kind "topstories"))
    (local key (or options.key (next-list-key kind)))
    (local label (or options.label (string.format "HN %s" kind)))
    (local node
        (GraphNode
            {:key key
             :label label
             :color (glm.vec4 0.95 0.6 0.15 1)
             :sub-color (glm.vec4 0.85 0.45 0.1 1)
             :size 8.0
             :view HackerNewsStoryListView}))
    (set node.kind kind)
    (set node.items {})
    (set node.ids [])
    (set node.inflight {})
    (set node.error nil)
    (set node.pending [])
    (set node.items-changed (Signal))
    (set node.item-changed (Signal))
    (set node.ensure-client ensure)

    (set node.make-story-node
         (fn [_self id item]
             (HackerNewsStoryNode {:id id
                                   :item item
                                   :ensure-client node.ensure-client})))

    (fn index-for-id [self id]
        (var index nil)
        (for [idx 1 (length self.ids)]
            (when (= (. self.ids idx) id)
                (set index idx)))
        index)
    (set node.index-for-id index-for-id)

    (fn track-future [self future cb]
        (when (and future future.on-complete)
            (table.insert self.pending future)
            (future.on-complete
             (fn [ok value err source]
                 (for [i (length self.pending) 1 -1]
                     (when (= (. self.pending i) future)
                         (table.remove self.pending i)))
                 (when cb
                     (cb ok value err source))))))

    (set node.render-label
         (fn [self id]
             (local item (. self.items id))
             (or (and item item.title) (.. "#" id " (loading)"))))

    (set node.render-items
         (fn [self]
             (if self.error
                 [{:id "error" :label (.. "Error: " self.error)}]
                 (if (= (length self.ids) 0)
                     [{:id "loading" :label "Loading stories..."}]
                     (icollect [_ story-id (ipairs self.ids)]
                         {:id story-id
                                         :label (self:render-label story-id)
                                          :item (. self.items story-id)})))))

    (set node.emit-items
         (fn [self]
             (local rendered (self:render-items))
             (when self.items-changed
                 (self.items-changed:emit rendered))
             rendered))

    (set node.emit-item
         (fn [self id]
             (local entry {:id id
                           :label (self:render-label id)
                           :item (. self.items id)})
             (local index (self:index-for-id id))
             (when (and self.item-changed index)
                 (self.item-changed:emit {:index index
                                          :entry entry}))
             entry))

    (set node.on-item-loaded
         (fn [self id item err]
             (if item
                 (do
                     (set (. self.items id) item)
                     (set (. self.inflight id) nil))
                 (do
                     (set (. self.items id) {:title (or err "Failed to load story")})
                     (set (. self.inflight id) nil)))
             (self:emit-item id)))

    (set node.fetch-item
         (fn [self id]
             (local client (and self.ensure-client (self.ensure-client)))
             (when (and client (not (. self.inflight id)))
                 (set (. self.inflight id) true)
                 (track-future self
                               (client.fetch-item id)
                               (fn [ok value err _source]
                                   (self:on-item-loaded id (and ok value) err))))))

    (set node.fetch-list
         (fn [self]
             (local client (and self.ensure-client (self.ensure-client)))
             (when client
                 (local fetch-fn (match self.kind
                                   "newstories" client.fetch-newstories
                                   "beststories" client.fetch-beststories
                                    _ client.fetch-topstories))
                 (when fetch-fn
                     (track-future self
                                   (fetch-fn)
                                   (fn [ok value err _source]
                                       (if ok
                                           (do
                                               (set self.error nil)
                                               (local limited [])
                                               (when value
                                                   (local count (math.min 10 (length value)))
                                                   (for [i 1 count]
                                                       (local story-id (. value i))
                                                       (when story-id
                                                           (table.insert limited story-id))))
                                               (set self.ids limited)
                                               (set self.items {})
                                               (set self.inflight {})
                                               (self:emit-items)
                                               (each [_ story-id (ipairs self.ids)]
                                                   (self:fetch-item story-id)))
                                           (do
                                               (set self.error (or err "failed to fetch stories"))
                                               (set self.ids [])
                                               (set self.items {})
                                               (self:emit-items)))))))))

    (set node.cancel-pending
         (fn [self]
             (each [_ future (ipairs self.pending)]
                 (when (and future future.cancel)
                     (future:cancel)))
             (set self.pending [])))

    (set node.drop
         (fn [self]
             (self:cancel-pending)
             (when self.items-changed
                 (self.items-changed:clear))
             (when self.item-changed
                 (self.item-changed:clear))))

    (set node.open-story
         (fn [self entry]
             (local graph self.graph)
             (when (and graph entry entry.id)
                 (local story-node (self:make-story-node entry.id entry.item))
                 (graph:add-edge
                     (GraphEdge {:source self
                                     :target story-node})))))

    (local mount node.mount)
    (set node.mount
         (fn [self graph]
             (mount self graph)
             (self:fetch-list)
             self))

    node)

HackerNewsStoryListNode
