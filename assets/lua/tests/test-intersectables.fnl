(local glm (require :glm))
(local _ (require :main))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))

(local tests [])

(fn with-ray-counter [body]
  (var calls 0)
  (local original app.screen-pos-ray)
  (set app.screen-pos-ray
       (fn [pointer]
         (set calls (+ calls 1))
         {:pointer pointer
          :origin (glm.vec3 0 0 0)
          :direction (glm.vec3 0 0 -1)}))
  (let [(ok result) (pcall body (fn [] calls))]
    (set app.screen-pos-ray original)
    (when (not ok)
      (error result))
    result))

(fn shared-intersector-reuses-rays []
  (with-ray-counter
    (fn [get-count]
      (local intersector (Intersectables))
      (local clickables (Clickables {:intersectables intersector}))
      (local hoverables (Hoverables {:intersectables intersector}))
      (local hover-state {:hovered false})
      (local hover-obj {})
      (set hover-obj.intersect
           (fn [_self _ray]
             (values true nil 0.5)))
      (set hover-obj.on-hovered
           (fn [_self entered]
             (set hover-state.hovered entered)))
      (local click-state {:clicks 0})
      (local click-obj {})
      (set click-obj.intersect
           (fn [_self _ray]
             (values true (glm.vec3 0 0 0) 1)))
      (set click-obj.on-click
           (fn [_self _event]
             (set click-state.clicks (+ click-state.clicks 1))))
      (hoverables:register hover-obj)
      (clickables:register click-obj)
      (local payload {:x 10 :y 15 :button 1 :timestamp 42})
      (hoverables:on-mouse-motion payload)
      (clickables:on-mouse-button-down payload)
      (clickables:on-mouse-button-up payload)
      (assert hover-state.hovered "hover should activate for payload")
      (assert (= click-state.clicks 1) "click should fire once")
      (assert (= (get-count) 1) "ray generation should happen once for shared pointer cache"))))

(fn depth-offset-breaks-distance-ties []
  (with-ray-counter
    (fn [_get-count]
      (local intersector (Intersectables))
      (local pointer {:x 0 :y 0})
      (local back {:layout {:depth-offset-index 1}})
      (local front {:depth-offset-index 5})
      (set back.intersect
           (fn [_self _ray]
             (values true nil 3)))
      (set front.intersect
           (fn [_self _ray]
             (values true nil 3)))
      (local entry (intersector:select-entry [back front] pointer {}))
      (assert (= entry.object front) "higher depth offset index should win at equal distance")
      (set front.intersect
           (fn [_self _ray]
             (values true nil 6)))
      (local closer-entry (intersector:select-entry [back front] pointer {}))
      (assert (= closer-entry.object back) "smaller distance should still win over depth offset"))))

(table.insert tests {:name "Intersectables share ray cache across systems" :fn shared-intersector-reuses-rays})
(table.insert tests {:name "Intersectables use depth offset index to break ties" :fn depth-offset-breaks-distance-ties})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "intersectables"
                       :tests tests})))

{:name "intersectables"
 :tests tests
 :main main}
