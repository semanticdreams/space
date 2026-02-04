(local Input (require :input))
(local {: Grid} (require :grid))
(local Text (require :text))
(local Button (require :button))
(local Aligned (require :aligned))
(local {: Flex : FlexChild} (require :flex))
(local ScrollView (require :scroll-view))

(fn LlmToolResultView [node opts]
    (assert node "LlmToolResultView requires a node")
    (local options (or opts {}))
    (local target (or node options.node))

    (fn build [ctx]
        (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
        (assert build-ctx "LlmToolResultView requires a build context")

        (local view {:node target
                     :inputs {}
                     :handlers []})

        (fn set-field [key value]
            (if (= key :name)
                (set target.name value)
                (if (= key :call-id)
                    (set target.call-id value)
                    (if (= key :output)
                        (set target.output value)
                        nil)))
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
                        ((Input {:text (tostring (or entry.value ""))
                                 :multiline? entry.multiline?
                                 :min-lines (or entry.min-lines 1)
                                 :max-lines (or entry.max-lines 1)
                                 :min-columns 12
                                 :max-columns 60})
                         child-ctx))
                    (tset view.inputs entry.key input)
                    (connect-input entry.key input)
                    input)))

        (local rows
            [{:key :name
              :label "Tool"
              :value (and target target.name)}
             {:key :call-id
              :label "Call Id"
              :value (and target target.call-id)}
             {:key :usage
              :label "Tokens"
              :widget :text
              :value (usage-summary target)}
             {:key :output
              :label "Output"
              :value (and target target.output)
              :multiline? true
              :min-lines 3
              :max-lines 10}])

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
        (local button-row
            ((Flex {:axis 1
                    :reverse false
                    :xalign :start
                    :yalign :center
                    :xspacing 0.6
                    :children [(FlexChild (fn [_] run-button) 0)]})
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
        (local content
            (content-builder build-ctx))
        (set view.layout content.layout)
        (set view.drop
             (fn [_self]
                 (each [_ record (ipairs view.handlers)]
                     (when (and record record.signal record.handler)
                         (record.signal:disconnect record.handler true)))
                 (content:drop)))
        view))

LlmToolResultView
