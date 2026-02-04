(local Button (require :button))
(local ListView (require :list-view))
(local Aligned (require :aligned))
(local {: Flex : FlexChild} (require :flex))
(local Padding (require :padding))

(fn LlmConversationsView [node opts]
    (assert node "LlmConversationsView requires a node")
    (local options (or opts {}))

    (fn build [ctx]
        (local context (or ctx options.ctx (and node node.graph node.graph.ctx)))
        (assert context "LlmConversationsView requires a build context")

        (local view {:layout nil})

        (fn create-conversation [_self]
            (assert (and node node.create-conversation) "LlmConversationsView requires node.create-conversation")
            (node:create-conversation))

        (local list-builder
            (ListView {:items []
                       :name "llm-conversations"
                       :show-head false
                       :item-spacing 0.2
                       :builder (fn [entry child-ctx]
                                    ((Button {:text entry.label
                                              :variant :ghost
                                              :on-click (fn [_btn _event]
                                                            (when (and node node.request-open)
                                                                (node:request-open entry)))})
                                     child-ctx))}))

        (local list (list-builder context))
        (local create-button
            ((Button {:text "New conversation"
                      :variant :primary
                      :on-click (fn [_btn _event]
                                    (view:create-conversation))})
             context))
        (local aligned-button
            ((Aligned {:alignment :start
                       :child (fn [_] create-button)})
             context))
        (local content-builder
            (Flex {:axis 2
                   :reverse true
                   :xalign :stretch
                   :yspacing 0.6
                   :children [(FlexChild (fn [_] aligned-button) 0)
                              (FlexChild (fn [_] list) 1)]}))
        (local content
            (content-builder context))

        (set view.layout content.layout)
        (set view.set-items (fn [_self items]
                                (list:set-items items)))
        (set view.create-conversation create-conversation)

        (local items-signal (and node node.items-changed))
        (local items-handler (and items-signal
                                  (fn [items]
                                      (view:set-items items))))
        (when items-signal
            (items-signal:connect items-handler))

        (when (and node node.refresh)
            (node:refresh))

        (set view.drop
             (fn [_self]
                 (when items-signal
                     (items-signal:disconnect items-handler true))
                 (content:drop)))

        view))

LlmConversationsView
