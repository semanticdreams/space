(local Ball (require :ball))
(local SceneTerrainRecovery (require :scene-terrain-recovery))
(local CanvasModes (require :canvas-modes))
(local Modifiers (require :input-modifiers))

(fn append-actions [target source]
  (each [_ action (ipairs (or source []))]
    (table.insert target action))
  target)

(fn merge-context-part [defaults overrides]
  (local merged {})
  (each [k v (pairs (or defaults {}))]
    (set (. merged k) v))
  (when (= (type overrides) :table)
    (each [k v (pairs overrides)]
      (set (. merged k) v)))
  merged)

(fn resolve-context-canvas-mode [mode-id]
  (if (= mode-id nil)
      app.active-canvas-mode
      (CanvasModes.resolve mode-id)))

(fn enrich-active-canvas-context! [context]
  (if (and (= context.surface :canvas)
           app.canvas-mode-context-enricher
           (= (CanvasModes.active-mode-id) context.canvas-mode))
      (do
        (app.canvas-mode-context-enricher context)
        context)
      context))

(fn build-context [event]
  (local surface (or app.active-interaction-surface :scene))
  (local canvas-mode
    (if (= surface :canvas)
        (resolve-context-canvas-mode
          app.active-canvas-mode)
        nil))
  (enrich-active-canvas-context!
    {:event event
     :surface surface
     :canvas-mode canvas-mode
     :modifiers {:shift? (Modifiers.shift-held? (and event event.mod))
                 :ctrl? (Modifiers.ctrl-held? (and event event.mod))
                 :alt? (Modifiers.alt-held? (and event event.mod))}
     :engine app.engine
     :targets {:canvas app.canvas
               :hud app.hud}
     :scene {:scene app.scene}
     :graph {:graph app.graph
             :graph-map app.graph-map
             :view app.graph-view}
     :drawing {}}))

(fn empty-context [surface opts]
  (local options (or opts {}))
  (local resolved-surface (or surface :scene))
  (local resolved-canvas-mode
    (if (= resolved-surface :canvas)
        (resolve-context-canvas-mode
          (or options.canvas-mode
              app.active-canvas-mode))
        nil))
  (local targets-defaults {:canvas app.canvas
                           :hud app.hud})
  (local scene-defaults {:scene app.scene})
  (local graph-defaults {:graph app.graph
                         :graph-map app.graph-map
                         :view (or (and options.graph options.graph.view)
                                   app.graph-view)})
  (enrich-active-canvas-context!
    {:event (or options.event nil)
     :surface resolved-surface
     :canvas-mode (if (= resolved-surface :canvas)
                      resolved-canvas-mode
                      nil)
     :modifiers (merge-context-part {:shift? false
                                     :ctrl? false
                                     :alt? false}
                                    options.modifiers)
     :engine (or options.engine app.engine)
     :targets (merge-context-part targets-defaults options.targets)
     :scene (merge-context-part scene-defaults options.scene)
     :graph (merge-context-part graph-defaults options.graph)
     :drawing (merge-context-part {} options.drawing)}))

(fn normalize-context [context]
  (local raw (or context {}))
  (empty-context (or raw.surface :scene)
                 {:event raw.event
                  :canvas-mode raw.canvas-mode
                  :modifiers raw.modifiers
                  :engine raw.engine
                  :targets raw.targets
                  :scene raw.scene
                  :graph raw.graph
                  :drawing raw.drawing}))

(fn shared-root-actions [context]
  [{:name "Quit"
    :icon "exit_to_app"
    :fn (fn [_button _event]
          (local engine context.engine)
          (when (and engine engine.quit)
            (engine.quit)))}])

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

(fn canvas-mode-root-actions [context]
  (if (and app.canvas-mode-root-actions
           (= (CanvasModes.active-mode-id) context.canvas-mode))
      (app.canvas-mode-root-actions context)
      []))

(fn canvas-mode-selection-actions [context]
  (if (and app.canvas-mode-selection-actions
           (= (CanvasModes.active-mode-id) context.canvas-mode))
      (app.canvas-mode-selection-actions context)
      []))

(local contributors
  [{:name :canvas-root
    :mode :replace
    :matches (fn [context]
               (= context.surface :canvas))
    :actions canvas-mode-root-actions}
   {:name :canvas-selection
    :mode :append
    :matches (fn [context]
               (= context.surface :canvas))
    :actions canvas-mode-selection-actions}
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
 :scene-root-actions scene-root-actions}
