(local HierarchyList (require :graph/view/views/hierarchy-list))

(HierarchyList.make {:name "world-activities-node-view"
                     :emit-method :emit-items
                     :signal-key :items-changed
                     :open-method :add-activity-node
                     :context-error "WorldActivitiesNodeView requires a build context"})
