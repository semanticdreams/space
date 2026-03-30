(local Ball (require :ball))
(local SceneTerrainRecovery (require :scene-terrain-recovery))

(fn show-link-entities-for-selection []
  (local graph app.graph)
  (when (not graph)
    (lua "return nil"))
  (local view app.graph-view)
  (local selected (or (and view view.selection view.selection.selected-nodes)
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

(fn default-root-actions []
  (local actions [])
  (table.insert actions
                {:name "Create String Entity"
                 :icon "note_add"
                 :fn (fn [_button _event]
                       (local StringEntityStore (require :entities/string))
                       (local store (StringEntityStore.get-default))
                       (local entity (store:create-entity {}))
                       (when (and app.graph entity)
                         (local {:StringEntityNode StringEntityNode} (require :graph/nodes/string-entity))
                         (local node (StringEntityNode {:entity-id entity.id
                                                        :store store}))
                         (app.graph:add-node node)))})
  (table.insert actions
                {:name "Create Link Entity"
                 :icon "link"
                 :fn (fn [_button _event]
                       (local LinkEntityStore (require :entities/link))
                       (local store (LinkEntityStore.get-default))
                       (local selected (or (and app.graph-view
                                                app.graph-view.selection
                                                app.graph-view.selection.selected-nodes)
                                           []))
                       (local opts {})
                       (when (= (length selected) 2)
                         (set opts.source-key (or (. selected 1 :key) ""))
                         (set opts.target-key (or (. selected 2 :key) "")))
                       (local entity (store:create-entity opts))
                       (when (and app.graph entity)
                         (local {:LinkEntityNode LinkEntityNode} (require :graph/nodes/link-entity))
                         (local node (LinkEntityNode {:entity-id entity.id
                                                      :store store}))
                         (app.graph:add-node node)))})
  (table.insert actions
                {:name "Show link entities"
                 :icon "link"
                 :fn (fn [_button _event]
                       (show-link-entities-for-selection))})
  (table.insert actions
                {:name "Create List Entity"
                 :icon "playlist_add"
                 :fn (fn [_button _event]
                       (local ListEntityStore (require :entities/list))
                       (local store (ListEntityStore.get-default))
                       (local selected (or (and app.graph-view
                                                app.graph-view.selection
                                                app.graph-view.selection.selected-nodes)
                                           []))
                       (local items [])
                       (each [_ node (ipairs selected)]
                         (when (and node node.key)
                           (table.insert items node.key)))
                       (local entity (store:create-entity {:items items}))
                       (when (and app.graph entity)
                         (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
                         (local node (ListEntityNode {:entity-id entity.id
                                                      :store store}))
                         (app.graph:add-node node)))})

  (table.insert actions
                {:name "Demo Browser"
                 :fn (fn [_button _event]
                       (local scene app.scene)
                       (when (and scene scene.add-demo-browser)
                         (scene:add-demo-browser)))})
  (table.insert actions
                {:name "Demo Video Player"
                 :fn (fn [_button _event]
                       (local launchable (require :launchables/demo-video-cube))
                       (launchable.open-panel {:scene app.scene}))})
  (table.insert actions
                {:name "add cuboid"
                 :fn (fn [_button _event]
                       (local scene app.scene)
                       (when (and scene scene.add-physics-body)
                         (scene:add-physics-body)))})
  (table.insert actions
                {:name "ball"
                 :fn (fn [_button _event]
                       (local scene app.scene)
                       (when (and scene scene.add-object)
                         (scene:add-object (Ball {}))))})
  (table.insert actions
                {:name "Add light ball"
                 :fn (fn [_button _event]
                       (local scene app.scene)
                       (when (and scene scene.add-light-ball)
                         (scene:add-light-ball {})))})
  (table.insert actions
                {:name "Recover Terrain-Bound Objects"
                 :fn (fn [_button _event]
                       (local scene app.scene)
                       (when scene
                         (SceneTerrainRecovery.recover scene)))})
  (table.insert actions
                {:name "Quit"
                 :icon "exit_to_app"
                 :fn (fn [_button _event]
                       (when (and app.engine app.engine.quit)
                         (app.engine.quit)))})
  actions)

{:default-root-actions default-root-actions}
