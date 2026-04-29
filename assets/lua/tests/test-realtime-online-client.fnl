(local realtime (require :realtime))
(local callbacks (require :callbacks))

(local debug-enabled (= (os.getenv "SPACE_REALTIME_DEBUG") "1"))

(fn debug-log [...]
  (when debug-enabled
    (print ...)))

(fn read-binary [path]
  (local fh (assert (io.open path "rb") (.. "failed to open " path " for read")))
  (local bytes (fh:read "*a"))
  (fh:close)
  bytes)

(fn main []
  (local token-path (assert (os.getenv "SPACE_REALTIME_TOKEN_PATH") "SPACE_REALTIME_TOKEN_PATH required"))
  (local client-id-value (assert (os.getenv "SPACE_REALTIME_CLIENT_ID") "SPACE_REALTIME_CLIENT_ID required"))
  (local client-id (tonumber client-id-value))
  (local registry (realtime.FeatureRegistry))
  (registry:register-feature {:id 1 :name "ping" :version 1})
  (registry:register-feature {:id 2 :name "echo" :version 1})
  (local service (realtime.Service))
  (local client (service:create-client {:registry registry
                                        :bind-address "127.0.0.1:0"}))
  (var done false)
  (var error-message nil)
  (var feature-deactivated false)
  (var settle-ticks nil)
  (client:set-callback "connected"
    (fn [_]
      (debug-log "client connected")))
  (client:set-callback "disconnected"
    (fn [_]
      (debug-log "client disconnected")))
  (client:set-callback "feature-offered"
    (fn [payload]
      (debug-log "client feature-offered" (. payload "feature-id") (. payload "version") (. payload "name"))
      (when (= (. payload "feature-id") 2)
        (set error-message "client was offered unauthorized feature")
        (set done true))))
  (client:set-callback "feature-activated"
    (fn [payload]
      (debug-log "client feature-activated" (. payload "feature-id"))
      (when (= (. payload "feature-id") 1)
        (assert (client:is-connected)
                "client should publish connected state before feature activation")
        (client:send-reliable 1 "ping"))))
  (client:set-callback "feature-deactivated"
    (fn [payload]
      (debug-log "client feature-deactivated" (. payload "feature-id"))
      (when (= (. payload "feature-id") 1)
        (set feature-deactivated true)
        (client:send-reliable 1 "late-client")
        (set settle-ticks 50))))
  (client:set-callback "message"
    (fn [payload]
      (debug-log "client message" (. payload "feature-id") (. payload "payload"))
      (when (= (. payload "feature-id") 1)
        (if (= (. payload "payload") "late-server")
            (do
              (set error-message "client received payload after deactivation")
              (set done true))
            (when (= (. payload "payload") "pong")
              nil)))))
  (client:set-callback "error"
    (fn [payload]
      (debug-log "client error" (. payload "message"))
      (set error-message (. payload "message"))
      (set done true)))
  (client:connect {:client-id client-id
                   :connect-token (read-binary token-path)})
  (local ok
    (callbacks.run-loop {:poll-jobs true
                         :poll-http false
                         :poll-process false
                         :sleep-ms 1
                         :timeout-ms 5000
                         :until (fn []
                                  (when settle-ticks
                                    (set settle-ticks (- settle-ticks 1))
                                    (when (<= settle-ticks 0)
                                      (set done true)))
                                  done)}))
  (client:close)
  (assert ok "client timed out waiting for pong")
  (assert feature-deactivated "client feature-deactivated callback should fire")
  (assert (not error-message)
          (or (and error-message (.. "client error: " error-message))
              "client error")))

{:main main}
