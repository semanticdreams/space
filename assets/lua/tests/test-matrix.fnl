(local matrix (require :matrix))
(local callbacks (require :callbacks))

(local username (os.getenv "MATRIX_USERNAME"))
(local password (os.getenv "MATRIX_PASSWORD"))
(local homeserver (or (os.getenv "MATRIX_HOMESERVER") "http://localhost:6167"))

(fn error->string [err]
  (if (and err (= (type err) "table"))
      (.. (or (. err "message") "unknown error")
          " (code "
          (tostring (or (. err "code") "n/a"))
          ")")
      "unknown error"))

(fn await [label timeout-secs predicate]
  (local start (os.clock))
  (var done false)
  (var ok false)
  (while (not done)
    (callbacks.dispatch)
    (if (predicate)
        (do
          (set done true)
          (set ok true))
        (when (> (- (os.clock) start) timeout-secs)
          (error (.. label " timed out")))))
  ok)

(fn test-matrix-login-sync-rooms []
  (assert username "MATRIX_USERNAME required for matrix test")
  (assert password "MATRIX_PASSWORD required for matrix test")

  (var created nil)
  (matrix.create-client {:homeserver-url homeserver
                         :callback (fn [payload]
                                     (set created payload))})
  (await "matrix create-client" 20 (fn [] created))
  (assert created.ok (.. "create-client failed: " (error->string created.error)))
  (local client (. created "client"))
  (assert client "matrix client missing")

  (var login-result nil)
  (client:login-password username password (fn [payload]
                                             (set login-result payload)))
  (await "matrix login" 20 (fn [] login-result))
  (assert login-result.ok (.. "login failed: " (error->string login-result.error)))
  (assert (. login-result "user-id") "login missing user-id")

  (var sync-result nil)
  (client:sync-once (fn [payload]
                      (set sync-result payload)))
  (await "matrix sync" 20 (fn [] sync-result))
  (assert sync-result.ok (.. "sync failed: " (error->string sync-result.error)))

  (var rooms-result nil)
  (client:rooms (fn [payload]
                  (set rooms-result payload)))
  (await "matrix rooms" 10 (fn [] rooms-result))
  (assert rooms-result.ok (.. "rooms failed: " (error->string rooms-result.error)))
  (local rooms (. rooms-result "rooms"))
  (assert (= (type rooms) "table") "rooms result missing table")
  (each [_ room-id (ipairs rooms)]
    (assert (= (type room-id) "string") "room id not string"))
  (client:close))

(local tests [{ :name "matrix login sync rooms" :fn test-matrix-login-sync-rooms}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "matrix"
                       :tests tests})))

{:name "matrix"
 :tests tests
 :main main}
