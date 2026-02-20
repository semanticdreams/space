(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))

(fn KernelInstanceNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "KernelInstanceNodeView requires a build context")
    (local view {})

    (local id-label
      ((Text {:text ""})
       build-ctx))

    (local status-label
      ((Text {:text ""})
       build-ctx))

    (local stop-button
      ((Button {:icon "stop"
                :text "Stop Instance"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.stop-instance)
                              (target:stop-instance)))})
       build-ctx))

    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.3
              :children [(FlexChild (fn [_] id-label) 0)
                         (FlexChild (fn [_] status-label) 0)
                         (FlexChild (fn [_] stop-button) 0)]})
       build-ctx))

    (set view.layout flex.layout)

    (set view.refresh
         (fn [_self]
           (local instance (and target target.get-instance (target:get-instance)))
           (when instance
             (id-label:set-text (.. "Instance id: " (tostring instance.id)))
             (status-label:set-text
               (.. "Status: "
                   (or instance.status "unknown")
                   (if (and instance.last-error (> (string.len instance.last-error) 0))
                       (.. " | " instance.last-error)
                       ""))))))

    (local changed-signal (and target target.changed))
    (local changed-handler (and changed-signal (fn [_] (view:refresh))))
    (when changed-signal
      (changed-signal:connect changed-handler))

    (set view.drop
         (fn [_self]
           (when changed-signal
             (changed-signal:disconnect changed-handler true))
           (id-label:drop)
           (status-label:drop)
           (stop-button:drop)
           (flex:drop)))

    (view:refresh)
    view))

KernelInstanceNodeView
