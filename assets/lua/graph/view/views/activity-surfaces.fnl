(local HierarchyList (require :graph/view/views/hierarchy-list))

(HierarchyList.make {:name "activity-surfaces-node-view"
                     :emit-method :emit-items
                     :signal-key :items-changed
                     :open-method :add-surface-node
                     :context-error "ActivitySurfacesNodeView requires a build context"})
