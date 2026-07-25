(local callbacks (require :callbacks))
(local EngineModule (require :engine))
(local test-verbose (os.getenv "TEST_VERBOSE"))

(fn log-line [msg]
  (print msg)
  (io.flush))

(fn run-headless-callback-dispatch-test []
  (global app {})
  (set app.testing true)
  (set app.engine (EngineModule.Engine {:headless true}))
  (assert (app.engine:start) "headless engine should start")

  (var queued-payload nil)
  (var job-result nil)
  (var timed-out false)
  (var elapsed-ms 0)
  (var callback-id nil)

  (set callback-id
    (callbacks.register
      (fn [payload]
        (set queued-payload payload))))

  (callbacks.enqueue callback-id "queued-payload")
  (assert (and app.engine app.engine.jobs app.engine.jobs.submit)
          "headless engine jobs binding missing")
  (app.engine.jobs.submit
    {:kind "echo"
     :payload "job-payload"
     :callback (fn [result]
                 (set job-result result))})

  (local updated-handle
    (app.engine.events.updated:connect
      (fn [delta-ms]
        (set elapsed-ms (+ elapsed-ms (or delta-ms 0)))
        (if (and queued-payload job-result)
            (app.engine.quit)
            (when (>= elapsed-ms 2000)
              (set timed-out true)
              (app.engine.quit))))))

  (local (ok err)
    (pcall
      (fn []
        (app.engine:run)
        (assert (not timed-out) "headless engine run timed out waiting for callback dispatch")
        (assert (= queued-payload "queued-payload")
                "headless engine run should dispatch queued callbacks")
        (assert job-result "headless engine run should dispatch job callbacks")
        (assert job-result.ok "headless job callback result should be ok")
        (assert (= job-result.kind "echo") "headless job callback kind should match")
        (assert (= job-result.result "job-payload") "headless job callback payload should match"))))

  (app.engine.events.updated:disconnect updated-handle true)
  (when callback-id
    (callbacks.unregister callback-id))
  (app.engine:shutdown)
  (assert ok err))

(fn run-headless-zero-fps-idle-test []
  (global app {})
  (set app.testing true)
  (set app.engine (EngineModule.Engine {:headless true}))
  (assert (app.engine:start) "headless engine should start")
  (app.engine.set-target-fps 0)

  (var queued-payload nil)
  (var job-result nil)
  (var callback-id nil)

  (fn maybe-finish []
    (when (and queued-payload job-result)
      (app.engine.quit)))

  (set callback-id
    (callbacks.register
      (fn [payload]
        (set queued-payload payload)
        (maybe-finish))))

  (callbacks.enqueue callback-id "queued-payload-zero-fps")
  (app.engine.jobs.submit
    {:kind "echo"
     :payload "job-payload-zero-fps"
     :callback (fn [result]
                 (set job-result result)
                 (maybe-finish))})

  (local (ok err)
    (pcall
      (fn []
        (app.engine:run)
        (assert (= queued-payload "queued-payload-zero-fps")
                "headless zero-fps run should dispatch queued callbacks")
        (assert job-result "headless zero-fps run should dispatch job callbacks")
        (assert job-result.ok "headless zero-fps job callback result should be ok")
        (assert (= job-result.kind "echo") "headless zero-fps job callback kind should match")
        (assert (= job-result.result "job-payload-zero-fps")
                "headless zero-fps job callback payload should match"))))

  (when callback-id
    (callbacks.unregister callback-id))
  (app.engine:shutdown)
  (assert ok err))

(fn run-headless-zero-fps-request-frame-test []
  (global app {})
  (set app.testing true)
  (set app.engine (EngineModule.Engine {:headless true}))
  (assert (app.engine:start) "headless engine should start")
  (app.engine.set-target-fps 0)

  (var updated-fired false)
  (var timed-out false)
  (var callback-id nil)

  (fn enqueue-watchdog []
    (callbacks.enqueue callback-id
      (fn [_payload]
        (when (not updated-fired)
          (set timed-out true)
          (app.engine.quit)))))

  (set callback-id
    (callbacks.register
      (fn [_payload]
        (enqueue-watchdog))))

  (callbacks.enqueue callback-id :initial)
  (assert (app.engine.request-frame) "headless engine should expose request-frame")
  (assert (app.engine.request-frame) "headless zero-fps request-frame should enqueue a wake event")

  (local updated-handle
    (app.engine.events.updated:connect
      (fn [_delta-ms]
        (set updated-fired true)
        (app.engine.quit))))

  (local (ok err)
    (pcall
      (fn []
        (app.engine:run)
        (assert (not timed-out) "headless zero-fps request-frame timed out")
        (assert updated-fired "headless zero-fps request-frame should wake the loop and emit updated"))))

  (app.engine.events.updated:disconnect updated-handle true)
  (when callback-id
    (callbacks.unregister callback-id))
  (app.engine:shutdown)
  (assert ok err))

(local main
  (fn []
    (when test-verbose
      (log-line "[RUN] headless engine run dispatches queued and job callbacks"))
    (run-headless-callback-dispatch-test)
    (when test-verbose
      (log-line "[PASS] headless engine run dispatches queued and job callbacks")
      (log-line "[RUN] headless zero-fps run dispatches queued and job callbacks"))
    (run-headless-zero-fps-idle-test)
    (when test-verbose
      (log-line "[PASS] headless zero-fps run dispatches queued and job callbacks")
      (log-line "[RUN] headless zero-fps request-frame wakes the loop"))
    (run-headless-zero-fps-request-frame-test)
    (when test-verbose
      (log-line "[PASS] headless zero-fps request-frame wakes the loop"))
    (log-line "Executed 3 Lua tests")))

{:name "headless-engine-run"
 :main main}
