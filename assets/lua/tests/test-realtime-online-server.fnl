(local realtime (require :realtime))
(local callbacks (require :callbacks))

(local debug-enabled (= (os.getenv "SPACE_REALTIME_DEBUG") "1"))

(fn debug-log [...]
  (when debug-enabled
    (print ...)))

(fn write-binary! [path bytes]
  (local fh (assert (io.open path "wb") (.. "failed to open " path " for write")))
  (fh:write bytes)
  (fh:close))

(fn make-loopback-ticket [client-id]
  (local issued-at (os.time))
  (realtime.make-dev-ticket {:ticket-id (.. "ticket-" client-id)
                             :subject-user-id (.. "user-" client-id)
                             :client-id client-id
                             :server-scope "loopback"
                             :allowed-features [1]
                             :issued-at issued-at
                             :expires-at (+ issued-at 60)
                             :secret "loopback-secret"}))

(fn main []
  (local token-path (assert (os.getenv "SPACE_REALTIME_TOKEN_PATH") "SPACE_REALTIME_TOKEN_PATH required"))
  (local client-id-value (assert (os.getenv "SPACE_REALTIME_CLIENT_ID") "SPACE_REALTIME_CLIENT_ID required"))
  (local client-id (tonumber client-id-value))
  (local registry (realtime.FeatureRegistry))
  (registry:register-feature {:id 1 :name "ping" :version 1})
  (registry:register-feature {:id 2 :name "echo" :version 1})
  (local service (realtime.Service))
  (local server (service:create-server {:registry registry
                                        :bind-address "0.0.0.0:0"
                                        :server-scope "loopback"
                                        :connect-addresses ["127.0.0.1:0"]
                                        :max-clients 4}))
  (var done false)
  (var error-message nil)
  (var sent-pong false)
  (var feature-deactivated false)
  (var settle-ticks nil)
  (server:set-callback "started"
    (fn [payload]
      (debug-log "server started" (. payload "address"))))
  (server:set-callback "client-connected"
    (fn [payload]
      (local auth-ticket (. payload "auth-ticket"))
      (debug-log "server client-connected"
                 (. payload "client-index")
                 (. payload "client-id")
                 (. auth-ticket "subject-user-id"))
      (assert (= (. auth-ticket "client-id") client-id) "server auth ticket should preserve client id")
      (assert (= (. auth-ticket "subject-user-id") (.. "user-" client-id)) "server auth ticket should preserve subject")
      (server:activate-feature (. payload "client-index") 1)))
  (server:set-callback "client-disconnected"
    (fn [payload]
      (debug-log "server client-disconnected" (. payload "client-index"))))
  (server:set-callback "feature-activated"
    (fn [payload]
      (debug-log "server feature-activated" (. payload "client-index") (. payload "feature-id"))))
  (server:set-callback "feature-deactivated"
    (fn [payload]
      (debug-log "server feature-deactivated" (. payload "client-index") (. payload "feature-id"))
      (when (= (. payload "feature-id") 1)
        (set feature-deactivated true)
        (when sent-pong
          (set settle-ticks 50)))))
  (server:set-callback "message"
    (fn [payload]
      (debug-log "server message" (. payload "feature-id") (. payload "payload"))
      (when (= (. payload "feature-id") 1)
        (if (= (. payload "payload") "ping")
            (do
              (server:send-reliable (. payload "client-index") 1 "pong")
              (server:deactivate-feature (. payload "client-index") 1)
              (server:send-reliable (. payload "client-index") 1 "late-server")
              (set sent-pong true))
            (when (= (. payload "payload") "late-client")
              (set error-message "server received payload after deactivation")
              (set done true))))))
  (server:set-callback "error"
    (fn [payload]
      (debug-log "server error" (. payload "message"))
      (set error-message (. payload "message"))
      (set done true)))
  (server:start)
  (write-binary! token-path (server:create-connect-token {:signed-ticket (make-loopback-ticket client-id)
                                                          :secret "loopback-secret"}))
  (local ok (callbacks.run-loop {:poll-jobs true
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
  (server:close)
  (assert ok "server timed out waiting for client message")
  (assert feature-deactivated "server feature-deactivated callback should fire")
  (assert (not error-message)
          (or (and error-message (.. "server error: " error-message))
              "server error")))

{:main main}
