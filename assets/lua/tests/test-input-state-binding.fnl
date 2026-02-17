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

(fn reset-controller-state []
  (local ids (app.engine.input:controller-ids))
  (each [_ id (ipairs ids)]
    (app.engine.input:on-controller-disconnected id 0)))

(fn game-controller-multi-state-and-primary []
  (local KeyStatus input-state.KeyStatus)
  (reset-controller-state)
  (assert (= (app.engine.input:controller-count) 0))
  (assert (= (app.engine.input:primary-controller-id) -1))
  (assert (= app.engine.input.controller nil))

  (app.engine.input:on-controller-connected 0 101 10)
  (app.engine.input:on-controller-connected 1 202 11)
  (assert (= (app.engine.input:controller-count) 2))
  (assert (= (app.engine.input:primary-controller-id) 101)
          "first connected controller should be primary initially")

  (app.engine.input:on-controller-axis 0 0.5 101 12)
  (app.engine.input:on-controller-axis 0 -0.75 202 13)

  (local controller-a (app.engine.input:controller-by-id 101))
  (local controller-b (app.engine.input:controller-by-id 202))
  (assert controller-a "controller 101 should exist")
  (assert controller-b "controller 202 should exist")
  (assert (= controller-a.connected true))
  (assert (= controller-b.connected true))
  (assert (= (controller-a:axis 0) 0.5))
  (assert (= (controller-b:axis 0) -0.75))
  (assert (= (app.engine.input:primary-controller-id) 202)
          "latest input source should become primary")

  (app.engine.input:on-controller-button 0 true 101 14)
  (assert (= (controller-a:button-state 0) KeyStatus.just-pressed))
  (assert (= (controller-b:button-state 0) KeyStatus.none)
          "button press on one controller should not affect siblings")
  (assert (= (app.engine.input:primary-controller-id) 101)
          "latest button input should become primary")

  (app.engine.input:begin-frame)
  (assert (= (controller-a:button-state 0) KeyStatus.held))
  (app.engine.input:on-controller-button 0 false 101 15)
  (assert (= (controller-a:button-state 0) KeyStatus.just-released))

  (local controllers (app.engine.input:controllers))
  (assert (= (type controllers) :table))
  (assert (. controllers 101) "controllers table should contain 101")
  (assert (. controllers 202) "controllers table should contain 202")

  (app.engine.input:on-controller-disconnected 101 16)
  (assert (= (app.engine.input:controller-count) 1))
  (assert (= (app.engine.input:primary-controller-id) 202)
          "primary should move to remaining controller")
  (assert (= (app.engine.input:controller-by-id 101) nil))

  (app.engine.input:on-controller-disconnected 202 17)
  (assert (= (app.engine.input:controller-count) 0))
  (assert (= (app.engine.input:primary-controller-id) -1))
  (assert (= app.engine.input.controller nil)))

(table.insert tests {:name "Input binding exposes app.engine.input.keyboard" :fn engine-input-available})
(table.insert tests {:name "KeyStatus enum exported with expected values" :fn key-status-enum-exposed})
(table.insert tests {:name "KeyboardState transitions can be mocked in Fennel" :fn mock-keyboard-state-transitions})
(table.insert tests {:name "app.engine.input keyboard is exported" :fn engine-input-can-be-inspected})
(table.insert tests {:name "Game controller binding supports multi-controller state and primary selection"
                     :fn game-controller-multi-state-and-primary})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "input-state-binding"
                       :tests tests})))

{:name "input-state-binding"
 :tests tests
 :main main}
