(local callbacks (require :callbacks))
(local realtime (require :realtime))
(local realtime-common (require :realtime.common))
(local realtime-test-features (require :realtime.test-features))
(local tests [])

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

(fn expect-zero-client-id-connect-fails [client connect-token]
  (local (zero-client-id-ok _zero-client-id-err)
    (pcall (fn []
             (client:connect {:client-id 0
                              :connect-token connect-token}))))
  (assert (not zero-client-id-ok) "client connect should require non-zero client-id"))

(fn expect-running-server-guards [server client connect-token signed issued-at expires-at]
  (local (unknown-running-deactivate-ok _unknown-running-deactivate-err)
    (pcall (fn []
             (server:deactivate-feature 0 999))))
  (assert (not unknown-running-deactivate-ok)
          "running server should reject unknown feature deactivation")
  (local (unknown-running-send-ok _unknown-running-send-err)
    (pcall (fn []
             (server:send-reliable 0 999 "oops"))))
  (assert (not unknown-running-send-ok)
          "running server should reject unknown feature payload sends")
  (expect-zero-client-id-connect-fails client connect-token)
  (local unsigned-ticket {:ticket-id "ticket-2"
                          :subject-user-id "dev-user"
                          :client-id 4242
                          :server-scope "loopback"
                          :allowed-features [1 2 3]
                          :issued-at issued-at
                          :expires-at expires-at
                          :secret "dev-secret"})
  (local (unsigned-ok _unsigned-err)
    (pcall (fn []
             (server:create-connect-token {:signed-ticket unsigned-ticket
                                           :secret "dev-secret"}))))
  (assert (not unsigned-ok) "raw unsigned ticket fields should not be accepted by create-connect-token")
  (local wrong-scope-signed
    (realtime.make-dev-ticket {:ticket-id "ticket-wrong-scope"
                               :subject-user-id "dev-user"
                               :client-id 4242
                               :server-scope "other-server"
                               :allowed-features [1 2 3]
                               :issued-at issued-at
                               :expires-at expires-at
                               :secret "dev-secret"}))
  (local (wrong-scope-ok _wrong-scope-err)
    (pcall (fn []
             (server:create-connect-token {:signed-ticket wrong-scope-signed
                                           :secret "dev-secret"}))))
  (assert (not wrong-scope-ok) "ticket server scope should be enforced during token creation")
  (local (bad-expire-ok _bad-expire-err)
    (pcall (fn []
             (server:create-connect-token {:signed-ticket signed
                                           :secret "dev-secret"
                                           :expire-seconds 0}))))
  (assert (not bad-expire-ok) "non-positive expire-seconds should fail loudly")
  (local (bad-timeout-ok _bad-timeout-err)
    (pcall (fn []
             (server:create-connect-token {:signed-ticket signed
                                           :secret "dev-secret"
                                           :timeout-seconds 0}))))
  (assert (not bad-timeout-ok) "non-positive timeout-seconds should fail loudly"))

(fn module-exports []
  (assert realtime.available "realtime module should be available")
  (assert (= (realtime.version) "1.2.5") "realtime version should match vendored yojimbo")
  (assert (= (type realtime.Service) :function) "realtime.Service should be a function")
  (assert (= (type realtime.FeatureRegistry) :function) "realtime.FeatureRegistry should be a function"))

(fn registry-behavior []
  (local registry (realtime.FeatureRegistry))
  (registry:register-feature {:id 1 :name "ping" :version 1})
  (local features (registry:list-features))
  (assert (= (# features) 1) "registry should contain one feature")
  (assert (= (. (. features 1) "id") 1) "feature id should match")
  (assert (= (. (. features 1) "name") "ping") "feature name should match")
  (local (dup-ok _dup-err) (pcall (fn []
                                    (registry:register-feature {:id 1 :name "dup" :version 1}))))
  (assert (not dup-ok) "duplicate feature ids should fail"))

(fn service-and-handles []
  (local service (realtime.Service))
  (local registry (realtime.FeatureRegistry))
  (registry:register-feature {:id 7 :name "echo" :version 3})
  (local server (service:create-server {:registry registry
                                        :bind-address "127.0.0.1:0"
                                        :server-scope "loopback"
                                        :max-clients 2}))
  (local client (service:create-client {:registry registry
                                        :bind-address "0.0.0.0:0"}))
  (assert (= (type server.start) :function) "server should expose start")
  (assert (= (type server.create-connect-token) :function) "server should expose create-connect-token")
  (assert (= (type client.connect) :function) "client should expose connect")
  (assert (not (server:is-running)) "server should not be running before start")
  (assert (not (client:is-connected)) "client should not be connected before connect")
  (cleanup server)
  (cleanup client))

(fn lifecycle-guards []
  (local service (realtime.Service))
  (local registry (realtime.FeatureRegistry))
  (registry:register-feature {:id 7 :name "echo" :version 3})
  (local server (service:create-server {:registry registry
                                        :bind-address "127.0.0.1:0"
                                        :max-clients 2}))
  (local client (service:create-client {:registry registry
                                        :bind-address "0.0.0.0:0"}))
  (local (unknown-ok _unknown-err)
    (pcall (fn []
             (server:activate-feature 0 999))))
  (assert (not unknown-ok) "activating an unknown feature should fail loudly")
  (local (bad-activate-index-ok _bad-activate-index-err)
    (pcall (fn []
             (server:activate-feature -2 7))))
  (assert (not bad-activate-index-ok) "invalid activate client-index should fail loudly")
  (local (bad-deactivate-index-ok _bad-deactivate-index-err)
    (pcall (fn []
             (server:deactivate-feature -1 7))))
  (assert (not bad-deactivate-index-ok) "broadcast deactivate should fail loudly")
  (local (unknown-deactivate-ok _unknown-deactivate-err)
    (pcall (fn []
             (server:deactivate-feature 0 999))))
  (assert (not unknown-deactivate-ok) "deactivating an unknown feature should fail loudly")
  (local (bad-send-index-ok _bad-send-index-err)
    (pcall (fn []
             (server:send-reliable -2 7 "oops"))))
  (assert (not bad-send-index-ok) "invalid send client-index should fail loudly")
  (local (unknown-server-send-ok _unknown-server-send-err)
    (pcall (fn []
             (server:send-reliable 0 999 "oops"))))
  (assert (not unknown-server-send-ok) "server send should reject unknown feature ids")
  (local (unknown-client-send-ok _unknown-client-send-err)
    (pcall (fn []
             (client:send-reliable 999 "oops"))))
  (assert (not unknown-client-send-ok) "client send should reject unknown feature ids")
  (local (zero-clients-ok _zero-clients-err)
    (pcall (fn []
             (service:create-server {:registry registry
                                     :bind-address "127.0.0.1:0"
                                     :max-clients 0}))))
  (assert (not zero-clients-ok) "zero max-clients should fail loudly")
  (local (too-many-clients-ok _too-many-clients-err)
    (pcall (fn []
             (service:create-server {:registry registry
                                     :bind-address "127.0.0.1:0"
                                     :max-clients 65}))))
  (assert (not too-many-clients-ok) "too-large max-clients should fail loudly")
  (local issued-at (os.time))
  (local expires-at (+ issued-at 60))
  (local signed
    (realtime.make-dev-ticket {:ticket-id "ticket-running"
                               :subject-user-id "dev-user"
                               :client-id 99
                               :server-scope "loopback"
                               :allowed-features [7]
                               :issued-at issued-at
                               :expires-at expires-at
                               :secret "dev-secret"}))
  (local (token-before-start-ok _token-before-start-err)
    (pcall (fn []
             (server:create-connect-token {:signed-ticket signed
                                           :secret "dev-secret"}))))
  (assert (not token-before-start-ok) "server should reject token creation before start")
  (local (bad-server-callback-ok _bad-server-callback-err)
    (pcall (fn []
             (server:set-callback "feature-activted" (fn [_payload] nil)))))
  (assert (not bad-server-callback-ok) "unknown server callback names should fail loudly")
  (local (bad-client-callback-ok _bad-client-callback-err)
    (pcall (fn []
             (client:set-callback "feature-offerd" (fn [_payload] nil)))))
  (assert (not bad-client-callback-ok) "unknown client callback names should fail loudly")
  (var callback-dispatch-count 0)
  (var self-unregister-id nil)
  (set self-unregister-id
    (callbacks.register
      (fn [payload]
        (set callback-dispatch-count (+ callback-dispatch-count 1))
        (when (= payload :first)
          (callbacks.unregister self-unregister-id)))))
  (callbacks.enqueue self-unregister-id :first)
  (callbacks.enqueue self-unregister-id :second)
  (callbacks.dispatch)
  (assert (= callback-dispatch-count 2)
          "callbacks unregistering during dispatch should not drop already-batched invocations")
  (var stopped-callback-fired false)
  (var stopped-saw-not-running false)
  (var restart-during-close-failed false)
  (var unrelated-callback-fired false)
  (local unrelated-callback-id
    (callbacks.register
      (fn [_payload]
        (set unrelated-callback-fired true))))
  (callbacks.enqueue unrelated-callback-id :queued-before-server-close)
  (server:set-callback "stopped"
    (fn [_payload]
      (set stopped-callback-fired true)
      (set stopped-saw-not-running (not (server:is-running)))
      (local (restart-ok _restart-err)
        (pcall (fn []
                 (server:start))))
      (set restart-during-close-failed (not restart-ok))))
  (server:start)
  (cleanup server)
  (assert stopped-callback-fired "server close should dispatch stopped callback before callback teardown")
  (assert stopped-saw-not-running "stopped callback should observe a non-running server")
  (assert restart-during-close-failed "server close should reject restart attempts during shutdown")
  (assert (not unrelated-callback-fired) "server close should not dispatch unrelated callback queues")
  (callbacks.dispatch)
  (assert unrelated-callback-fired "unrelated callbacks should remain queued after server close")
  (callbacks.unregister unrelated-callback-id)
  (cleanup server)
  (local (server-after-close-ok _server-after-close-err)
    (pcall (fn []
             (server:start))))
  (assert (not server-after-close-ok) "server operations after close should fail loudly")
  (cleanup client)
  (cleanup client)
  (local (client-after-close-ok _client-after-close-err)
    (pcall (fn []
             (client:connect {:client-id 1
                              :connect-token "00"}))))
  (assert (not client-after-close-ok) "client operations after close should fail loudly")
  (var destructor-stopped-fired false)
  (do
    (local gc-server (service:create-server {:registry registry
                                             :bind-address "127.0.0.1:0"
                                             :max-clients 1}))
    (gc-server:set-callback "stopped"
      (fn [_payload]
        (set destructor-stopped-fired true)))
    (gc-server:start))
  (collectgarbage)
  (collectgarbage)
  (callbacks.dispatch)
  (assert (not destructor-stopped-fired)
          "dropping a realtime server handle should not emit stopped during finalization"))

(fn wrapper-modules []
  (local registry (realtime-common.new-feature-registry realtime-test-features.all))
  (local features (registry:list-features))
  (assert (= (# features) 3) "wrapper registry should register all test features")
  (assert (= (. (. features 1) "name") "ping") "wrapper should preserve ping feature")
  (assert (= (. realtime-test-features.echo :id) 2) "echo test feature id should match"))

(fn dev-ticket-helper []
  (local issued-at (os.time))
  (local expires-at (+ issued-at 60))
  (local signed
    (realtime.make-dev-ticket {:ticket-id "ticket-1"
                               :subject-user-id "dev-user"
                               :client-id 4242
                               :server-scope "loopback"
                               :allowed-features [1 2 3]
                               :issued-at issued-at
                               :expires-at expires-at
                               :secret "dev-secret"}))
  (assert (= (. signed "ticket-id") "ticket-1") "dev ticket should preserve ticket id")
  (assert (= (. signed "subject-user-id") "dev-user") "dev ticket should preserve subject user id")
  (assert (= (. signed "client-id") 4242) "dev ticket should preserve client id")
  (assert (= (. (. signed "allowed-features") 2) 2) "dev ticket should preserve allowed feature ordering")
  (local service (realtime.Service))
  (local registry (realtime.FeatureRegistry))
  (registry:register-feature {:id 1 :name "ping" :version 1})
  (registry:register-feature {:id 2 :name "echo" :version 1})
  (registry:register-feature {:id 3 :name "draw" :version 1})
  (local server (service:create-server {:registry registry
                                        :bind-address "127.0.0.1:0"
                                        :server-scope "loopback"
                                        :max-clients 1}))
  (server:start)
  (local connect-token (server:create-connect-token {:signed-ticket signed
                                                     :secret "dev-secret"}))
  (assert (> (# connect-token) 0) "dev ticket output should be accepted by create-connect-token")
  (local client (service:create-client {:registry registry
                                        :bind-address "127.0.0.1:0"}))
  (with-cleanup [client server]
    (fn []
      (expect-running-server-guards server client connect-token signed issued-at expires-at)))
  (local wildcard-server
    (service:create-server {:registry registry
                            :bind-address "0.0.0.0:0"
                            :server-scope "loopback"
                            :max-clients 1}))
  (wildcard-server:start)
  (local (wildcard-token-ok _wildcard-token-err)
    (pcall (fn []
             (wildcard-server:create-connect-token {:signed-ticket signed
                                                    :secret "dev-secret"}))))
  (assert (not wildcard-token-ok) "wildcard bind without connect-addresses should fail loudly")
  (cleanup wildcard-server)
  (local advertised-server
    (service:create-server {:registry registry
                            :bind-address "0.0.0.0:0"
                            :server-scope "loopback"
                            :connect-addresses ["127.0.0.1:0"]
                            :max-clients 1}))
  (advertised-server:start)
  (local advertised-token
    (advertised-server:create-connect-token {:signed-ticket signed
                                             :secret "dev-secret"}))
  (assert (> (# advertised-token) 0)
          "wildcard bind with connect-addresses should mint a connect token")
  (cleanup advertised-server)
  (local (wildcard-advertised-ok _wildcard-advertised-err)
    (pcall (fn []
             (service:create-server {:registry registry
                                     :bind-address "0.0.0.0:0"
                                     :server-scope "loopback"
                                     :connect-addresses ["0.0.0.0:0"]
                                     :max-clients 1}))))
  (assert (not wildcard-advertised-ok)
          "wildcard connect-addresses should fail loudly")
  (local (family-mismatch-ok _family-mismatch-err)
    (pcall (fn []
             (service:create-server {:registry registry
                                     :bind-address "127.0.0.1:0"
                                     :server-scope "loopback"
                                     :connect-addresses ["[::1]:0"]
                                     :max-clients 1}))))
  (assert (not family-mismatch-ok)
          "connect-address family mismatch should fail loudly")
  (local overlong-id (string.rep "x" 256))
  (local (oversized-ticket-ok _oversized-ticket-err)
    (pcall (fn []
             (realtime.make-dev-ticket {:ticket-id overlong-id
                                        :subject-user-id "dev-user"
                                        :client-id 4242
                                        :server-scope "loopback"
                                        :allowed-features [1 2 3]
                                        :issued-at issued-at
                                        :expires-at expires-at
                                        :secret "dev-secret"}))))
  (assert (not oversized-ticket-ok) "oversized auth ticket fields should fail during signing")
  (local verified
    (realtime.verify-dev-ticket {:payload-json (. signed "payload-json")
                                 :signature (. signed "signature")
                                 :secret "dev-secret"
                                 :now (+ issued-at 1)}))
  (assert (= (. verified "server-scope") "loopback") "verified ticket should preserve server scope")
  (local (bad-ok _bad-err)
    (pcall (fn []
             (realtime.verify-dev-ticket {:payload-json (. signed "payload-json")
                                          :signature (. signed "signature")
                                          :secret "wrong-secret"
                                          :now (+ issued-at 1)}))))
  (assert (not bad-ok) "wrong dev ticket secret should fail verification"))

(table.insert tests {:name "realtime module exports" :fn module-exports})
(table.insert tests {:name "realtime registry behavior" :fn registry-behavior})
(table.insert tests {:name "realtime service creates handles" :fn service-and-handles})
(table.insert tests {:name "realtime lifecycle guards" :fn lifecycle-guards})
(table.insert tests {:name "realtime wrapper modules" :fn wrapper-modules})
(table.insert tests {:name "realtime dev ticket helper" :fn dev-ticket-helper})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "realtime-offline"
                       :tests tests})))

{:name "realtime-offline"
 :tests tests
 :main main}
