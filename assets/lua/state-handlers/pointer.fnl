(local Runtime (require :state-runtime))
(local Common (require :state-handlers/common))

(local SDL_BUTTON_LEFT 1)
(local SDL_BUTTON_RIGHT 3)

(local InputMouseButtonDownDispatch
  {:mouse-button-down (fn [ctx payload]
                        (when (Runtime.dispatch-input :on-mouse-button-down payload)
                          ((. ctx :mark-event-consumed!))))})

(local ResizableMouseButtonDown
  {:mouse-button-down
   (fn [ctx payload]
     (local app ((. Common :app-from) ctx))
     (local mouse-down (and app.resizables app.resizables.on-mouse-button-down))
     (when (and (not ((. ctx :event-consumed?)))
                mouse-down
                (= payload.button SDL_BUTTON_RIGHT)
                (Runtime.alt-held? payload))
       (mouse-down app.resizables payload)))})

(local ClickableMouseButtonDown
  {:mouse-button-down
   (fn [ctx payload]
     (local app ((. Common :app-from) ctx))
     (assert app.clickables "state handlers require app.clickables")
     (when (and (not ((. ctx :event-consumed?)))
                (not ((. Common :resize-blocked?))))
       (app.clickables:on-mouse-button-down payload)))})

(local MovableMouseButtonDown
  {:mouse-button-down
   (fn [ctx payload]
     (local app ((. Common :app-from) ctx))
     (local mouse-down (and app.movables app.movables.on-mouse-button-down))
     (when (and (not ((. ctx :event-consumed?)))
                mouse-down
                (= payload.button SDL_BUTTON_LEFT)
                (Runtime.alt-held? payload))
       (mouse-down app.movables payload)))})

(local SelectionMouseButtonDown
  {:mouse-button-down
   (fn [ctx payload]
     (local selector ((. Common :selector-from) ctx))
     (when (and (not ((. ctx :event-consumed?)))
                selector
                (not ((. Common :pointer-blocked?)))
                (= payload.button SDL_BUTTON_LEFT))
       (selector:on-mouse-button payload)
       ((. ctx :mark-event-consumed!))))})

(local CameraMouseButtonDown
  {:mouse-button-down
   (fn [ctx payload]
     (local controls ((. Common :controls-from) ctx))
     (local handler (and controls controls.on-mouse-button-down))
     (when (and (not ((. ctx :event-consumed?)))
                handler
                (not ((. Common :pointer-blocked?))))
       (handler controls payload)
       ((. ctx :mark-event-consumed!))))})

(local InputMouseButtonUpDispatch
  {:mouse-button-up (fn [ctx payload]
                      (when (Runtime.dispatch-input :on-mouse-button-up payload)
                        ((. ctx :mark-event-consumed!))))})

(local ResizableMouseButtonUp
  {:mouse-button-up
   (fn [ctx payload]
     (local app ((. Common :app-from) ctx))
     (local mouse-up (and app.resizables app.resizables.on-mouse-button-up))
     (when (and (not ((. ctx :event-consumed?)))
                mouse-up
                (= payload.button SDL_BUTTON_RIGHT))
       (mouse-up app.resizables payload)))})

(local ClickableMouseButtonUp
  {:mouse-button-up
   (fn [ctx payload]
     (local app ((. Common :app-from) ctx))
     (assert app.clickables "state handlers require app.clickables")
     (when (and (not ((. ctx :event-consumed?)))
                (not ((. Common :resize-blocked?))))
       (app.clickables:on-mouse-button-up payload)))})

(local MovableMouseButtonUp
  {:mouse-button-up
   (fn [ctx payload]
     (local app ((. Common :app-from) ctx))
     (local mouse-up (and app.movables app.movables.on-mouse-button-up))
     (when (and (not ((. ctx :event-consumed?))) mouse-up)
       (mouse-up app.movables payload)))})

(local SelectionMouseButtonUp
  {:mouse-button-up
   (fn [ctx payload]
     (local selector ((. Common :selector-from) ctx))
     (when (and (not ((. ctx :event-consumed?)))
                selector
                (not ((. Common :pointer-blocked?)))
                (= payload.button SDL_BUTTON_LEFT))
       (selector:on-mouse-button payload)
       ((. ctx :mark-event-consumed!))))})

(local CameraMouseButtonUp
  {:mouse-button-up
   (fn [ctx payload]
     (local controls ((. Common :controls-from) ctx))
     (local handler (and controls controls.on-mouse-button-up))
     (when (and (not ((. ctx :event-consumed?)))
                handler
                (not ((. Common :pointer-blocked?))))
       (handler controls payload)
       ((. ctx :mark-event-consumed!))))})

(local InputMouseMotionDispatch
  {:mouse-motion (fn [ctx payload]
                   (when (Runtime.dispatch-input :on-mouse-motion payload)
                     ((. ctx :mark-event-consumed!))))})

(local MovableMouseMotion
  {:mouse-motion
   (fn [ctx payload]
     (local app ((. Common :app-from) ctx))
     (local motion (and app.movables app.movables.on-mouse-motion))
     (when (and (not ((. ctx :event-consumed?))) motion)
       (motion app.movables payload)))})

(local ResizableMouseMotion
  {:mouse-motion
   (fn [ctx payload]
     (local app ((. Common :app-from) ctx))
     (local motion (and app.resizables app.resizables.on-mouse-motion))
     (when (and (not ((. ctx :event-consumed?))) motion)
       (motion app.resizables payload)))})

(local CameraDragMouseMotion
  {:mouse-motion
   (fn [ctx payload]
     (local controls ((. Common :controls-from) ctx))
     (local handler (and controls controls.on-mouse-motion))
     (local dragging? (and controls controls.drag-active? (controls:drag-active?)))
     (when (and (not ((. ctx :event-consumed?)))
                handler
                dragging?
                (not ((. Common :pointer-blocked?))))
       (controls:on-mouse-motion payload)
       ((. ctx :mark-event-consumed!))))})

(local SelectionMouseMotion
  {:mouse-motion
   (fn [ctx payload]
     (local selector ((. Common :selector-from) ctx))
     (local active? (and selector (Runtime.selection-active?)))
     (when (and (not ((. ctx :event-consumed?))) active?)
       (selector:on-mouse-motion payload)
       ((. ctx :mark-event-consumed!))))})

(local CameraMouseMotion
  {:mouse-motion
   (fn [ctx payload]
     (local controls ((. Common :controls-from) ctx))
     (local handler (and controls controls.on-mouse-motion))
     (when (and (not ((. ctx :event-consumed?)))
                handler
                (not ((. Common :move-blocked?)))
                (not ((. Common :resize-blocked?))))
       (controls:on-mouse-motion payload)))})

(local InputMouseWheelDispatch
  {:mouse-wheel (fn [_ctx payload]
                  (Runtime.dispatch-input :on-mouse-wheel payload))})

(local HoveredMouseWheel
  {:mouse-wheel (fn [_ctx payload]
                  (Runtime.dispatch-hovered-mouse-wheel payload))})

(local CameraMouseWheel
  {:mouse-wheel
   (fn [ctx payload]
     (local controls ((. Common :controls-from) ctx))
     (when controls
       (controls:on-mouse-wheel payload)))})

{:InputMouseButtonDownDispatch InputMouseButtonDownDispatch
 :ResizableMouseButtonDown ResizableMouseButtonDown
 :ClickableMouseButtonDown ClickableMouseButtonDown
 :MovableMouseButtonDown MovableMouseButtonDown
 :SelectionMouseButtonDown SelectionMouseButtonDown
 :CameraMouseButtonDown CameraMouseButtonDown
 :InputMouseButtonUpDispatch InputMouseButtonUpDispatch
 :ResizableMouseButtonUp ResizableMouseButtonUp
 :ClickableMouseButtonUp ClickableMouseButtonUp
 :MovableMouseButtonUp MovableMouseButtonUp
 :SelectionMouseButtonUp SelectionMouseButtonUp
 :CameraMouseButtonUp CameraMouseButtonUp
 :InputMouseMotionDispatch InputMouseMotionDispatch
 :MovableMouseMotion MovableMouseMotion
 :ResizableMouseMotion ResizableMouseMotion
 :CameraDragMouseMotion CameraDragMouseMotion
 :SelectionMouseMotion SelectionMouseMotion
 :CameraMouseMotion CameraMouseMotion
 :InputMouseWheelDispatch InputMouseWheelDispatch
 :HoveredMouseWheel HoveredMouseWheel
 :CameraMouseWheel CameraMouseWheel}
