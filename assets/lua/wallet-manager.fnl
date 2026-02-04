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

    (fn ensure-wallet-dir []
        (local (ok err) (pcall fs.create-dirs wallet-dir))
        (when (not ok)
            (error (string.format "WalletManager failed to create %s: %s"
                                  wallet-dir
                                  err)))
        true)

    (fn read-active-id []
        (when (not (fs.exists active-path))
            (values nil nil))
        (local (ok content) (pcall fs.read-file active-path))
        (when (not ok)
            (when logging
                (logging.warn (string.format "[wallet] failed to read %s: %s"
                                             active-path
                                             content)))
            (values nil nil))
        (local (parse-ok decoded) (pcall json.loads content))
        (when (not parse-ok)
            (pcall (fn [] (fs.remove active-path)))
            (values nil nil))
        (local id (and decoded decoded.id))
        (values id decoded))

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
            (set app.wallet.active active)))

    (fn set-active [_self wallet]
        (assert wallet "WalletManager.set-active requires wallet or id")
        (local resolved (resolve-wallet wallet))
        (assert resolved.id "WalletManager.set-active requires wallet id")
        (set active resolved)
        (persist-active-id resolved.id)
        (sync-app-wallet)
        resolved)

    (fn clear-active [_self]
        (set active nil)
        (clear-active-file)
        (sync-app-wallet)
        true)

    (fn get-active [_self]
        active)

    (fn load-active [_self]
        (local (id _payload) (read-active-id))
        (if id
            (do
                (set active (store:load-wallet id))
                (sync-app-wallet)
                active)
            nil))

    (local self {:store store
     :get-active get-active
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
