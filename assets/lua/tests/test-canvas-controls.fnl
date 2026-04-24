(local glm (require :glm))
(local _ (require :main))
(local Canvas (require :canvas))
(local CanvasControls (require :canvas-controls))
(local Camera (require :camera))

(local tests [])

(fn approx [a b epsilon]
  (< (math.abs (- a b)) (or epsilon 1e-6)))

(fn make-canvas [scale-factor]
  (local canvas {:scale-factor (or scale-factor 1.0)})
  (set canvas.set-scale-factor
       (fn [self value]
         (set self.scale-factor value)))
  canvas)

(fn set-test-viewport []
  (if app.set-viewport
      (app.set-viewport {:x 0 :y 0 :width 100 :height 100})
      (set app.viewport {:x 0 :y 0 :width 100 :height 100})))

(fn make-real-canvas [camera]
  (set-test-viewport)
  (local canvas (Canvas {:camera camera}))
  (canvas:on-viewport-changed app.viewport)
  canvas)

(fn scroll-wheel-zooms-canvas-in []
  (local camera (Camera {:position (glm.vec3 0 0 0)}))
  (local canvas (make-canvas 1.0))
  (local controls (CanvasControls {:canvas canvas
                                   :camera camera}))
  (controls:on-mouse-wheel {:x 0 :y 1})
  (assert (< canvas.scale-factor 1.0)
          "Positive mouse wheel input should zoom the canvas in")
  (controls:drop))

(fn scroll-wheel-allows-zooming-past-previous-near-clamp []
  (local camera (Camera {:position (glm.vec3 0 0 0)}))
  (local canvas (make-canvas 1.0))
  (local controls (CanvasControls {:canvas canvas
                                   :camera camera}))
  (for [_ 1 12]
    (controls:on-mouse-wheel {:x 0 :y 1}))
  (assert (< canvas.scale-factor 0.25)
          "Canvas zoom should allow moving closer than the previous 0.25 clamp")
  (for [_ 1 128]
    (controls:on-mouse-wheel {:x 0 :y 1}))
  (assert (approx canvas.scale-factor 0.05 1e-6)
          "Canvas zoom should still clamp at the new near zoom floor")
  (controls:drop))

(fn horizontal-wheel-pans-canvas-camera []
  (local camera (Camera {:position (glm.vec3 0 0 0)}))
  (local canvas (make-canvas 1.0))
  (set canvas.world-units-per-pixel 2.0)
  (local controls (CanvasControls {:canvas canvas
                                   :camera camera}))
  (controls:on-mouse-wheel {:x 1 :y 0})
  (assert (> camera.position.x 0)
          "Positive horizontal wheel input should pan the canvas camera laterally")
  (assert (approx camera.position.y 0)
          "Horizontal wheel panning should not affect vertical camera position")
  (assert (approx camera.position.z 0)
          "Horizontal wheel panning should not affect camera depth")
  (controls:drop))

(fn zoom-in-follows-mouse-pointer-direction []
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local canvas (make-real-canvas camera))
  (local controls (CanvasControls {:canvas canvas
                                   :camera camera}))
  (controls:on-mouse-motion {:x 75 :y 50})
  (controls:on-mouse-wheel {:x 0 :y 1})
  (assert (> camera.position.x 0)
          "Zoom-in should move toward the mouse pointer direction on the canvas plane")
  (assert (approx camera.position.z 100)
          "Pointer-directed canvas zoom should keep camera depth fixed")
  (controls:drop)
  (canvas:drop)
  (camera:drop))

(fn zoom-out-does-not-follow-mouse-pointer-direction []
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local canvas (make-real-canvas camera))
  (local controls (CanvasControls {:canvas canvas
                                   :camera camera}))
  (controls:on-mouse-motion {:x 75 :y 50})
  (controls:on-mouse-wheel {:x 0 :y -1})
  (assert (approx camera.position.x 0)
          "Zoom-out should not recenter toward the mouse pointer")
  (assert (approx camera.position.z 100)
          "Zoom-out should keep camera depth fixed")
  (controls:drop)
  (canvas:drop)
  (camera:drop))

(fn touch-transform-pans-canvas-camera []
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local canvas (make-real-canvas camera))
  (local controls (CanvasControls {:canvas canvas
                                   :camera camera}))
  (assert (controls:on-touch-transform-start {:count 2
                                              :centroid {:x 50 :y 50}
                                              :previous-centroid {:x 50 :y 50}
                                              :span 20
                                              :previous-span 20}))
  (controls:on-touch-transform {:count 2
                                :centroid {:x 60 :y 50}
                                :previous-centroid {:x 50 :y 50}
                                :span 20
                                :previous-span 20})
  (assert (< camera.position.x 0)
          "Two-finger touch pan should move the camera opposite the screen drag")
  (controls:on-touch-transform-end {:gesture {:count 1}})
  (assert (not (controls:drag-active?)))
  (controls:drop)
  (canvas:drop)
  (camera:drop))

(fn pinch-touch-zooms-canvas-in []
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local canvas (make-real-canvas camera))
  (local controls (CanvasControls {:canvas canvas
                                   :camera camera}))
  (controls:on-touch-transform-start {:count 2
                                      :centroid {:x 50 :y 50}
                                      :previous-centroid {:x 50 :y 50}
                                      :span 20
                                      :previous-span 20})
  (controls:on-touch-transform {:count 2
                                :centroid {:x 50 :y 50}
                                :previous-centroid {:x 50 :y 50}
                                :span 40
                                :previous-span 20})
  (assert (< canvas.scale-factor 1.0)
          "Moving fingers apart should zoom the canvas in")
  (controls:drop)
  (canvas:drop)
  (camera:drop))

(fn right-click-without-drag-does-not-suppress-click []
  (local camera (Camera {:position (glm.vec3 0 0 0)}))
  (local canvas (make-canvas 1.0))
  (local controls (CanvasControls {:canvas canvas
                                   :camera camera}))
  (controls:on-mouse-button-down {:button 3 :x 10 :y 12})
  (assert (not (controls:drag-active?))
          "Canvas right click should not count as an active drag before the pan threshold")
  (assert (not (controls:should-suppress-click? {:button 3}))
          "Canvas right click should keep context click enabled before the pan threshold")
  (controls:on-mouse-button-up {:button 3 :x 10 :y 12})
  (controls:drop))

(fn right-drag-suppresses-click-after-pan-threshold []
  (local camera (Camera {:position (glm.vec3 0 0 0)}))
  (local canvas (make-canvas 1.0))
  (local controls (CanvasControls {:canvas canvas
                                   :camera camera}))
  (controls:on-mouse-button-down {:button 3 :x 10 :y 12})
  (controls:on-mouse-motion {:x 30 :y 12})
  (assert (controls:drag-active?)
          "Canvas right drag should engage once motion crosses the pan threshold")
  (assert (< camera.position.x 0)
          "Canvas right drag should start panning immediately on the threshold-crossing motion")
  (assert (controls:should-suppress-click? {:button 3})
          "Canvas right drag should explicitly suppress context click dispatch")
  (controls:on-mouse-button-up {:button 3 :x 30 :y 12})
  (assert (not (controls:drag-active?))
          "Canvas right drag should clear engagement on mouse up")
  (controls:drop))

(table.insert tests {:name "Canvas controls zoom in on mouse wheel"
                     :fn scroll-wheel-zooms-canvas-in})
(table.insert tests {:name "Canvas controls allow deeper zoom before clamping"
                     :fn scroll-wheel-allows-zooming-past-previous-near-clamp})
(table.insert tests {:name "Canvas controls pan laterally on horizontal wheel input"
                     :fn horizontal-wheel-pans-canvas-camera})
(table.insert tests {:name "Canvas controls zoom in toward the mouse pointer"
                     :fn zoom-in-follows-mouse-pointer-direction})
(table.insert tests {:name "Canvas controls zoom out without pointer recentering"
                     :fn zoom-out-does-not-follow-mouse-pointer-direction})
(table.insert tests {:name "Canvas controls pan with touch transform"
                     :fn touch-transform-pans-canvas-camera})
(table.insert tests {:name "Canvas controls zoom with pinch touch transform"
                     :fn pinch-touch-zooms-canvas-in})
(table.insert tests {:name "Canvas controls keep context click enabled before right-drag threshold"
                     :fn right-click-without-drag-does-not-suppress-click})
(table.insert tests {:name "Canvas controls suppress context click after right-drag threshold"
                     :fn right-drag-suppresses-click-after-pan-threshold})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "canvas-controls"
                       :tests tests})))

{:name "canvas-controls"
 :tests tests
 :main main}
