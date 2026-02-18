(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local NotebookStore (require :notebooks/store))
(local {:NotebookNode NotebookNode} (require :graph/nodes/notebook))
(local Utils (require :graph/view/utils))

(local BLUE (glm.vec4 0.35 0.45 0.9 1))
(local BLUE_ACCENT (glm.vec4 0.45 0.55 0.95 1))

(fn notebook-label [notebook]
  (local name (or (and notebook notebook.name) ""))
  (local id (or (and notebook notebook.id) "unknown"))
  (local base (if (> (string.len name) 0) name id))
  (Utils.truncate-with-ellipsis base 50))

(fn NotebooksNode [opts]
  (local options (or opts {}))
  (local store (or options.store (NotebookStore.get-default)))
  (local NotebooksNodeView (require :graph/view/views/notebooks))

  (local node
    (GraphNode {:key "notebooks"
                :label "notebooks"
                :color BLUE
                :sub-color BLUE_ACCENT
                :size 8.0
                :view NotebooksNodeView}))

  (set node.store store)
  (set node.items-changed (Signal))

  (fn collect-items [self]
    (local notebooks (self.store:list-notebooks))
    (local produced [])
    (each [_ notebook (ipairs notebooks)]
      (table.insert produced [notebook (notebook-label notebook)]))
    produced)

  (fn emit-items [self]
    (local items (collect-items self))
    (self.items-changed:emit items)
    items)

  (set node.collect-items collect-items)
  (set node.emit-items emit-items)

  (set node.add-notebook-node
       (fn [self notebook]
         (local graph self.graph)
         (when (and graph notebook notebook.id)
           (local notebook-node (NotebookNode {:notebook-id notebook.id
                                               :store self.store}))
           (graph:add-edge (GraphEdge {:source self
                                       :target notebook-node})))))

  (set node.create-notebook
       (fn [self opts]
         (local notebook (self.store:create-notebook opts))
         (self:emit-items)
         notebook))

  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
               (node:emit-items))}
        {:name "New Notebook"
         :icon "add"
         :fn (fn [_button _event]
               (node:create-notebook {}))}])

  (var created-handler nil)
  (var updated-handler nil)
  (var deleted-handler nil)
  (var items-handler nil)

  (set created-handler
       (store.notebook-created:connect
         (fn [_notebook]
           (node:emit-items))))

  (set updated-handler
       (store.notebook-updated:connect
         (fn [_notebook]
           (node:emit-items))))

  (set deleted-handler
       (store.notebook-deleted:connect
         (fn [_notebook]
           (node:emit-items))))

  (set items-handler
       (store.notebook-items-changed:connect
         (fn [_payload]
           (node:emit-items))))

  (set node.drop
       (fn [self]
         (when created-handler
           (store.notebook-created:disconnect created-handler true)
           (set created-handler nil))
         (when updated-handler
           (store.notebook-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (when deleted-handler
           (store.notebook-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when items-handler
           (store.notebook-items-changed:disconnect items-handler true)
           (set items-handler nil))
         (self.items-changed:clear)))

  node)

NotebooksNode
