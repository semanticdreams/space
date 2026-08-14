(local SearchView (require :search-view))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))

(local M {})

(fn invoke-method [target method-name item]
  (local method (and target (. target method-name)))
  (when (and method item)
    (method target (. item 1))))

(fn make-click-handler [target method-name item]
  (fn hierarchy-list-click [_button _event]
    (invoke-method target method-name item)))

(fn make-button-builder [target method-name]
  (fn [item child-ctx]
    (local label (tostring (. item 2)))
    ((Button {:text label
              :variant :ghost
              :on-click (make-click-handler target method-name item)})
     child-ctx)))

(fn build-search [target spec ctx]
  ((SearchView {:items []
                :name spec.name
                :num-per-page 10
                :builder (make-button-builder target spec.open-method)})
   ctx))

(fn build-layout [search ctx]
  (fn search-child [_]
    search)
  ((Flex {:axis 2
          :xalign :stretch
          :yspacing 0.3
          :children [(FlexChild search-child 1)]})
   ctx))

(fn normalize-items [spec raw-items]
  (if spec.normalize
      (spec.normalize raw-items)
      (= raw-items nil) []
      raw-items))

(fn read-items [target spec]
  (local reader (and target (. target spec.emit-method)))
  (normalize-items spec (if reader (reader target) [])))

(fn set-search-items [search items]
  (search:set-items items)
  (set search.items items))

(fn connect-updates [target spec view]
  (local signal (and target (. target spec.signal-key)))
  (local handler (and signal (fn hierarchy-list-update [raw-items]
                              (view:set-items (normalize-items spec raw-items)))))
  (when signal
    (signal:connect handler))
  {:signal signal :handler handler})

(fn M.pair-categories [categories]
  (local items [])
  (each [_ category (ipairs (if categories categories []))]
    (table.insert items [category category.label]))
  items)

(fn resolve-build-ctx [target spec ctx]
  (if ctx ctx
      spec.ctx spec.ctx
      (and target target.graph target.graph.ctx)))

(fn build-view [target spec ctx]
  (local build-ctx (resolve-build-ctx target spec ctx))
  (assert build-ctx spec.context-error)
  (local view {})
  (local search (build-search target spec build-ctx))
  (local flex (build-layout search build-ctx))
  (set view.search search)
  (set view.layout flex.layout)
  (set view.set-items (fn [_self items] (set-search-items search items)))
  (set view.refresh-items (fn [self] (self:set-items (read-items target spec))))
  (local update (connect-updates target spec view))
  (fn submitted-handler [item]
    (invoke-method target spec.open-method item))
  (search.submitted:connect submitted-handler)
  (set view.drop
       (fn [_self]
         (when update.signal
           (update.signal:disconnect update.handler true))
         (flex:drop)))
  (view:refresh-items)
  view)

(fn M.make [spec]
  (fn HierarchyListNodeView [node opts]
    (local options (if opts opts {}))
    (local target (if node node options.node))
    (fn build [ctx]
      (local local-spec {})
      (each [key value (pairs spec)]
        (set (. local-spec key) value))
      (set local-spec.ctx options.ctx)
      (build-view target local-spec ctx))))

M
