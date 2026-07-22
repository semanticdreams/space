(fn selected-graph-nodes [view]
  (or (and view view.selection view.selection.selected-nodes)
      []))

(fn show-link-entities-for-selection [context]
  (local graph (and context.graph context.graph.graph))
  (when (not graph)
    (lua "return nil"))
  (local selected (or (and context.graph context.graph.selected-nodes)
                      []))
  (when (<= (length selected) 0)
    (lua "return nil"))

  (local selected-keys {})
  (each [_ node (ipairs selected)]
    (local key (and node node.key))
    (when key
      (set (. selected-keys (tostring key)) true)))
  (when (= (next selected-keys) nil)
    (lua "return nil"))

  (local LinkEntityStore (require :entities/link))
  (local store (LinkEntityStore.get-default))
  (local {:LinkEntityNode LinkEntityNode} (require :graph/nodes/link-entity))
  (local entities (store:list-entities))
  (each [_ entity (ipairs (or entities []))]
    (local source-key (tostring (or (and entity entity.source-key) "")))
    (local target-key (tostring (or (and entity entity.target-key) "")))
    (local entity-keys {source-key true target-key true})
    (var all-match true)
    (each [k _ (pairs selected-keys) &until (not all-match)]
      (when (not (. entity-keys k))
        (set all-match false)))
    (when all-match
      (local id (tostring (or (and entity entity.id) "")))
      (when (> (string.len id) 0)
        (local key (.. "link-entity:" id))
        (when (not (graph:lookup key))
          (graph:add-node (LinkEntityNode {:entity-id id
                                           :store store}))))))
  nil)

(fn graph-root-actions [context]
  (local actions [])
  (local graph (and context.graph context.graph.graph))
  (local selected (or (and context.graph context.graph.selected-nodes) []))
  (local canvas-target (or (and context.targets context.targets.canvas)
                           (and context.targets context.targets.hud)))
    (table.insert actions
                 {:name "Create String Entity"
                  :icon "note_add"
                  :fn (fn [_button _event]
                        (local StringEntityStore (require :entities/string))
                        (local store (StringEntityStore.get-default))
                        (store:create-entity {}))})
  (table.insert actions
                {:name "Create Link Entity"
                 :icon "link"
                 :fn (fn [_button _event]
                       (local LinkEntityStore (require :entities/link))
                       (local store (LinkEntityStore.get-default))
                       (local opts {})
                       (when (= (length selected) 2)
                         (set opts.source-key (or (. selected 1 :key) ""))
                         (set opts.target-key (or (. selected 2 :key) ""))
                         nil)
                       (local entity (store:create-entity opts))
                       (when (and graph entity)
                         (local {:LinkEntityNode LinkEntityNode} (require :graph/nodes/link-entity))
                         (local node (LinkEntityNode {:entity-id entity.id
                                                      :store store}))
                         (graph:add-node node)))})
  (table.insert actions
                {:name "Show link entities"
                 :icon "link"
                 :fn (fn [_button _event]
                       (show-link-entities-for-selection context))})
  (table.insert actions
                {:name "Create List Entity"
                 :icon "playlist_add"
                 :fn (fn [_button _event]
                       (local ListEntityStore (require :entities/list))
                       (local store (ListEntityStore.get-default))
                       (local items [])
                       (each [_ node (ipairs selected)]
                         (when (and node node.key)
                           (table.insert items node.key)))
                       (local entity (store:create-entity {:items items}))
                       (when (and graph entity)
                         (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
                         (local node (ListEntityNode {:entity-id entity.id
                                                      :store store}))
                         (graph:add-node node)))})
  (table.insert actions
                {:name "Graph Control"
                 :icon "tune"
                 :fn (fn [_button _event]
                       (local launchable (require :launchables/graph-control))
                       (launchable.open-panel {:target canvas-target}))})
  actions)

{:selected-graph-nodes selected-graph-nodes
 :graph-root-actions graph-root-actions}
