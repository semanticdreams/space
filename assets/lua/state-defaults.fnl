(local Runtime (require :state-runtime))

(local SDL_BUTTON_LEFT 1)
(local SDL_BUTTON_RIGHT 3)

(local HoverLifecycle
  {:enter (fn [_ctx]
            (assert app.hoverables "state defaults require app.hoverables")
            (app.hoverables:on-enter))
   :leave (fn [_ctx]
            (assert app.hoverables "state defaults require app.hoverables")
            (app.hoverables:on-leave))})

(local DefaultTextInput
  {:text-input (fn [_ctx payload]
                 (Runtime.dispatch-text-input payload))})

(local DefaultTextEditing
  {:text-editing (fn [_ctx payload]
                   (Runtime.dispatch-text-editing payload))})

(local InputActiveKeyBlock
  {:key-down (fn [_ctx _payload]
               (if (Runtime.active-input)
                   true
                   false))
   :key-up (fn [_ctx _payload]
             (if (Runtime.active-input)
                 true
                 false))})

(local DefaultKeyDown
  {:key-down (fn [_ctx payload]
               (if (Runtime.dispatch-input :on-key-down payload)
                   true
                   (if (Runtime.handle-focus-tab payload)
                       true
                       (if (Runtime.handle-focus-direction payload)
                           true
                           (if (Runtime.active-input)
                               true
                               false)))))})

(local DefaultKeyUp
  {:key-up (fn [_ctx payload]
             (if (Runtime.dispatch-input :on-key-up payload)
                 true
                 (if (Runtime.active-input)
                     true
                     false)))})

(local DefaultMouseButtonDown
  {:mouse-button-down
   (fn [_ctx payload]
     (if (Runtime.dispatch-input :on-mouse-button-down payload)
         true
         (do
           (assert app.clickables "state defaults require app.clickables")
           (var resize-engaged? false)
           (local resizables-mouse-down
             (and app.resizables app.resizables.on-mouse-button-down))
           (when (and resizables-mouse-down
                      (= payload.button SDL_BUTTON_RIGHT)
                      (Runtime.alt-held? payload))
             (set resize-engaged? (resizables-mouse-down app.resizables payload)))
           (when (not resize-engaged?)
             (app.clickables:on-mouse-button-down payload))
           (local movables-mouse-down
             (and app.movables app.movables.on-mouse-button-down))
           (when (and movables-mouse-down
                      (= payload.button SDL_BUTTON_LEFT)
                      (Runtime.alt-held? payload))
             (movables-mouse-down app.movables payload))
           (local selector (Runtime.selection-handler))
           (local controls app.first-person-controls)
           (local click-active? (Runtime.clickables-active?))
           (local move-active? (Runtime.movables-active?))
           (local resize-active? (Runtime.resizables-active?))
           (local selector-handles?
             (and selector
                  (not click-active?)
                  (not move-active?)
                  (not resize-active?)
                  (= payload.button SDL_BUTTON_LEFT)))
           (if selector-handles?
               (selector:on-mouse-button payload)
               (when (and (not move-active?) (not resize-active?) (not click-active?))
                 (local handler (and controls controls.on-mouse-button-down))
                 (when handler
                   (handler controls payload)))))))})

(local DefaultMouseButtonUp
  {:mouse-button-up
   (fn [_ctx payload]
     (if (Runtime.dispatch-input :on-mouse-button-up payload)
         true
         (do
           (assert app.clickables "state defaults require app.clickables")
           (local resizables-mouse-up
             (and app.resizables app.resizables.on-mouse-button-up))
           (when (and resizables-mouse-up (= payload.button SDL_BUTTON_RIGHT))
             (resizables-mouse-up app.resizables payload))
           (local resize-engaged? (Runtime.resizables-active?))
           (when (not resize-engaged?)
             (app.clickables:on-mouse-button-up payload))
           (local movables-mouse-up
             (and app.movables app.movables.on-mouse-button-up))
           (when movables-mouse-up
             (movables-mouse-up app.movables payload))
           (local selector (Runtime.selection-handler))
           (local controls app.first-person-controls)
           (local click-active? (Runtime.clickables-active?))
           (local move-active? (Runtime.movables-active?))
           (local resize-active? (Runtime.resizables-active?))
           (local selector-handles?
             (and selector
                  (not click-active?)
                  (not move-active?)
                  (not resize-active?)
                  (= payload.button SDL_BUTTON_LEFT)))
           (if selector-handles?
               (selector:on-mouse-button payload)
               (when (and (not move-active?) (not resize-active?) (not click-active?))
                 (local handler (and controls controls.on-mouse-button-up))
                 (when handler
                   (handler controls payload))))
           (Runtime.handle-hover payload))))})

(local DefaultMouseMotion
  {:mouse-motion
   (fn [_ctx payload]
     (if (Runtime.dispatch-input :on-mouse-motion payload)
         true
         (do
           (local movables-mouse-motion
             (and app.movables app.movables.on-mouse-motion))
           (when movables-mouse-motion
             (movables-mouse-motion app.movables payload))
           (local resizables-mouse-motion
             (and app.resizables app.resizables.on-mouse-motion))
           (when resizables-mouse-motion
             (resizables-mouse-motion app.resizables payload))
           (local selector (Runtime.selection-handler))
           (local controls app.first-person-controls)
           (local click-active? (Runtime.clickables-active?))
           (local move-active? (Runtime.movables-active?))
           (local resize-active? (Runtime.resizables-active?))
           (local selector-active? (and selector (Runtime.selection-active?)))
           (local controls-handler (and controls controls.on-mouse-motion))
           (local controls-dragging?
             (and controls controls.drag-active? (controls:drag-active?)))
           (fn dispatch-motion []
             (if (and (not move-active?) (not resize-active?) (not click-active?)
                      controls-handler controls-dragging?)
                 (controls:on-mouse-motion payload)
                 (if selector-active?
                     (selector:on-mouse-motion payload)
                     (if (and (not move-active?) (not resize-active?) controls-handler)
                         (controls:on-mouse-motion payload)))))
           (dispatch-motion)
           (Runtime.handle-hover payload))))})

(local DefaultMouseWheel
  {:mouse-wheel (fn [_ctx payload]
                  (if (Runtime.dispatch-input :on-mouse-wheel payload)
                      true
                      (Runtime.dispatch-mouse-wheel payload)))})

(local DefaultGamepad
  {:gamepad-button-down (fn [_ctx payload]
                          (when app.first-person-controls
                            (app.first-person-controls:on-gamepad-button-down payload)))
   :gamepad-axis-motion (fn [_ctx payload]
                          (when app.first-person-controls
                            (app.first-person-controls:on-gamepad-axis-motion payload)))
   :gamepad-removed (fn [_ctx payload]
                      (when app.first-person-controls
                        (app.first-person-controls:on-gamepad-removed payload)))})

(local DefaultUpdated
  {:updated (fn [_ctx delta]
              (when app.first-person-controls
                (app.first-person-controls:update delta))
              (assert app.hoverables "state defaults require app.hoverables")
              (local update-fn app.hoverables.update-from-input)
              (when update-fn
                (update-fn app.hoverables)))})

{:HoverLifecycle HoverLifecycle
 :DefaultTextInput DefaultTextInput
 :DefaultTextEditing DefaultTextEditing
 :DefaultKeyDown DefaultKeyDown
 :DefaultKeyUp DefaultKeyUp
 :DefaultMouseButtonDown DefaultMouseButtonDown
 :DefaultMouseButtonUp DefaultMouseButtonUp
 :DefaultMouseMotion DefaultMouseMotion
 :DefaultMouseWheel DefaultMouseWheel
 :DefaultGamepad DefaultGamepad
 :DefaultUpdated DefaultUpdated}
