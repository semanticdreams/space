(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local CodeEntityStore (require :entities/code))
(local Utils (require :graph/view/utils))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local CODE_BLUE (glm.vec4 0.2 0.35 0.85 1))
(local CODE_BLUE_ACCENT (glm.vec4 0.3 0.45 0.9 1))

(local SCHEME "code-entity")
(local KEY_PREFIX (KeyLoaderUtils.key-prefix SCHEME))

(fn make-label [entity]
  (local name (or (and entity entity.name) ""))
  (if (> (string.len name) 0)
      (Utils.truncate-with-ellipsis name 50)
      (do
        (local language (or (and entity entity.language) "fnl"))
        (.. "code (" language ")"))))

(fn CodeEntityNode [opts]
  (local options (or opts {}))
  (local entity-id (assert options.entity-id "CodeEntityNode requires entity-id"))
  (local store (or options.store (CodeEntityStore.get-default)))
  (local CodeEntityNodeView (require :graph/view/views/code-entity))

  (local entity (store:get-entity entity-id))
  (local initial-label (make-label entity))

  (local node
    (GraphNode {:key (.. KEY_PREFIX entity-id)
                :label initial-label
                :color CODE_BLUE
                :sub-color CODE_BLUE_ACCENT
                :size 8.0
                :view CodeEntityNodeView}))

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

  (set node.update-name
       (fn [self new-name]
         (self.store:update-entity self.entity-id {:name new-name})
         (self:refresh-label)))

  (set node.update-language
       (fn [self new-language]
         (self.store:update-entity self.entity-id {:language new-language})
         (self:refresh-label)))

  (set node.update-source
       (fn [self new-source]
         (self.store:update-entity self.entity-id {:source new-source})
         (self:refresh-label)))

  (set node.delete-entity
       (fn [self]
         (self.store:delete-entity self.entity-id)))

  (set node.actions
       [{:name "Delete Entity"
         :icon "delete"
         :fn (fn [_button _event]
                 (node:delete-entity))}])

  (var deleted-handler nil)
  (var updated-handler nil)

  (set deleted-handler
       (store.code-entity-deleted:connect
         (fn [deleted]
           (when (= (tostring deleted.id) (tostring entity-id))
             (node.entity-deleted:emit deleted)
             (when (and node.graph node.graph.remove-nodes)
               (node.graph:remove-nodes [node]))))))

  (set updated-handler
       (store.code-entity-updated:connect
         (fn [updated]
           (when (= (tostring updated.id) (tostring entity-id))
             (node:refresh-label)))))

  (set node.drop
       (fn [self]
         (when deleted-handler
           (store.code-entity-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when updated-handler
           (store.code-entity-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (self.entity-deleted:clear)
         (when self.changed
           (self.changed:clear))))

  node)

(local register-loader
  (KeyLoaderUtils.make-register-loader SCHEME
    CodeEntityStore.get-default
    (fn [entity-id store]
      (CodeEntityNode {:entity-id entity-id :store store}))))

{:CodeEntityNode CodeEntityNode
 :register-loader register-loader}
