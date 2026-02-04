(local Button (require :button))

(fn QuitNodeView [node]
    (assert node "QuitNodeView requires a node")

    (fn resolve-handler []
        (local handler (or node.on-quit (and app.engine app.engine.quit)))
        (assert (= (type handler) :function) "QuitNodeView requires a quit handler")
        handler)

    (fn build [ctx]
        (local view {:node node})

        (fn perform-quit [_self]
            ((resolve-handler)))

        (local button
            ((Button {:text "Quit"
                      :on-click (fn [_button _event]
                                      (view:perform-quit))})
             ctx))

        (set view.button button)
        (set view.layout button.layout)
        (set view.perform-quit perform-quit)
        (set view.drop (fn [_self]
                            (button:drop)))
        view))

QuitNodeView
