(local glm (require :glm))
(local {:GraphNode GraphNode
        :node-id node-id} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local ListEntityStore (require :entities/list))
(local Utils (require :graph/view/utils))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local CYAN (glm.vec4 0.0 0.6 0.7 1))
(local CYAN_ACCENT (glm.vec4 0.05 0.65 0.75 1))

(local SCHEME "list-entity")
(local KEY_PREFIX (KeyLoaderUtils.key-prefix SCHEME))

(fn make-label [entity]
  (local name (or (and entity entity.name) ""))
  (if (> (string.len name) 0)
      (Utils.truncate-with-ellipsis name 50)
      (or (and entity entity.id) "list entity")))

(fn edge-key [source target]
  (.. (node-id source) "->" (node-id target)))

(fn remove-edge-by-key [graph key]
  (when (and graph graph.edges graph.edge-map key)
    (local existing (. graph.edge-map key))
    (when existing
      (for [i (length graph.edges) 1 -1]
        (when (= (. graph.edges i) existing)
          (table.remove graph.edges i)))
      (set (. graph.edge-map key) nil)
      (when (and graph.edge-removed graph.edge-removed.emit)
        (graph.edge-removed:emit {:edge existing})))))

(fn entity-contains-node-key? [entity node-key]
  (local key (tostring node-key))
  (var found? false)
  (each [_ value (ipairs (or (and entity entity.items) []))]
    (when (= (tostring value) key)
      (set found? true)))
  found?)

(fn ListEntityNode [opts]
  (local options (or opts {}))
  (local entity-id (assert options.entity-id "ListEntityNode requires entity-id"))
  (local store (or options.store (ListEntityStore.get-default)))
  (local ListEntityNodeView (require :graph/view/views/list-entity))

  (local entity (store:get-entity entity-id))
  (local initial-label (make-label entity))

  (local node
    (GraphNode {:key (.. KEY_PREFIX entity-id)
                :label initial-label
                :color CYAN
                :sub-color CYAN_ACCENT
                :size 8.0
                :view ListEntityNodeView}))

  (set node.entity-id entity-id)
  (set node.store store)
  (set node.entity-deleted (Signal))
  (set node.changed (Signal))
  (set node.items-changed (Signal))
  (set node.list-item-edge-keys {})

  (fn refresh-label [self]
    (local current (self.store:get-entity self.entity-id))
    (set self.label (make-label current))
    (when self.changed
      (self.changed:emit self)))

  (set node.refresh-label refresh-label)

  (set node.get-entity
       (fn [self]
         (self.store:get-entity self.entity-id)))

  (set node.add-item-nodes
       (fn [self]
         (local graph self.graph)
         (when (and graph graph.load-by-key graph.add-edge)
           (local current (self:get-entity))
           (local items (or (and current current.items) []))
           (local desired {})
           (each [_ item-key (ipairs items)]
             (local target (graph:load-by-key item-key))
             (when target
               (graph:add-edge (GraphEdge {:source self :target target})
                               {:from-list-entity self.entity-id})
               (set (. desired (edge-key self target)) true)))
           (each [k _ (pairs (or self.list-item-edge-keys {}))]
             (when (not (. desired k))
               (remove-edge-by-key graph k)))
           (set self.list-item-edge-keys desired))))

  (set node.update-name
       (fn [self new-name]
         (self.store:update-entity self.entity-id {:name new-name})
         (self:refresh-label)))

  (set node.add-item
       (fn [self node-key]
         (self.store:add-item self.entity-id node-key)
         (self:add-item-nodes)))

  (set node.remove-item
       (fn [self node-key]
         (self.store:remove-item self.entity-id node-key)
         (self:add-item-nodes)))

  (set node.move-item
       (fn [self from-index to-index]
         (self.store:move-item self.entity-id from-index to-index)
         (self:add-item-nodes)))

  (set node.delete-entity
       (fn [self]
         (self.store:delete-entity self.entity-id)))

  (var deleted-handler nil)
  (var updated-handler nil)
  (var items-handler nil)

  (set deleted-handler
       (store.list-entity-deleted:connect
         (fn [deleted]
           (when (= (tostring deleted.id) (tostring entity-id))
             (node.entity-deleted:emit deleted)
             (when (and node.graph node.graph.remove-nodes)
               (node.graph:remove-nodes [node]))))))

  (set updated-handler
       (store.list-entity-updated:connect
         (fn [updated]
           (when (= (tostring updated.id) (tostring entity-id))
             (node:refresh-label)))))

  (fn handle-items-changed [payload]
    (local id (or (and payload payload.id) ""))
    (when (= (tostring id) (tostring entity-id))
      (node.items-changed:emit payload)
      (node:add-item-nodes)))

  (set items-handler
       (store.list-entity-items-changed:connect handle-items-changed))

  (set node.added
       (fn [self _graph]
         (self:add-item-nodes)
         self))

  (var graph-node-added-handler nil)
  (var graph-node-added-signal nil)

  (local mount node.mount)
  (set node.mount
       (fn [self graph]
         (mount self graph)
         (local signal (and graph graph.node-added))
         ;; When item nodes are added later, attach edges from this list node if relevant.
         (when (and signal (not graph-node-added-handler))
           (set graph-node-added-signal signal)
           (set graph-node-added-handler
                (signal:connect
                  (fn [payload]
                    (local added (and payload payload.node))
                    (when (and added (not (= (tostring added.key) (tostring self.key))))
                      (local entity (self:get-entity))
                      (when (and entity (entity-contains-node-key? entity added.key))
                        (self:add-item-nodes)))))))
         self))

  (set node.drop
       (fn [self]
         (when (and graph-node-added-signal graph-node-added-handler)
           (graph-node-added-signal:disconnect graph-node-added-handler true)
           (set graph-node-added-handler nil))
         (when deleted-handler
           (store.list-entity-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when updated-handler
           (store.list-entity-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (when items-handler
           (store.list-entity-items-changed:disconnect items-handler true)
           (set items-handler nil))
         (self.entity-deleted:clear)
         (self.items-changed:clear)
         (when self.changed
           (self.changed:clear))))

  node)

(local register-loader
  (KeyLoaderUtils.make-register-loader SCHEME
    ListEntityStore.get-default
    (fn [entity-id store]
      (ListEntityNode {:entity-id entity-id :store store}))))

{:ListEntityNode ListEntityNode
 :register-loader register-loader}
