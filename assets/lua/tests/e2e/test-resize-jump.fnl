(local Harness (require :tests.e2e.harness))
(local Dialog (require :dialog))
(local Text (require :text))
(local TextStyle (require :text-style))
(local glm (require :glm))
(local viewport-utils (require :viewport-utils))

;; E2E test to reproduce the "resize jump" bug:
;; 1. Create a dialog in tiles
;; 2. Drag it (promoting to float)
;; 3. Release the drag
;; 4. Resize it
;; 5. Verify the position didn't jump back to origin

(fn project-to-screen [position view projection viewport]
  (assert (and glm glm.project) "glm.project is required")
  (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
  (local projected (glm.project position view projection viewport-vec))
  (assert projected "glm.project returned nil")
  (glm.vec3 projected.x
            (- (+ viewport.height viewport.y) projected.y)
            projected.z))

(fn world-to-screen [hud world-pos]
  (local viewport (viewport-utils.to-table app.viewport))
  (project-to-screen world-pos
                     (hud:get-view-matrix)
                     hud.projection
                     viewport))

(fn format-vec3 [v]
  (if v
      (string.format "(%.2f, %.2f, %.2f)" (or v.x 0) (or v.y 0) (or v.z 0))
      "nil"))

(fn run-resize-jump-test [ctx]
  (local hud (Harness.make-hud-target {:width ctx.width
                                       :height ctx.height
                                       :builder (Harness.make-test-hud-builder)}))
  (set app.hud hud)
  (hud:update)
  
  ;; Create a dialog in the TILES layout (not float)
  (local theme (app.themes.get-active-theme))
  (local text-color (and theme theme.text theme.text.foreground))
  (local child-style (TextStyle {:scale 2 :color (or text-color (glm.vec4 1 1 1 1))}))
  (local dialog-builder
    (Dialog {:title "Resize Jump Test"
             :child (fn [child-ctx]
                      ((Text {:text "Drag then resize me" :style child-style}) child-ctx))}))
  
  ;; Add to tiles (not float!)
  (local element (hud:add-panel-child {:builder dialog-builder
                                       :location :tiles}))
  (assert element "Expected dialog element")
  (hud:update)
  
  (local wrapper element.__hud_wrapper)
  (assert wrapper "Expected wrapper")
  (local layout wrapper.layout)
  (assert layout "Expected layout")
  
  ;; Verify it's in tiles initially
  (assert (= layout.parent hud.tiles.layout) "Dialog should start in tiles")
  
  ;; Get initial position in tiles
  (local tile-pos (glm.vec3 (or layout.position.x 0)
                            (or layout.position.y 0)
                            (or layout.position.z 0)))
  (print (.. "[RESIZE-JUMP] Tile position: " (format-vec3 tile-pos)))
  
  ;; STEP 1: Drag the dialog to promote it to float
  ;; Find the center of the dialog for dragging
  (local size (or layout.size layout.measure (glm.vec3 10 6 0)))
  (local drag-offset (glm.vec3 (/ size.x 2) 1 0)) ;; center-top area for title bar
  (local drag-world-start (+ layout.position drag-offset))
  (local drag-screen-start (world-to-screen hud drag-world-start))
  
  (print (.. "[RESIZE-JUMP] Drag start screen: " (format-vec3 drag-screen-start)))
  
  ;; Simulate drag: mouse down -> motion -> mouse up
  (local state (app.states:active-state))
  (assert state "Required active state")
  
  ;; Start drag
  (local drag-down {:button 1 :x drag-screen-start.x :y drag-screen-start.y :mod 256})
  (state.on-mouse-button-down drag-down)
  
  ;; Check if movables engaged
  (local drag-engaged (and app.movables (app.movables:drag-engaged?)))
  (print (.. "[RESIZE-JUMP] Drag engaged: " (tostring drag-engaged)))
  
  (when (not drag-engaged)
    (print "[RESIZE-JUMP] WARNING: Movables drag not engaged, trying Alt+drag")
    ;; Try Alt+drag
    (state.on-mouse-button-up drag-down)
    (local alt-down {:button 1 :x drag-screen-start.x :y drag-screen-start.y :mod 256})
    (state.on-mouse-button-down alt-down))
  
  ;; Move 50 pixels to the right
  (local drag-end-x (+ drag-screen-start.x 50))
  (local drag-end-y drag-screen-start.y)
  (local drag-move {:x drag-end-x :y drag-end-y :mod 0})
  (state.on-mouse-motion drag-move)
  
  ;; Release
  (local drag-up {:button 1 :x drag-end-x :y drag-end-y :mod 0})
  (state.on-mouse-button-up drag-up)
  
  (hud:update)
  
  ;; Check if promoted to float
  (local in-float (not= layout.parent hud.tiles.layout))
  (print (.. "[RESIZE-JUMP] In float after drag: " (tostring in-float)))
  
  ;; Record position after drag
  (local post-drag-pos (glm.vec3 layout.position.x layout.position.y layout.position.z))
  (print (.. "[RESIZE-JUMP] Post-drag position: " (format-vec3 post-drag-pos)))
  
  ;; Draw intermediate state
  (Harness.draw-targets ctx.width ctx.height [{:target hud}])
  (Harness.capture-snapshot {:name "resize-jump-after-drag"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 3})
  
  ;; STEP 2: Now resize the dialog
  ;; We want to verify that the resize targets the Correct wrapper (FloatLayer) and not the stale Layout (Tiles).
  ;; If it targets the stale Layout, the FloatLayer layouter will overwrite the size changes on the next frame (Size Reset),
  ;; OR if we manage to change position (Top-Left resize), it will reset position (Position Jump).

  (local size-before-resize (glm.vec3 layout.size.x layout.size.y 0))
  (print (.. "[RESIZE-JUMP] Size before resize: " (format-vec3 size-before-resize)))

  ;; Resize from Bottom-Right (standard) - this reliably reproduces the "Size Reset" symptom of the stale target.
  (local resize-offset (glm.vec3 (- size.x 0.5) (- size.y 0.5) 0))
  (local resize-world-start (+ layout.position resize-offset))
  (local resize-screen-start (world-to-screen hud resize-world-start))
  
  (print (.. "[RESIZE-JUMP] Resize start screen: " (format-vec3 resize-screen-start)))
  
  ;; Alt+Right-click for resize (mod 256 = Alt, button 3 = right)
  (local resize-down {:button 3 :x resize-screen-start.x :y resize-screen-start.y :mod 256})
  (state.on-mouse-button-down resize-down)
  
  ;; Check if resize engaged
  (local resize-engaged (and app.resizables (app.resizables:drag-engaged?)))
  (print (.. "[RESIZE-JUMP] Resize engaged: " (tostring resize-engaged)))
  
  ;; Move to resize (+50 width, +20 height)
  (local resize-end-x (+ resize-screen-start.x 50))
  (local resize-end-y (+ resize-screen-start.y 20))
  (local resize-move {:x resize-end-x :y resize-end-y :mod 256})
  (state.on-mouse-motion resize-move)
  
  ;; Release resize
  (local resize-up {:button 3 :x resize-end-x :y resize-end-y :mod 256})
  (state.on-mouse-button-up resize-up)
  
  (hud:update)
  
  ;; Record state after resize
  (local post-resize-pos (glm.vec3 layout.position.x layout.position.y layout.position.z))
  (local post-resize-size (glm.vec3 layout.size.x layout.size.y layout.size.z))
  
  (print (.. "[RESIZE-JUMP] Post-resize position: " (format-vec3 post-resize-pos)))
  (print (.. "[RESIZE-JUMP] Post-resize size: " (format-vec3 post-resize-size)))
  
  ;; THE BUG CHECK:
  ;; 1. Position should be stable (since we resized bottom-right).
  ;; 2. Size SHOULD CHANGE. If it is same as before, it means FloatLayer reset it (Stale Target).
  
  (local x-delta (math.abs (- post-resize-pos.x post-drag-pos.x)))
  (local y-delta (math.abs (- post-resize-pos.y post-drag-pos.y)))
  (local size-delta-x (math.abs (- post-resize-size.x size-before-resize.x)))
  
  (print (.. "[RESIZE-JUMP] Position delta: x=" x-delta " y=" y-delta))
  (print (.. "[RESIZE-JUMP] Size delta X: " size-delta-x))
  
  ;; Capture final snapshot
  (Harness.draw-targets ctx.width ctx.height [{:target hud}])
  (Harness.capture-snapshot {:name "resize-jump-after-resize"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 3})
  
  (when (> x-delta 1.0)
    (print "[RESIZE-JUMP] FAIL: Position jumped!")
    (error "Position jump detected"))

  (when (< size-delta-x 0.1)
    (print "[RESIZE-JUMP] FAIL: Size reset! (Stale Target Bug)")
    (error "Size reset detected - Stale Target Bug confirmed"))
  
  (print "[RESIZE-JUMP] Test passed: position stable and size changed")
  hud)

(fn run [ctx]
  (local previous-hud app.hud)
  (var hud nil)
  (let [(ok err)
        (pcall (fn []
                 (set hud (run-resize-jump-test ctx))))]
    (set app.hud previous-hud)
    (when hud
      (Harness.cleanup-target hud))
    (when (not ok)
      (error err))))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E resize jump test complete"))

{:run run
 :main main}
