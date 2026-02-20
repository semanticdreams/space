(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Input (require :input))
(local ScrollView (require :scroll-view))
(local Text (require :text))

(fn kernel-display [entity]
  (if (and entity (not (= entity.kernel nil)))
      (tostring entity.kernel)
      "0"))

(fn kernel-name-value [entity]
  (if (and entity (= (type entity.kernel) "string"))
      entity.kernel
      ""))

(fn CodeEntityNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "CodeEntityNodeView requires a build context")
    (local view {})
    (local entity (and target target.get-entity (target:get-entity)))

    (local source-input
      ((Input {:text ""
               :placeholder "Source..."
               :multiline? true
               :min-lines 6
               :max-lines 12
               :on-change (fn [_input new-value]
                            (when (and target target.update-source)
                              (target:update-source new-value)))})
       build-ctx))
    (when (and source-input source-input.set-text entity)
      (source-input:set-text (or entity.source "") {:reset-cursor? false}))

    (fn run-source []
      (when (and target target.run-entity)
        (target:run-entity)))
    (local source-submitted-handler
      (and source-input source-input.submitted
           (fn [_payload]
             (run-source))))
    (when source-submitted-handler
      (source-input.submitted:connect source-submitted-handler))

    (local kernel-id-label
      ((Text {:text (.. "Kernel: " (kernel-display entity))})
       build-ctx))
    (local source-label
      ((Text {:text "Source"})
       build-ctx))
    (local result-title
      ((Text {:text "Result"})
       build-ctx))

    (local kernel-name-input
      ((Input {:text (kernel-name-value entity)
               :placeholder "Kernel"
               :on-change (fn [_input new-value]
                            (when (and target target.update-kernel)
                              (if (> (string.len new-value) 0)
                                  (target:update-kernel new-value)
                                  (target:update-kernel 0))))})
       build-ctx))

    (local selected-button
      ((Button {:icon "my_location"
                :text "Use Selected"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.set-kernel-from-selection)
                              (target:set-kernel-from-selection))
                            (local latest (and target target.get-entity (target:get-entity)))
                            (kernel-id-label:set-text (.. "Kernel: " (kernel-display latest))))})
       build-ctx))

    (local run-button
      ((Button {:icon "play_arrow"
                :text "Run"
                :variant :secondary
                :on-click (fn [_button _event]
                            (run-source))})
       build-ctx))

    (local result-label
      ((Text {:text "(no result yet)"})
       build-ctx))

    (local header-row
      ((Flex {:axis 1
              :xalign :stretch
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] kernel-id-label) 1)
                         (FlexChild (fn [_] run-button) 0)]})
       build-ctx))

    (local kernel-controls
      ((Flex {:axis 1
              :xalign :stretch
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] kernel-name-input) 1)
                         (FlexChild (fn [_] selected-button) 0)]})
       build-ctx))

    (local content
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.4
              :children [(FlexChild (fn [_] header-row) 0)
                         (FlexChild (fn [_] kernel-controls) 0)
                         (FlexChild (fn [_] source-label) 0)
                         (FlexChild (fn [_] source-input) 0)
                         (FlexChild (fn [_] result-title) 0)
                         (FlexChild (fn [_] result-label) 0)
                         ]})
       build-ctx))
    (local scroll-view
      ((ScrollView {:child (fn [_] content)
                    :padding false
                    :scrollbar-policy :as-needed})
       build-ctx))
    (local run-signal (and target target.run-result-changed))
    (local run-handler
      (and run-signal
           (fn [value]
             (result-label:set-text (or value ""))
             (local latest (and target target.get-entity (target:get-entity)))
             (kernel-id-label:set-text (.. "Kernel: " (kernel-display latest))))))
    (when run-signal
      (run-signal:connect run-handler))
    (when (and target target.last-run-result)
      (result-label:set-text target.last-run-result))

    (set view.layout scroll-view.layout)
    (set view.drop
         (fn [_self]
           (when run-signal
             (run-signal:disconnect run-handler true))
           (when source-submitted-handler
             (source-input.submitted:disconnect source-submitted-handler true))
           (scroll-view:drop)))
    view))

CodeEntityNodeView
