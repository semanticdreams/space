(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local ListEntityStore (require :entities/list))
(local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
(local Utils (require :graph/view/utils))

(local CYAN (glm.vec4 0.0 0.6 0.7 1))
(local CYAN_ACCENT (glm.vec4 0.05 0.65 0.75 1))

(fn item-count-label [entity]
  (local count (length (or (and entity entity.items) [])))
  (if (= count 1) "1 item" (.. count " items")))

(fn make-entity-label [entity]
  (local name (or (and entity entity.name) ""))
  (local id (or (and entity entity.id) "unknown"))
  (local base
    (if (> (string.len name) 0)
        name
        id))
  (.. (Utils.truncate-with-ellipsis base 45) " (" (item-count-label entity) ")"))

(fn ListEntityListNode [opts]
  (local options (or opts {}))
  (local store (or options.store (ListEntityStore.get-default)))
  (local ListEntityListNodeView (require :graph/view/views/list-entity-list))

  (local node
    (GraphNode {:key "list-entity-list"
                :label "list entities"
                :color CYAN
                :sub-color CYAN_ACCENT
                :size 8.0
                :view ListEntityListNodeView}))

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
           (local entity-node (ListEntityNode {:entity-id entity.id
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
  (var items-handler nil)

  (set created-handler
       (store.list-entity-created:connect
         (fn [_entity]
           (node:emit-items))))

  (set updated-handler
       (store.list-entity-updated:connect
         (fn [_entity]
           (node:emit-items))))

  (set deleted-handler
       (store.list-entity-deleted:connect
         (fn [_entity]
           (node:emit-items))))

  (set items-handler
       (store.list-entity-items-changed:connect
         (fn [_payload]
           (node:emit-items))))

  (set node.drop
       (fn [self]
         (when created-handler
           (store.list-entity-created:disconnect created-handler true)
           (set created-handler nil))
         (when updated-handler
           (store.list-entity-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (when deleted-handler
           (store.list-entity-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when items-handler
           (store.list-entity-items-changed:disconnect items-handler true)
           (set items-handler nil))
         (self.items-changed:clear)))

  node)

ListEntityListNode
