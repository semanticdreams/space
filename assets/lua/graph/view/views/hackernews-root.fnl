(local Button (require :button))
(local ListView (require :list-view))

(fn default-button [label on-click child-ctx]
    ((Button {:text label
              :variant :ghost
              :on-click (fn [_btn _event] (on-click))})
     child-ctx))

(fn HackerNewsRootView [node opts]
    (local options (or opts {}))
    (local target (or node options.node))
    (local feeds (or options.feeds []))
    (local context-node (or target options.node))

    (fn build [ctx]
        (local context (or ctx options.ctx (and context-node context-node.graph context-node.graph.ctx)))
        (assert context "HackerNewsRootView requires a build context")

        (local view {:layout nil})

        (local list-builder
            (ListView {:items []
                       :name "hackernews-root"
                       :show-head false
                       :item-spacing 0.25
                       :builder (fn [entry child-ctx]
                                    (default-button entry.label
                                        (fn []
                                            (when (and target target.add-feed)
                                                (target:add-feed entry)))
                                        child-ctx))}))

        (local list (list-builder context))
        (tset view :layout list.layout)
        (tset view :set-feeds (fn [_self items] (list:set-items items)))
        (local initial-feeds
              (or (and target target.emit-feeds (target:emit-feeds))
                  (and target target.feeds)
                  feeds))
        (view:set-feeds initial-feeds)

        (local feeds-signal (and target target.feeds-changed))
        (local feeds-handler (and feeds-signal
                                  (fn [new-feeds]
                                      (view:set-feeds new-feeds))))
        (when feeds-signal
            (feeds-signal:connect feeds-handler))
        (tset view :drop (fn [_self]
                            (when feeds-signal
                                (feeds-signal:disconnect feeds-handler true))
                            (list:drop)))
        view))

HackerNewsRootView
