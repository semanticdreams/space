(local tests [])
(local input-state (require :input-state))

(local SAMPLE_SCANCODE 4) ;; SDL_SCANCODE_A

(fn engine-input-available []
  (assert app.engine "engine table not initialized")
  (assert app.engine.input "app.engine.input missing from bindings")
  (assert app.engine.input.keyboard "app.engine.input.keyboard missing from bindings")
  (assert (app.engine.input.keyboard:is-up SAMPLE_SCANCODE)))

(fn key-status-enum-exposed []
  (local KeyStatus input-state.KeyStatus)
  (assert KeyStatus "KeyStatus enum not bound")
  (assert (= KeyStatus.none 0))
  (assert (= KeyStatus.just-pressed 1))
  (assert (= KeyStatus.held 2))
  (assert (= KeyStatus.just-released 3)))

(fn mock-keyboard-state-transitions []
  (local KeyStatus input-state.KeyStatus)
  (var previous {})
  (var current {})

  (fn edge [scancode]
    (local prev (or (. previous scancode) 0))
    (local curr (or (. current scancode) 0))
    (if (= prev 0)
        (if (= curr 0)
            KeyStatus.none
            KeyStatus.just-pressed)
        (if (= curr 0)
            KeyStatus.just-released
            KeyStatus.held)))

  ;; initial up
  (assert (= (edge SAMPLE_SCANCODE) KeyStatus.none))
  ;; press
  (set (. current SAMPLE_SCANCODE) 1)
  (assert (= (edge SAMPLE_SCANCODE) KeyStatus.just-pressed))
  ;; hold
  (set (. previous SAMPLE_SCANCODE) 1)
  (assert (= (edge SAMPLE_SCANCODE) KeyStatus.held))
  ;; release
  (set (. current SAMPLE_SCANCODE) 0)
  (assert (= (edge SAMPLE_SCANCODE) KeyStatus.just-released)))

(fn engine-input-can-be-inspected []
  (assert app.engine.input.keyboard "Expected keyboard binding to exist")
  ;; Tests rely on mocked input, so just ensure the binding exports the object
  (assert (= (type app.engine.input.keyboard) :userdata)))

(fn reset-gamepad-state []
  (local ids (app.engine.input:gamepad-ids))
  (each [_ id (ipairs ids)]
    (app.engine.input:on-gamepad-disconnected id 0)))

(fn gamepad-multi-state-and-primary []
  (local KeyStatus input-state.KeyStatus)
  (reset-gamepad-state)
  (assert (= (app.engine.input:gamepad-count) 0))
  (assert (= (app.engine.input:primary-gamepad-id) 0))
  (assert (= app.engine.input.gamepad nil))

  (app.engine.input:on-gamepad-connected 0 101 10)
  (app.engine.input:on-gamepad-connected 1 202 11)
  (assert (= (app.engine.input:gamepad-count) 2))
  (assert (= (app.engine.input:primary-gamepad-id) 101)
          "first connected gamepad should be primary initially")

  (app.engine.input:on-gamepad-axis 0 0.5 101 12)
  (app.engine.input:on-gamepad-axis 0 -0.75 202 13)

  (local gamepad-a (app.engine.input:gamepad-by-id 101))
  (local gamepad-b (app.engine.input:gamepad-by-id 202))
  (assert gamepad-a "gamepad 101 should exist")
  (assert gamepad-b "gamepad 202 should exist")
  (assert (= gamepad-a.connected true))
  (assert (= gamepad-b.connected true))
  (assert (= (gamepad-a:axis 0) 0.5))
  (assert (= (gamepad-b:axis 0) -0.75))
  (assert (= (app.engine.input:primary-gamepad-id) 202)
          "latest input source should become primary")

  (app.engine.input:on-gamepad-button 0 true 101 14)
  (assert (= (gamepad-a:button-state 0) KeyStatus.just-pressed))
  (assert (= (gamepad-b:button-state 0) KeyStatus.none)
          "button press on one gamepad should not affect siblings")
  (assert (= (app.engine.input:primary-gamepad-id) 101)
          "latest button input should become primary")

  (app.engine.input:begin-frame)
  (assert (= (gamepad-a:button-state 0) KeyStatus.held))
  (app.engine.input:on-gamepad-button 0 false 101 15)
  (assert (= (gamepad-a:button-state 0) KeyStatus.just-released))

  (local gamepads (app.engine.input:gamepads))
  (assert (= (type gamepads) :table))
  (assert (. gamepads 101) "gamepads table should contain 101")
  (assert (. gamepads 202) "gamepads table should contain 202")

  (app.engine.input:on-gamepad-disconnected 101 16)
  (assert (= (app.engine.input:gamepad-count) 1))
  (assert (= (app.engine.input:primary-gamepad-id) 202)
          "primary should move to remaining gamepad")
  (assert (= (app.engine.input:gamepad-by-id 101) nil))

  (app.engine.input:on-gamepad-disconnected 202 17)
  (assert (= (app.engine.input:gamepad-count) 0))
  (assert (= (app.engine.input:primary-gamepad-id) 0))
  (assert (= app.engine.input.gamepad nil)))

(fn reset-touch-state []
  (local ids (app.engine.input:touch-ids))
  (each [_ id (ipairs ids)]
    (app.engine.input:on-touch-up id.touch-id id.finger-id 0 0 0 0 0 0))
  (app.engine.input:begin-frame)
  (app.engine.input:begin-frame))

(fn approx= [a b]
  (< (math.abs (- a b)) 1e-6))

(fn touch-state-binding-exposes-primary-touch []
  (local KeyStatus input-state.KeyStatus)
  (reset-touch-state)
  (assert (= (app.engine.input:touch-count) 0))
  (assert (= (app.engine.input:primary-touch-id) nil))
  (assert (= app.engine.input.touch nil))

  (app.engine.input:on-touch-down 7 301 0.25 0.5 0 0 0.8 10)
  (assert (= (app.engine.input:touch-count) 1))
  (local primary-id (app.engine.input:primary-touch-id))
  (assert primary-id "primary touch id should exist")
  (assert (= primary-id.touch-id 7))
  (assert (= primary-id.finger-id 301))
  (local touch (app.engine.input:touch-by-id 7 301))
  (assert touch "touch 301 should exist")
  (assert (= touch.touch-id 7))
  (assert (= touch.finger-id 301))
  (assert (approx= touch.x 0.25))
  (assert (approx= touch.y 0.5))
  (assert (approx= touch.pressure 0.8))
  (assert (= (touch:touch-state) KeyStatus.just-pressed))
  (assert (= (app.engine.input.touch:touch-state) KeyStatus.just-pressed))

  (app.engine.input:begin-frame)
  (assert (= (touch:touch-state) KeyStatus.held))

  (app.engine.input:on-touch-motion 7 301 0.5 0.75 0.25 0.25 0.9 11)
  (assert (approx= touch.dx 0.25))
  (assert (approx= touch.dy 0.25))
  (assert (approx= touch.x 0.5))
  (assert (approx= touch.y 0.75))
  (assert (approx= touch.pressure 0.9))
  (assert (= (app.engine.input:touch-count) 1))

  (local touches (app.engine.input:touches))
  (assert (= (type touches) :table))
  (assert (= (# touches) 1))
  (assert (= (. touches 1) touch) "touches table should contain active touch objects")

  (app.engine.input:on-touch-up 7 301 0.5 0.75 0 0 0.4 12)
  (assert (= (touch:touch-state) KeyStatus.just-released))
  (assert (= (app.engine.input:touch-count) 0))
  (app.engine.input:begin-frame)
  (app.engine.input:begin-frame)
  (assert (= (app.engine.input:touch-by-id 7 301) nil))
  (assert (= (app.engine.input:primary-touch-id) nil)))

(fn touch-state-binding-distinguishes-touch-devices []
  (reset-touch-state)
  (app.engine.input:on-touch-down 7 301 0.1 0.2 0 0 0.5 10)
  (app.engine.input:on-touch-down 8 301 0.7 0.8 0 0 0.9 11)
  (assert (= (app.engine.input:touch-count) 2))
  (local touch-a (app.engine.input:touch-by-id 7 301))
  (local touch-b (app.engine.input:touch-by-id 8 301))
  (assert touch-a "touch on device 7 should exist")
  (assert touch-b "touch on device 8 should exist")
  (assert (not (= touch-a touch-b)) "touches on different devices should not alias")
  (local ids (app.engine.input:touch-ids))
  (assert (= (# ids) 2))
  (app.engine.input:on-touch-up 7 301 0.1 0.2 0 0 0 12)
  (app.engine.input:on-touch-up 8 301 0.7 0.8 0 0 0 13)
  (app.engine.input:begin-frame)
  (app.engine.input:begin-frame)
  (assert (= (app.engine.input:touch-by-id 7 301) nil))
  (assert (= (app.engine.input:touch-by-id 8 301) nil)))

(table.insert tests {:name "Input binding exposes app.engine.input.keyboard" :fn engine-input-available})
(table.insert tests {:name "KeyStatus enum exported with expected values" :fn key-status-enum-exposed})
(table.insert tests {:name "KeyboardState transitions can be mocked in Fennel" :fn mock-keyboard-state-transitions})
(table.insert tests {:name "app.engine.input keyboard is exported" :fn engine-input-can-be-inspected})
(table.insert tests {:name "Gamepad binding supports multi-gamepad state and primary selection"
                     :fn gamepad-multi-state-and-primary})
(table.insert tests {:name "Touch binding supports primary touch and state transitions"
                     :fn touch-state-binding-exposes-primary-touch})
(table.insert tests {:name "Touch binding distinguishes touch devices"
                     :fn touch-state-binding-distinguishes-touch-devices})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "input-state-binding"
                       :tests tests})))

{:name "input-state-binding"
 :tests tests
 :main main}
