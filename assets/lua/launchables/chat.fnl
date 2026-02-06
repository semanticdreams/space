(local LlmChatView (require :llm-chat-view))

{:name "Chat"
 :run (fn []
        (assert (and app.hud app.hud.add-panel-child) "Chat launchable requires app.hud.add-panel-child")
        (app.hud:add-panel-child {:builder (LlmChatView {})}))}
