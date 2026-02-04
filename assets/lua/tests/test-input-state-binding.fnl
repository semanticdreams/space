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

(table.insert tests {:name "Input binding exposes app.engine.input.keyboard" :fn engine-input-available})
(table.insert tests {:name "KeyStatus enum exported with expected values" :fn key-status-enum-exposed})
(table.insert tests {:name "KeyboardState transitions can be mocked in Fennel" :fn mock-keyboard-state-transitions})
(table.insert tests {:name "app.engine.input keyboard is exported" :fn engine-input-can-be-inspected})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "input-state-binding"
                       :tests tests})))

{:name "input-state-binding"
 :tests tests
 :main main}
