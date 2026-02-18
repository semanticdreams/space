(local glm (require :glm))
(local {:GraphNode GraphNode
        :node-id node-id} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local NotebookStore (require :notebooks/store))
(local StringEntityStore (require :entities/string))
(local {:StringEntityNode StringEntityNode} (require :graph/nodes/string-entity))
(local Utils (require :graph/view/utils))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local BLUE (glm.vec4 0.35 0.45 0.9 1))
(local BLUE_ACCENT (glm.vec4 0.45 0.55 0.95 1))

(local SCHEME "notebook")
(local KEY_PREFIX (KeyLoaderUtils.key-prefix SCHEME))
(local STRING_ENTITY_KEY_PREFIX (KeyLoaderUtils.key-prefix "string-entity"))

(fn make-label [notebook]
  (local name (or (and notebook notebook.name) ""))
  (if (> (string.len name) 0)
      (Utils.truncate-with-ellipsis name 50)
      (Utils.truncate-with-ellipsis (or (and notebook notebook.id) "notebook") 50)))

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

(fn notebook-contains-node-key? [notebook node-key]
  (local key (tostring node-key))
  (var found? false)
  (each [_ value (ipairs (or (and notebook notebook.items) []))]
    (when (= (tostring value) key)
      (set found? true)))
  found?)

(fn NotebookNode [opts]
  (local options (or opts {}))
  (local notebook-id (assert options.notebook-id "NotebookNode requires notebook-id"))
  (local store (or options.store (NotebookStore.get-default)))
  (local string-store (or options.string-store (StringEntityStore.get-default)))
  (local NotebookNodeView (require :graph/view/views/notebook))

  (local notebook (store:get-notebook notebook-id))
  (local initial-label (make-label notebook))

  (local node
    (GraphNode {:key (.. KEY_PREFIX notebook-id)
                :label initial-label
                :color BLUE
                :sub-color BLUE_ACCENT
                :size 8.0
                :view NotebookNodeView}))

  (set node.notebook-id notebook-id)
  (set node.store store)
  (set node.string-store string-store)
  (set node.notebook-deleted (Signal))
  (set node.changed (Signal))
  (set node.items-changed (Signal))
  (set node.notebook-item-edge-keys {})

  (fn refresh-label [self]
    (local current (self.store:get-notebook self.notebook-id))
    (set self.label (make-label current))
    (when self.changed
      (self.changed:emit self)))

  (set node.refresh-label refresh-label)

  (set node.get-notebook
       (fn [self]
         (self.store:get-notebook self.notebook-id)))

  (set node.add-item-nodes
       (fn [self]
         (local graph self.graph)
         (when (and graph graph.load-by-key graph.add-edge)
           (local current (self:get-notebook))
           (local items (or (and current current.items) []))
           (local desired {})
           (each [_ item-key (ipairs items)]
             (local target (or (graph:lookup item-key)
                               (graph:load-by-key item-key)))
             (when target
               (graph:add-edge (GraphEdge {:source self :target target})
                               {:from-notebook self.notebook-id})
               (set (. desired (edge-key self target)) true)))
           (each [k _ (pairs (or self.notebook-item-edge-keys {}))]
             (when (not (. desired k))
               (remove-edge-by-key graph k)))
           (set self.notebook-item-edge-keys desired))))

  (set node.update-name
       (fn [self new-name]
         (self.store:update-notebook self.notebook-id {:name new-name})
         (self:refresh-label)))

  (set node.add-item
       (fn [self node-key]
         (self.store:add-item self.notebook-id node-key)
         (self:add-item-nodes)))

  (set node.remove-item
       (fn [self node-key]
         (self.store:remove-item self.notebook-id node-key)
         (self:add-item-nodes)))

  (set node.move-item
       (fn [self from-index to-index]
         (self.store:move-item self.notebook-id from-index to-index)
         (self:add-item-nodes)))

  (set node.delete-notebook
       (fn [self]
         (self.store:delete-notebook self.notebook-id)))

  (set node.add-string-entity
       (fn [self opts]
         (local entity (self.string-store:create-entity (or opts {})))
         (local entity-key (.. STRING_ENTITY_KEY_PREFIX (tostring entity.id)))
         (self:add-item entity-key)
         (local graph self.graph)
         (when (and graph (not (graph:lookup entity-key)))
           (local entity-node (StringEntityNode {:entity-id entity.id
                                                 :store self.string-store}))
           (graph:add-edge (GraphEdge {:source self :target entity-node})
                           {:from-notebook self.notebook-id})
           (set (. self.notebook-item-edge-keys (edge-key self entity-node)) true))
         entity))

  (set node.actions
       [{:name "Refresh Items"
         :icon "refresh"
         :fn (fn [_button _event]
                 (node:add-item-nodes))}
        {:name "Add String Entity"
         :icon "add"
         :fn (fn [_button _event]
                 (node:add-string-entity {}))}
        {:name "Delete Notebook"
         :icon "delete"
         :fn (fn [_button _event]
               (node:delete-notebook))}])

  (var deleted-handler nil)
  (var updated-handler nil)
  (var items-handler nil)

  (set deleted-handler
       (store.notebook-deleted:connect
         (fn [deleted]
           (when (= (tostring deleted.id) (tostring notebook-id))
             (node.notebook-deleted:emit deleted)
             (when (and node.graph node.graph.remove-nodes)
               (node.graph:remove-nodes [node]))))))

  (set updated-handler
       (store.notebook-updated:connect
         (fn [updated]
           (when (= (tostring updated.id) (tostring notebook-id))
             (node:refresh-label)))))

  (fn handle-items-changed [payload]
    (local id (or (and payload payload.id) ""))
    (when (= (tostring id) (tostring notebook-id))
      (node.items-changed:emit payload)
      (node:add-item-nodes)))

  (set items-handler
       (store.notebook-items-changed:connect handle-items-changed))

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
         ;; Connect notebook item edges when matching nodes are added later.
         (when (and signal (not graph-node-added-handler))
           (set graph-node-added-signal signal)
           (set graph-node-added-handler
                (signal:connect
                  (fn [payload]
                    (local added (and payload payload.node))
                    (when (and added (not (= (tostring added.key) (tostring self.key))))
                      (local notebook (self:get-notebook))
                      (when (and notebook (notebook-contains-node-key? notebook added.key))
                        (self:add-item-nodes)))))))
         self))

  (set node.drop
       (fn [self]
         (when (and graph-node-added-signal graph-node-added-handler)
           (graph-node-added-signal:disconnect graph-node-added-handler true)
           (set graph-node-added-handler nil))
         (when deleted-handler
           (store.notebook-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when updated-handler
           (store.notebook-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (when items-handler
           (store.notebook-items-changed:disconnect items-handler true)
           (set items-handler nil))
         (self.notebook-deleted:clear)
         (self.items-changed:clear)
         (when self.changed
           (self.changed:clear))))

  node)

(local register-loader
  (fn [graph opts]
    (local options (or opts {}))
    (local store (or options.store (NotebookStore.get-default)))
    (graph:register-key-loader SCHEME
      (fn [key]
        (local notebook-id (KeyLoaderUtils.extract-id SCHEME key))
        (when notebook-id
          (local notebook (store:get-notebook notebook-id))
          (when notebook
            (NotebookNode {:notebook-id notebook-id
                           :store store})))))))

{:NotebookNode NotebookNode
 :register-loader register-loader}
