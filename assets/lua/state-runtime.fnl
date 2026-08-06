(local InputState (require :input-state-router))
(local Modifiers (require :input-modifiers))

(local SDLK_TAB 9)
(local SDLK_LEFT 1073741904)
(local SDLK_RIGHT 1073741903)
(local SDLK_DOWN 1073741905)
(local SDLK_UP 1073741906)
(local KEY_H (string.byte "h"))
(local KEY_J (string.byte "j"))
(local KEY_K (string.byte "k"))
(local KEY_L (string.byte "l"))

(var ignore-next-text-input-count 0)

(fn shift-held? [payload]
  (Modifiers.shift-held? (and payload payload.mod)))

(fn ctrl-held? [payload]
  (Modifiers.ctrl-held? (and payload payload.mod)))

(fn alt-held? [payload]
  (Modifiers.alt-held? (and payload payload.mod)))

(fn activity-object-drag-mode []
  (if app.activity-object-drag-mode-provider
      (do
        (local mode (app.activity-object-drag-mode-provider))
        (if (or (= mode nil)
                (= mode :move)
                (= mode :grab))
            mode
            (error (.. "Invalid activity object drag mode: " (tostring mode)))))
      nil))

(fn drag-attachment-mode []
  (if (= (activity-object-drag-mode) :grab)
      :anchor
      :center))

(fn clickables-active? []
  (assert app.clickables "state runtime requires app.clickables")
  app.clickables.active?)

(fn active-controls []
  (or (and app.presentation-input-controls
           (app.presentation-input-controls))
      app.active-pointer-controls))

(fn movables-active? []
  (and app.movables
       (if app.movables.drag-engaged?
           (app.movables:drag-engaged?)
           (and app.movables.drag-active?
                (app.movables:drag-active?)))))

(fn resizables-active? []
  (and app.resizables
       (if app.resizables.drag-engaged?
           (app.resizables:drag-engaged?)
           (and app.resizables.drag-active?
                (app.resizables:drag-active?)))))

(fn selection-handler []
  (and app.object-selector app.object-selector))

(fn selection-active? []
  (local handler (selection-handler))
  (and handler (handler:active?)))

(fn hover-eligible? []
  (assert app.hoverables "state runtime requires app.hoverables")
  (and app.hoverables
       (not (clickables-active?))
       (not (movables-active?))
       (not (resizables-active?))
       (do
         (local controls (active-controls))
         (or (not controls)
             (do
               (local drag? (and controls controls.drag-active?))
               (not (and drag? (drag? controls))))))))

(fn handle-hover [payload] (local hoverables (assert app.hoverables "state runtime requires app.hoverables"))
  (when (hover-eligible?)
    (hoverables:on-mouse-motion payload)))

(fn hovered-object []
  (assert app.hoverables "state runtime requires app.hoverables")
  (local getter app.hoverables.get-active-object)
  (local entry (and (not getter) app.hoverables.active-entry))
  (if getter
      (app.hoverables:get-active-object)
      (and entry entry.object)))

(fn dispatch-hovered-mouse-wheel [payload]
  (local hovered (hovered-object))
  (and hovered
       hovered.on-mouse-wheel
       (hovered:on-mouse-wheel payload)))

(fn dispatch-mouse-wheel [payload]
  (local handled (dispatch-hovered-mouse-wheel payload))
  (if handled
      true
      (do
        (local controls (active-controls))
        (and controls
             (controls:on-mouse-wheel payload)))))

(fn ctx-focus-manager [ctx action]
  (assert (and ctx ctx.focus-manager)
          "state runtime focus handling requires ctx.focus-manager")
  (local focus-manager ((. ctx :focus-manager)))
  (assert focus-manager
          (.. "state runtime focus handling requires a focus manager for " action))
  focus-manager)

(fn handle-focus-tab [ctx payload]
  (if (and payload
           (= payload.key SDLK_TAB)
           (not (ctrl-held? payload))
           (not (alt-held? payload)))
      (do
        (local focus-manager (ctx-focus-manager ctx "tab navigation"))
        (assert focus-manager.focus-next
                "state runtime focus tab handling requires focus-manager:focus-next")
        (focus-manager:focus-next {:backwards? (shift-held? payload)})
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

(fn handle-focus-direction [ctx payload]
  (if payload
      (do
        (local direction (focus-direction-for-key payload.key))
        (if direction
            (if (InputState.active-input)
                false
                (do
                  (local focus-manager (ctx-focus-manager ctx "directional navigation"))
                  (assert focus-manager.focus-direction
                          "state runtime focus direction handling requires focus-manager:focus-direction")
                  (focus-manager:focus-direction {:direction direction
                                                   :camera (app.presentation-camera)})
                  true))
            false))
      false))

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

(fn reset []
  (set ignore-next-text-input-count 0)
  (InputState.reset))

{:shift-held? shift-held?
 :ctrl-held? ctrl-held?
 :alt-held? alt-held?
 :activity-object-drag-mode activity-object-drag-mode
 :drag-attachment-mode drag-attachment-mode
 :active-controls active-controls
 :clickables-active? clickables-active?
 :movables-active? movables-active?
 :resizables-active? resizables-active?
 :selection-handler selection-handler
 :selection-active? selection-active?
 :hover-eligible? hover-eligible?
 :handle-hover handle-hover
 :hovered-object hovered-object
 :dispatch-hovered-mouse-wheel dispatch-hovered-mouse-wheel
 :dispatch-mouse-wheel dispatch-mouse-wheel
 :handle-focus-tab handle-focus-tab
 :handle-focus-direction handle-focus-direction
 :ignore-next-text-input ignore-next-text-input
 :dispatch-text-input dispatch-text-input
 :dispatch-text-editing dispatch-text-editing
 :reset reset
 :dispatch-input InputState.dispatch-input
 :connect-input InputState.connect-input
 :disconnect-input InputState.disconnect-input
 :active-input (fn [] (InputState.active-input))}
