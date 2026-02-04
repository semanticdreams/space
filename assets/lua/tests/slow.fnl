(local suite
  {:name "slow"
   :modules []})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-modules suite)))

{:name "slow"
 :modules suite.modules
 :main main}
