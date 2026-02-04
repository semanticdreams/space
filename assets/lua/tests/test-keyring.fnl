(local tests [])
(local keyring (require :keyring))

(fn resolve-keyring []
  (if (= (type keyring) "table") keyring nil))

(fn make-context [label service account]
  (when (os.getenv "SKIP_KEYRING_TESTS")
    (values nil "SKIP"))
  (let [binding (resolve-keyring)]
    (when (not binding)
      (values nil "missing-binding"))
    (let [set-fn (. binding "set-password")
          get-fn (. binding "get-password")
          delete-fn (. binding "delete-password")]
      (when (not (= (type set-fn) "function"))
        (error "keyring set-password missing"))
      (when (not (= (type get-fn) "function"))
        (error "keyring get-password missing"))
      (when (not (= (type delete-fn) "function"))
        (error "keyring delete-password missing"))
      (let [probe-service "space-test-keyring-probe"
            probe-account (.. "probe-" (os.time))
            probe-secret "probe-secret"]
        (let [(ok err) (pcall (fn [] (set-fn probe-service probe-account probe-secret)))]
          (when (not ok)
            (values nil err))
          (pcall (fn [] (delete-fn probe-service probe-account))))
        {:binding binding
         :set set-fn
         :get get-fn
         :del delete-fn
         :service service
         :account account}))))

(fn cleanup [ctx]
  (when ctx
    (pcall (fn [] ((. ctx :del) (. ctx :service) (. ctx :account))))))

(fn with-context [label service account f]
  (let [(ctx err) (make-context label service account)]
    (if (not ctx)
        true
        (let [(ok result) (pcall f ctx)]
          (cleanup ctx)
          (when (not ok)
            (error result))
          result))))

(fn keyring-roundtrip []
  (let [service "space-test-keyring"
        account (.. "user-" (os.time))
        secret (.. "secret-" (os.time))]
    (with-context "roundtrip" service account
      (fn [ctx]
        (assert ((. ctx :set) service account secret) "set-password should succeed")
        (assert (= ((. ctx :get) service account) secret) "get-password should return stored secret")
        (assert ((. ctx :del) service account) "delete-password should return true for existing secret")
        (assert (not ((. ctx :get) service account)) "secret should be cleared after delete")
        true))))

(fn keyring-overwrite []
  (let [service "space-test-keyring"
        account (.. "user-" (os.time) "-overwrite")
        first-secret "initial-secret"
        second-secret "updated-secret"]
    (with-context "overwrite" service account
      (fn [ctx]
        (assert ((. ctx :set) service account first-secret))
        (assert (= ((. ctx :get) service account) first-secret))
        (assert ((. ctx :set) service account second-secret))
        (assert (= ((. ctx :get) service account) second-secret))
        true))))

(fn keyring-delete-missing []
  (let [service "space-test-keyring"
        account (.. "missing-" (os.time))]
    (with-context "delete-missing" service account
      (fn [ctx]
        (assert (not ((. ctx :del) service account)) "deleting missing secret should return false")
        (assert (not ((. ctx :get) service account)) "get-password should return nil for missing secret")
        true))))

(table.insert tests {:name "keyring roundtrip stores secret" :fn keyring-roundtrip})
(table.insert tests {:name "keyring overwrite replaces secret" :fn keyring-overwrite})
(table.insert tests {:name "keyring delete missing returns false" :fn keyring-delete-missing})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "keyring"
                       :tests tests})))

{:name "keyring"
 :tests tests
 :main main}
