(local Activities (require :activities))
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

(fn resolve-context-activity [activity-id]
  (if (= activity-id nil)
      app.active-activity-id
      (Activities.resolve activity-id)))

(fn canvas-panel-target []
  (or (and app.canvas
           app.canvas.active-activity-slot
           app.canvas.active-activity-slot.visible?
           app.canvas.active-activity-slot)
      app.canvas))

(fn enrich-active-activity-context! [context]
  (if (and (= context.surface :canvas)
           app.activity-context-enricher
           (= (Activities.active-activity-id) context.activity))
      (do
        (app.activity-context-enricher context)
        context)
      context))

(fn build-context [event]
  (local surface (or app.active-interaction-surface :scene))
  (local activity
    (if (or (= surface :canvas) (= surface :scene))
        (resolve-context-activity
          app.active-activity-id)
        nil))
  (enrich-active-activity-context!
    {:event event
     :surface surface
     :activity activity
     :modifiers {:shift? (Modifiers.shift-held? (and event event.mod))
                 :ctrl? (Modifiers.ctrl-held? (and event event.mod))
                 :alt? (Modifiers.alt-held? (and event event.mod))}
     :engine app.engine
     :targets {:canvas (canvas-panel-target)
               :hud app.hud}
     :scene {:scene app.scene}
     :graph {:graph app.graph
             :graph-map app.graph-map
             :view app.graph-view}
     :drawing {}}))

(fn empty-context [surface opts]
  (local options (or opts {}))
  (local resolved-surface (or surface :scene))
  (local resolved-activity
    (if (or (= resolved-surface :canvas) (= resolved-surface :scene))
        (resolve-context-activity
          (or options.activity
              app.active-activity-id))
        nil))
  (local targets-defaults {:canvas (canvas-panel-target)
                           :hud app.hud})
  (local scene-defaults {:scene app.scene})
  (local graph-defaults {:graph app.graph
                         :graph-map app.graph-map
                         :view (or (and options.graph options.graph.view)
                                   app.graph-view)})
  (enrich-active-activity-context!
    {:event (or options.event nil)
     :surface resolved-surface
     :activity (if (or (= resolved-surface :canvas)
                       (= resolved-surface :scene))
                  resolved-activity
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
                  :activity raw.activity
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

(fn activity-root-actions [context]
  (if (and app.activity-root-actions
           (= (Activities.active-activity-id) context.activity))
      (app.activity-root-actions context)
      []))

(fn activity-selection-actions [context]
  (if (and app.activity-selection-actions
           (= (Activities.active-activity-id) context.activity))
      (app.activity-selection-actions context)
      []))

(local contributors
  [{:name :canvas-root
    :mode :replace
    :matches (fn [context]
               (= context.surface :canvas))
    :actions activity-root-actions}
   {:name :canvas-selection
    :mode :append
    :matches (fn [context]
               (= context.surface :canvas))
    :actions activity-selection-actions}
   {:name :scene-root
     :mode :replace
     :matches (fn [context]
                (= context.surface :scene))
     :actions activity-root-actions}
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
 :actions-for-surface actions-for-surface}
