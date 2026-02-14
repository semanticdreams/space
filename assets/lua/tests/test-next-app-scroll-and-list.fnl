(local _ (require :main))
(local ScrollWidget (require :next-app/scroll-widget))
(local VirtualListWidget (require :next-app/virtual-list-widget))
(local TextWidget (require :next-app/text-widget))
(local NextLayout (require :next-app/layout))
(local glm (require :glm))

(local tests [])

(fn matrix-any-diff? [a b]
  (local samples [(glm.vec4 0 0 0 1)
                  (glm.vec4 1 0 0 1)
                  (glm.vec4 0 1 0 1)])
  (var diff? false)
  (each [_ p (ipairs samples)]
    (local pa (* a p))
    (local pb (* b p))
    (when (or (> (math.abs (- pa.x pb.x)) 1e-6)
              (> (math.abs (- pa.y pb.y)) 1e-6)
              (> (math.abs (- pa.z pb.z)) 1e-6))
      (set diff? true)))
  diff?)

(fn next-scroll-widget-clamps-offset []
  (local content
    (TextWidget {:text "line1\nline2\nline3\nline4\nline5\nline6"
                 :scale 0.06}))
  (local scroll (ScrollWidget {:child content
                               :width 1.0
                               :height 0.3}))
  (NextLayout.run-frame scroll 1.0 0.3 0)
  (assert (>= scroll.max-scroll 0))
  (scroll:set-scroll-y 999)
  (NextLayout.run-frame scroll 1.0 0.3 0)
  (assert (<= scroll.scroll-y scroll.max-scroll)))

(fn next-virtual-list-materializes-visible-window []
  (var builds 0)
  (local list
    (VirtualListWidget {:item-count 200
                        :item-height 0.05
                        :width 1.0
                        :height 0.3
                        :item-builder (fn [idx]
                                        (set builds (+ builds 1))
                                        (TextWidget {:text (.. "item-" idx)
                                                     :scale 0.04}))}))
  (NextLayout.run-frame list 1.0 0.3 0)
  (local first-builds builds)
  (assert (> first-builds 0))
  (assert (< first-builds 40))
  (list:set-scroll-y 4.0)
  (NextLayout.run-frame list 1.0 0.3 0)
  (assert (> builds first-builds))
  (assert (>= list.first-visible-index 70)))

(fn next-virtual-list-range-updates-when-item-count-changes []
  (local list
    (VirtualListWidget {:item-count 10
                        :item-height 0.1
                        :width 1.0
                        :height 0.3
                        :item-builder (fn [idx]
                                        (TextWidget {:text (.. "r-" idx)
                                                     :scale 0.05}))}))
  (NextLayout.run-frame list 1.0 0.3 0)
  (local before-max list.max-scroll)
  (list:set-item-count 30)
  (NextLayout.run-frame list 1.0 0.3 0)
  (assert (> list.max-scroll before-max)))

(fn next-scroll-widget-composes-parent-and-local-clip-matrices []
  (local content (TextWidget {:text "abc" :scale 0.05}))
  (local scroll (ScrollWidget {:child content
                               :width 1.0
                               :height 0.3}))
  (NextLayout.run-frame scroll 1.0 0.3 0)
  (local local-only (scroll:get-clip-matrix nil))
  (local parent-matrix (glm.mat4-trs-z 0.5 0 0 0))
  (local composed (scroll:get-clip-matrix parent-matrix))
  (assert (matrix-any-diff? composed local-only)
          "composed clip matrix should include parent transform"))

(table.insert tests {:name "Next scroll widget clamps scroll offset"
                     :fn next-scroll-widget-clamps-offset})
(table.insert tests {:name "Next virtual list renders only visible window"
                     :fn next-virtual-list-materializes-visible-window})
(table.insert tests {:name "Next virtual list updates max-scroll on item-count change"
                     :fn next-virtual-list-range-updates-when-item-count-changes})
(table.insert tests {:name "Next scroll widget composes nested clip matrices"
                     :fn next-scroll-widget-composes-parent-and-local-clip-matrices})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-app-scroll-and-list"
                       :tests tests})))

{:name "next-app-scroll-and-list"
 :tests tests
 :main main}
