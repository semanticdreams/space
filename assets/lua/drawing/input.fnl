(local Runtime (require :state-runtime))
(local Common (require :state-handlers/common))
(local HitTest (require :drawing/hit-test))

(local SDL_BUTTON_LEFT 1)
(local SDLK_DELETE 127)
(local KEY_Z_LOWER (string.byte "z"))
(local KEY_Z_UPPER (string.byte "Z"))
(local KEY_Y_LOWER (string.byte "y"))
(local KEY_Y_UPPER (string.byte "Y"))
(local SDLK_ESCAPE 27)

(fn active-input []
  (and Runtime.active-input
       (Runtime.active-input)))

(fn active-controller []
  (and app.drawing-controller
       (= app.canvas-interactive? true)
       (= app.active-canvas-feature "drawing")
       app.drawing-controller))

(fn active-canvas-point [payload]
  (and app.canvas
       (HitTest.screen-pos->canvas-point app.canvas payload)))

(fn hit-tolerance []
  (* (or (and app.canvas app.canvas.world-units-per-pixel) 1.0) 8.0))

(fn active-layer []
  (and app.drawing-controller app.drawing-controller.active-layer
       (app.drawing-controller:active-layer)))

(local DrawingKeyDown
  {:key-down
   (fn [ctx payload]
     (local controller (active-controller))
     (if (or (not controller)
             (active-input))
         false
         (do
           (local key payload.key)
           (if (= key SDLK_DELETE)
               (controller:on-delete-selection)
               (and (Runtime.ctrl-held? payload)
                    (or (= key KEY_Z_LOWER) (= key KEY_Z_UPPER)))
               (controller:on-undo)
               (and (Runtime.ctrl-held? payload)
                    (or (= key KEY_Y_LOWER) (= key KEY_Y_UPPER)))
               (controller:on-redo)
               (= key SDLK_ESCAPE)
               (controller:cancel-gesture)
               false))))})

(local DrawingMouseButtonDown
  {:mouse-button-down
   (fn [ctx payload]
     (local controller (active-controller))
     (local point (and controller (active-canvas-point payload)))
     (when (and controller
                point
                (= payload.button SDL_BUTTON_LEFT)
                (not ((. Common :pointer-blocked?))))
       (local tool (controller:active-tool))
       (local layer (active-layer))
       (if (= tool "select")
           (do
             (local object
               (if (= (and layer layer.kind) "vector")
                   (HitTest.select-object layer point (hit-tolerance))
                   nil))
             (controller:on-select object (Runtime.ctrl-held? payload))
             ((. ctx :mark-event-consumed!))
             true)
           (if (controller:begin-gesture tool point {:pressure (or payload.pressure 1.0)})
               (do
                 (when (and (= tool "eraser")
                            (= (and layer layer.kind) "vector"))
                   (each [_ object-id (ipairs (HitTest.collect-hit-object-ids layer point (hit-tolerance)))]
                     (controller:touch-erase-id! object-id)))
                 ((. ctx :mark-event-consumed!))
                 true)
               false))))})

(local DrawingMouseMotion
  {:mouse-motion
   (fn [_ctx payload]
     (local controller (active-controller))
     (local point (and controller (active-canvas-point payload)))
     (local layer (active-layer))
     (when (and controller point (controller:gesture-active?))
       (controller:update-gesture point (Runtime.shift-held? payload) {:pressure (or payload.pressure 1.0)})
       (when (and (= (controller:active-tool) "eraser")
                  (= (and layer layer.kind) "vector"))
         (each [_ object-id (ipairs (HitTest.collect-hit-object-ids layer point (hit-tolerance)))]
           (controller:touch-erase-id! object-id)))
       ((. _ctx :mark-event-consumed!))
       true))})

(local DrawingMouseButtonUp
  {:mouse-button-up
   (fn [ctx payload]
     (local controller (active-controller))
     (local point (and controller (active-canvas-point payload)))
     (local layer (active-layer))
     (when (and controller point (= payload.button SDL_BUTTON_LEFT))
       (local tool (controller:active-tool))
       (if (= tool "select")
           false
           (if (controller:gesture-active?)
               (do
                 (controller:update-gesture point (Runtime.shift-held? payload) {:pressure (or payload.pressure 1.0)})
                 (when (and (= tool "eraser")
                            (= (and layer layer.kind) "vector"))
                   (each [_ object-id (ipairs (HitTest.collect-hit-object-ids layer point (hit-tolerance)))]
                     (controller:touch-erase-id! object-id)))
                 (controller:commit-gesture)
                 ((. ctx :mark-event-consumed!))
                 true)
               false))))})

{:DrawingKeyDown DrawingKeyDown
 :DrawingMouseButtonDown DrawingMouseButtonDown
 :DrawingMouseMotion DrawingMouseMotion
 :DrawingMouseButtonUp DrawingMouseButtonUp}
