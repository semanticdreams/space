(local InputState (require :input-state-router))
(local Modifiers (require :input-modifiers))

(local SDLK_TAB 9)
(local SDLK_LEFT 1073741904)
(local SDLK_RIGHT 1073741903)
(local SDLK_DOWN 1073741905)
(local SDLK_UP 1073741906)
(local SDL_BUTTON_LEFT 1)
(local SDL_BUTTON_RIGHT 3)
(local KEY_H (string.byte "h"))
(local KEY_J (string.byte "j"))
(local KEY_K (string.byte "k"))
(local KEY_L (string.byte "l"))

(fn movables-active? []
  (and app.movables
       (if app.movables.drag-engaged?
           (app.movables:drag-engaged?)
           (app.movables:drag-active?))))

(fn resizables-active? []
  (and app.resizables
       (if app.resizables.drag-engaged?
           (app.resizables:drag-engaged?)
           (app.resizables:drag-active?))))

(fn clickables-active? []
  (assert app.clickables "state-base requires app.clickables")
  app.clickables.active?)

(fn selection-handler []
  (and app.object-selector app.object-selector))

(fn selection-active? []
  (local handler (selection-handler))
  (and handler (handler:active?)))

(fn hover-eligible? []
  (assert app.hoverables "state-base requires app.hoverables")
  (and app.hoverables
       (not (clickables-active?))
       (not (movables-active?))
       (not (resizables-active?))
       (or (not app.first-person-controls)
           (let [drag? (and app.first-person-controls app.first-person-controls.drag-active?)]
             (not (and drag? (drag? app.first-person-controls)))))))

(fn handle-hover [payload]
  (when (hover-eligible?)
    (app.hoverables:on-mouse-motion payload)))

(fn hovered-object []
  (assert app.hoverables "state-base requires app.hoverables")
  (local getter app.hoverables.get-active-object)
  (local entry (and (not getter) app.hoverables.active-entry))
  (if getter
      (app.hoverables:get-active-object)
      (and entry entry.object)))

(fn dispatch-mouse-wheel [payload]
  (local hovered (hovered-object))
  (local handled
    (and hovered
         hovered.on-mouse-wheel
         (hovered:on-mouse-wheel payload)))
  (if handled
      true
      (and app.first-person-controls
           (app.first-person-controls:on-mouse-wheel payload))))

(fn shift-held? [payload]
  (Modifiers.shift-held? (and payload payload.mod)))

(fn ctrl-held? [payload]
  (Modifiers.ctrl-held? (and payload payload.mod)))

(fn alt-held? [payload]
  (Modifiers.alt-held? (and payload payload.mod)))

(fn handle-focus-tab [payload]
  (if (and app.focus
           payload
           (= payload.key SDLK_TAB)
           (not (ctrl-held? payload))
           (not (alt-held? payload)))
      (do
        (app.focus:focus-next {:backwards? (shift-held? payload)})
        true)
      false))

(fn focus-direction-for-key [key]
  (if (or (= key SDLK_LEFT) (= key KEY_H))
      :left
      (if (or (= key SDLK_RIGHT) (= key KEY_L))
          :right
          (if (or (= key SDLK_UP) (= key KEY_K))
              :up
              (if (or (= key SDLK_DOWN) (= key KEY_J))
                  :down
                  nil)))))

(fn handle-focus-direction [payload]
  (if (and app.focus payload)
      (let [direction (focus-direction-for-key payload.key)]
        (if direction
            (if (InputState.active-input)
                false
                (do
                  (app.focus:focus-direction {:direction direction
                                              :camera app.camera})
                  true))
            false))
      false))

(var ignore-next-text-input-count 0)

(fn ignore-next-text-input []
  (set ignore-next-text-input-count (+ ignore-next-text-input-count 1)))

(fn consume-text-input-ignore []
  (if (> ignore-next-text-input-count 0)
      (do
        (set ignore-next-text-input-count (- ignore-next-text-input-count 1))
        true)
      false))

(fn dispatch-text-input [payload]
  (if (consume-text-input-ignore)
      true
      (InputState.dispatch-input :on-text-input payload)))

(fn dispatch-text-editing [payload]
  (InputState.dispatch-input :on-text-editing payload))

(fn default-on-text-input [payload]
  (dispatch-text-input payload))

(fn default-on-text-editing [payload]
  (dispatch-text-editing payload))

(fn default-on-key-up [payload]
  (local handled (InputState.dispatch-input :on-key-up payload))
  (if handled
      true
      (if (InputState.active-input)
          true
          false)))

(fn default-on-key-down [payload]
  (local handled (InputState.dispatch-input :on-key-down payload))
  (if handled
      true
      (if (handle-focus-tab payload)
          true
          (if (handle-focus-direction payload)
              true
              (if (InputState.active-input)
                  true
                  false)))))

(fn default-on-mouse-button-up [payload]
  (local handled (InputState.dispatch-input :on-mouse-button-up payload))
  (if handled
      true
      (do
        (assert app.clickables "state-base requires app.clickables")
        (when (and app.resizables (= payload.button SDL_BUTTON_RIGHT))
          (app.resizables:on-mouse-button-up payload))
        (local resize-engaged? (resizables-active?))
        (when (not resize-engaged?)
          (app.clickables:on-mouse-button-up payload))
        (when app.movables
          (app.movables:on-mouse-button-up payload))
        (local selector (selection-handler))
        (local controls app.first-person-controls)
        (local click-active? (clickables-active?))
        (local move-active? (movables-active?))
        (local resize-active? (resizables-active?))
        (local selector-handles?
          (and selector
               (not click-active?) (not move-active?) (not resize-active?)
               (= payload.button SDL_BUTTON_LEFT)))
        (if selector-handles?
            (selector:on-mouse-button payload)
            (when (and (not move-active?) (not resize-active?) (not click-active?))
              (local handler (and controls controls.on-mouse-button-up))
              (when handler
                (handler controls payload))))
        (handle-hover payload))))

(fn default-on-mouse-button-down [payload]
  (local handled (InputState.dispatch-input :on-mouse-button-down payload))
  (if handled
      true
      (do
        (assert app.clickables "state-base requires app.clickables")
        (var resize-engaged? false)
        (when (and app.resizables (= payload.button SDL_BUTTON_RIGHT) (alt-held? payload))
          (set resize-engaged? (app.resizables:on-mouse-button-down payload)))
        (when (not resize-engaged?)
          (app.clickables:on-mouse-button-down payload))
        (when (and app.movables (= payload.button SDL_BUTTON_LEFT) (alt-held? payload))
          (app.movables:on-mouse-button-down payload))
        (local selector (selection-handler))
        (local controls app.first-person-controls)
        (local click-active? (clickables-active?))
        (local move-active? (movables-active?))
        (local resize-active? (resizables-active?))
        (local selector-handles?
          (and selector
               (not click-active?) (not move-active?) (not resize-active?)
               (= payload.button SDL_BUTTON_LEFT)))
        (if selector-handles?
            (selector:on-mouse-button payload)
            (when (and (not move-active?) (not resize-active?) (not click-active?))
              (local handler (and controls controls.on-mouse-button-down))
              (when handler
                (handler controls payload)))))))

(fn default-on-mouse-motion [payload]
  (local handled (InputState.dispatch-input :on-mouse-motion payload))
  (if handled
      true
      (do
        (when app.movables
          (app.movables:on-mouse-motion payload))
        (when app.resizables
          (app.resizables:on-mouse-motion payload))
        (local selector (selection-handler))
        (local controls app.first-person-controls)
        (local click-active? (clickables-active?))
        (local move-active? (movables-active?))
        (local resize-active? (resizables-active?))
        (local selector-active? (and selector (selection-active?)))
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
        (handle-hover payload))))

(fn default-on-mouse-wheel [payload]
  (if (InputState.dispatch-input :on-mouse-wheel payload)
      true
      (dispatch-mouse-wheel payload)))

(fn default-on-gamepad-button-down [payload]
  (when app.first-person-controls
    (app.first-person-controls:on-gamepad-button-down payload)))

(fn default-on-gamepad-axis-motion [payload]
  (when app.first-person-controls
    (app.first-person-controls:on-gamepad-axis-motion payload)))

(fn default-on-gamepad-removed [payload]
  (when app.first-person-controls
    (app.first-person-controls:on-gamepad-removed payload)))

(fn default-on-updated [delta]
  (when app.first-person-controls
    (app.first-person-controls:update delta))
  (assert app.hoverables "state-base requires app.hoverables")
  (let [update-fn app.hoverables.update-from-input]
    (when update-fn
      (update-fn app.hoverables))))

(fn register-hover-enter []
  (assert app.hoverables "state-base requires app.hoverables")
  (app.hoverables:on-enter))

(fn register-hover-leave []
  (assert app.hoverables "state-base requires app.hoverables")
  (app.hoverables:on-leave))

(fn make-state [opts]
  (assert opts "state-base requires opts")
  (local handlers
    {:on-text-input (or opts.on-text-input default-on-text-input)
     :on-text-editing (or opts.on-text-editing default-on-text-editing)
     :on-key-down (or opts.on-key-down default-on-key-down)
     :on-key-up (or opts.on-key-up default-on-key-up)
     :on-mouse-button-up (or opts.on-mouse-button-up default-on-mouse-button-up)
     :on-mouse-button-down (or opts.on-mouse-button-down default-on-mouse-button-down)
     :on-mouse-motion (or opts.on-mouse-motion default-on-mouse-motion)
     :on-mouse-wheel (or opts.on-mouse-wheel default-on-mouse-wheel)
     :on-gamepad-button-down (or opts.on-gamepad-button-down default-on-gamepad-button-down)
     :on-gamepad-axis-motion (or opts.on-gamepad-axis-motion default-on-gamepad-axis-motion)
     :on-gamepad-removed (or opts.on-gamepad-removed default-on-gamepad-removed)
     :on-updated (or opts.on-updated default-on-updated)})

  (fn on-enter []
    (app.engine.events.text-input.connect handlers.on-text-input)
    (app.engine.events.text-editing.connect handlers.on-text-editing)
    (app.engine.events.key-up.connect handlers.on-key-up)
    (app.engine.events.key-down.connect handlers.on-key-down)
    (app.engine.events.mouse-button-up.connect handlers.on-mouse-button-up)
    (app.engine.events.mouse-button-down.connect handlers.on-mouse-button-down)
    (app.engine.events.mouse-motion.connect handlers.on-mouse-motion)
    (app.engine.events.mouse-wheel.connect handlers.on-mouse-wheel)
    (app.engine.events.gamepad-button-down.connect handlers.on-gamepad-button-down)
    (app.engine.events.gamepad-axis-motion.connect handlers.on-gamepad-axis-motion)
    (app.engine.events.gamepad-removed.connect handlers.on-gamepad-removed)
    (app.engine.events.updated.connect handlers.on-updated)
    (register-hover-enter)
    (when opts.on-enter
      (opts.on-enter)))

  (fn on-leave []
    (app.engine.events.text-input.disconnect handlers.on-text-input)
    (app.engine.events.text-editing.disconnect handlers.on-text-editing)
    (app.engine.events.key-up.disconnect handlers.on-key-up)
    (app.engine.events.key-down.disconnect handlers.on-key-down)
    (app.engine.events.mouse-button-up.disconnect handlers.on-mouse-button-up)
    (app.engine.events.mouse-button-down.disconnect handlers.on-mouse-button-down)
    (app.engine.events.mouse-motion.disconnect handlers.on-mouse-motion)
    (app.engine.events.mouse-wheel.disconnect handlers.on-mouse-wheel)
    (app.engine.events.gamepad-button-down.disconnect handlers.on-gamepad-button-down)
    (app.engine.events.gamepad-axis-motion.disconnect handlers.on-gamepad-axis-motion)
    (app.engine.events.gamepad-removed.disconnect handlers.on-gamepad-removed)
    (app.engine.events.updated.disconnect handlers.on-updated)
    (register-hover-leave)
    (when opts.on-leave
      (opts.on-leave)))

 {:on-enter on-enter
   :on-leave on-leave
   :on-key-down handlers.on-key-down
   :on-key-up handlers.on-key-up
   :on-mouse-button-up handlers.on-mouse-button-up
   :on-mouse-button-down handlers.on-mouse-button-down
   :on-mouse-motion handlers.on-mouse-motion
   :on-mouse-wheel handlers.on-mouse-wheel
   :on-gamepad-button-down handlers.on-gamepad-button-down
   :on-gamepad-axis-motion handlers.on-gamepad-axis-motion
   :on-gamepad-removed handlers.on-gamepad-removed
   :on-updated handlers.on-updated
   :on-text-input handlers.on-text-input
   :on-text-editing handlers.on-text-editing
   :connect-input InputState.connect-input
   :disconnect-input InputState.disconnect-input
   :active-input (fn [] (InputState.active-input))
   :handle-focus-tab handle-focus-tab
   :shift-held? shift-held?
   :ctrl-held? ctrl-held?})

{:make-state make-state
 :handle-focus-tab handle-focus-tab
 :shift-held? shift-held?
 :ctrl-held? ctrl-held?
 :movables-active? movables-active?
 :clickables-active? clickables-active?
 :hover-eligible? hover-eligible?
 :selection-active? selection-active?
 :ignore-next-text-input ignore-next-text-input
 :dispatch-text-input dispatch-text-input
 :dispatch-text-editing dispatch-text-editing
 :dispatch-mouse-wheel dispatch-mouse-wheel}

;
