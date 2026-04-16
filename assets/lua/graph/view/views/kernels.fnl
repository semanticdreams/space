(local SearchView (require :search-view))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))

(fn KernelsNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))
  (local items (or options.items []))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "KernelsNodeView requires a build context")
    (local view {})

    (local create-button
      ((Button {:icon "add"
                :text "Create Kernel"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.create-kernel)
                              (target:create-kernel {})))})
       build-ctx))

    (local search
      ((SearchView {:items []
                    :name "kernels-node-view"
                    :num-per-page 10
                    :builder (fn [item child-ctx]
                               (local kernel (. item 1))
                               (local label (tostring (. item 2)))
                               ((Button {:text label
                                         :variant :ghost
                                         :enabled? (not (= (tostring kernel.id) "0"))
                                         :on-click (fn [_button _event]
                                                     (when (and target target.add-kernel-node)
                                                       (target:add-kernel-node kernel)))})
                                child-ctx))})
       build-ctx))

    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.3
              :children [(FlexChild (fn [_] create-button) 0)
                         (FlexChild (fn [_] search) 1)]})
       build-ctx))

    (set view.search search)
    (set view.create-button create-button)
    (set view.layout flex.layout)

    (set view.set-items
         (fn [_self new-items]
           (search:set-items new-items)))

    (set view.refresh-items
         (fn [self]
           (local refreshed
             (if (and target target.emit-items)
                 (target:emit-items)
                 items))
           (self:set-items refreshed)
           (set self.search.items refreshed)))

    (local items-signal (and target target.items-changed))
    (local items-handler
      (and items-signal
           (fn [new-items]
             (view:set-items new-items))))
    (local submitted-handler
      (fn [item]
        (local kernel (and item (. item 1)))
        (when (and kernel
                   (not (= (tostring kernel.id) "0"))
                   target
                   target.add-kernel-node)
          (target:add-kernel-node kernel))))
    (when items-signal
      (items-signal:connect items-handler))
    (search.submitted:connect submitted-handler)

    (set view.drop
         (fn [_self]
           (when items-signal
             (items-signal:disconnect items-handler true))
           (search.submitted:disconnect submitted-handler true)
           (flex:drop)))

    (view:refresh-items)
    view))

KernelsNodeView
