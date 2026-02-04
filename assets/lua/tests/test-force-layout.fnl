(local glm (require :glm))
(local tests [])

(local {:ForceLayout ForceLayout :ForceLayoutSignal ForceLayoutSignal} (require :force-layout))
(fn distance [a b]
  (glm.length (- b a)))

(fn layout-relaxes-edge []
  (local layout (ForceLayout))
  (layout:add-node (glm.vec3 -120 0 0))
  (layout:add-node (glm.vec3 120 0 0))
  (layout:add-edge 0 1 true)
  (layout:start)
  (layout:update 40)
  (local positions (layout:get-positions))
  (assert (= (length positions) 2))
  (local dist (distance (. positions 1) (. positions 2)))
  (assert (< dist 240))
  (assert (> dist 40)))

(fn respects-pinned []
  (local layout (ForceLayout))
  (layout:add-node (glm.vec3 0 0 0))
  (layout:add-node (glm.vec3 200 0 0))
  (layout:pin-node 0 true)
  (layout:start)
  (layout:update 40)
  (local positions (layout:get-positions))
  (local pinned-pos (. positions 1))
  (assert (= pinned-pos.x 0))
  (assert (= pinned-pos.y 0)))

(fn emits-stabilized []
  (local layout (ForceLayout (glm.vec3 0 0 0) 50 6250 1 0.02 0.0001 1000 1000 100 0.1))
  (layout:add-node (glm.vec3 0 0 0))
  (layout:start)
  (var fired false)
  (layout.stabilized:connect (fn [] (set fired true)))
  (layout:update 1)
  (assert fired)
  (assert (not layout.active)))

(fn clamps-to-bounds []
  (local layout (ForceLayout))
  (layout:set-bounds (glm.vec3 -100 0 0) (glm.vec3 100 300 0))
  (layout:add-node (glm.vec3 0 400 0))
  (layout:add-node (glm.vec3 0 -50 0))
  (layout:start)
  (layout:update 1)
  (local positions (layout:get-positions))
  (local upper (. positions 1))
  (local lower (. positions 2))
  (assert (<= upper.y 300))
  (assert (>= lower.y 0)))

(fn auto-centers-when-enabled []
  (local layout (ForceLayout))
  (layout:set-bounds (glm.vec3 -40 10 0) (glm.vec3 60 210 0))
  (assert (= layout.center-position.x 10))
  (assert (= layout.center-position.y 110)))

(fn keeps-manual-center-when-disabled []
  (local layout (ForceLayout))
  (set layout.auto-center-within-bounds false)
  (layout:set-center-position (glm.vec3 5 25 0))
  (layout:set-bounds (glm.vec3 -100 0 0) (glm.vec3 100 200 0))
  (assert (= layout.center-position.x 5))
  (assert (= layout.center-position.y 25)))

(table.insert tests {:name "ForceLayout relaxes connected nodes" :fn layout-relaxes-edge})
(table.insert tests {:name "ForceLayout respects pinned nodes" :fn respects-pinned})
(table.insert tests {:name "ForceLayout emits stabilized when thresholds met" :fn emits-stabilized})
(table.insert tests {:name "ForceLayout clamps nodes within bounds" :fn clamps-to-bounds})
(table.insert tests {:name "ForceLayout auto centers within bounds" :fn auto-centers-when-enabled})
(table.insert tests {:name "ForceLayout can disable auto centering" :fn keeps-manual-center-when-disabled})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "force-layout"
                       :tests tests})))

{:name "force-layout"
 :tests tests
 :main main}
