(local LlmConversationMessagesView (require :llm-conversation-messages-view))
(local Persistence (require :hud-panel-persistence))

(local kind "llm-conversation-messages-view-dialog")
(local restorer-module "graph/view/views/llm-conversation-messages-dialog")

(fn open-panel [opts]
  (local options (or opts {}))
  (local target (assert (or options.hud options.target)
                        "Llm conversation messages dialog requires HUD target"))
  (local panel (or options.panel {}))
  (local key
    (or options.node-key
        (Persistence.assert-string-field panel :node-key
                                         "llm-conversation-messages-view-dialog requires string :node-key")))
  (local graph (or options.graph (and app app.graph)))
  (assert graph "llm-conversation-messages-view-dialog requires graph")
  (local node
    (or options.node
        (and graph.lookup (graph:lookup key))
        (and graph.load-by-key (graph:load-by-key key))))
  (assert node
          (.. "llm-conversation-messages-view-dialog missing node: " key))
  (local placement (Persistence.panel-placement-options panel))
  (target:add-panel-child {:builder (LlmConversationMessagesView {:node node})
                           :location placement.location
                           :align-x placement.align-x
                           :align-y placement.align-y
                           :position placement.position
                           :rotation placement.rotation
                           :size placement.size
                           :persistence {:kind kind
                                         :node-key key
                                         :restorer-module restorer-module}}))

(fn restore [opts]
  (open-panel opts))

{:kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore}
