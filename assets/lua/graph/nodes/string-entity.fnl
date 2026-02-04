(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local StringEntityStore (require :entities/string))
(local Utils (require :graph/view/utils))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local DARK_BLUE (glm.vec4 0.1 0.2 0.5 1))
(local DARK_BLUE_ACCENT (glm.vec4 0.15 0.25 0.55 1))

(local SCHEME "string-entity")
(local KEY_PREFIX (KeyLoaderUtils.key-prefix SCHEME))

(fn make-label [entity]
  (if (and entity entity.value (> (string.len entity.value) 0))
      (Utils.truncate-with-ellipsis entity.value 50)
      (or (and entity entity.id) "string entity")))

(fn StringEntityNode [opts]
  (local options (or opts {}))
  (local entity-id (assert options.entity-id "StringEntityNode requires entity-id"))
  (local store (or options.store (StringEntityStore.get-default)))
  (local StringEntityNodeView (require :graph/view/views/string-entity))

  (local entity (store:get-entity entity-id))
  (local initial-label (make-label entity))

  (local node
    (GraphNode {:key (.. KEY_PREFIX entity-id)
                :label initial-label
                :color DARK_BLUE
                :sub-color DARK_BLUE_ACCENT
                :size 8.0
                :view StringEntityNodeView}))

  (set node.entity-id entity-id)
  (set node.store store)
  (set node.entity-deleted (Signal))
  (set node.changed (Signal))

  (fn refresh-label [self]
    (local current (self.store:get-entity self.entity-id))
    (set self.label (make-label current))
    (when self.changed
      (self.changed:emit self)))

  (set node.refresh-label refresh-label)

  (set node.get-entity
       (fn [self]
         (self.store:get-entity self.entity-id)))

  (set node.update-value
       (fn [self new-value]
         (self.store:update-entity self.entity-id {:value new-value})
         (self:refresh-label)))

  (set node.delete-entity
       (fn [self]
         (self.store:delete-entity self.entity-id)))

  (var deleted-handler nil)
  (var updated-handler nil)

  (set deleted-handler
       (store.string-entity-deleted:connect
         (fn [deleted]
           (when (= (tostring deleted.id) (tostring entity-id))
             (node.entity-deleted:emit deleted)
             (when (and node.graph node.graph.remove-nodes)
               (node.graph:remove-nodes [node]))))))

  (set updated-handler
       (store.string-entity-updated:connect
         (fn [updated]
           (when (= (tostring updated.id) (tostring entity-id))
             (node:refresh-label)))))

  (set node.drop
       (fn [self]
         (when deleted-handler
           (store.string-entity-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when updated-handler
           (store.string-entity-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (self.entity-deleted:clear)
         (when self.changed
           (self.changed:clear))))

  node)

(local register-loader
  (KeyLoaderUtils.make-register-loader SCHEME
    StringEntityStore.get-default
    (fn [entity-id store]
      (StringEntityNode {:entity-id entity-id :store store}))))

{:StringEntityNode StringEntityNode
 :register-loader register-loader}
