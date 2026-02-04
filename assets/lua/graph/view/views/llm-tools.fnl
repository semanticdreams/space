(local SearchView (require :search-view))

(fn LlmToolsView [node opts]
    (assert node "LlmToolsView requires a node")
    (local options (or opts {}))

    (fn build [ctx]
        (local context (or ctx options.ctx (and node node.graph node.graph.ctx)))
        (assert context "LlmToolsView requires a build context")

        (local view {:node node
                     :handlers []})

        (local search
            ((SearchView {:items (if (and node node.emit-items)
                                     (node:emit-items)
                                     [])
                          :name "llm-tools"
                          :placeholder "Search tools"
                          :items-per-page 12})
             context))

        (local submit-handler
            (search.submitted:connect
                (fn [item]
                    (local tool (. item 1))
                    (when (and node node.create-tool)
                        (node:create-tool tool)))))
        (table.insert view.handlers {:signal search.submitted
                                     :handler submit-handler})

        (local items-signal (and node node.items-changed))
        (local items-handler (and items-signal
                                  (fn [items]
                                      (search:set-items items))))
        (when items-signal
            (items-signal:connect items-handler))

        (when (and node node.refresh)
            (node:refresh))

        (set view.layout search.layout)
        (set view.drop
             (fn [_self]
                 (when items-signal
                     (items-signal:disconnect items-handler true))
                 (when search.submitted
                     (search.submitted:disconnect submit-handler true))
                 (search:drop)))

        view))

LlmToolsView
