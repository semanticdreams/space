(local glm (require :glm))
(local Button (require :button))
(local DefaultDialog (require :default-dialog))
(local {: Flex : FlexChild} (require :flex))
(local ListView (require :list-view))
(local Padding (require :padding))
(local Text (require :text))
(local WalletStore (require :wallet-store))

(fn wallet-label [wallet]
    (local name (or wallet.name wallet.coin "Wallet"))
    (local suffix (if (= wallet.status "needs-recovery")
                      " (Needs recovery)"
                      ""))
    (if wallet.address
        (.. name " - " wallet.address suffix)
        (.. name suffix)))

(fn build-wallet-load-dialog [options ctx runtime-opts]
    (local store (or options.store (WalletStore {})))
    (local wallets [])
    (var dialog nil)
    (var error-text nil)
    (var recovery-count 0)

    (each [_ wallet (ipairs (store:list-wallets))]
        (local described (store:describe-wallet wallet.id))
        (when (= described.status "needs-recovery")
            (set recovery-count (+ recovery-count 1)))
        (table.insert wallets described))

    (fn update-error [message]
        (when error-text
            (error-text:set-text (or message ""))))

    (fn handle-select [wallet]
        (if (= wallet.status "needs-recovery")
            (do
                (update-error nil)
                (if options.on-recover
                    (do
                        (options.on-recover wallet)
                        (when dialog
                            (dialog:drop)))
                    (update-error (or wallet.recovery-message
                                      "Wallet secret missing on this device"))))
            (do
                (local (ok result)
                       (pcall (fn [] (store:load-wallet wallet.id))))
                (if ok
                    (do
                        (update-error nil)
                        (when options.on-load
                            (options.on-load result))
                        (when dialog
                            (dialog:drop)))
                    (update-error result)))))

    (fn error-row [child-ctx]
        (local builder (Text {:text ""
                              :name "wallet-load-error"
                              :color (glm.vec4 1 0.4 0.4 1)}))
        (local element (builder child-ctx))
        (set error-text element)
        element)

    (local list-body
        (if (= (length wallets) 0)
            (Text {:text "No wallets saved yet."})
            (ListView {:name "wallet-list"
                       :items wallets
                       :scroll true
                       :paginate false
                       :builder
                       (fn [wallet child-ctx]
                           ((Button {:text (wallet-label wallet)
                                     :variant :ghost
                                     :padding [0.4 0.4]
                                     :on-click (fn [_button _event]
                                                 (handle-select wallet))})
                            child-ctx))})))

    (local content
        (Flex {:axis 2
               :xalign :stretch
               :yspacing 0.5
               :children
               [(FlexChild (Text {:text (if (> recovery-count 0)
                                            "Select a wallet. Entries marked Needs recovery must be recovered on this device first."
                                            "Select a wallet to load.")}))
                (FlexChild list-body 1)
                (FlexChild error-row)]}))

    (local dialog-builder
        (DefaultDialog {:title "Load wallet"
                        :name (or options.name "wallet-load-dialog")
                        :on-close options.on-close
                        :child (Padding {:edge-insets [0.6 0.6]
                                         :child content})}))
    (set dialog (dialog-builder ctx runtime-opts))
    dialog)

(fn WalletLoadDialog [opts]
    (local options (or opts {}))
    (fn [ctx runtime-opts]
        (build-wallet-load-dialog options ctx runtime-opts)))

(local exports {:WalletLoadDialog WalletLoadDialog})

(setmetatable exports {:__call (fn [_ ...]
                                 (WalletLoadDialog ...))})

exports
