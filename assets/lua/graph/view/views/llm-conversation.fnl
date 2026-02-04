(local Button (require :button))
(local Input (require :input))
(local ComboBox (require :combo-box))
(local Text (require :text))
(local {: Grid} (require :grid))
(local {: Flex : FlexChild} (require :flex))
(local Aligned (require :aligned))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local ScrollView (require :scroll-view))

(fn LlmConversationView [node]
    (assert node "LlmConversationView requires a node")

    (fn build [ctx]
        (local view {:node node
                     :handlers []})
        (local provider (or (and node node.provider) "openai"))

        (fn model-items-for-provider [provider-name]
            (if (= provider-name "zai")
                ["glm-4.7"]
                ["gpt-5.2" "gpt-4.1" "gpt-4o" "gpt-4o-mini"]))

        (fn add-message [_self]
            (assert (and node node.add-message) "LlmConversationView requires node.add-message")
            (node:add-message))

        (fn expand-messages [_self]
            (assert (and node node.expand) "LlmConversationView requires node.expand")
            (node:expand))

        (fn contract-messages [_self]
            (assert (and node node.contract) "LlmConversationView requires node.contract")
            (node:contract))

        (fn attach-selected-tools [_self]
            (assert (and app app.graph-view app.graph-view.selection)
                    "LlmConversationView requires graph selection")
            (local graph (and node node.graph))
            (assert graph "LlmConversationView requires a mounted graph")
            (local selected (or app.graph-view.selection.selected-nodes []))
            (local tool-names [])
            (each [_ selected-node (ipairs selected)]
                (when (and selected-node (= selected-node.kind "llm-tool"))
                    (table.insert tool-names (tostring (or selected-node.name selected-node.label)))
                    (graph:add-edge (GraphEdge {:source node
                                                :target selected-node}))))
            (when (and node node.attach-tools)
                (node:attach-tools tool-names)))

        (fn delete-conversation [_self]
            (assert (and node node.delete) "LlmConversationView requires node.delete")
            (node:delete))

        (fn open-messages-view [_self]
            (assert (and app app.hud app.hud.add-panel-child)
                    "LlmConversationView requires app.hud:add-panel-child")
            (local LlmConversationMessagesView (require :llm-conversation-messages-view))
            (app.hud:add-panel-child {:builder (LlmConversationMessagesView {:node node})}))

        (local button
            ((Button {:text "Add message"
                      :on-click (fn [_button _event]
                                      (view:add-message))})
             ctx))
        (local view-messages-button
            ((Button {:text "View messages"
                      :on-click (fn [_button _event]
                                      (view:open-messages-view))})
             ctx))
        (local expand-button
            ((Button {:text "Expand messages"
                      :on-click (fn [_button _event]
                                      (view:expand-messages))})
             ctx))
        (local contract-button
            ((Button {:text "Contract messages"
                      :on-click (fn [_button _event]
                                      (view:contract-messages))})
             ctx))
        (local attach-button
            ((Button {:text "Attach selected tools"
                      :on-click (fn [_button _event]
                                      (view:attach-selected-tools))})
             ctx))
        (local delete-button
            ((Button {:text "Delete conversation"
                      :on-click (fn [_button _event]
                                      (view:delete-conversation))})
             ctx))

        (local name-input
            ((Input {:text (tostring (or node.name ""))})
             ctx))
        (when (and name-input name-input.changed)
            (local handler
                (name-input.changed:connect
                    (fn [value]
                        (if (and node node.set-name)
                            (node:set-name value)
                            (set node.name value))
                        (when node.touch
                            (node:touch)))))
            (table.insert view.handlers {:signal name-input.changed
                                         :handler handler}))

        (local provider-input
            ((ComboBox {:items ["openai" "zai"]
                        :value provider
                        :name "llm-conversation-provider"})
             ctx))

        (local model-input
            ((ComboBox {:items (model-items-for-provider provider)
                        :value (and node node.model)
                        :name "llm-conversation-model"})
             ctx))

        (when (and provider-input provider-input.changed)
            (local handler
                (provider-input.changed:connect
                    (fn [value]
                        (set node.provider value)
                        (if (and node node.set-provider)
                            (node:set-provider value)
                            (when node.touch
                                (node:touch)))
                        (when (and model-input model-input.set-items)
                            (model-input:set-items (model-items-for-provider value)))
                        (when (and model-input model-input.set-value)
                            (model-input:set-value (or (and node node.model) "glm-4.7"))))))
            (table.insert view.handlers {:signal provider-input.changed
                                         :handler handler}))

        (when (and model-input model-input.changed)
            (local handler
                (model-input.changed:connect
                    (fn [value]
                        (set node.model value)
                        (when node.touch
                            (node:touch)))))
            (table.insert view.handlers {:signal model-input.changed
                                         :handler handler}))

        (local cwd-input
            ((Input {:text (tostring (or node.cwd ""))
                     :name "llm-conversation-cwd"})
             ctx))
        (when (and cwd-input cwd-input.changed)
            (local handler
                (cwd-input.changed:connect
                    (fn [value]
                         (if (and node node.set-cwd)
                             (node:set-cwd value)
                             (set node.cwd value))
                        (when node.touch
                            (node:touch)))))
            (table.insert view.handlers {:signal cwd-input.changed
                                         :handler handler}))

        (local max-tool-rounds-input
            ((Input {:text (tostring (or (. node :max-tool-rounds) ""))
                     :name "llm-conversation-max-tool-rounds"})
             ctx))
        (when (and max-tool-rounds-input max-tool-rounds-input.changed)
            (local handler
                (max-tool-rounds-input.changed:connect
                    (fn [value]
                        (local parsed (tonumber value))
                        (set (. node :max-tool-rounds) parsed)
                        (when node.touch
                            (node:touch)))))
            (table.insert view.handlers {:signal max-tool-rounds-input.changed
                                         :handler handler}))

        (local reasoning-effort-input
            ((ComboBox {:items ["none" "low" "medium" "high" "xhigh"]
                        :value (or (and node (. node :reasoning-effort)) "none")
                        :name "llm-conversation-reasoning-effort"})
             ctx))
        (when (and reasoning-effort-input reasoning-effort-input.changed)
            (local handler
                (reasoning-effort-input.changed:connect
                    (fn [value]
                        (if (and node node.set-reasoning-effort)
                            (node:set-reasoning-effort value)
                            (set (. node :reasoning-effort) value))
                        (when node.touch
                            (node:touch)))))
            (table.insert view.handlers {:signal reasoning-effort-input.changed
                                         :handler handler}))

        (local text-verbosity-input
            ((ComboBox {:items ["low" "medium" "high"]
                        :value (or (and node (. node :text-verbosity)) "medium")
                        :name "llm-conversation-text-verbosity"})
             ctx))
        (when (and text-verbosity-input text-verbosity-input.changed)
            (local handler
                (text-verbosity-input.changed:connect
                    (fn [value]
                        (if (and node node.set-text-verbosity)
                            (node:set-text-verbosity value)
                            (set (. node :text-verbosity) value))
                        (when node.touch
                            (node:touch)))))
            (table.insert view.handlers {:signal text-verbosity-input.changed
                                         :handler handler}))

        (local grid-builder
            (Grid {:rows 7
                   :columns 2
                   :xmode :even
                   :ymode :tight
                   :align-x :stretch
                   :align-y :end
                   :xspacing 0.8
                   :yspacing 0.6
                   :column-specs [{:flex 0}
                                  {:flex 1}]
                   :children [{:widget (fn [child-ctx]
                                         ((Text {:text "Name"}) child-ctx))}
                              {:widget (fn [child-ctx]
                                         ((Text {:text "Provider"}) child-ctx))}
                              {:widget (fn [child-ctx]
                                         ((Text {:text "Model"}) child-ctx))}
                              {:widget (fn [child-ctx]
                                         ((Text {:text "CWD"}) child-ctx))}
                              {:widget (fn [child-ctx]
                                         ((Text {:text "Max Tool Rounds"}) child-ctx))}
                              {:widget (fn [child-ctx]
                                         ((Text {:text "Reasoning Effort"}) child-ctx))}
                              {:widget (fn [child-ctx]
                                         ((Text {:text "Verbosity"}) child-ctx))}
                              {:widget (fn [_] name-input)
                               :align-x :stretch}
                              {:widget (fn [_] provider-input)
                               :align-x :stretch}
                              {:widget (fn [_] model-input)
                               :align-x :stretch}
                              {:widget (fn [_] cwd-input)
                               :align-x :stretch}
                              {:widget (fn [_] max-tool-rounds-input)
                               :align-x :stretch}
                              {:widget (fn [_] reasoning-effort-input)
                               :align-x :stretch}
                              {:widget (fn [_] text-verbosity-input)
                               :align-x :stretch}]}))
        (local form-row (grid-builder ctx))
        (local scrollable-form
            ((ScrollView {:child (fn [_] form-row)
                          :scrollbar-policy :as-needed
                          :name "llm-conversation-form"})
             ctx))
        (local button-row
            ((Flex {:axis 1
                    :reverse false
                    :xalign :start
                    :yalign :center
                    :xspacing 0.6
                    :children [(FlexChild (fn [_] button) 0)
                               (FlexChild (fn [_] attach-button) 0)
                               (FlexChild (fn [_] delete-button) 0)]})
             ctx))
        (local expand-row
            ((Flex {:axis 1
                    :reverse false
                    :xalign :start
                    :yalign :center
                    :xspacing 0.6
                    :children [(FlexChild (fn [_] expand-button) 0)
                               (FlexChild (fn [_] view-messages-button) 0)
                               (FlexChild (fn [_] contract-button) 0)]})
             ctx))
        (local button-column
            ((Flex {:axis 2
                    :reverse true
                    :xalign :start
                    :yspacing 0.6
                    :children [(FlexChild (fn [_] button-row) 0)
                               (FlexChild (fn [_] expand-row) 0)]})
             ctx))
        (local aligned-button
            ((Aligned {:alignment :start
                       :child (fn [_] button-column)})
             ctx))
        (local content-builder
            (Flex {:axis 2
                   :reverse true
                   :xalign :stretch
                   :yspacing 0.8
                   :children [(FlexChild (fn [_] aligned-button) 0)
                              (FlexChild (fn [_] scrollable-form) 1)]}))
        (local content
            (content-builder ctx))

        (set view.button button)
        (set view.view-messages-button view-messages-button)
        (set view.open-messages-view open-messages-view)
        (set view.expand-messages expand-messages)
        (set view.contract-messages contract-messages)
        (set view.attach-selected-tools attach-selected-tools)
        (set view.name-input name-input)
        (set view.provider-input provider-input)
        (set view.model-input model-input)
        (set view.cwd-input cwd-input)
        (set view.reasoning-effort-input reasoning-effort-input)
        (set view.text-verbosity-input text-verbosity-input)
        (set view.layout content.layout)
        (set view.add-message add-message)
        (set view.delete-conversation delete-conversation)
        (set view.drop (fn [_self]
                            (each [_ record (ipairs view.handlers)]
                                (when (and record record.signal record.handler)
                                    (record.signal:disconnect record.handler true)))
                            (content:drop)))
        view))

LlmConversationView
