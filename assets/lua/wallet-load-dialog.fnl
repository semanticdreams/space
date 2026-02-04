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
    (if wallet.address
        (.. name " - " wallet.address)
        name))

(fn build-wallet-load-dialog [options ctx]
    (local store (or options.store (WalletStore {})))
    (local wallets (store:list-wallets))
    (var dialog nil)
    (var error-text nil)

    (fn update-error [message]
        (when error-text
            (error-text:set-text (or message ""))))

    (fn handle-load [wallet]
        (local (ok result)
               (pcall (fn [] (store:load-wallet wallet.id))))
        (if ok
            (do
                (update-error nil)
                (when options.on-load
                    (options.on-load result))
                (when dialog
                    (dialog:drop)))
            (update-error result)))

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
                                                 (handle-load wallet))})
                            child-ctx))})))

    (local content
        (Flex {:axis 2
               :xalign :stretch
               :yspacing 0.5
               :children
               [(FlexChild (Text {:text "Select a wallet to load."}))
                (FlexChild list-body 1)
                (FlexChild error-row)]}))

    (local dialog-builder
        (DefaultDialog {:title "Load wallet"
                        :name (or options.name "wallet-load-dialog")
                        :on-close options.on-close
                        :child (Padding {:edge-insets [0.6 0.6]
                                         :child content})}))
    (set dialog (dialog-builder ctx))
    dialog)

(fn WalletLoadDialog [opts]
    (local options (or opts {}))
    (fn [ctx]
        (build-wallet-load-dialog options ctx)))

(local exports {:WalletLoadDialog WalletLoadDialog})

(setmetatable exports {:__call (fn [_ ...]
                                 (WalletLoadDialog ...))})

exports
