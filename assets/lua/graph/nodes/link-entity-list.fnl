(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local LinkEntityStore (require :entities/link))
(local {:LinkEntityNode LinkEntityNode} (require :graph/nodes/link-entity))
(local Utils (require :graph/view/utils))

(local PALE_YELLOW (glm.vec4 0.7 0.65 0.3 1))
(local PALE_YELLOW_ACCENT (glm.vec4 0.75 0.7 0.35 1))

(fn make-entity-label [entity]
  (if (and entity entity.source-key entity.target-key
           (> (string.len entity.source-key) 0)
           (> (string.len entity.target-key) 0))
      (.. (Utils.truncate-with-ellipsis entity.source-key 15)
          " → "
          (Utils.truncate-with-ellipsis entity.target-key 15))
      (or entity.id "unknown")))

(fn LinkEntityListNode [opts]
  (local options (or opts {}))
  (local store (or options.store (LinkEntityStore.get-default)))
  (local LinkEntityListNodeView (require :graph/view/views/link-entity-list))

  (local node
    (GraphNode {:key "link-entity-list"
                :label "link entities"
                :color PALE_YELLOW
                :sub-color PALE_YELLOW_ACCENT
                :size 8.0
                :view LinkEntityListNodeView}))

  (set node.store store)
  (set node.items-changed (Signal))

  (fn collect-items [self]
    (local entities (self.store:list-entities))
    (local produced [])
    (each [_ entity (ipairs entities)]
      (local label (make-entity-label entity))
      (table.insert produced [entity label]))
    produced)

  (fn emit-items [self]
    (local items (collect-items self))
    (self.items-changed:emit items)
    items)

  (set node.collect-items collect-items)
  (set node.emit-items emit-items)

  (set node.add-entity-node
       (fn [self entity]
         (local graph self.graph)
         (when (and graph entity entity.id)
           (local entity-node (LinkEntityNode {:entity-id entity.id
                                               :store self.store}))
           (graph:add-edge (GraphEdge {:source self
                                       :target entity-node})))))

  (set node.create-entity
       (fn [self opts]
         (local entity (self.store:create-entity opts))
         (self:emit-items)
         entity))

  (var created-handler nil)
  (var updated-handler nil)
  (var deleted-handler nil)

  (set created-handler
       (store.link-entity-created:connect
         (fn [_entity]
           (node:emit-items))))

  (set updated-handler
       (store.link-entity-updated:connect
         (fn [_entity]
           (node:emit-items))))

  (set deleted-handler
       (store.link-entity-deleted:connect
         (fn [_entity]
           (node:emit-items))))

  (set node.drop
       (fn [self]
         (when created-handler
           (store.link-entity-created:disconnect created-handler true)
           (set created-handler nil))
         (when updated-handler
           (store.link-entity-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (when deleted-handler
           (store.link-entity-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (self.items-changed:clear)))

  node)

LinkEntityListNode
