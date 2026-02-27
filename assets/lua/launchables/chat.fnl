(local LlmChatView (require :llm-chat-view))
(local Persistence (require :hud-panel-persistence))

(local kind "llm-chat-view-dialog")
(local restorer-module "launchables/chat")

(fn open-panel [opts]
  (local options (or opts {}))
  (local target (assert (or options.hud options.target)
                        "Chat launchable requires HUD target"))
  (local placement (Persistence.panel-placement-options options.panel))
  (target:add-panel-child {:builder (LlmChatView {})
                           :location placement.location
                           :align-x placement.align-x
                           :align-y placement.align-y
                           :position placement.position
                           :rotation placement.rotation
                           :size placement.size
                           :persistence {:kind kind
                                         :restorer-module restorer-module}}))

(fn restore [opts]
  (open-panel opts))

{:name "Chat"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn []
        (open-panel {:hud app.hud}))}
