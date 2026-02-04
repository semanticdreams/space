(local tests [])

(fn engine-quit-binding-exists []
  (assert app.engine "engine table not initialized")
  (assert (= (type app.engine.quit) :function) "app.engine.quit binding missing"))

(table.insert tests {:name "app.engine.quit binding exists" :fn engine-quit-binding-exists})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "quit-binding"
                       :tests tests})))

{:name "quit-binding"
 :tests tests
 :main main}
