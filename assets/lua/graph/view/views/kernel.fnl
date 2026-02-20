(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Input (require :input))
(local ListView (require :list-view))
(local Text (require :text))

(fn list-items [instances]
  (icollect [_ instance (ipairs (or instances []))]
    [instance (.. (or instance.id "instance")
                  " ["
                  (or instance.status "unknown")
                  "]")]))

(fn KernelNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "KernelNodeView requires a build context")
    (local view {})
    (local kernel (and target target.get-kernel (target:get-kernel)))
    (local immutable? (= (tostring (and kernel kernel.id)) "0"))

    (local id-label
      ((Text {:text (.. "Kernel id: " (tostring (or (and kernel kernel.id) "?")))})
       build-ctx))

    (local name-input
      ((Input {:text (or (and kernel kernel.name) "")
               :placeholder "Name..."
               :editable? (not immutable?)
               :on-change (fn [_input new-value]
                            (when (and (not immutable?) target target.update-name)
                              (target:update-name new-value)))})
       build-ctx))

    (local cmd-input
      ((Input {:text (or (and kernel kernel.cmd) "")
               :placeholder "Command..."
               :editable? (not immutable?)
               :on-change (fn [_input new-value]
                            (when (and (not immutable?) target target.update-cmd)
                              (target:update-cmd new-value)))})
       build-ctx))

    (local cwd-input
      ((Input {:text (or (and kernel kernel.cwd) "")
               :placeholder "Cwd..."
               :editable? (not immutable?)
               :on-change (fn [_input new-value]
                            (when (and (not immutable?) target target.update-cwd)
                              (target:update-cwd new-value)))})
       build-ctx))

    (local run-button
      ((Button {:icon "play_arrow"
                :text "Run Kernel"
                :variant :ghost
                :enabled? (not immutable?)
                :on-click (fn [_button _event]
                            (when (and (not immutable?) target target.create-instance)
                              (target:create-instance)))})
       build-ctx))

    (local delete-button
      ((Button {:icon "delete"
                :text "Delete Kernel"
                :variant :ghost
                :enabled? (not immutable?)
                :on-click (fn [_button _event]
                            (when (and (not immutable?) target target.delete-kernel)
                              (target:delete-kernel)))})
       build-ctx))

    (local actions-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] run-button) 0)
                         (FlexChild (fn [_] delete-button) 0)]})
       build-ctx))

    (local list
      ((ListView {:name "kernel-instance-list"
                  :items []
                  :scroll true
                  :paginate false
                  :show-head false
                  :item-spacing 0.2
                  :builder (fn [item child-ctx]
                             (local instance (. item 1))
                             (local label (tostring (. item 2)))
                             ((Button {:text label
                                       :variant :ghost
                                       :on-click (fn [_button _event]
                                                   (when (and target target.add-instance-node)
                                                     (target:add-instance-node instance)))})
                              child-ctx))})
       build-ctx))

    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.3
              :children [(FlexChild (fn [_] id-label) 0)
                         (FlexChild (fn [_] name-input) 0)
                         (FlexChild (fn [_] cmd-input) 0)
                         (FlexChild (fn [_] cwd-input) 0)
                         (FlexChild (fn [_] actions-row) 0)
                         (FlexChild (fn [_] list) 1)]})
       build-ctx))

    (set view.layout flex.layout)
    (set view.list list)

    (set view.refresh
         (fn [_self]
           (local current-kernel (and target target.get-kernel (target:get-kernel)))
           (when current-kernel
             (id-label:set-text (.. "Kernel id: " (tostring current-kernel.id)))
             (when (and name-input name-input.set-text)
               (name-input:set-text (or current-kernel.name "") {:reset-cursor? false}))
             (when (and cmd-input cmd-input.set-text)
               (cmd-input:set-text (or current-kernel.cmd "") {:reset-cursor? false}))
             (when (and cwd-input cwd-input.set-text)
               (cwd-input:set-text (or current-kernel.cwd "") {:reset-cursor? false})))
           (local instances (and target target.list-instances (target:list-instances)))
           (list:set-items (list-items instances))))

    (local changed-signal (and target target.changed))
    (local changed-handler (and changed-signal (fn [_] (view:refresh))))
    (when changed-signal
      (changed-signal:connect changed-handler))

    (set view.drop
         (fn [_self]
           (when changed-signal
             (changed-signal:disconnect changed-handler true))
           (id-label:drop)
           (name-input:drop)
           (cmd-input:drop)
           (cwd-input:drop)
           (run-button:drop)
           (delete-button:drop)
           (actions-row:drop)
           (list:drop)
           (flex:drop)))

    (view:refresh)
    view))

KernelNodeView
