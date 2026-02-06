(local _ (require :main))
(local glm (require :glm))
(local States (require :states))
(local NormalState (require :normal-state))
(local LeaderState (require :leader-state))
(local QuitState (require :quit-state))
(local TextState (require :text-state))
(local InsertState (require :insert-state))
(local CameraState (require :camera-state))
(local Camera (require :camera))
(local FpcState (require :fpc-state))
(local InputState (require :input-state-router))
(local StateBase (require :state-base))
(local InputModel (require :input-model))

(local tests [])

(local SHIFT-MOD 1)
(local KEY_ESCAPE 27)
(local KEY_SPACE (string.byte " "))
(local KEY_DELETE 127)
(local KEY_RETURN 13)
(local KEY_C (string.byte "c"))
(local KEY_F (string.byte "f"))
(local KEY_H (string.byte "h"))
(local KEY_J (string.byte "j"))
(local KEY_K (string.byte "k"))
(local KEY_L (string.byte "l"))
(local KEY_F4 1073741885)
(local KEY_Q (string.byte "q"))
(local KEY_LEFT 1073741904)
(local KEY_RIGHT 1073741903)
(local KEY_DOWN 1073741905)
(local KEY_UP 1073741906)

(fn transitions-call-enter-and-leave []
  (local states (States))
  (local log [])
  (fn push [label]
    (table.insert log label))
  (states.add-state :alpha {:on-enter (fn [] (push :alpha-enter))
                            :on-leave (fn [] (push :alpha-leave))})
  (states.add-state :beta {:on-enter (fn [] (push :beta-enter))
                           :on-leave (fn [] (push :beta-leave))})
  (states.set-state :alpha)
  (states.set-state :beta)
  (assert (= (# log) 3))
  (assert (= (. log 1) :alpha-enter))
  (assert (= (. log 2) :alpha-leave))
  (assert (= (. log 3) :beta-enter)))

(fn reselecting-active-state-noops []
  (local states (States))
  (var enters 0)
  (states.add-state :solo {:on-enter (fn [] (set enters (+ enters 1)))})
  (states.set-state :solo)
  (states.set-state :solo)
  (assert (= enters 1)))

(fn state-history-tracks-transitions []
  (local states (States {:history-limit 2}))
  (states.add-state :alpha {})
  (states.add-state :beta {})
  (states.add-state :gamma {})
  (states.set-state :alpha)
  (states.set-state :beta)
  (states.set-state :gamma)
  (local history (states.get-history))
  (local first (. history 1))
  (local second (. history 2))
  (assert (= (# history) 2))
  (assert (= first.previous :alpha))
  (assert (= first.current :beta))
  (assert (= second.previous :beta))
  (assert (= second.current :gamma))
  (states.clear-history)
  (assert (= (# (states.get-history)) 0)))

(fn create-controls-stub []
  (local record
    {:key_down nil
     :key_up nil
     :mouse_wheel nil
     :mouse_motion nil
     :mouse_button_down nil
     :mouse_button_up nil
     :controller_button nil
     :controller_axis nil
     :controller_removed false
     :updated nil})
  (local controls
    {:record record
     :on-key-down (fn [self payload] (set record.key_down payload.key))
     :on-key-up (fn [self payload] (set record.key_up payload.key))
     :on-mouse-wheel (fn [self payload] (set record.mouse_wheel payload.y))
     :on-mouse-motion (fn [self payload] (set record.mouse_motion {:x payload.x :y payload.y}))
     :on-mouse-button-down (fn [self payload] (set record.mouse_button_down payload.button))
     :on-mouse-button-up (fn [self payload] (set record.mouse_button_up payload.button))
     :on-controller-button-down (fn [self payload] (set record.controller_button payload.button))
     :on-controller-axis-motion (fn [self payload] (set record.controller_axis payload.value))
     :on-controller-device-removed (fn [self payload] (set record.controller_removed payload.which))
     :drag-active? (fn [_self] false)
     :update (fn [self delta] (set record.updated delta))})
  controls)

(fn make-hoverables-stub []
  (local record {:enter 0 :leave 0 :motions []})
  (local stub {:record record})
  (set stub.on-enter (fn []
                       (set record.enter (+ record.enter 1))))
  (set stub.on-leave (fn []
                       (set record.leave (+ record.leave 1))))
  (set stub.on-mouse-motion (fn [_self payload]
                              (table.insert record.motions payload)))
  stub)

(fn recorded-motion? [record x y]
  (var found false)
  (each [_ payload (ipairs record.motions)]
    (when (and (= payload.x x) (= payload.y y))
      (set found true)))
  found)

(fn normal-state-forwards-events []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (local original-hoverables app.hoverables)
  (local hoverables (make-hoverables-stub))
  (set app.hoverables hoverables)
  (assert app.hoverables.on-mouse-motion "test hoverables stub missing on-mouse-motion")
  (local state (NormalState))
  (state.on-enter)
  (app.engine.events.key-down.emit {:key 44})
  (app.engine.events.key-up.emit {:key 45})
  (app.engine.events.mouse-wheel.emit {:x 0 :y 2})
  (app.engine.events.mouse-motion.emit {:x 10 :y 20})
  (app.engine.events.mouse-button-down.emit {:button 1 :x 0 :y 0})
  (app.engine.events.mouse-button-up.emit {:button 1 :x 0 :y 0})
  (app.engine.events.controller-button-down.emit {:button 5 :which 1})
  (app.engine.events.controller-axis-motion.emit {:axis 0 :value 0.5 :which 1})
  (app.engine.events.controller-device-removed.emit {:which 1})
  (app.engine.events.updated.emit 0.25)
  (assert (= controls.record.key_down nil))
  (assert (= controls.record.key_up nil))
  (assert (= controls.record.mouse_wheel 2))
  (assert (= controls.record.mouse_motion.x 10))
  (assert (= controls.record.mouse_button_down 1))
  (assert (= controls.record.mouse_button_up 1))
  (assert (= controls.record.controller_button 5))
  (assert (= controls.record.controller_axis 0.5))
  (assert (= controls.record.controller_removed 1))
  (assert (= controls.record.updated 0.25))

  (assert (= hoverables.record.enter 1) "hoverables should receive on-enter")
  (assert (recorded-motion? hoverables.record 10 20) "hoverables should see mouse motion payloads")
  (state.on-leave)
  (assert (= hoverables.record.leave 1) "hoverables should receive on-leave")
  (app.engine.events.key-down.emit {:key 99})
  (assert (= controls.record.key_down nil))
  (set app.first-person-controls nil)
  (set app.hoverables original-hoverables))

(fn normal-state-tab-cycles-focus []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (local calls [])
  (set app.focus {:focus-next (fn [_self opts]
                                  (table.insert calls opts))})
  (local state (NormalState))
  (state.on-enter)
  (app.engine.events.key-down.emit {:key 9 :mod 0})
  (assert (= (# calls) 1) "Tab should invoke focus cycling")
  (assert (= (. (. calls 1) :backwards?) false))
  (assert (= controls.record.key_down nil) "Tab should not reach controls")
  (app.engine.events.key-down.emit {:key 9 :mod 1})
  (assert (= (# calls) 2) "Shift+Tab should also invoke focus cycling")
  (assert (. (. calls 2) :backwards?) "Shift modifier should request backwards traversal")
  (state.on-leave)
  (set app.focus nil)
  (set app.first-person-controls nil))

(fn normal-state-swallows-keys-when-input-active []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (local input {:on-key-down (fn [_self _payload] false)})
  (InputState.connect-input input)
  (local state (NormalState))
  (state.on-enter)
  (app.engine.events.key-down.emit {:key 87})
  (assert (= controls.record.key_down nil) "Input should block controls when connected")
  (state.on-leave)
  (InputState.disconnect-input input)
  (set app.first-person-controls nil))

(fn normal-state-delete-removes-graph-selection []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (var removed 0)
  (set app.graph-view {:remove-selected-nodes (fn [_self]
                                                (set removed (+ removed 1))
                                                1)})
  (local state (NormalState))
  (state.on-enter)
  (app.engine.events.key-down.emit {:key KEY_DELETE})
  (assert (= removed 1) "Delete should trigger graph selection removal")
  (assert (= controls.record.key_down nil) "Handled delete should not reach controls")
  (state.on-leave)
  (set app.graph-view nil)
  (set app.first-person-controls nil))

(fn normal-state-enter-opens-focused-graph-node []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (var opened 0)
  (set app.graph-view {:open-focused-node (fn [_self]
                                            (set opened (+ opened 1))
                                            true)})
  (local state (NormalState))
  (state.on-enter)
  (app.engine.events.key-down.emit {:key KEY_RETURN})
  (assert (= opened 1) "Enter should open focused graph node")
  (assert (= controls.record.key_down nil) "Handled enter should not reach controls")
  (state.on-leave)
  (set app.graph-view nil)
  (set app.first-person-controls nil))

(fn normal-state-directional-focus-triggers []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (local calls [])
  (local camera {:id :cam})
  (set app.camera camera)
  (set app.focus {:focus-direction (fn [_self opts]
                                     (table.insert calls opts))})
  (local state (NormalState))
  (state.on-enter)
  (local keys [KEY_LEFT KEY_RIGHT KEY_UP KEY_DOWN KEY_H KEY_L KEY_K KEY_J])
  (local expected [:left :right :up :down :left :right :up :down])
  (for [i 1 (length keys)]
    (app.engine.events.key-down.emit {:key (. keys i)})
    (local entry (. calls i))
    (assert entry "Directional focus should be invoked")
    (assert (= (. entry :direction) (. expected i)))
    (assert (= (. entry :camera) camera)))
  (state.on-leave)
  (set app.focus nil)
  (set app.camera nil)
  (set app.first-person-controls nil))

(fn normal-state-directional-focus-skips-with-input []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (local calls [])
  (set app.focus {:focus-direction (fn [_self opts]
                                     (table.insert calls opts))})
  (local input {:on-key-down (fn [_self _payload] false)})
  (InputState.connect-input input)
  (local state (NormalState))
  (state.on-enter)
  (app.engine.events.key-down.emit {:key KEY_RIGHT})
  (assert (= (# calls) 0) "Directional focus should skip while input active")
  (state.on-leave)
  (InputState.disconnect-input input)
  (set app.focus nil)
  (set app.first-person-controls nil))

(fn normal-state-f4-toggles-graph-view []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (var created 0)
  (var dropped 0)
  (set app.graph-view-factory (fn []
                                (set created (+ created 1))
                                {:drop (fn [_self]
                                         (set dropped (+ dropped 1)))}))
  (local state (NormalState))
  (state.on-enter)
  (app.engine.events.key-down.emit {:key KEY_F4})
  (assert (= created 1) "F4 should create a graph view when missing")
  (assert app.graph-view "F4 should set app.graph-view")
  (assert (= controls.record.key_down nil) "Handled F4 should not reach controls")
  (app.engine.events.key-down.emit {:key KEY_F4})
  (assert (= dropped 1) "F4 should drop an existing graph view")
  (assert (not app.graph-view) "F4 should clear app.graph-view after drop")
  (state.on-leave)
  (set app.graph-view-factory nil)
  (set app.first-person-controls nil))

(table.insert tests {:name "State transitions call enter/leave hooks" :fn transitions-call-enter-and-leave})
(table.insert tests {:name "Setting the same state twice is a no-op" :fn reselecting-active-state-noops})
(table.insert tests {:name "State history records recent transitions" :fn state-history-tracks-transitions})
(table.insert tests {:name "Normal state forwards events to controls" :fn normal-state-forwards-events})
(table.insert tests {:name "Normal state Tab cycles focus" :fn normal-state-tab-cycles-focus})
(table.insert tests {:name "Normal state swallows keys when input is active" :fn normal-state-swallows-keys-when-input-active})
(table.insert tests {:name "Normal state directional focus triggers" :fn normal-state-directional-focus-triggers})
(table.insert tests {:name "Normal state directional focus skips while input active"
                     :fn normal-state-directional-focus-skips-with-input})
(table.insert tests {:name "Normal state delete removes selected graph nodes" :fn normal-state-delete-removes-graph-selection})
(table.insert tests {:name "Normal state Enter opens focused graph node" :fn normal-state-enter-opens-focused-graph-node})
(table.insert tests {:name "Normal state F4 toggles graph view" :fn normal-state-f4-toggles-graph-view})

(fn with-state-recorder [body]
  (local original app.states)
  (local transitions [])
  (set app.states {:set-state (fn [name]
                                  (table.insert transitions name))
                     :active-name (fn [] :text)})
  (let [(ok result) (pcall (fn [] (body transitions)))]
    (set app.states original)
    (when (not ok)
      (error result))
    result))

(fn normal-state-leader-enters-leader-state []
  (with-state-recorder
    (fn [transitions]
      (local state (NormalState))
      (state.on-key-down {:key KEY_SPACE})
      (assert (= (# transitions) 1) "Space should move to leader state")
      (assert (= (. transitions 1) :leader))
      (state.on-key-down {:key KEY_Q})
      (assert (= (# transitions) 1) "Non-leader keys should defer to base handling"))
    ))

(fn leader-state-c-enters-camera-state []
  (with-state-recorder
    (fn [transitions]
      (local state (LeaderState))
      (state.on-key-down {:key KEY_C})
      (assert (= (# transitions) 1) "C should move to camera state")
      (assert (= (. transitions 1) :camera)))))

(fn camera-state-f-enters-fpc-state []
  (with-state-recorder
    (fn [transitions]
      (local state (CameraState))
      (state.on-key-down {:key KEY_F})
      (assert (= (# transitions) 1) "F should move to fpc state")
      (assert (= (. transitions 1) :fpc)))))

(fn camera-state-escape-exits-to-normal []
  (with-state-recorder
    (fn [transitions]
      (local state (CameraState))
      (state.on-key-down {:key KEY_ESCAPE})
      (assert (= (# transitions) 1) "Escape should move to normal state")
      (assert (= (. transitions 1) :normal)))))

(fn camera-state-zero-resets-camera []
  (with-state-recorder
    (fn [transitions]
      (local original-camera app.camera)
      (local camera (Camera {:position (glm.vec3 1 2 3)
                             :rotation (glm.quat 0 1 0 0)}))
      (set app.camera camera)
      (local state (CameraState))
      (state.on-key-down {:key (string.byte "0")})
      (assert (= (# transitions) 0))
      (assert (= camera.position.x 0))
      (assert (= camera.position.y 0))
      (assert (= camera.position.z 0))
      (assert (= camera.rotation.w 1))
      (assert (= camera.rotation.x 0))
      (assert (= camera.rotation.y 0))
      (assert (= camera.rotation.z 0))
      (camera:drop)
      (set app.camera original-camera))))

(fn fpc-state-escape-exits-to-normal []
  (with-state-recorder
    (fn [transitions]
      (local state (FpcState))
      (state.on-key-down {:key KEY_ESCAPE})
      (assert (= (# transitions) 1) "Escape should move to normal state")
      (assert (= (. transitions 1) :normal)))))

(fn fpc-state-routes-input-only-to-controls []
  (reset-engine-events)
  (local calls {:input 0 :clickables 0 :hover 0 :movables 0})
  (local controls (create-controls-stub))
  (local original-controls app.first-person-controls)
  (local original-clickables app.clickables)
  (local original-hoverables app.hoverables)
  (local original-movables app.movables)
  (set app.first-person-controls controls)
  (set app.clickables {:on-mouse-button-down (fn [_self _payload]
                                               (set calls.clickables (+ calls.clickables 1)))
                       :on-mouse-button-up (fn [_self _payload]
                                             (set calls.clickables (+ calls.clickables 1)))
                       :active? false})
  (set app.hoverables {:on-mouse-motion (fn [_self _payload]
                                          (set calls.hover (+ calls.hover 1)))
                       :on-enter (fn [] nil)
                       :on-leave (fn [] nil)})
  (set app.movables {:on-mouse-motion (fn [_self _payload]
                                        (set calls.movables (+ calls.movables 1)))
                     :drag-active? (fn [_self] false)})
  (local input {:on-key-down (fn [_self _payload]
                               (set calls.input (+ calls.input 1))
                               true)
                :on-mouse-button-down (fn [_self _payload]
                                        (set calls.input (+ calls.input 1))
                                        true)})
  (InputState.connect-input input)
  (local state (FpcState))
  (state.on-enter)
  (app.engine.events.key-down.emit {:key 44})
  (app.engine.events.mouse-button-down.emit {:button 1 :x 0 :y 0})
  (app.engine.events.mouse-motion.emit {:x 5 :y 6})
  (assert (= calls.input 0) "InputState should not receive events in fpc state")
  (assert (= calls.clickables 0) "Clickables should not receive events in fpc state")
  (assert (= calls.hover 0) "Hoverables should not receive events in fpc state")
  (assert (= calls.movables 0) "Movables should not receive events in fpc state")
  (assert (= controls.record.key_down 44))
  (assert (= controls.record.mouse_button_down 1))
  (state.on-leave)
  (InputState.disconnect-input input)
  (set app.clickables original-clickables)
  (set app.hoverables original-hoverables)
  (set app.movables original-movables)
  (set app.first-person-controls original-controls))

(fn leader-state-q-and-escape-transitions []
  (with-state-recorder
    (fn [transitions]
      (local state (LeaderState))
      (state.on-key-down {:key KEY_Q})
      (state.on-key-down {:key KEY_ESCAPE})
      (assert (= (# transitions) 2))
      (assert (= (. transitions 1) :quit))
      (assert (= (. transitions 2) :normal))))
  )

(fn quit-state-quits-and-escapes []
  (local original-quit app.engine.quit)
  (var quit-calls 0)
  (set app.engine.quit (fn [] (set quit-calls (+ quit-calls 1))))
  (let [(ok err)
        (pcall
          (fn []
            (with-state-recorder
              (fn [transitions]
                (local state (QuitState))
                (state.on-key-down {:key KEY_Q})
                (state.on-key-down {:key KEY_ESCAPE})
                (assert (= quit-calls 1) "Quit state should invoke app.engine.quit on q")
                (assert (= (# transitions) 1))
                (assert (= (. transitions 1) :normal))))))]
    (set app.engine.quit original-quit)
    (when (not ok)
      (error err))))

(fn make-input-stub [opts]
  (local options (or opts {}))
  (local model (InputModel {:text (or options.text "")}))
  (local initial-cursor (or options.cursor-index 0))
  (local stub {:model model
               :cursor-index model.cursor-index
               :cursor-line model.cursor-line
               :cursor-column model.cursor-column
               :codepoints model.codepoints
               :lines model.lines
               :mode model.mode
               :deleted-before 0
               :deleted-at 0
               :moved-to nil
               :movement-log []
               :inserted []
               :multiline? (and (= options.multiline? true))})

  (fn sync []
    (set stub.cursor-index model.cursor-index)
    (set stub.cursor-line (or model.cursor-line 0))
    (set stub.cursor-column (or model.cursor-column 0))
    (set stub.codepoints model.codepoints)
    (set stub.lines model.lines)
    (set stub.mode model.mode))

  (set stub.enter-insert-mode (fn [_self]
                                (model:enter-insert-mode)
                                (sync)
                                true))
  (set stub.enter-normal-mode (fn [_self]
                                (model:enter-normal-mode)
                                (sync)
                                true))
  (set stub.move-caret (fn [self delta]
                         (local moved (model:move-caret delta))
                         (table.insert self.movement-log delta)
                         (when moved
                           (sync))
                         moved))
  (set stub.move-caret-to (fn [self position]
                            (local moved (model:move-caret-to position))
                            (set self.moved-to position)
                            (when moved
                              (sync))
                            moved))
  (set stub.delete-before-cursor (fn [self]
                                    (local removed (model:delete-before-cursor))
                                    (when removed
                                      (set self.deleted-before (+ self.deleted-before 1))
                                      (sync))
                                    removed))
  (set stub.delete-at-cursor (fn [self]
                                (local removed (model:delete-at-cursor))
                                (when removed
                                  (set self.deleted-at (+ self.deleted-at 1))
                                  (sync))
                                removed))
  (set stub.insert-text (fn [self text]
                          (when text
                            (table.insert self.inserted text)
                            (model:insert-text text)
                            (sync))
                          true))
  (set stub.on-text-input (fn [self payload]
                            (when (and payload payload.text)
                              (self:insert-text payload.text))
                            true))
  (model:move-caret-to initial-cursor)
  (sync)
  stub)

(fn text-state-handles-navigation []
  (with-state-recorder
    (fn [transitions]
      (local input (make-input-stub {:text "abc"}))
      (InputState.connect-input input)
      (local state (TextState))
      (state.on-key-down {:key (string.byte "i")})
      (StateBase.dispatch-text-input nil)
      (assert (= (. transitions 1) :insert))
      (assert (= input.mode :insert))
      (state.on-key-down {:key (string.byte "h")})
      (state.on-key-down {:key (string.byte "l")})
      (state.on-key-down {:key (string.byte "4") :mod SHIFT-MOD})
      (assert (= input.model.cursor-column 2))
      (state.on-key-down {:key (string.byte "0")})
      (state.on-key-down {:key (string.byte "x")})
      (assert (= input.deleted-at 1))
      (assert (= input.moved-to 0))
      (InputState.disconnect-input input))))

(fn text-state-horizontal-stays-on-line []
  (with-state-recorder
    (fn [_transitions]
      (local input (make-input-stub {:text "alpha\nbeta" :multiline? true}))
      (InputState.connect-input input)
      (input:move-caret-to 5)
      (local state (TextState))
      (state.on-key-down {:key (string.byte "l")})
      (assert (= input.model.cursor-line 0))
      (assert (= input.model.cursor-column 4))
      (input:move-caret-to 6)
      (state.on-key-down {:key (string.byte "h")})
      (assert (= input.model.cursor-line 1))
      (assert (= input.model.cursor-column 0))
      (InputState.disconnect-input input))))

(fn text-state-supports-vertical-navigation []
  (with-state-recorder
    (fn [_transitions]
      (local input (make-input-stub {:text "car\ntruck\nplane" :multiline? true}))
      (InputState.connect-input input)
      (input:move-caret-to 2)
      (local state (TextState))
      (state.on-key-down {:key (string.byte "j")})
      (assert (= input.model.cursor-line 1))
      (assert (= input.model.cursor-column 2))
      (state.on-key-down {:key (string.byte "k")})
      (assert (= input.model.cursor-line 0))
      (InputState.disconnect-input input))))

(fn text-state-open-line-commands []
  (with-state-recorder
    (fn [_transitions]
      (local state (TextState))
      (local below (make-input-stub {:text "foo\nbar" :multiline? true}))
      (InputState.connect-input below)
      (state.on-key-down {:key (string.byte "o")})
      (StateBase.dispatch-text-input nil)
      (assert (= below.mode :insert))
      (assert (= (below.model:get-text) "foo\n\nbar"))
      (InputState.disconnect-input below)

      (local above (make-input-stub {:text "foo\nbar\nbaz" :multiline? true}))
      (InputState.connect-input above)
      (above:move-caret-to 4)
      (state.on-key-down {:key (string.byte "o") :mod SHIFT-MOD})
      (StateBase.dispatch-text-input nil)
      (assert (= (above.model:get-text) "foo\n\nbar\nbaz"))
      (assert (= above.mode :insert))
      (assert (= above.model.cursor-line 1))
      (InputState.disconnect-input above))))

(fn text-state-line-jumps []
  (with-state-recorder
    (fn [_transitions]
      (local input (make-input-stub {:text "one\ntwo\nthree" :multiline? true}))
      (InputState.connect-input input)
      (input:move-caret-to 4)
      (local state (TextState))
      (state.on-key-down {:key (string.byte "g")})
      (state.on-key-down {:key (string.byte "g")})
      (assert (= input.model.cursor-line 0))
      (input:move-caret-to 2)
      (state.on-key-down {:key (string.byte "g") :mod SHIFT-MOD})
      (assert (= input.model.cursor-line 2))
      (assert (= input.model.cursor-column 2))
      (InputState.disconnect-input input))))

(fn text-state-linewise-insert-shortcuts []
  (with-state-recorder
    (fn [_transitions]
      (local state (TextState))
      (local input (make-input-stub {:text "  foo" :multiline? true}))
      (InputState.connect-input input)
      (state.on-key-down {:key (string.byte "i") :mod SHIFT-MOD})
      (StateBase.dispatch-text-input nil)
      (assert (= input.mode :insert))
      (assert (= input.model.cursor-column 2))
      (InputState.disconnect-input input)

      (local append (make-input-stub {:text "bar" :multiline? true}))
      (InputState.connect-input append)
      (state.on-key-down {:key (string.byte "a") :mod SHIFT-MOD})
      (StateBase.dispatch-text-input nil)
      (assert (= append.mode :insert))
      (assert (= append.model.cursor-column 3))
      (InputState.disconnect-input append))))

(fn text-state-clamps-before-delete []
  (with-state-recorder
    (fn [_transitions]
      (local state (TextState))
      (local input (make-input-stub {:text "abc"}))
      (InputState.connect-input input)
      (input:move-caret-to 3)
      (state.on-key-down {:key (string.byte "x")})
      (assert (= input.deleted-at 1))
      (assert (= input.model.cursor-column 1))
      (InputState.disconnect-input input))))

(fn text-state-ignores-text-input-when-entering-insert []
  (with-state-recorder
    (fn [_transitions]
      (local input (make-input-stub))
      (InputState.connect-input input)
      (local text-state (TextState))
      (local insert-state (InsertState))
      (text-state.on-key-down {:key (string.byte "i")})
      (insert-state.on-text-input {:text "i"})
      (insert-state.on-text-input {:text "a"})
      (local inserted-count (# input.inserted))
      (assert (= inserted-count 1)
              (.. "expected 1 inserted value, got " inserted-count))
      (local first-insert (. input.inserted 1))
      (assert (= first-insert "a")
              (.. "expected 'a' as first insert but saw " (tostring first-insert)))
      (InputState.disconnect-input input))))

(fn text-state-swallows-unhandled-keys-when-input-active []
  (with-state-recorder
    (fn [_transitions]
      (local controls (create-controls-stub))
      (set app.first-person-controls controls)
      (local input (make-input-stub {:text "abc"}))
      (InputState.connect-input input)
      (local state (TextState))
      (state.on-key-down {:key (string.byte "z")})
      (assert (= controls.record.key_down nil)
              "Unhandled text keys should not reach controls when input is active")
      (InputState.disconnect-input input)
      (set app.first-person-controls nil))))

(fn insert-state-handles-editing []
  (with-state-recorder
    (fn [transitions]
      (local input (make-input-stub {:text "abcd"}))
      (input:move-caret-to 2)
      (InputState.connect-input input)
      (local state (InsertState))
      (state.on-key-down {:key 27})
      (assert (= (. transitions 1) :text))
      (assert (= input.mode :normal))
      (assert (= input.cursor-index 1))
      (state.on-key-down {:key 8})
      (assert (= input.deleted-before 1))
      (state.on-key-down {:key 127})
      (assert (= input.deleted-at 1))
      (state.on-key-down {:key 1073741904})
      (state.on-key-down {:key 1073741903})
      (assert (= (# input.movement-log) 3))
      (InputState.disconnect-input input))))

(fn insert-state-inserts-newline-when-multiline []
  (with-state-recorder
    (fn [transitions]
      (local input (make-input-stub {:multiline? true}))
      (InputState.connect-input input)
      (input:enter-insert-mode)
      (local state (InsertState))
      (state.on-key-down {:key 13})
      (assert (= input.mode :insert))
      (assert (= (. input.inserted 1) "\n"))
      (assert (= (# transitions) 0))
      (InputState.disconnect-input input))))

(table.insert tests {:name "Normal state leader key enters leader state" :fn normal-state-leader-enters-leader-state})
(table.insert tests {:name "Leader state C enters camera state" :fn leader-state-c-enters-camera-state})
(table.insert tests {:name "Camera state F enters fpc state" :fn camera-state-f-enters-fpc-state})
(table.insert tests {:name "Camera state escape exits to normal" :fn camera-state-escape-exits-to-normal})
(table.insert tests {:name "Camera state 0 resets camera transform" :fn camera-state-zero-resets-camera})
(table.insert tests {:name "Fpc state escape exits to normal" :fn fpc-state-escape-exits-to-normal})
(table.insert tests {:name "Fpc state routes input only to controls" :fn fpc-state-routes-input-only-to-controls})
(table.insert tests {:name "Leader state routes to quit or normal" :fn leader-state-q-and-escape-transitions})
(table.insert tests {:name "Quit state quits and escapes to normal" :fn quit-state-quits-and-escapes})
(table.insert tests {:name "Text state handles navigation commands" :fn text-state-handles-navigation})
(table.insert tests {:name "Text state horizontal movement stays within a line" :fn text-state-horizontal-stays-on-line})
(table.insert tests {:name "Text state supports vertical navigation" :fn text-state-supports-vertical-navigation})
(table.insert tests {:name "Text state open line commands insert correctly" :fn text-state-open-line-commands})
(table.insert tests {:name "Text state handles gg and G line jumps" :fn text-state-line-jumps})
(table.insert tests {:name "Text state linewise insert shortcuts" :fn text-state-linewise-insert-shortcuts})
(table.insert tests {:name "Text state clamps cursor before deletes" :fn text-state-clamps-before-delete})
(table.insert tests {:name "Text state ignores text input when entering insert" :fn text-state-ignores-text-input-when-entering-insert})
(table.insert tests {:name "Text state swallows unhandled keys when input is active" :fn text-state-swallows-unhandled-keys-when-input-active})
(table.insert tests {:name "Insert state handles editing commands" :fn insert-state-handles-editing})
(table.insert tests {:name "Insert state inserts newline for multiline input" :fn insert-state-inserts-newline-when-multiline})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "states"
                       :tests tests})))

{:name "states"
 :tests tests
 :main main}
