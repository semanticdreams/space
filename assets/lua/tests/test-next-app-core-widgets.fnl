(local _ (require :main))
(local glm (require :glm))
(local NextLayout (require :next-app/layout))
(local ToggleWidget (require :next-app/toggle-widget))
(local ProgressWidget (require :next-app/progress-widget))

(local tests [])

(fn stub-clickables []
  {:register (fn [_ _] nil)
   :unregister (fn [_ _] nil)})

(fn stub-hoverables []
  {:register (fn [_ _] nil)
   :unregister (fn [_ _] nil)})

(fn toggle-widget-click-toggles-state-and-emits []
  (var changed-count 0)
  (local toggle (ToggleWidget {:text "Metrics"
                               :checked? false
                               :clickables (stub-clickables)
                               :hoverables (stub-hoverables)}))
  (toggle.changed.connect (fn [_event]
                            (set changed-count (+ changed-count 1))))
  (assert (= toggle.checked? false))
  (toggle:on-click {:button 1})
  (assert (= toggle.checked? true))
  (assert (= changed-count 1))
  (toggle:on-click {:button 1})
  (assert (= toggle.checked? false))
  (assert (= changed-count 2)))

(fn toggle-widget-layout-updates-knob-position []
  (local toggle (ToggleWidget {:checked? false
                               :width 0.4
                               :height 0.2
                               :clickables (stub-clickables)
                               :hoverables (stub-hoverables)}))
  (NextLayout.run-frame toggle 0.6 0.3 0)
  (local off-x toggle.knob.local-x)
  (toggle:set-checked true)
  (NextLayout.run-frame toggle 0.6 0.3 0)
  (local on-x toggle.knob.local-x)
  (assert (> on-x off-x)))

(fn progress-widget-clamps-and-lays-out-fill []
  (local progress (ProgressWidget {:value 0.25
                                   :width 1.0
                                   :height 0.2}))
  (NextLayout.run-frame progress 1.0 0.2 0)
  (assert (= progress.value 0.25))
  (assert (> progress.fill.width 0))
  (progress:set-value 4)
  (assert (= progress.value 1))
  (NextLayout.run-frame progress 1.0 0.2 0)
  (assert (= progress.fill.width 1.0))
  (progress:set-value -1)
  (assert (= progress.value 0))
  (NextLayout.run-frame progress 1.0 0.2 0)
  (assert (= progress.fill.width 0)))

(table.insert tests {:name "Next toggle widget toggles and emits changed"
                     :fn toggle-widget-click-toggles-state-and-emits})
(table.insert tests {:name "Next toggle widget layout moves knob"
                     :fn toggle-widget-layout-updates-knob-position})
(table.insert tests {:name "Next progress widget clamps values and fill width"
                     :fn progress-widget-clamps-and-lays-out-fill})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-app-core-widgets"
                       :tests tests})))

{:name "next-app-core-widgets"
 :tests tests
 :main main}
