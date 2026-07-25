(local EngineModule (require :engine))
(local test-verbose (os.getenv "TEST_VERBOSE"))

(fn log-line [msg]
  (print msg)
  (io.flush))

(fn browser-smoke-url []
  "data:text/html,%3Chtml%3E%3Cbody%3ECEF%20SMOKE%3C/body%3E%3C/html%3E")

(fn run-cef-browser-smoke []
  (global app {})
  (set app.testing true)
  (set app.engine (EngineModule.Engine {:headless false
                                         :width 128
                                         :height 128
                                         :window-mode "windowed"}))
  (assert (app.engine:start) "engine should start for CEF browser smoke")
  (assert app.engine.browser "engine.browser binding is required")

  (local surface-id "release-cef-smoke")
  (local create-surface (assert (. app.engine.browser "create-surface")
                                "engine.browser.create-surface is required"))
  (local surface-stats (assert (. app.engine.browser "surface-stats")
                               "engine.browser.surface-stats is required"))
  (local destroy-surface (assert (. app.engine.browser "destroy-surface")
                                 "engine.browser.destroy-surface is required"))
  (local created
    (create-surface {:id surface-id
                     :url (browser-smoke-url)
                     :texture-name "release/cef-smoke"
                     :width 64
                     :height 64
                     :max-fps 30}))
  (assert created "CEF browser surface should be created")

  (var elapsed-ms 0)
  (var painted false)
  (var timed-out false)
  (local updated-handle
    (app.engine.events.updated:connect
      (fn [delta-ms]
        (set elapsed-ms (+ elapsed-ms (or delta-ms 0)))
        (local stats (surface-stats surface-id))
        (when (and stats
                   (. stats :texture-allocated)
                   (> (or (. stats "paint-count") 0) 0))
          (set painted true)
          (app.engine.quit))
        (when (>= elapsed-ms 5000)
          (set timed-out true)
          (app.engine.quit)))))

  (local (ok err)
    (pcall
      (fn []
        (app.engine:run)
        (assert (not timed-out) "CEF browser smoke timed out waiting for paint")
        (assert painted "CEF browser surface should paint at least once"))))

  (app.engine.events.updated:disconnect updated-handle true)
  (destroy-surface surface-id)
  (app.engine:shutdown)
  (assert ok err))

(local main
  (fn []
    (when test-verbose
      (log-line "[RUN] CEF browser surface smoke"))
    (run-cef-browser-smoke)
    (when test-verbose
      (log-line "[PASS] CEF browser surface smoke"))
    (log-line "Executed 1 Lua test")))

{:name "cef-browser-smoke"
 :main main}
