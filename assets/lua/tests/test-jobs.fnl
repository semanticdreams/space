(local submit
  (fn [kind payload]
    (if payload
        (app.engine.jobs.submit kind payload)
        (app.engine.jobs.submit kind))))

(local poll
  (fn [max]
    (if max
        (app.engine.jobs.poll max)
        (app.engine.jobs.poll))))

(local wait-callback
  (fn [predicate]
    (local deadline (+ (os.clock) 2))
    (while (and (not (predicate)) (< (os.clock) deadline))
      (poll)
      (app.engine.callbacks.dispatch))
    (assert (predicate) "Timed out waiting for callback")))

(local wait-for
  (fn [job-id]
    (local deadline (+ (os.clock) 2))
    (var result nil)
    (while (and (not result) (< (os.clock) deadline))
      (each [_ entry (ipairs (poll))]
        (when (= entry.id job-id)
          (set result entry))))
    (assert result (string.format "Timed out waiting for job %s" (tostring job-id)))
    result))

(fn test-echo []
  (local payload "hello-world")
  (local id (submit "echo" payload))
  (local res (wait-for id))
  (assert res.ok "echo should succeed")
  (assert (= res.result payload) "echo should return the original payload"))

(fn test-unknown-job []
  (local id (submit "missing" ""))
  (local res (wait-for id))
  (assert (not res.ok) "missing handler should fail")
  (assert res.error "missing handler should include an error")
  (assert (string.find res.error "Unknown job kind" 1 true) res.error))

(fn test-sleep-job []
  (local id (submit "sleep_ms" "25"))
  (local first (poll 1))
  (when (> (length first) 0)
    (local first-entry (. first 1))
    (assert (not (= first-entry.id id)) "sleep job should not finish immediately"))
  (local res (wait-for id))
  (assert res.ok "sleep_ms should succeed"))

(fn test-callback-dispatch []
  (var received nil)
  (var cb-count 0)
  (local payload "from-callback")
  (local id (app.engine.jobs.submit
             {:kind "echo"
              :payload payload
              :callback (fn [res]
                          (set received res)
                          (set cb-count (+ cb-count 1)))}))
  (wait-callback (fn [] received))
  (assert (= cb-count 1) "callback should fire once")
  (assert received.ok "callback result should mark ok")
  (assert (= received.id id))
  (assert (= received.kind "echo"))
  (assert (= received.result payload))
  (assert (= 0 (length (poll))) "callback results should not surface in poll"))

(local tests [{ :name "jobs echo returns payload" :fn test-echo}
 { :name "jobs unknown kind returns error" :fn test-unknown-job}
 { :name "jobs sleep completes asynchronously" :fn test-sleep-job}
 { :name "jobs callback dispatches through central registry" :fn test-callback-dispatch}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "jobs"
                       :tests tests})))

{:name "jobs"
 :tests tests
 :main main}
