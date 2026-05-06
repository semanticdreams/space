(local appdirs (require :appdirs))
(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local logging (require :logging))
(local WalletStore (require :wallet-store))

(fn WalletManager [opts]
    (local options (or opts {}))
    (local store (or options.store (WalletStore options)))
    (local data-dir (or options.data-dir
                        (and appdirs (appdirs.user-data-dir "space"))))
    (assert data-dir "WalletManager requires data-dir")
    (local wallet-dir (fs.join-path data-dir "wallets"))
    (local active-path (fs.join-path wallet-dir "active.json"))
    (var active nil)
    (var recovery nil)

    (fn ensure-wallet-dir []
        (local (ok err) (pcall fs.create-dirs wallet-dir))
        (when (not ok)
            (error (string.format "WalletManager failed to create %s: %s"
                                  wallet-dir
                                  err)))
        true)

    (fn read-active-id []
        (if (not (fs.exists active-path))
            (values nil nil)
            (do
                (local (ok content) (pcall fs.read-file active-path))
                (if (not ok)
                    (do
                        (when logging
                            (logging.warn (string.format "[wallet] failed to read %s: %s"
                                                         active-path
                                                         content)))
                        (values nil nil))
                    (do
                        (local (parse-ok decoded) (pcall json.loads content))
                        (if (not parse-ok)
                            (do
                                (pcall (fn [] (fs.remove active-path)))
                                (values nil nil))
                            (do
                                (local id (and decoded decoded.id))
                                (values id decoded))))))))

    (fn persist-active-id [id]
        (ensure-wallet-dir)
        (local payload {:id id})
        (local (ok err) (pcall (fn [] (JsonUtils.write-json! active-path payload))))
        (when (not ok)
            (error (string.format "WalletManager failed to write %s: %s"
                                  active-path
                                  err)))
        true)

    (fn clear-active-file []
        (when (fs.exists active-path)
            (pcall (fn [] (fs.remove active-path)))))

    (fn active-wallet-not-found? [err]
        (and err (string.find err " not found" 1 true)))

    (fn resolve-wallet [wallet]
        (if (= (type wallet) :string)
            (store:load-wallet wallet)
            (if (and wallet wallet.id (not wallet.mnemonic))
                (store:load-wallet wallet.id)
                wallet)))

    (fn sync-app-wallet []
        (when (and app (= (type app) :table))
            (when (not app.wallet)
                (set app.wallet {}))
            (set app.wallet.active active)
            (set app.wallet.recovery recovery)))

    (fn set-active [_self wallet]
        (assert wallet "WalletManager.set-active requires wallet or id")
        (local resolved (resolve-wallet wallet))
        (assert resolved.id "WalletManager.set-active requires wallet id")
        (set active resolved)
        (set recovery nil)
        (persist-active-id resolved.id)
        (sync-app-wallet)
        resolved)

    (fn clear-active [_self]
        (set active nil)
        (set recovery nil)
        (clear-active-file)
        (sync-app-wallet)
        true)

    (fn get-active [_self]
        active)

    (fn get-recovery-wallet [_self]
        recovery)

    (fn load-active [_self]
        (local (id _payload) (read-active-id))
        (if id
            (do
                (local (describe-ok described-or-err)
                       (pcall (fn [] (store:describe-wallet id))))
                (if (not describe-ok)
                    (if (active-wallet-not-found? described-or-err)
                        (do
                            (set active nil)
                            (set recovery nil)
                            (clear-active-file)
                            (when logging
                                (logging.warn (string.format "[wallet] active wallet %s missing from metadata; clearing active selection"
                                                             id)))
                            (sync-app-wallet)
                            nil)
                        (error described-or-err))
                    (do
                        (local described described-or-err)
                        (if (= described.status "needs-recovery")
                            (do
                                (set active nil)
                                (set recovery described)
                                (when logging
                                    (logging.warn (string.format "[wallet] active wallet %s missing secret on this device; recovery required"
                                                                 id)))
                                (sync-app-wallet)
                                nil)
                            (do
                                (set active (store:load-wallet id))
                                (set recovery nil)
                                (sync-app-wallet)
                                active)))))
            (do
                (set active nil)
                (set recovery nil)
                (sync-app-wallet)
                nil)))

    (local self {:store store
     :get-active get-active
     :get-recovery-wallet get-recovery-wallet
     :set-active set-active
     :clear-active clear-active
     :load-active load-active
     :active-path active-path})

    (when (and app (= (type app) :table))
        (when (not app.wallet)
            (set app.wallet {}))
        (set app.wallet.manager self))

    self)

WalletManager
