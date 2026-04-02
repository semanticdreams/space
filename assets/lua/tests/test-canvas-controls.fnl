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

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "canvas-controls"
                       :tests tests})))

{:name "canvas-controls"
 :tests tests
 :main main}
