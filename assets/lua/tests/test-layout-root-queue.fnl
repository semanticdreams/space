(local glm (require :glm))
(local {: Layout : LayoutRoot} (require :layout))

(local tests [])

(fn layout-root-allows-drop-during-update []
  (local root (LayoutRoot))
  (local dropped {:value false})
  (local victim
    (Layout {:name "victim"
             :measurer (fn [self]
                         (set self.measure (glm.vec3 1 1 0)))
             :layouter (fn [_self] nil)}))
  (local trigger
    (Layout {:name "trigger"
             :measurer (fn [self]
                         (set self.measure (glm.vec3 1 1 0)))
             :layouter (fn [_self]
                         (when (not dropped.value)
                           (set dropped.value true)
                           (victim:drop)))}))
  (local parent
    (Layout {:name "parent"
             :children [trigger victim]
             :measurer (fn [self]
                         (trigger:measurer)
                         (victim:measurer)
                         (set self.measure (glm.vec3 2 2 0)))
             :layouter (fn [self]
                         (set self.size self.measure)
                         (set trigger.size (glm.vec3 1 1 0))
                         (set victim.size (glm.vec3 1 1 0))
                         (set trigger.position self.position)
                         (set victim.position (+ self.position (glm.vec3 1 0 0)))
                         (set trigger.rotation self.rotation)
                         (set victim.rotation self.rotation)
                         (trigger:layouter)
                         (victim:layouter))}))
  (parent:set-root root)
  (parent:mark-measure-dirty)
  (parent:mark-layout-dirty)
  (local (ok err)
    (pcall (fn [] (root:update))))
  (assert ok (.. "layout-root update failed: " (tostring err))))

(table.insert tests {:name "LayoutRoot update tolerates drops during pass" :fn layout-root-allows-drop-during-update})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "layout-root-queue"
                       :tests tests})))

{:name "layout-root-queue"
 :tests tests
 :main main}
