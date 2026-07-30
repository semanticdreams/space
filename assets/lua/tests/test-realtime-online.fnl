(local realtime (require :realtime))
(local callbacks (require :callbacks))
(local process (require :process))
(local fs (require :fs))
(local sysinfo (require :sysinfo))

(local tests [])

(local platform-os (. (sysinfo.platform) :os))
(local is-windows (= platform-os "windows"))

(fn executable-name []
  (if is-windows "build/space.exe" "./build/space"))

(fn temp-root []
  (or (os.getenv "TMPDIR")
      (os.getenv "TEMP")
      "/tmp"))

(fn make-temp-dir []
  (local dir (fs.join-path (temp-root) (.. "space-realtime-" (os.time) "-" (math.random 1000000))))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn wait-until [pred timeout-ms ?poll-process]
  (callbacks.run-loop {:poll-jobs true
                       :poll-http false
                       :poll-process (if (= ?poll-process nil) false ?poll-process)
                       :sleep-ms 1
                       :timeout-ms timeout-ms
                       :until pred}))

(fn runtime-env [extra]
  (local env {:SPACE_ASSETS_PATH (assert (os.getenv "SPACE_ASSETS_PATH") "SPACE_ASSETS_PATH required")
              :SPACE_DISABLE_AUDIO "1"
              :SPACE_LOG_DIR (or (os.getenv "SPACE_LOG_DIR") "/tmp/space/log")})
  (local fennel-path (os.getenv "FENNEL_PATH"))
  (local fennel-macro-path (os.getenv "FENNEL_MACRO_PATH"))
  (when fennel-path
    (set (. env :FENNEL_PATH) fennel-path))
  (when fennel-macro-path
    (set (. env :FENNEL_MACRO_PATH) fennel-macro-path))
  (each [k v (pairs (or extra {}))]
    (set (. env k) v))
  env)

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

(fn cleanup [handle]
  (when handle
    (handle:close)))

(fn cleanup-handles [handles]
  (var first-error nil)
  (each [_ handle (ipairs handles)]
    (local (ok result) (pcall cleanup handle))
    (when (and (not ok) (not first-error))
      (set first-error result)))
  (when first-error
    (error first-error)))

(fn with-cleanup [handles body]
  (local (ok result) (pcall body))
  (local (cleanup-ok cleanup-result) (pcall cleanup-handles handles))
  (if (not ok)
      (error result)
      (not cleanup-ok)
      (error cleanup-result)))

(fn assert-no-realtime-error [failure prefix]
  (when failure
    (error (.. prefix failure))))

(fn same-process-loopback []
  (local registry (realtime.FeatureRegistry))
  (registry:register-feature {:id 1 :name "ping" :version 1})
  (registry:register-feature {:id 2 :name "echo" :version 1})
  (local service (realtime.Service))
  (local server (service:create-server {:registry registry
                                        :bind-address "0.0.0.0:0"
                                        :server-scope "loopback"
                                        :connect-addresses ["127.0.0.1:0"]
                                        :max-clients 4}))
  (local client (service:create-client {:registry registry
                                        :bind-address "127.0.0.1:0"}))
  (var done false)
  (var failure nil)
  (var server-activated-count 0)
  (var client-activated-count 0)
  (var server-deactivated-count 0)
  (var client-deactivated-count 0)
  (var server-deactivated false)
  (var client-deactivated false)
  (var settle-ticks nil)

  (fn finish-after-settle []
    (when (and server-deactivated client-deactivated (not settle-ticks))
      (set settle-ticks 50)))

  (server:set-callback "client-connected"
    (fn [payload]
      (local auth-ticket (. payload "auth-ticket"))
      (assert (= (. auth-ticket "client-id") 4242) "server callback should expose auth ticket client id")
      (assert (= (. auth-ticket "subject-user-id") "user-4242") "server callback should expose auth ticket subject")
      (server:activate-feature (. payload "client-index") 1)
      (server:activate-feature (. payload "client-index") 1)))
  (server:set-callback "feature-activated"
    (fn [payload]
      (when (= (. payload "feature-id") 1)
        (set server-activated-count (+ server-activated-count 1))
        (when (> server-activated-count 1)
          (set failure "server feature activation was not idempotent")
          (set done true)))))
  (server:set-callback "feature-deactivated"
    (fn [payload]
      (when (= (. payload "feature-id") 1)
        (set server-deactivated-count (+ server-deactivated-count 1))
        (when (> server-deactivated-count 1)
          (set failure "server feature deactivation was not idempotent")
          (set done true))
        (set server-deactivated true)
        (finish-after-settle))))
  (server:set-callback "message"
    (fn [payload]
      (when (= (. payload "feature-id") 1)
        (if (= (. payload "payload") "ping")
            (do
              (server:send-reliable (. payload "client-index") 1 "pong")
              (server:deactivate-feature (. payload "client-index") 1)
              (server:deactivate-feature (. payload "client-index") 1)
              (server:send-reliable (. payload "client-index") 1 "late-server"))
            (when (= (. payload "payload") "late-client")
              (set failure "server received payload after deactivation")
              (set done true))))))
  (server:set-callback "error"
    (fn [payload]
      (set failure (. payload "message"))
      (set done true)))
  (client:set-callback "feature-activated"
    (fn [payload]
      (when (= (. payload "feature-id") 1)
        (set client-activated-count (+ client-activated-count 1))
        (when (> client-activated-count 1)
          (set failure "client feature activation was not idempotent")
          (set done true))
        (when (not (client:is-connected))
          (set failure "client did not publish connected state before feature activation")
          (set done true))
        (client:send-reliable 1 "ping"))))
  (client:set-callback "feature-offered"
    (fn [payload]
      (when (= (. payload "feature-id") 2)
        (set failure "client was offered unauthorized feature")
        (set done true))))
  (client:set-callback "feature-deactivated"
    (fn [payload]
      (when (= (. payload "feature-id") 1)
        (set client-deactivated-count (+ client-deactivated-count 1))
        (when (> client-deactivated-count 1)
          (set failure "client feature deactivation was not idempotent")
          (set done true))
        (set client-deactivated true)
        (client:send-reliable 1 "late-client")
        (finish-after-settle))))
  (client:set-callback "message"
    (fn [payload]
      (when (= (. payload "feature-id") 1)
        (if (= (. payload "payload") "late-server")
            (do
              (set failure "client received payload after deactivation")
              (set done true))
            (when (= (. payload "payload") "pong")
              nil)))))
  (client:set-callback "error"
    (fn [payload]
      (set failure (. payload "message"))
      (set done true)))
  (server:start)
  (client:connect {:client-id 4242
                   :connect-token (server:create-connect-token {:signed-ticket (make-loopback-ticket 4242)
                                                                 :secret "loopback-secret"})})
  (fn done-after-settle? []
    (when settle-ticks
      (set settle-ticks (- settle-ticks 1))
      (when (<= settle-ticks 0)
        (set done true)))
    done)
  (with-cleanup [client server]
    (fn []
      (local loop-ok (wait-until done-after-settle? 5000 false))
      (assert loop-ok "same-process realtime test timed out")
      (assert (= server-activated-count 1) "same-process realtime server activation should be idempotent")
      (assert (= client-activated-count 1) "same-process realtime client activation should be idempotent")
      (assert server-deactivated "same-process realtime server deactivation callback should fire")
      (assert client-deactivated "same-process realtime client deactivation callback should fire")
      (assert (= server-deactivated-count 1) "same-process realtime server deactivation should be idempotent")
      (assert (= client-deactivated-count 1) "same-process realtime client deactivation should be idempotent")
      (assert-no-realtime-error failure "same-process realtime error: "))))

(fn same-process-close-inside-callback []
  (local registry (realtime.FeatureRegistry))
  (registry:register-feature {:id 1 :name "ping" :version 1})
  (local service (realtime.Service))
  (local server (service:create-server {:registry registry
                                        :bind-address "0.0.0.0:0"
                                        :server-scope "loopback"
                                        :connect-addresses ["127.0.0.1:0"]
                                        :max-clients 4}))
  (local client (service:create-client {:registry registry
                                        :bind-address "127.0.0.1:0"}))
  (var done false)
  (var failure nil)
  (var saw-close-now false)
  (var saw-after-close false)
  (var server-saw-disconnect false)

  (server:set-callback "client-connected"
    (fn [payload]
      (server:activate-feature (. payload "client-index") 1)))
  (server:set-callback "message"
    (fn [payload]
      (when (and (= (. payload "feature-id") 1)
                 (= (. payload "payload") "ping"))
        (server:send-reliable (. payload "client-index") 1 "close-now")
        (server:send-reliable (. payload "client-index") 1 "after-close"))))
  (server:set-callback "client-disconnected"
    (fn [_payload]
      (set server-saw-disconnect true)
      (set done true)))
  (server:set-callback "error"
    (fn [payload]
      (set failure (. payload "message"))
      (set done true)))
  (client:set-callback "feature-activated"
    (fn [payload]
      (when (= (. payload "feature-id") 1)
        (client:send-reliable 1 "ping"))))
  (client:set-callback "message"
    (fn [payload]
      (when (= (. payload "feature-id") 1)
        (if (= (. payload "payload") "close-now")
            (do
              (set saw-close-now true)
              (cleanup client))
            (when (= (. payload "payload") "after-close")
              (set saw-after-close true)
              (set failure "client processed queued message after closing inside callback")
              (set done true))))))
  (client:set-callback "error"
    (fn [payload]
      (set failure (. payload "message"))
      (set done true)))

  (server:start)
  (client:connect {:client-id 5252
                   :connect-token (server:create-connect-token {:signed-ticket (make-loopback-ticket 5252)
                                                                 :secret "loopback-secret"})})
  (fn done? [] done)
  (with-cleanup [client server]
    (fn []
      (local loop-ok (wait-until done? 5000 false))
      (assert loop-ok "same-process reentrant close test timed out")
      (assert saw-close-now "client should receive the first queued message before closing")
      (assert (not saw-after-close) "client should not process queued callbacks after closing inside callback")
      (assert server-saw-disconnect "server should observe disconnect after client closes inside callback")
      (assert-no-realtime-error failure "same-process reentrant close error: "))))

(fn separate-process-loopback []
  (local dir (make-temp-dir))
  (local token-path (fs.join-path dir "token.bin"))
  (local client-id "9898")
  (local server-id
    (process.spawn {:args [(executable-name) "-m" "tests.test-realtime-online-server:main"]
                    :cwd "."
                    :env (runtime-env {:SPACE_REALTIME_TOKEN_PATH token-path
                                       :SPACE_REALTIME_CLIENT_ID client-id})}))
  (assert (> server-id 0) "server process should start")
  (local token-ready (wait-until (fn [] (fs.exists token-path)) 5000 true))
  (assert token-ready "server did not produce token file")
  (local client-result
    (process.run {:args [(executable-name) "-m" "tests.test-realtime-online-client:main"]
                  :cwd "."
                  :env (runtime-env {:SPACE_REALTIME_TOKEN_PATH token-path
                                     :SPACE_REALTIME_CLIENT_ID client-id})
                  :timeout 10}))
  (local server-result (process.wait server-id))
  (fs.remove-all dir)
  (assert (= client-result.exit-code 0)
          (.. "separate-process client failed stdout=" (tostring client-result.stdout)
              " stderr=" (tostring client-result.stderr)
              " signal=" (tostring client-result.signal)
              " timed-out=" (tostring (. client-result "timed-out"))))
  (assert (= server-result.exit-code 0)
          (.. "separate-process server failed stdout=" (tostring server-result.stdout)
              " stderr=" (tostring server-result.stderr)
              " signal=" (tostring server-result.signal)
              " timed-out=" (tostring (. server-result "timed-out")))))

(table.insert tests {:name "realtime same-process loopback" :fn same-process-loopback})
(table.insert tests {:name "realtime same-process close inside callback" :fn same-process-close-inside-callback})
(table.insert tests {:name "realtime separate-process loopback" :fn separate-process-loopback})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "realtime-online"
                       :tests tests})))

{:name "realtime-online"
 :tests tests
 :main main}
