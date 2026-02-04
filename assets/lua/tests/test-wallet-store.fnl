(local fs (require :fs))
(local WalletStore (require :wallet-store))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "wallet-store"))

(fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "wallet-store-" (os.time) "-" temp-counter)))

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

(fn wallet-store-saves-and-lists []
    (with-temp-dir
        (fn [root]
            (local keyring (make-keyring-stub))
            (local store (WalletStore {:data-dir root
                                       :keyring keyring
                                       :service "space-wallet-test"}))
            (local record
                (store:save-wallet {:coin "arbitrumnova"
                                    :address "0xabc"
                                    :mnemonic "test mnemonic"
                                    :name "Arbitrum Nova"}))
            (local wallets (store:list-wallets))
            (assert (= (length wallets) 1) "WalletStore should list saved wallet")
            (assert (= record.id "arbitrumnova:0xabc") "WalletStore should generate id")
            (assert (= (. (. wallets 1) :address) "0xabc") "WalletStore should persist address")
            (assert (fs.exists (fs.join-path root "wallets" "metadata.json"))
                    "WalletStore should persist metadata file"))))

(fn wallet-store-loads-mnemonic []
    (with-temp-dir
        (fn [root]
            (local keyring (make-keyring-stub))
            (local store (WalletStore {:data-dir root
                                       :keyring keyring
                                       :service "space-wallet-test"}))
            (store:save-wallet {:coin "arbitrumnova"
                                :address "0xdef"
                                :mnemonic "load mnemonic"
                                :name "Arbitrum Nova"})
            (local loaded (store:load-wallet "arbitrumnova:0xdef"))
            (assert (= loaded.mnemonic "load mnemonic")
                    "WalletStore should load mnemonic from keyring"))))

(fn wallet-store-reloads-metadata []
    (with-temp-dir
        (fn [root]
            (local keyring (make-keyring-stub))
            (local store (WalletStore {:data-dir root
                                       :keyring keyring
                                       :service "space-wallet-test"}))
            (store:save-wallet {:coin "arbitrumnova"
                                :address "0x123"
                                :mnemonic "persist mnemonic"
                                :name "Arbitrum Nova"})
            (local reloaded (WalletStore {:data-dir root
                                          :keyring keyring
                                          :service "space-wallet-test"}))
            (local wallets (reloaded:list-wallets))
            (assert (= (length wallets) 1) "WalletStore should reload metadata")
            (assert (= (. (. wallets 1) :id) "arbitrumnova:0x123")
                    "WalletStore should preserve wallet id"))))

(fn wallet-store-requires-name []
    (with-temp-dir
        (fn [root]
            (local keyring (make-keyring-stub))
            (local store (WalletStore {:data-dir root
                                       :keyring keyring
                                       :service "space-wallet-test"}))
            (local (ok err)
                   (pcall
                     (fn []
                       (store:save-wallet {:coin "arbitrumnova"
                                           :address "0x456"
                                           :mnemonic "name missing"
                                           :name ""}))))
            (assert (not ok) "WalletStore should reject empty name")
            (assert err "WalletStore should return error for missing name"))))

(table.insert tests {:name "WalletStore saves and lists" :fn wallet-store-saves-and-lists})
(table.insert tests {:name "WalletStore loads mnemonic" :fn wallet-store-loads-mnemonic})
(table.insert tests {:name "WalletStore reloads metadata" :fn wallet-store-reloads-metadata})
(table.insert tests {:name "WalletStore requires name" :fn wallet-store-requires-name})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "wallet-store"
                           :tests tests})))

{:name "wallet-store"
 :tests tests
 :main main}
