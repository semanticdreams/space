(local _ (require :main))
(local fs (require :fs))
(local WalletStore (require :wallet-store))
(local WalletManager (require :wallet-manager))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "wallet-manager"))

(fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "wallet-manager-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
    (local dir (make-temp-dir))
    (fs.create-dirs dir)
    (f dir))

(fn make-keyring-stub []
    (local secrets {})
    (fn make-key [service account]
        (.. service ":" account))
    {:set-password (fn [service account secret]
                     (tset secrets (make-key service account) secret)
                     true)
     :get-password (fn [service account]
                     (. secrets (make-key service account)))
     :delete-password (fn [service account]
                        (local key (make-key service account))
                        (local existing (. secrets key))
                        (set (. secrets key) nil)
                        (not (= existing nil)))})

(fn wallet-manager-persists-active []
    (with-temp-dir
        (fn [root]
            (local keyring (make-keyring-stub))
            (local original-wallet app.wallet)
            (local store (WalletStore {:data-dir root
                                       :keyring keyring
                                       :service "space-wallet-test"}))
            (local record
                (store:save-wallet {:coin "arbitrumnova"
                                    :address "0xabc"
                                    :mnemonic "manager mnemonic"
                                    :name "Primary"}))
            (local manager (WalletManager {:data-dir root
                                           :store store}))
            (local active (manager:set-active record))
            (assert active.mnemonic "Active wallet should load mnemonic")
            (assert (= active.name "Primary") "Active wallet should include name")
            (assert (fs.exists manager.active-path) "Active wallet should persist to disk")
            (assert app.wallet "WalletManager should create app.wallet")
            (assert app.wallet.active "WalletManager should set app.wallet.active")
            (local reloaded (WalletManager {:data-dir root
                                            :store store}))
            (local loaded (reloaded:load-active))
            (assert loaded "WalletManager should load active wallet")
            (assert (= loaded.id record.id) "Loaded active wallet should match id")
            (reloaded:clear-active)
            (assert (not (fs.exists reloaded.active-path))
                    "clear-active should remove active metadata")
            (set app.wallet original-wallet))))

(table.insert tests {:name "WalletManager persists active wallet" :fn wallet-manager-persists-active})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "wallet-manager"
                           :tests tests})))

{:name "wallet-manager"
 :tests tests
 :main main}
