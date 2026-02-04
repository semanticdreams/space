(local suite (require :tests/fast))

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-modules suite)))

{:name "init"
 :modules suite.modules
 :main main}
