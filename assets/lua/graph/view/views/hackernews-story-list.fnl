(local Button (require :button))
(local ListView (require :list-view))

(fn default-button [label on-click child-ctx]
    ((Button {:text label
              :variant :ghost
              :on-click (fn [_btn _event] (on-click))})
     child-ctx))

(fn HackerNewsStoryListView [node opts]
    (local options (or opts {}))
    (local target (or node options.node))
    (local items (or options.items []))
    (local list-name (.. "hackernews-" (or (and target target.kind) "stories")))

    (fn build [ctx]
        (local context (or ctx options.ctx (and target target.graph target.graph.ctx)))
        (assert context "HackerNewsStoryListView requires a build context")

        (local view {:layout nil})

        (local list-builder
            (ListView {:items []
                       :name list-name
                       :show-head false
                       :item-spacing 0.2
                       :builder (fn [entry child-ctx]
                                    (default-button entry.label
                                        (fn []
                                            (when (and target target.open-story)
                                                (target:open-story entry)))
                                        child-ctx))}))

        (local list (list-builder context))

        (tset view :layout list.layout)
        (tset view :set-items (fn [_self new-items]
                                  (list:set-items new-items)))
        (tset view :fetch_list
              (fn [self]
                  (when (and target target.fetch-list)
                      (target:fetch-list))))

        (local initial-items
              (if (and target target.emit-items)
                  (target:emit-items)
                  (if (and target target.render-items)
                      (target:render-items)
                      items)))
        (view:set-items initial-items)

        (local items-signal (and target target.items-changed))
        (local items-handler (and items-signal
                                  (fn [new-items]
                                      (view:set-items new-items))))
        (when items-signal
            (items-signal:connect items-handler))
        (local item-signal (and target target.item-changed))
        (local item-handler (and item-signal
                                 (fn [entry]
                                     (when (and list list.update-item entry)
                                         (list:update-item entry.index entry.entry)))))
        (when item-signal
            (item-signal:connect item-handler))

        (tset view :drop (fn [_self]
                            (when items-signal
                                (items-signal:disconnect items-handler true))
                            (when item-signal
                                (item-signal:disconnect item-handler true))
                            (list:drop)))
        view))

HackerNewsStoryListView
