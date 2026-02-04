(local Input (require :input))
(local ComboBox (require :combo-box))
(local {: Grid} (require :grid))
(local Text (require :text))
(local Button (require :button))
(local Aligned (require :aligned))
(local {: Flex : FlexChild} (require :flex))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local LlmToolNode (require :graph/nodes/llm-tool))
(local ScrollView (require :scroll-view))

(fn LlmMessageView [node opts]
    (assert node "LlmMessageView requires a node")
    (local options (or opts {}))
    (local target (or node options.node))
    (local view-name (or options.name "llm-message"))

    (fn build [ctx]
        (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
        (assert build-ctx "LlmMessageView requires a build context")

        (local view {:node target
                     :inputs {}
                     :handlers []})

        (fn add-child-message [_self]
            (assert (and target target.find-conversation) "LlmMessageView requires node.find-conversation")
            (local convo (target:find-conversation))
            (assert convo "LlmMessageView requires a conversation ancestor")
            (assert (and convo convo.add-message) "LlmMessageView requires conversation.add-message")
            (convo:add-message {:role "user"} target))

        (fn attach-selected-tools [_self]
            (assert (and app app.graph-view app.graph-view.selection)
                    "LlmMessageView requires graph selection")
            (local graph (and target target.graph))
            (assert graph "LlmMessageView requires a mounted graph")
            (local selected (or app.graph-view.selection.selected-nodes []))
            (local tool-names [])
            (each [_ selected-node (ipairs selected)]
                (when (and selected-node (= selected-node.kind "llm-tool"))
                    (table.insert tool-names (tostring (or selected-node.name selected-node.label)))
                    (graph:add-edge (GraphEdge {:source target
                                                :target selected-node}))))
            (when (and target target.attach-tools)
                (target:attach-tools tool-names)))

        (fn add-attached-tool-nodes [_self]
            (local graph (and target target.graph))
            (assert graph "LlmMessageView requires a mounted graph")
            (local tools (and target target.collect-attached-tools (target:collect-attached-tools)))
            (each [_ tool (ipairs (or tools []))]
                (local tool-name (and tool tool.name))
                (when tool-name
                    (local key (.. "llm-tool:" (tostring tool-name)))
                    (local existing (and graph.nodes (. graph.nodes key)))
                    (local tool-node
                        (or existing
                            (LlmToolNode {:key key
                                          :name tool-name
                                          :tool tool
                                          :description tool.description
                                          :parameters tool.parameters})))
                    (graph:add-node tool-node)
                    (graph:add-edge (GraphEdge {:source target
                                                :target tool-node})))))

        (local field-setters
            {:role (fn [value] (set target.role value))
             :content (fn [value]
                          (if (and target target.set-content)
                              (target:set-content value)
                              (set target.content value)))
             :tool-name (fn [value] (tset target :tool-name value))
             :tool-call-id (fn [value] (tset target :tool-call-id value))})

        (fn set-field [key value]
            (local setter (. field-setters key))
            (when setter
                (setter value))
            (when (and target target.touch)
                (target:touch)))

        (fn connect-input [key input]
            (local signal (and input input.changed))
            (when signal
                (local handler (signal:connect (fn [value]
                                                   (set-field key value))))
                (table.insert view.handlers {:signal signal :handler handler})))

        (fn usage-summary [node]
            (local usage (and node (. node :last-usage)))
            (local total (and usage usage.total_tokens))
            (local window (and node (. node :last-context-window)))
            (if (and total window (> window 0))
                (let [percent (* 100 (/ total window))
                      total-int (math.floor total)
                      window-int (math.floor window)]
                    (string.format "%.1f%% (%d / %d)" percent total-int window-int))
                (if total
                    (string.format "%d tokens" (math.floor total))
                    "No usage yet")))

        (when (and target target.changed)
            (local handler (target.changed:connect
                (fn [_value]
                    (when (and view.usage-text view.usage-text.set-text)
                        (view.usage-text:set-text (usage-summary target))))))
            (table.insert view.handlers {:signal target.changed :handler handler}))

        (fn build-label [entry child-ctx]
            ((Text {:text entry.label}) child-ctx))

        (fn build-input [entry child-ctx]
            (if (= entry.widget :text)
                (let [text-widget ((Text {:text (tostring (or entry.value ""))}) child-ctx)]
                    (when (= entry.key :usage)
                        (set view.usage-text text-widget))
                    text-widget)
                (do
                    (local input
                        (if (= entry.widget :combo)
                            ((ComboBox {:items entry.items
                                        :value entry.value
                                        :name entry.name
                                        :max-menu-height entry.max-menu-height
                                        :max-visible-items entry.max-visible-items})
                             child-ctx)
                            ((Input {:text (tostring (or entry.value ""))
                                     :multiline? entry.multiline?
                                     :min-lines (or entry.min-lines 1)
                                     :max-lines (or entry.max-lines 1)
                                     :min-columns 12
                                     :max-columns 60})
                             child-ctx)))
                    (tset view.inputs entry.key input)
                    (connect-input entry.key input)
                    input)))

        (local rows
            [{:key :role
              :label "Role"
              :value (and target target.role)
              :widget :combo
             :items (or options.role-items
                         ["user" "assistant" "system" "tool" "developer"])
              :name "llm-message-role"}
             {:key :content
             :label "Content"
             :value (and target target.content)
              :multiline? true
              :min-lines 4
              :max-lines 12}
             {:key :usage
              :label "Tokens"
              :widget :text
              :value (usage-summary target)}
             {:key :tool-name
             :label "Tool Name"
              :value (and target (. target :tool-name))}
             {:key :tool-call-id
              :label "Tool Call Id"
              :value (and target (. target :tool-call-id))}])

        (local grid-children [])
        (each [_ entry (ipairs rows)]
            (local row entry)
            (table.insert grid-children {:widget (fn [child-ctx]
                                                    (build-label row child-ctx))}))
        (each [_ entry (ipairs rows)]
            (local row entry)
            (table.insert grid-children {:widget (fn [child-ctx]
                                                    (build-input row child-ctx))
                                         :align-x :stretch}))
        (local grid-builder
            (Grid {:rows (length rows)
                   :columns 2
                   :xmode :tight
                   :ymode :tight
                   :align-x :start
                   :align-y :end
                   :xspacing 0.6
                   :yspacing 0.35
                   :column-specs [{:flex 0}
                                  {:flex 1}]
                   :children grid-children}))

        (local grid (grid-builder build-ctx))
        (local run-button
            ((Button {:text "Run"
                      :variant :primary
                      :on-click (fn [_btn _event]
                                    (when (and target target.run-request)
                                        (target:run-request)))})
             build-ctx))
        (local add-button
            ((Button {:text "Add message"
                      :on-click (fn [_btn _event]
                                    (view:add-child-message))})
             build-ctx))
        (local attach-button
            ((Button {:text "Attach selected tools"
                      :on-click (fn [_btn _event]
                                    (view:attach-selected-tools))})
             build-ctx))
        (local add-tool-nodes-button
            ((Button {:text "Add tool nodes"
                      :on-click (fn [_btn _event]
                                    (view:add-attached-tool-nodes))})
             build-ctx))
        (local button-row
            ((Flex {:axis 1
                    :reverse false
                    :xalign :start
                    :yalign :center
                    :xspacing 0.6
                    :children [(FlexChild (fn [_] run-button) 0)
                               (FlexChild (fn [_] add-button) 0)
                               (FlexChild (fn [_] attach-button) 0)
                               (FlexChild (fn [_] add-tool-nodes-button) 0)]})
             build-ctx))
        (local aligned-button
            ((Aligned {:alignment :start
                       :child (fn [_] button-row)})
             build-ctx))
        (local scrollable-form
            ((ScrollView {:child (fn [_] grid)
                          :scrollbar-policy (or options.scrollbar-policy :as-needed)})
             build-ctx))
        (local content-builder
            (Flex {:axis 2
                   :reverse true
                   :xalign :stretch
                   :yspacing 0.6
                   :children [(FlexChild (fn [_] aligned-button) 0)
                              (FlexChild (fn [_] scrollable-form) 1)]}))
        (local layout
            (content-builder build-ctx))
        (set view.grid grid)
        (set view.layout layout.layout)
        (set view.add-child-message add-child-message)
        (set view.attach-selected-tools attach-selected-tools)
        (set view.add-attached-tool-nodes add-attached-tool-nodes)
        (set view.drop
             (fn [_self]
                 (each [_ record (ipairs view.handlers)]
                     (when (and record record.signal record.handler)
                         (record.signal:disconnect record.handler true)))
                 (layout:drop)))

        view))

LlmMessageView
