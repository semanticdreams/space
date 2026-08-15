(local HierarchyList (require :graph/view/views/hierarchy-list))

(HierarchyList.make {:name "world-activity-node-view"
                     :emit-method :emit-items
                     :open-method :open-item
                     :context-error "WorldActivityNodeView requires a build context"})
