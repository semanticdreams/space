(local appdirs (require :appdirs))
(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))

(fn WalletStore [opts]
    (local options (or opts {}))
    (local data-dir (or options.data-dir
                        (and appdirs (appdirs.user-data-dir "space"))))
    (assert data-dir "WalletStore requires data-dir")
    (local binding
        (or options.keyring
            (do
                (local (ok result) (pcall (fn [] (require :keyring))))
                (if ok
                    result
                    (error (.. "WalletStore requires keyring binding: " result))))))
    (assert binding "WalletStore requires keyring binding")
    (local set-password (. binding :set-password))
    (local get-password (. binding :get-password))
    (local delete-password (. binding :delete-password))
    (assert (= (type set-password) "function") "WalletStore requires keyring set-password")
    (assert (= (type get-password) "function") "WalletStore requires keyring get-password")
    (assert (= (type delete-password) "function") "WalletStore requires keyring delete-password")

    (local service (or options.service "space-wallet"))
    (local wallet-dir (fs.join-path data-dir "wallets"))
    (local metadata-path (fs.join-path wallet-dir "metadata.json"))
    (var metadata {:wallets []})

    (fn copy-table [source]
        (local clone {})
        (when source
            (each [k v (pairs source)]
                (set (. clone k) v)))
        clone)

    (fn ensure-wallet-dir []
        (local (ok err) (pcall fs.create-dirs wallet-dir))
        (when (not ok)
            (error (string.format "WalletStore failed to create %s: %s"
                                  wallet-dir
                                  err)))
        true)

    (fn load-metadata []
        (ensure-wallet-dir)
        (if (not (fs.exists metadata-path))
            (set metadata {:wallets []})
            (do
                (local (read-ok content) (pcall fs.read-file metadata-path))
                (when (not read-ok)
                    (error (string.format "WalletStore failed to read %s: %s"
                                          metadata-path
                                          content)))
                (local (parse-ok decoded) (pcall json.loads content))
                (when (not parse-ok)
                    (error (string.format "WalletStore failed to parse %s: %s"
                                          metadata-path
                                          decoded)))
                (local wallets (or (. decoded :wallets) []))
                (when (not (= (type wallets) :table))
                    (error "WalletStore metadata wallets must be a list"))
                (set metadata {:wallets wallets}))))

    (fn persist []
        (ensure-wallet-dir)
        (local payload {:wallets metadata.wallets})
        (local (write-ok err) (pcall (fn [] (JsonUtils.write-json! metadata-path payload))))
        (when (not write-ok)
            (error (string.format "WalletStore failed to write %s: %s"
                                  metadata-path
                                  err)))
        true)

    (fn resolve-id [wallet]
        (or wallet.id (.. wallet.coin ":" wallet.address)))

    (fn find-wallet-index [id]
        (var found nil)
        (each [idx wallet (ipairs metadata.wallets)]
            (when (= wallet.id id)
                (set found idx)))
        found)

    (fn list-wallets [_self]
        (local copy [])
        (each [_ wallet (ipairs metadata.wallets)]
            (table.insert copy (copy-table wallet)))
        copy)

    (fn save-wallet [_self wallet]
        (assert wallet "WalletStore.save-wallet requires wallet data")
        (assert wallet.coin "WalletStore.save-wallet requires wallet coin")
        (assert wallet.address "WalletStore.save-wallet requires wallet address")
        (assert wallet.mnemonic "WalletStore.save-wallet requires wallet mnemonic")
        (assert (and wallet.name (not (= wallet.name "")))
                "WalletStore.save-wallet requires wallet name")
        (local id (resolve-id wallet))
        (local record {:id id
                       :name wallet.name
                       :coin wallet.coin
                       :address wallet.address})
        (local (ok err) (pcall (fn [] (set-password service id wallet.mnemonic))))
        (when (not ok)
            (error (string.format "WalletStore failed to store mnemonic: %s" err)))
        (local index (find-wallet-index id))
        (if index
            (tset metadata.wallets index record)
            (table.insert metadata.wallets record))
        (persist)
        (copy-table record))

    (fn load-wallet [_self id]
        (assert id "WalletStore.load-wallet requires id")
        (local index (find-wallet-index id))
        (when (not index)
            (error (string.format "WalletStore wallet %s not found" id)))
        (local record (. metadata.wallets index))
        (local mnemonic (get-password service id))
        (when (not mnemonic)
            (error (string.format "WalletStore mnemonic missing for %s" id)))
        (local resolved (copy-table record))
        (set resolved.mnemonic mnemonic)
        resolved)

    (fn delete-wallet [_self id]
        (assert id "WalletStore.delete-wallet requires id")
        (local index (find-wallet-index id))
        (when (not index)
            (error (string.format "WalletStore wallet %s not found" id)))
        (table.remove metadata.wallets index)
        (local (ok err) (pcall (fn [] (delete-password service id))))
        (when (not ok)
            (error (string.format "WalletStore failed to delete mnemonic: %s" err)))
        (persist)
        true)

    (local self {:list-wallets list-wallets
                 :save-wallet save-wallet
                 :load-wallet load-wallet
                 :delete-wallet delete-wallet
                 :metadata-path metadata-path
                 :wallet-dir wallet-dir})

    (load-metadata)
    self)

WalletStore
