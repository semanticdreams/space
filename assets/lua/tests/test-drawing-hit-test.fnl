(local glm (require :glm))
(local HitTest (require :drawing/hit-test))

(local tests [])

(fn approx= [actual expected]
  (< (math.abs (- actual expected)) 0.0001))

(fn screen-pos-to-canvas-point-uses-active-presentation-canvas-ray []
  (local old-presentation-screen-pos-ray app.presentation-screen-pos-ray)
  (local calls [])
  (set app.presentation-screen-pos-ray
       (fn [pos opts]
         (table.insert calls {:pos pos :opts opts})
         (assert (= opts.surface :canvas)
                 "drawing hit-test should request the active canvas presentation ray")
         {:origin (glm.vec3 2 4 10)
          :direction (glm.vec3 0 0 -2)}))
  (local raw-canvas
    {:screen-pos-ray (fn [_self _pos _opts]
                       (error "raw canvas ray must not be used"))})
  (local (ok result-or-err)
    (pcall (fn []
             (HitTest.screen-pos->canvas-point raw-canvas {:x 12 :y 34}))))
  (set app.presentation-screen-pos-ray old-presentation-screen-pos-ray)
  (when (not ok)
    (error result-or-err))
  (assert (= (length calls) 1)
          "drawing hit-test should resolve exactly one presentation ray")
  (assert (approx= result-or-err.x 2))
  (assert (approx= result-or-err.y 4))
  (assert (approx= result-or-err.z 0)))

(table.insert tests {:name "Drawing hit-testing uses active presentation canvas ray"
                     :fn screen-pos-to-canvas-point-uses-active-presentation-canvas-ray})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-hit-test"
                       :tests tests})))

{:name "drawing-hit-test"
 :tests tests
 :main main}
