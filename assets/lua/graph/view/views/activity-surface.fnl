(local HierarchyList (require :graph/view/views/hierarchy-list))

(HierarchyList.make {:name "activity-surface-node-view"
                     :emit-method :emit-categories
                     :signal-key :categories-changed
                     :open-method :add-category-node
                     :normalize HierarchyList.pair-categories
                     :context-error "ActivitySurfaceNodeView requires a build context"})
