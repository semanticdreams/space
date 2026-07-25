(local LlmConversationMessagesView (require :llm-conversation-messages-view))
(local PanelUtils (require :target-panel-utils))

(local kind "llm-conversation-messages-view-dialog")
(local restorer-module "graph/view/views/llm-conversation-messages-dialog")
(local panel-tokens {})

(fn remove-extra-panel-entry! [node-key graph-map-id]
    (assert graph-map-id "llm-conversation-messages-view-dialog requires graph-map-id for persistence cleanup")
    (when (and app.graph-view app.graph-view.remove-extra-panel-entry!)
        (app.graph-view:remove-extra-panel-entry! kind node-key graph-map-id)))

(fn target-kind-for [target]
    (if (= target app.hud) "hud"
        (= target app.scene) "scene"
        "canvas"))

(fn make-persistence [key graph-map-id]
    {:kind kind
     :node-key key
     :graph-map-id graph-map-id
     :restorer-module restorer-module})

(fn make-extra-panel-entry [key graph-map-id target panel]
    (local entry (make-persistence key graph-map-id))
    (set entry.target-kind (target-kind-for target))
    (set entry.panel panel)
    entry)

(fn register-extra-panel-state! [target element key graph-map-id panel]
    (when (and app.graph-view app.graph-view.register-extra-panel!)
        (app.graph-view:register-extra-panel!
          (make-extra-panel-entry key graph-map-id target panel)
          target
          element)))

(fn open-panel [opts]
  (local options (or opts {}))
  (local target (assert (or options.hud options.target)
                        "Llm conversation messages dialog requires target"))
  (local raw-panel (or options.panel {}))
  ;; If called from graph-view restore, layout is nested at raw-panel.panel.
  (local panel (or raw-panel.panel raw-panel))
  (local key
    (or raw-panel.node-key
        options.node-key
        (PanelUtils.assert-string-field panel :node-key
                                        "llm-conversation-messages-view-dialog requires string :node-key")))
  (fn graph-map-of [maybe-target]
      (and maybe-target maybe-target.graph-map))
  (local graph (or options.graph
                   (graph-map-of target)
                   (graph-map-of options.scene)
                   (graph-map-of options.canvas)
                   app.graph-map
                   (and app.active-world-runtime app.active-world-runtime.graph-map)))
  (assert graph "llm-conversation-messages-view-dialog requires graph")
  (when options.restore?
      (when (and raw-panel.graph-map-id graph.id
                  (not= raw-panel.graph-map-id graph.id))
          (lua "return nil")))
  (local graph-id (or raw-panel.graph-map-id (and graph graph.id) "main"))
  (local node
    (or options.node
        (and graph.lookup (graph:lookup key))
        (if options.restore?
            nil
            (and graph.load-by-key (graph:load-by-key key)))))
  (when (not node)
      (if options.restore?
          (do
              (register-extra-panel-state! target nil key graph-id panel)
              (lua "return nil"))
          (error (.. "llm-conversation-messages-view-dialog missing node: " key))))
  ;; Generate a stale-close token so only the last-opened panel's close handler removes metadata.
  (local token-composite (.. (or graph-id "unknown") ":" key))
  (local token (+ (or (. panel-tokens token-composite) 0) 1))
  (local placement (PanelUtils.panel-placement-options target panel))
  (local element
         (target:add-panel-child {:builder (LlmConversationMessagesView {:node node})
                                  :builder-options {:on-close (fn [_dialog _button _event]
                                                                  (when (= token (. panel-tokens token-composite))
                                                                      (remove-extra-panel-entry! key graph-id)))}
                                  :location placement.location
                                  :align-x placement.align-x
                                   :align-y placement.align-y
                                   :position placement.position
                                   :rotation placement.rotation
                                   :size placement.size
                                   :persistence (make-persistence key graph-id)}))
  (when (not element)
      (lua "return nil"))
  (set (. panel-tokens token-composite) token)
  ;; Store in per-map graph-view persistence so panels survive map switches.
  (local panel-state (when target.capture-panel-element-state
                         (target:capture-panel-element-state element)))
  (register-extra-panel-state! target element key graph-id panel-state)
  element)

(fn restore [opts]
  ;; Panels are managed per-map via graph-view extra-panels.
  ;; Record stale panels there so they survive across saves.
  (when (and app.graph-view app.graph-view.register-extra-panel!)
      (local options (or opts {}))
      (local panel (or options.panel {}))
      (local graph-map-id (assert panel.graph-map-id
                                  "llm-conversation-messages-view-dialog restore requires graph-map-id"))
      (app.graph-view:register-extra-panel!
        {:kind kind
         :node-key panel.node-key
         :graph-map-id graph-map-id
         :restorer-module restorer-module
         :target-kind (if (and options.hud) "hud"
                         (and options.scene) "scene"
                         "canvas")
         :panel panel}))
  nil)

{:kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore}
