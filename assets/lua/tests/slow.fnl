(local suite
  {:name "slow"
   :modules [:tests.test-c-ir
             :tests.test-gccjit]})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-modules suite)))

{:name "slow"
 :modules suite.modules
 :main main}
