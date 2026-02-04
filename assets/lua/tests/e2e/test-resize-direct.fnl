(local Harness (require :tests.e2e.harness))
(local Dialog (require :dialog))
(local Text (require :text))
(local TextStyle (require :text-style))
(local glm (require :glm))
(local viewport-utils (require :viewport-utils))
(local input-model (require :input-model)) (local glm (require :glm))

(fn project-to-screen [position view projection viewport]
  (assert (and glm glm.project) "glm.project is required")
  (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
  (local projected (glm.project position view projection viewport-vec))
  (assert projected "glm.project returned nil")
  (glm.vec3 projected.x
            (- (+ viewport.height viewport.y) projected.y)
            projected.z))

(fn world-to-screen [hud world-pos]
  (local app _G.app)
  (local viewport (viewport-utils.to-table app.viewport))
  (project-to-screen world-pos
                     (hud:get-view-matrix)
                     hud.projection
                     viewport))

(fn format-vec3 [v]
  (if v
      (string.format "(%.2f, %.2f, %.2f)" (or v.x 0) (or v.y 0) (or v.z 0))
      "nil"))

(fn run-resize-direct-test [ctx]
  (local app _G.app)
  (local hud (Harness.make-hud-target {:width ctx.width
                                       :height ctx.height
                                       :builder (Harness.make-test-hud-builder)}))
  (set app.hud hud)
  (hud:update)
  
  (local child-style (TextStyle {:scale 2 :color (glm.vec4 1 1 1 1)}))
  (local dialog-builder
    (Dialog {:title "Direct Resize Test"
             :child (fn [child-ctx]
                      ((Text {:text "Direct Resize Me" :style child-style}) child-ctx))}))
  
  (local element (hud:add-panel-child {:builder dialog-builder
                                       :location :tiles}))
                                       
  (hud:update)
  (local wrapper element.__hud_wrapper)
  (local layout wrapper.layout)
  (assert (= layout.parent hud.tiles.layout) "Initially in tiles")
  
  (local tile-pos (glm.vec3 (or layout.position.x 0) layout.position.y layout.position.z))
  (print (.. "[RESIZE-DIRECT] Tile position: " (format-vec3 tile-pos)))
  
  ;; Resize Attempt 1
  (local size (or layout.size layout.measure (glm.vec3 10 6 0)))
  (local resize-offset (glm.vec3 (- size.x 0.5) (/ size.y 2) 0)) ;; Right Edge Center-ish
  (local resize-world-start (+ layout.position resize-offset))
  (local resize-screen-start (world-to-screen hud resize-world-start))
  
  (print (.. "[RESIZE-DIRECT] Resize Screen Start: " (format-vec3 resize-screen-start)))
  
  (local state (app.states:active-state))
  (local resize-down {:button 3 :x resize-screen-start.x :y resize-screen-start.y :mod 256})
  (state.on-mouse-button-down resize-down)
  
  (local engaged-1 (and app.resizables (app.resizables:drag-engaged?)))
  (print (.. "[RESIZE-DIRECT] Engaged 1: " (tostring engaged-1)))
  
  ;; Move slightly
  (local move-1 {:x (+ resize-screen-start.x 50) :y resize-screen-start.y :mod 256})
  (state.on-mouse-motion move-1)
  
  ;; Check cancellation
  (local engaged-1-after (and app.resizables (app.resizables:drag-engaged?)))
  (print (.. "[RESIZE-DIRECT] Engaged 1 After Move: " (tostring engaged-1-after)))
  
  (if (not engaged-1-after)
      (error "FAIL: Action 1 Cancelled/Ignored (Bug Reproduced)")
      (print "[RESIZE-DIRECT] SUCCESS: Action 1 Continued"))

  (state.on-mouse-button-up {:button 3 :x move-1.x :y move-1.y :mod 256})
  
  (hud:update)
  
  ;; Check final state
  (local final-pos layout.position)
  (print (.. "[RESIZE-DIRECT] Final Pos: " (format-vec3 final-pos)))
  
  (if (not= layout.parent hud.float.layout)
      (error "FAIL: Element not promoted to float"))
      
  (if (< (math.abs (- final-pos.y tile-pos.y)) 0.1)
      (error "FAIL: Position did not change (Resize failed)"))
      
  (print "[RESIZE-DIRECT] Action 1 (Resize) Complete due to Fix.")
  
  ;; Action 2: Move (Drag)
  ;; Verify if it snaps back to tile position or origin.
  (print "[RESIZE-DIRECT] Starting Action 2: Drag")
  
  (local size-after-resize layout.size)
  (local drag-offset (glm.vec3 (/ size-after-resize.x 2) 1 0))
  (local drag-world-start (+ layout.position drag-offset))
  (local drag-screen-start (world-to-screen hud drag-world-start))
  
  (local drag-down {:button 1 :x drag-screen-start.x :y drag-screen-start.y :mod 256})
  (state.on-mouse-button-down drag-down)
  
  (local drag-engaged (and app.movables (app.movables:drag-engaged?)))
  (print (.. "[RESIZE-DIRECT] Drag Engaged: " (tostring drag-engaged)))
  
  (if (not drag-engaged)
      (error "FAIL: Drag failed to engage after resize"))
      
  (local drag-move {:x (+ drag-screen-start.x 50) :y (+ drag-screen-start.y 50) :mod 0})
  (state.on-mouse-motion drag-move)
  (state.on-mouse-button-up {:button 1 :x drag-move.x :y drag-move.y :mod 0})
  
  (hud:update)
  
  (local final-pos-2 layout.position)
  (print (.. "[RESIZE-DIRECT] Final Pos After Drag: " (format-vec3 final-pos-2)))
  
  ;; Check for snap to original tile pos
  (if (< (math.abs (- final-pos-2.y tile-pos.y)) 1.0)
      (error "CONFIRMED: Snapped back to original tile Y!"))
  
  (print "[RESIZE-DIRECT] Test Passed (No Snap)")
  hud)

(fn run [ctx]
  (local previous-hud app.hud)
  (var hud nil)
  (let [(ok err)
        (pcall (fn []
                 (set hud (run-resize-direct-test ctx))))]
    (set app.hud previous-hud)
    (when hud
      (Harness.cleanup-target hud))
    (when (not ok)
      (error err))))

(fn main []
  (Harness.with-app {} run))

{:run run :main main}
