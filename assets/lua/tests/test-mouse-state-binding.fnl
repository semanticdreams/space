(local tests [])

(fn mouse-binding-exists []
  (assert app.engine "engine table not initialized")
  (assert app.engine.input "app.engine.input missing")
  (assert app.engine.input.mouse "app.engine.input.mouse missing")
  (assert (app.engine.input.mouse.is-up
           app.engine.input.mouse
           (or (and app.engine.mouse-buttons app.engine.mouse-buttons.left) 1))))

(fn mouse-button-constants []
  (assert app.engine.mouse-buttons "mouse button constants missing")
  (assert app.engine.mouse-buttons.left)
  (assert app.engine.mouse-buttons.right)
  (assert app.engine.mouse-buttons.middle))

(table.insert tests {:name "Mouse binding exports state on app.engine.input" :fn mouse-binding-exists})
(table.insert tests {:name "Mouse button constants available" :fn mouse-button-constants})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "mouse-state-binding"
                       :tests tests})))

{:name "mouse-state-binding"
 :tests tests
 :main main}
