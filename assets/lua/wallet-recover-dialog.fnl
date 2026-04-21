(local glm (require :glm))
(local Button (require :button))
(local DefaultDialog (require :default-dialog))
(local {: Flex : FlexChild} (require :flex))
(local Input (require :input))
(local Padding (require :padding))
(local Text (require :text))
(local Wallet (require :wallet))
(local WalletStore (require :wallet-store))

(fn normalize-address [value]
    (string.lower (or value "")))

(fn validate-mnemonic [mnemonic]
    (if (= mnemonic "")
        "Recovery phrase required"
        (if (not (Wallet.validate-mnemonic mnemonic))
            "Invalid recovery phrase"
            nil)))

(fn build-wallet-recover-dialog [options ctx runtime-opts]
    (local wallet (assert options.wallet "WalletRecoverDialog requires wallet metadata"))
    (local store (or options.store (WalletStore {})))
    (local state {:mnemonic ""
                  :address nil
                  :error nil})
    (var dialog nil)
    (var derived-address-text nil)
    (var error-text nil)

    (fn update-status []
        (when derived-address-text
            (derived-address-text:set-text
                (.. "Derived address: " (or state.address "-"))))
        (when error-text
            (error-text:set-text (or state.error ""))))

    (fn set-error [message]
        (set state.error message)
        (set state.address nil)
        (update-status))

    (fn handle-recover [_button _event]
        (local validation (validate-mnemonic state.mnemonic))
        (if validation
            (set-error validation)
            (do
                (local (create-ok created-or-err)
                       (pcall (fn []
                                (Wallet.create-arbitrumnova {:mnemonic state.mnemonic}))))
                (if (not create-ok)
                    (set-error created-or-err)
                    (do
                        (local created created-or-err)
                        (set state.address created.address)
                        (if (not (= (normalize-address created.address)
                                    (normalize-address wallet.address)))
                            (set-error (.. "Recovery phrase does not match " wallet.address))
                            (do
                                (local (save-ok saved-or-err)
                                       (pcall
                                         (fn []
                                             (store:save-wallet {:coin wallet.coin
                                                                 :address wallet.address
                                                                 :mnemonic created.mnemonic
                                                                 :name wallet.name}))))
                                (if (not save-ok)
                                    (set-error saved-or-err)
                                    (do
                                        (set state.error nil)
                                        (update-status)
                                        (when options.on-recovered
                                            (options.on-recovered (store:load-wallet wallet.id)))
                                        (when dialog
                                            (dialog:drop)))))))))))

    (fn mnemonic-input [child-ctx]
        ((Input {:placeholder "Recovery phrase"
                 :name (or options.input-name "wallet-recovery-mnemonic")
                 :multiline? true
                 :min-lines 3
                 :max-lines 3
                 :min-width 18
                 :min-height 4.8
                 :on-change (fn [_ text]
                              (set state.mnemonic text)
                              (set state.error nil)
                              (update-status))})
         child-ctx))

    (fn derived-address-row [child-ctx]
        (local builder (Text {:text "Derived address: -"
                              :name "wallet-recovery-derived-address"}))
        (local element (builder child-ctx))
        (set derived-address-text element)
        (update-status)
        element)

    (fn error-row [child-ctx]
        (local builder (Text {:text ""
                              :name "wallet-recovery-error"
                              :color (glm.vec4 1 0.4 0.4 1)}))
        (local element (builder child-ctx))
        (set error-text element)
        (update-status)
        element)

    (local content
        (Flex {:axis 2
               :xalign :stretch
               :yspacing 0.5
               :children
               [(FlexChild (Text {:text "Wallet secret missing on this device. Enter the recovery phrase for this saved wallet."}))
                (FlexChild (Text {:text (.. "Name: " (or wallet.name "-"))}))
                (FlexChild (Text {:text (.. "Coin: " (or wallet.coin "-"))}))
                (FlexChild (Text {:text (.. "Address: " (or wallet.address "-"))}))
                (FlexChild mnemonic-input)
                (FlexChild (Button {:text "Recover wallet"
                                    :icon "wallet"
                                    :variant :primary
                                    :padding [0.4 0.4]
                                    :on-click handle-recover}))
                (FlexChild derived-address-row)
                (FlexChild error-row)]}))

    (set dialog
         ((DefaultDialog {:title "Recover wallet"
                          :name (or options.name "wallet-recover-dialog")
                          :on-close options.on-close
                          :child (Padding {:edge-insets [0.6 0.6]
                                           :child content})})
          ctx
          runtime-opts))
    dialog)

(fn WalletRecoverDialog [opts]
    (local options (or opts {}))
    (fn [ctx runtime-opts]
        (build-wallet-recover-dialog options ctx runtime-opts)))

(local exports {:WalletRecoverDialog WalletRecoverDialog})

(setmetatable exports {:__call (fn [_ ...]
                                 (WalletRecoverDialog ...))})

exports
