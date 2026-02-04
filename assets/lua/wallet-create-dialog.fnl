(local glm (require :glm))
(local Button (require :button))
(local DefaultDialog (require :default-dialog))
(local {: Flex : FlexChild} (require :flex))
(local Input (require :input))
(local Padding (require :padding))
(local Text (require :text))
(local Wallet (require :wallet))
(local WalletStore (require :wallet-store))

(fn validate-name [name]
    (if (= name "")
        "Name required"
        nil))

(fn validate-mnemonic [mnemonic]
    (if (= mnemonic "")
        "Mnemonic required"
        (if (not (Wallet.validate-mnemonic mnemonic))
            "Invalid mnemonic"
            nil)))

(fn create-wallet [store name mnemonic]
    (local created (Wallet.create-arbitrumnova {:mnemonic mnemonic}))
    (local record
        (store:save-wallet {:coin "arbitrumnova"
                            :address created.address
                            :mnemonic created.mnemonic
                            :name name}))
    {:address created.address
     :record record})

(fn build-wallet-create-dialog [options ctx]
    (local store (or options.store (WalletStore {})))
    (local state {:name ""
                  :mnemonic ""
                  :address nil
                  :error nil})
    (var address-text nil)
    (var error-text nil)
    (var mnemonic-field nil)

    (fn update-status []
        (when address-text
            (address-text:set-text
                (if state.address
                    (.. "Address: " state.address)
                    "Address: -")))
        (when error-text
            (error-text:set-text (or state.error ""))))

    (fn set-error [message]
        (set state.error message)
        (set state.address nil)
        (update-status))

    (fn apply-create-result [ok result]
        (if ok
            (do
                (set state.address result.address)
                (set state.error nil)
                (update-status)
                (when options.on-created
                    (options.on-created result.record)))
            (set-error result)))

    (fn validate-form []
        (or (validate-name state.name)
            (validate-mnemonic state.mnemonic)))

    (fn handle-create [_button _event]
        (local validation (validate-form))
        (if validation
            (set-error validation)
            (do
                (local (ok result)
                       (pcall (fn [] (create-wallet store state.name state.mnemonic))))
                (apply-create-result ok result))))

    (fn handle-generate [_button _event]
        (local result (Wallet.create-arbitrumnova {:strength 128}))
        (set state.mnemonic result.mnemonic)
        (set state.address result.address)
        (set state.error nil)
        (when mnemonic-field
            (mnemonic-field:set-text result.mnemonic))
        (update-status))

    (fn name-input [child-ctx]
        (local builder
            (Input {:placeholder "Wallet name"
                    :name (or options.name-input-name "wallet-name")
                    :min-width 12
                    :min-height 1.8
                    :on-change (fn [_ text]
                                 (set state.name text)
                                 (set state.error nil)
                                 (update-status))}))
        (builder child-ctx))

    (fn mnemonic-input [child-ctx]
        (local builder
            (Input {:placeholder "Mnemonic"
                    :name (or options.input-name "wallet-mnemonic")
                    :min-width 18
                    :min-height 1.8
                    :on-change (fn [_ text]
                                 (set state.mnemonic text)
                                 (set state.error nil)
                                 (update-status))}))
        (local element (builder child-ctx))
        (set mnemonic-field element)
        element)

    (fn address-row [child-ctx]
        (local builder (Text {:text "Address: -"
                              :name "wallet-address"}))
        (local element (builder child-ctx))
        (set address-text element)
        (update-status)
        element)

    (fn error-row [child-ctx]
        (local builder (Text {:text ""
                              :name "wallet-error"
                              :color (glm.vec4 1 0.4 0.4 1)}))
        (local element (builder child-ctx))
        (set error-text element)
        (update-status)
        element)

    (local create-button
        (Button {:text "Create Arbitrum Nova"
                 :icon "wallet"
                 :variant :primary
                 :padding [0.4 0.4]
                 :on-click handle-create}))

    (local generate-button
        (Button {:text "Generate"
                 :variant :secondary
                 :padding [0.4 0.4]
                 :on-click handle-generate}))

    (local action-row
        (Flex {:axis 1
               :xspacing 0.5
               :children
               [(FlexChild generate-button)
                (FlexChild create-button)]}))

    (local content
        (Flex {:axis 2
               :xalign :stretch
               :yspacing 0.5
               :children
               [(FlexChild (Text {:text "Create a new Arbitrum Nova wallet."}))
                (FlexChild name-input)
                (FlexChild mnemonic-input)
                (FlexChild action-row)
                (FlexChild address-row)
                (FlexChild error-row)]}))

    (local dialog-builder
        (DefaultDialog {:title "Create wallet"
                        :name (or options.name "wallet-create-dialog")
                        :on-close options.on-close
                        :child (Padding {:edge-insets [0.6 0.6]
                                         :child content})}))
    (dialog-builder ctx))

(fn WalletCreateDialog [opts]
    (local options (or opts {}))
    (fn [ctx]
        (build-wallet-create-dialog options ctx)))

(local exports {:WalletCreateDialog WalletCreateDialog})

(setmetatable exports {:__call (fn [_ ...]
                                 (WalletCreateDialog ...))})

exports
