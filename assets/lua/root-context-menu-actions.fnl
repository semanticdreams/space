(local Ball (require :ball))
(local SceneTerrainRecovery (require :scene-terrain-recovery))
(local CanvasFeatures (require :canvas-features))
(local Modifiers (require :input-modifiers))

(fn append-actions [target source]
  (each [_ action (ipairs (or source []))]
    (table.insert target action))
  target)

(fn selected-graph-nodes [view]
  (or (and view view.selection view.selection.selected-nodes)
      []))

(fn merge-context-part [defaults overrides]
  (local merged {})
  (each [k v (pairs (or defaults {}))]
    (set (. merged k) v))
  (when (= (type overrides) :table)
    (each [k v (pairs overrides)]
      (set (. merged k) v)))
  merged)

(fn build-context [event]
  (local surface (or app.active-interaction-surface :scene))
  (local canvas-feature
    (if (= surface :canvas)
        (CanvasFeatures.resolve app.active-canvas-feature)
        nil))
  (local drawing-controller
    (if (and (= surface :canvas)
             (CanvasFeatures.supports-drawing-controller? canvas-feature))
        app.drawing-controller
        nil))
  (local active-layer
    (and drawing-controller drawing-controller.active-layer
         (drawing-controller:active-layer)))
  (local selection-count
    (if (and drawing-controller drawing-controller.selection-count)
        (drawing-controller:selection-count)
        0))
  (local layer-count
    (if (and drawing-controller drawing-controller.layer-count)
        (drawing-controller:layer-count)
        0))
  (local graph-view app.graph-view)
  {:event event
   :surface surface
   :canvas-feature canvas-feature
   :modifiers {:shift? (Modifiers.shift-held? (and event event.mod))
               :ctrl? (Modifiers.ctrl-held? (and event event.mod))
               :alt? (Modifiers.alt-held? (and event event.mod))}
   :engine app.engine
   :targets {:canvas app.canvas
             :hud app.hud}
   :scene {:scene app.scene}
   :graph {:graph app.graph
           :view graph-view
           :selected-nodes (selected-graph-nodes graph-view)}
   :drawing {:controller drawing-controller
             :active-layer active-layer
             :selection-count selection-count
             :layer-count layer-count
             :has-selection? (> selection-count 0)}})

(fn empty-context [surface opts]
  (local options (or opts {}))
  (local resolved-surface (or surface :scene))
  (local resolved-canvas-feature
    (if (= resolved-surface :canvas)
        (CanvasFeatures.resolve (or options.canvas-feature app.active-canvas-feature))
        nil))
  (local drawing-controller
    (if (and (= resolved-surface :canvas)
             (CanvasFeatures.supports-drawing-controller? resolved-canvas-feature))
        (or (and options.drawing options.drawing.controller)
            app.drawing-controller)
        nil))
  (local graph-view (or (and options.graph options.graph.view)
                        app.graph-view))
  (local targets-defaults {:canvas app.canvas
                           :hud app.hud})
  (local scene-defaults {:scene app.scene})
  (local graph-defaults {:graph app.graph
                         :view graph-view
                         :selected-nodes (selected-graph-nodes graph-view)})
  (local drawing-defaults
    {:controller drawing-controller
     :active-layer (and drawing-controller drawing-controller.active-layer
                        (drawing-controller:active-layer))
     :selection-count (if (and drawing-controller drawing-controller.selection-count)
                          (drawing-controller:selection-count)
                          0)
     :layer-count (if (and drawing-controller drawing-controller.layer-count)
                      (drawing-controller:layer-count)
                      0)
     :has-selection? (if (and drawing-controller drawing-controller.selection-count)
                         (> (drawing-controller:selection-count) 0)
                         false)})
  {:event (or options.event nil)
   :surface resolved-surface
   :canvas-feature (if (= resolved-surface :canvas)
                       resolved-canvas-feature
                       nil)
   :modifiers (merge-context-part {:shift? false
                                   :ctrl? false
                                   :alt? false}
                                  options.modifiers)
   :engine (or options.engine app.engine)
   :targets (merge-context-part targets-defaults options.targets)
   :scene (merge-context-part scene-defaults options.scene)
   :graph (merge-context-part graph-defaults options.graph)
   :drawing (merge-context-part drawing-defaults options.drawing)})

(fn normalize-context [context]
  (local raw (or context {}))
  (empty-context (or raw.surface :scene)
                 {:event raw.event
                  :canvas-feature raw.canvas-feature
                  :modifiers raw.modifiers
                  :engine raw.engine
                  :targets raw.targets
                  :scene raw.scene
                  :graph raw.graph
                  :drawing raw.drawing}))

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

(fn shared-root-actions [context]
  [{:name "Quit"
    :icon "exit_to_app"
    :fn (fn [_button _event]
          (local engine context.engine)
          (when (and engine engine.quit)
            (engine.quit)))}])

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
                       (local entity (store:create-entity {}))
                       (when (and graph entity)
                         (local {:StringEntityNode StringEntityNode} (require :graph/nodes/string-entity))
                         (local node (StringEntityNode {:entity-id entity.id
                                                        :store store}))
                         (graph:add-node node)))})
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

(fn drawing-root-actions [context]
  (local controller (and context.drawing context.drawing.controller))
  (local actions [])
  (when controller
    (table.insert actions
                  {:name "Add Vector Layer"
                   :icon "draw"
                   :fn (fn [_button _event]
                         (controller:add-layer "vector"))})
    (table.insert actions
                  {:name "Add Raster Layer"
                   :icon "brush"
                   :fn (fn [_button _event]
                         (controller:add-layer "raster"))})
    (table.insert actions
                  {:name "Duplicate Layer"
                   :icon "layers"
                   :fn (fn [_button _event]
                         (controller:duplicate-active-layer))})
    (when (> (or context.drawing.layer-count 0) 1)
      (table.insert actions
                    {:name "Delete Active Layer"
                     :icon "delete"
                     :variant :danger
                     :fn (fn [_button _event]
                           (controller:delete-active-layer))})))
  actions)

(fn drawing-selection-actions [context]
  (local controller (and context.drawing context.drawing.controller))
  (if (and controller
           context.drawing.has-selection?)
      [{:name "Delete Selection"
        :icon "delete"
        :variant :danger
        :fn (fn [_button _event]
              (controller:on-delete-selection))}]
      []))

(fn scene-root-actions [context]
  (local scene (and context.scene context.scene.scene))
  (local actions [])
  (table.insert actions
                {:name "Demo Browser"
                 :fn (fn [_button _event]
                       (when (and scene scene.add-demo-browser)
                         (scene:add-demo-browser)))})
  (table.insert actions
                {:name "Demo Video Player"
                 :fn (fn [_button _event]
                       (local launchable (require :launchables/demo-video-cube))
                       (launchable.open-panel {:scene scene}))})
  (table.insert actions
                {:name "add cuboid"
                 :fn (fn [_button _event]
                       (when (and scene scene.add-physics-body)
                         (scene:add-physics-body)))})
  (table.insert actions
                {:name "ball"
                 :fn (fn [_button _event]
                       (when (and scene scene.add-object)
                         (scene:add-object (Ball {}))))})
  (table.insert actions
                {:name "Add light ball"
                 :fn (fn [_button _event]
                       (when (and scene scene.add-light-ball)
                         (scene:add-light-ball {})))})
  (table.insert actions
                {:name "Recover Terrain-Bound Objects"
                 :fn (fn [_button _event]
                       (when scene
                         (SceneTerrainRecovery.recover scene)))})
  actions)

(local canvas-context-action-builders
  {:graph graph-root-actions
   :drawing drawing-root-actions
   :drawing-selection drawing-selection-actions})

(fn canvas-feature-action-builder [feature-spec key opts]
  (local options (or opts {}))
  (assert feature-spec "Canvas feature action dispatch requires feature spec")
  (local feature-id (. feature-spec :id))
  (local action-key (and feature-spec (. feature-spec key)))
  (when (and options.required?
             (not action-key))
    (error (.. "Canvas feature "
               feature-id
               " missing required "
               (tostring key)
               " metadata")))
  (if action-key
      (do
        (local builder (. canvas-context-action-builders action-key))
        (assert builder
                (.. "Canvas feature "
                    feature-id
                    " references unknown "
                    (tostring key)
                    " "
                    (tostring action-key)))
        builder)
      nil))

(fn validate-canvas-feature-action-builders []
  (each [_ feature-spec (ipairs (CanvasFeatures.feature-specs-in-order))]
    (canvas-feature-action-builder feature-spec :root-context-actions-key {:required? true})
    (canvas-feature-action-builder feature-spec :selection-context-actions-key))
  true)

(validate-canvas-feature-action-builders)

(fn canvas-feature-root-actions [context]
  (local feature-spec
    (if (= context.surface :canvas)
        (CanvasFeatures.spec context.canvas-feature)
        nil))
  (local builder
    (canvas-feature-action-builder feature-spec
                                   :root-context-actions-key
                                   {:required? true}))
  (builder context))

(fn canvas-feature-selection-actions [context]
  (local feature-spec
    (if (= context.surface :canvas)
        (CanvasFeatures.spec context.canvas-feature)
        nil))
  (local builder (canvas-feature-action-builder feature-spec :selection-context-actions-key))
  (if builder
      (builder context)
      []))

(local contributors
  [{:name :canvas-root
    :mode :replace
    :matches (fn [context]
               (= context.surface :canvas))
    :actions canvas-feature-root-actions}
   {:name :canvas-selection
    :mode :append
    :matches (fn [context]
               (= context.surface :canvas))
    :actions canvas-feature-selection-actions}
   {:name :scene-root
    :mode :replace
    :matches (fn [context]
               (= context.surface :scene))
    :actions scene-root-actions}
   {:name :shared
    :mode :append
    :matches (fn [_context] true)
    :actions shared-root-actions}])

(fn apply-contributor [actions contributor context]
  (local next-actions
    (if (= contributor.mode :replace)
        []
        actions))
  (append-actions next-actions (contributor.actions context)))

(fn actions-for-context [context]
  (local resolved-context (normalize-context context))
  (var actions [])
  (var stopped? false)
  (each [_ contributor (ipairs contributors) &until stopped?]
    (when (contributor.matches resolved-context)
      (set actions (apply-contributor actions contributor resolved-context))
      (when contributor.stop?
        (set stopped? true))))
  actions)

(fn actions-for-event [event]
  (actions-for-context (build-context event)))

(fn actions-for-surface [surface opts]
  (actions-for-context (empty-context surface opts)))

(fn default-root-actions []
  (actions-for-context (build-context nil)))

{:build-context build-context
 :empty-context empty-context
 :normalize-context normalize-context
 :default-root-actions default-root-actions
 :actions-for-event actions-for-event
 :actions-for-context actions-for-context
 :actions-for-surface actions-for-surface
 :validate-canvas-feature-action-builders validate-canvas-feature-action-builders
 :scene-root-actions scene-root-actions
 :graph-root-actions graph-root-actions
 :drawing-root-actions drawing-root-actions}
