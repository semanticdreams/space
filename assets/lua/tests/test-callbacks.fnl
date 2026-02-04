(local callbacks (require :callbacks))

(local wait-until
  (fn [pred]
    (callbacks.run-loop {:poll-jobs true
                         :poll-http false
                         :sleep-ms 0
                         :timeout-ms 2000
                         :until pred})))

(fn test-callbacks-run-loop []
  (var received nil)
  (local payload "from-run-loop")
  (app.engine.jobs.submit {:kind "echo"
                           :payload payload
                           :callback (fn [res]
                                       (set received res))})
  (local ok (wait-until (fn [] received)))
  (assert ok "run-loop should return true when predicate met")
  (assert received.ok "callback result should mark ok")
  (assert (= received.result payload)))

(fn test-callbacks-run-loop-timeout []
  (local ok (callbacks.run-loop {:poll-jobs false
                                 :poll-http false
                                 :sleep-ms 0
                                 :timeout-ms 1
                                 :until (fn [] false)}))
  (assert (= ok false) "run-loop should return false on timeout"))

(local tests [{ :name "callbacks.run-loop dispatches job callbacks" :fn test-callbacks-run-loop}
 { :name "callbacks.run-loop returns false on timeout" :fn test-callbacks-run-loop-timeout}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "callbacks"
                       :tests tests})))

{:name "callbacks"
 :tests tests
 :main main}
