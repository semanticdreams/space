(local Harness (require :tests.e2e.harness))
(local Dialog (require :dialog))
(local Text (require :text))
(local TextStyle (require :text-style))
(local glm (require :glm))
(local viewport-utils (require :viewport-utils))

(fn project-to-screen [position view projection viewport]
  (assert (and glm glm.project) "glm.project is required for e2e HUD resize")
  (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
  (local projected (glm.project position view projection viewport-vec))
  (assert projected "glm.project returned nil")
  (glm.vec3 projected.x
            (- (+ viewport.height viewport.y) projected.y)
            projected.z))

(fn screen-point-for-layout [hud layout offset]
  (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
  (local world-pos (+ layout.position (rotation:rotate offset)))
  (local viewport (viewport-utils.to-table app.viewport))
  (local units-per-pixel (or hud.world-units-per-pixel 1))
  (local manual {:x (+ (/ world-pos.x units-per-pixel) (/ viewport.width 2))
                 :y (- (/ viewport.height 2) (/ world-pos.y units-per-pixel))})
  (local projected (project-to-screen world-pos
                                      (hud:get-view-matrix)
                                      hud.projection
                                      viewport))
  (values manual projected world-pos))

(fn format-vec3 [value]
  (if (not value)
      "nil"
      (let [x (or value.x (. value 1) 0)
            y (or value.y (. value 2) 0)
            z (or value.z (. value 3) 0)]
        (string.format "(%.3f, %.3f, %.3f)" x y z))))

(fn resize-dialog [ctx]
  (local hud (Harness.make-hud-target {:width ctx.width
                                      :height ctx.height
                                      :builder (Harness.make-test-hud-builder)}))
  (set app.hud hud)
  (hud:update)
  (local float-layout (and hud.float hud.float.layout))
  (assert float-layout "e2e HUD resize requires float layout")
  (local float-center
    (+ float-layout.position
       (glm.vec3 (/ float-layout.size.x 2)
                 (/ float-layout.size.y 2)
                 0)))
  (local theme (app.themes.get-active-theme))
  (local text-color (and theme theme.text theme.text.foreground))
  (local child-style (TextStyle {:scale 2
                                 :color (or text-color (glm.vec4 1 1 1 1))}))
  (local dialog-builder
    (Dialog {:title "Resize"
             :child (fn [child-ctx]
                      ((Text {:text "Alt+Right drag"
                              :style child-style}) child-ctx))}))
  (local element (hud:add-panel-child {:builder dialog-builder
                                       :location :float
                                       :position float-center
                                       :size (glm.vec3 18 10 0)}))
  (assert element "e2e HUD resize expected dialog")
  (hud:update)
  (local wrapper element.__hud_wrapper)
  (assert wrapper "e2e HUD resize expected wrapper")
  (local layout wrapper.layout)
  (assert layout "e2e HUD resize expected wrapper layout")
  (local initial-size (or layout.size layout.measure (glm.vec3 0 0 0)))
  (Harness.draw-targets ctx.width ctx.height [{:target hud}])
  (Harness.capture-snapshot {:name "hud-float-resize-baseline"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 3})
  (local size (or layout.size layout.measure (glm.vec3 0 0 0)))
  (local margin 0.4)
  (local offset (glm.vec3 (- size.x margin)
                          (- size.y margin)
                          0))
  (let [(manual projected world-pos) (screen-point-for-layout hud layout offset)]
    (local ray-manual (hud:screen-pos-ray manual))
    (local ray-proj (hud:screen-pos-ray projected))
    (let [(hit-manual _point-manual _distance-manual) (layout:intersect ray-manual)
          (hit-proj _point-proj _distance-proj) (layout:intersect ray-proj)]
      (assert (or hit-manual hit-proj) "HUD resize expected a hit test")
      (var start nil)
      (if hit-manual
          (set start manual)
          (set start projected))
      (local end {:x (+ start.x 40)
                  :y (+ start.y 30)
                  :mod 256
                  :button 3})
      (local payload-down {:button 3
                           :x start.x
                           :y start.y
                           :mod 256})
      (local payload-move {:x end.x
                           :y end.y
                           :mod 256})
      (local payload-up {:button 3
                         :x end.x
                         :y end.y
                         :mod 256})
      (local state (app.states:active-state))
      (assert state "e2e HUD resize requires active state")
      (state.on-mouse-button-down payload-down)
      (assert (and app.resizables (app.resizables:drag-engaged?))
              "HUD resize expected to engage resizables")
      (state.on-mouse-motion payload-move)
      (state.on-mouse-button-up payload-up)
      (hud:update)))
  (local final-size (or layout.size layout.measure (glm.vec3 0 0 0)))
  (assert (> final-size.x initial-size.x) "HUD resize should increase width")
  (Harness.draw-targets ctx.width ctx.height [{:target hud}])
  (Harness.capture-snapshot {:name "hud-float-resize"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 3})
  hud)

(fn run [ctx]
  (local previous-hud app.hud)
  (var hud nil)
  (let [(ok err)
        (pcall (fn []
                 (set hud (resize-dialog ctx))))]
    (set app.hud previous-hud)
    (when hud
      (Harness.cleanup-target hud))
    (when (not ok)
      (error err))))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E hud float resize snapshot complete"))

{:run run
 :main main}
