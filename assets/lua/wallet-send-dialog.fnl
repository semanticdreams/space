(local glm (require :glm))
(local Button (require :button))
(local DefaultDialog (require :default-dialog))
(local {: Flex : FlexChild} (require :flex))
(local Input (require :input))
(local Padding (require :padding))
(local Text (require :text))
(local Wallet (require :wallet))
(local WalletRpc (require :wallet-rpc))
(local WalletTxUtils (require :wallet-tx-utils))

(fn trim-text [value]
    (var trimmed (string.gsub (or value "") "^%s+" ""))
    (set trimmed (string.gsub trimmed "%s+$" ""))
    trimmed)

(fn resolve-active-wallet [options]
    (or options.wallet
        (and options.manager (options.manager:get-active))
        (and app app.wallet app.wallet.active)))

(fn ensure-hex-prefix [value]
    (if (and value (string.match value "^0x"))
        value
        (.. "0x" value)))

(fn build-wallet-send-dialog [opts ctx]
    (local options (or opts {}))
    (local rpc (or options.rpc (WalletRpc {})))
    (local owns-rpc? (not options.rpc))
    (local state {:to ""
                  :amount ""
                  :data ""
                  :status nil
                  :error nil
                  :nonce nil
                  :gas-price nil
                  :gas-limit nil
                  :tx-hash nil})
    (var from-text nil)
    (var status-text nil)
    (var error-text nil)
    (var nonce-text nil)
    (var gas-price-text nil)
    (var gas-limit-text nil)
    (var tx-text nil)
    (var update-handler nil)

    (fn disconnect-updates []
        (when (and app.engine app.engine.events app.engine.events.updated update-handler)
            (app.engine.events.updated:disconnect update-handler true)
            (set update-handler nil)))

    (fn connect-updates []
        (when (and rpc app.engine app.engine.events app.engine.events.updated (not update-handler))
            (set update-handler (app.engine.events.updated:connect
                                 (fn [_delta]
                                     (rpc:poll 0)
                                     (when (= (rpc:pending-count) 0)
                                         (disconnect-updates)))))))

    (fn update-status []
        (local wallet (resolve-active-wallet options))
        (when from-text
            (from-text:set-text
                (.. "From: " (or (and wallet wallet.address) "-"))))
        (when status-text
            (status-text:set-text (.. "Status: " (or state.status "-"))))
        (when error-text
            (error-text:set-text (or state.error "")))
        (when nonce-text
            (nonce-text:set-text (.. "Nonce: " (or state.nonce "-"))))
        (when gas-price-text
            (gas-price-text:set-text (.. "Gas price: " (or (. state :gas-price) "-"))))
        (when gas-limit-text
            (gas-limit-text:set-text (.. "Gas limit: " (or (. state :gas-limit) "-"))))
        (when tx-text
            (tx-text:set-text (.. "Tx hash: " (or (. state :tx-hash) "-")))))

    (fn set-error [message]
        (set state.error message)
        (set state.status nil)
        (update-status))

    (fn set-status [message]
        (set state.status message)
        (set state.error nil)
        (update-status))

(fn resolve-amount-wei [amount]
        (WalletTxUtils.eth-to-wei amount))

    (fn handle-send [_button _event]
        (local wallet (resolve-active-wallet options))
        (when (not wallet)
            (set-error "No active wallet selected")
            (lua "return nil"))
        (when (not wallet.mnemonic)
            (set-error "Active wallet is missing mnemonic")
            (lua "return nil"))
        (local to-address (trim-text state.to))
        (when (= to-address "")
            (set-error "Recipient address required")
            (lua "return nil"))
        (local amount-text (trim-text state.amount))
        (when (= amount-text "")
            (set-error "Amount required")
            (lua "return nil"))
        (local (amount-ok amount-wei)
               (pcall resolve-amount-wei amount-text))
        (when (not amount-ok)
            (set-error amount-wei)
            (lua "return nil"))
        (local value-hex (WalletTxUtils.decimal-to-hex amount-wei))
        (local data-text (trim-text state.data))
        (set state.nonce nil)
        (tset state :gas-price nil)
        (tset state :gas-limit nil)
        (tset state :tx-hash nil)
        (set-status "Estimating gas...")
        (var done? false)
        (var nonce nil)
        (var gas-price nil)
        (var gas-limit nil)

        (fn fail [message]
            (when (not done?)
                (set done? true)
                (set-error (or message "Send failed"))))

        (fn maybe-send []
            (when (and (not done?) nonce gas-price gas-limit)
                (set done? true)
                (set state.nonce nonce)
                (tset state :gas-price gas-price)
                (tset state :gas-limit gas-limit)
                (set-status "Signing transaction...")
                (local (sign-ok signed)
                       (pcall
                         (fn []
                             (Wallet.sign-arbitrumnova-transfer
                               {:wallet wallet
                                :to to-address
                                :amount-eth amount-text
                                :nonce nonce
                                :gas-price gas-price
                                :gas-limit gas-limit
                                :data data-text}))))
                (if (not sign-ok)
                    (fail signed)
                    (do
                        (set-status "Sending transaction...")
                        (local raw (ensure-hex-prefix signed))
                        (local future (rpc:send-raw-transaction raw))
                        (connect-updates)
                        (future.on-complete
                          (fn [ok value err _source]
                              (if ok
                                  (do
                                      (tset state :tx-hash value)
                                      (set-status "Transaction sent")
                                      (when options.on-sent
                                          (options.on-sent value)))
                                  (fail err))))))))

        (local nonce-future (rpc:fetch-nonce wallet.address))
        (local gas-price-future (rpc:fetch-gas-price))
        (local estimate-future
            (rpc:estimate-gas {:from wallet.address
                               :to to-address
                               :value value-hex
                               :data data-text}))
        (connect-updates)
        (nonce-future.on-complete
          (fn [ok value err _source]
              (if ok
                  (do
                      (set nonce value)
                      (set state.nonce value)
                      (update-status)
                      (maybe-send))
                  (fail err))))
        (gas-price-future.on-complete
          (fn [ok value err _source]
              (if ok
                  (do
                      (set gas-price value)
                      (tset state :gas-price value)
                      (update-status)
                      (maybe-send))
                  (fail err))))
        (estimate-future.on-complete
          (fn [ok value err _source]
              (if ok
                  (do
                      (set gas-limit value)
                      (tset state :gas-limit value)
                      (update-status)
                      (maybe-send))
                  (fail err)))))

    (fn from-row [child-ctx]
        (local builder (Text {:text "From: -"
                              :name "wallet-send-from"}))
        (local element (builder child-ctx))
        (set from-text element)
        (update-status)
        element)

    (fn to-input [child-ctx]
        ((Input {:placeholder "Recipient address"
                 :name "wallet-send-to"
                 :min-width 18
                 :min-height 1.8
                 :on-change (fn [_ value]
                              (set state.to value))})
         child-ctx))

    (fn amount-input [child-ctx]
        ((Input {:placeholder "Amount (ETH)"
                 :name "wallet-send-amount"
                 :min-width 12
                 :min-height 1.8
                 :on-change (fn [_ value]
                              (set state.amount value))})
         child-ctx))

    (fn data-input [child-ctx]
        ((Input {:placeholder "Data (hex, optional)"
                 :name "wallet-send-data"
                 :min-width 18
                 :min-height 1.8
                 :on-change (fn [_ value]
                              (set state.data value))})
         child-ctx))

    (fn status-row [child-ctx]
        (local builder (Text {:text "Status: -"
                              :name "wallet-send-status"}))
        (local element (builder child-ctx))
        (set status-text element)
        (update-status)
        element)

    (fn nonce-row [child-ctx]
        (local builder (Text {:text "Nonce: -"
                              :name "wallet-send-nonce"}))
        (local element (builder child-ctx))
        (set nonce-text element)
        (update-status)
        element)

    (fn gas-price-row [child-ctx]
        (local builder (Text {:text "Gas price: -"
                              :name "wallet-send-gas-price"}))
        (local element (builder child-ctx))
        (set gas-price-text element)
        (update-status)
        element)

    (fn gas-limit-row [child-ctx]
        (local builder (Text {:text "Gas limit: -"
                              :name "wallet-send-gas-limit"}))
        (local element (builder child-ctx))
        (set gas-limit-text element)
        (update-status)
        element)

    (fn tx-row [child-ctx]
        (local builder (Text {:text "Tx hash: -"
                              :name "wallet-send-tx"}))
        (local element (builder child-ctx))
        (set tx-text element)
        (update-status)
        element)

    (fn error-row [child-ctx]
        (local builder (Text {:text ""
                              :name "wallet-send-error"
                              :color (glm.vec4 1 0.4 0.4 1)}))
        (local element (builder child-ctx))
        (set error-text element)
        (update-status)
        element)

    (local send-button
        (Button {:text "Send"
                 :variant :primary
                 :padding [0.4 0.4]
                 :on-click handle-send}))

    (local content
        (Flex {:axis 2
               :xalign :stretch
               :yspacing 0.5
               :children
               [(FlexChild (Text {:text "Send Arbitrum Nova."}))
                (FlexChild from-row)
                (FlexChild to-input)
                (FlexChild amount-input)
                (FlexChild data-input)
                (FlexChild send-button)
                (FlexChild status-row)
                (FlexChild nonce-row)
                (FlexChild gas-price-row)
                (FlexChild gas-limit-row)
                (FlexChild tx-row)
                (FlexChild error-row)]}))

    (local dialog-builder
        (DefaultDialog {:title "Send"
                        :name (or options.name "wallet-send-dialog")
                        :on-close options.on-close
                        :child (Padding {:edge-insets [0.6 0.6]
                                         :child content})}))
    (local dialog (dialog-builder ctx))
    (set-status "Ready")
    (when dialog
        (local base-drop dialog.drop)
        (set dialog.drop
             (fn [self]
                 (disconnect-updates)
                 (when (and rpc owns-rpc?)
                     (rpc:drop))
                 (when base-drop
                     (base-drop self)))))
    dialog)

(fn WalletSendDialog [opts]
    (local options (or opts {}))
    (fn [ctx]
        (build-wallet-send-dialog options ctx)))

(local exports {:WalletSendDialog WalletSendDialog})

(setmetatable exports {:__call (fn [_ ...]
                                 (WalletSendDialog ...))})

exports
