(local Button (require :button))
(local DefaultDialog (require :default-dialog))
(local {: Flex : FlexChild} (require :flex))
(local gl (require :gl))
(local Padding (require :padding))
(local {: QrCodeWidget} (require :qr-code-widget))
(local Text (require :text))
(local WalletCreateDialog (require :wallet-create-dialog))
(local WalletLoadDialog (require :wallet-load-dialog))
(local WalletManager (require :wallet-manager))
(local WalletRpc (require :wallet-rpc))
(local WalletSendDialog (require :wallet-send-dialog))
(local WalletStore (require :wallet-store))
(local WalletTxUtils (require :wallet-tx-utils))

(fn resolve-target [ctx options]
    (or options.target
        (and ctx ctx.pointer-target)
        app.hud
    app.scene))

(local format-balance (. WalletTxUtils :format-balance))

(fn make-dialog-content [opts]
    (local options (or opts {}))
    (Flex {:axis 2
           :xalign :stretch
           :yspacing 0.5
           :children
           [(FlexChild (Text {:text "Manage your wallet."}))
            (FlexChild (Button {:text "Create wallet"
                                :variant :primary
                                :padding [0.5 0.5]
                                :on-click options.on-create}))
            (FlexChild (Button {:text "Load wallet"
                                :variant :secondary
                                :padding [0.5 0.5]
                                :on-click options.on-load}))
            (FlexChild (Button {:text "Send"
                                :variant :secondary
                                :padding [0.5 0.5]
                                :on-click options.on-send}))]}))

(fn build-wallet-view [options ctx]
    (local store (or options.store
                     (and options.manager options.manager.store)
                     (WalletStore {})))
    (local manager (or options.manager (WalletManager {:store store})))
    (local rpc (or options.rpc (WalletRpc {})))
    (var dialog nil)
    (var name-text nil)
    (var coin-text nil)
    (var address-text nil)
    (var balance-text nil)
    (var qr-widget nil)
    (var update-handler nil)
    (var balance-wallet-id nil)
    (var current-wallet nil)
    (local target (resolve-target ctx options))
    (assert (and target target.add-panel-child)
            "WalletView requires a pointer target with add-panel-child")

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

    (fn update-current-text [name coin address]
        (when name-text
            (name-text:set-text (.. "Name: " (or name "-"))))
        (when coin-text
            (coin-text:set-text (.. "Coin: " (or coin "-"))))
        (when address-text
            (address-text:set-text (.. "Address: " (or address "-")))))

    (fn update-current-qr [address]
        (when qr-widget
            (qr-widget:set-value address)))

    (fn update-current [wallet]
        (local current (or wallet (and manager (manager:get-active))))
        (set current-wallet current)
        (local name (and current current.name))
        (local coin (and current current.coin))
        (local address (and current current.address))
        (update-current-text name coin address)
        (update-current-qr address))

    (fn update-balance [value]
        (when balance-text
            (balance-text:set-text (.. "Balance: " (or value "-")))))

    (fn request-balance [wallet opts]
        (local force? (and opts opts.force?))
        (local current (or wallet current-wallet (and manager (manager:get-active))))
        (local id (and current current.id))
        (local address (and current current.address))
        (if (and id address rpc)
            (when (or force? (not (= id balance-wallet-id)))
                (set balance-wallet-id id)
                (update-balance "loading...")
                (local future (rpc:fetch-balance address))
                (connect-updates)
                (future.on-complete
                 (fn [ok value err _source]
                     (if ok
                         (update-balance (format-balance value))
                         (update-balance (or err "error"))))))
            (do
                (set balance-wallet-id nil)
                (update-balance "-"))))

    (fn open-dialog [builder]
        (target:add-panel-child {:builder builder}))

    (fn handle-created [wallet]
        (local resolved (if manager (manager:set-active wallet) wallet))
        (update-current resolved)
        (request-balance resolved)
        (when options.on-created
            (options.on-created resolved)))

    (fn handle-loaded [wallet]
        (local resolved (if manager (manager:set-active wallet) wallet))
        (update-current resolved)
        (request-balance resolved)
        (when options.on-load
            (options.on-load resolved)))

    (fn handle-open-create [_button _event]
        (if options.on-open-create
            (options.on-open-create store)
            (open-dialog (WalletCreateDialog {:store store
                                              :on-created handle-created}))))

    (fn handle-open-load [_button _event]
        (if options.on-open-load
            (options.on-open-load store)
            (open-dialog (WalletLoadDialog {:store store
                                            :on-load handle-loaded}))))

    (fn open-send-dialog []
        (open-dialog (WalletSendDialog {:manager manager})))

    (fn handle-open-send [_button _event]
        (if options.on-open-send
            (options.on-open-send manager)
            (open-send-dialog)))

    (fn name-row [child-ctx]
        (local builder (Text {:text "Name: -"
                              :name "wallet-current-name"}))
        (local element (builder child-ctx))
        (set name-text element)
        (update-current options.current-wallet)
        element)

    (fn coin-row [child-ctx]
        (local builder (Text {:text "Coin: -"
                              :name "wallet-current-coin"}))
        (local element (builder child-ctx))
        (set coin-text element)
        (update-current options.current-wallet)
        element)

    (fn address-row [child-ctx]
        (local text-builder
            (Text {:text "Address: -"
                   :name "wallet-current-address"}))
        (fn address-text-builder [inner-ctx]
            (local element (text-builder inner-ctx))
            (set address-text element)
            (update-current options.current-wallet)
            element)
        (local copy-builder
            (Button {:icon "content_copy"
                     :variant :ghost
                     :padding [0.2 0.2]
                     :content-spacing 0.35
                     :on-click (fn [_button _event]
                                   (local current (or current-wallet (and manager (manager:get-active))))
                                   (local address (and current current.address))
                                   (assert address "WalletView copy requires an address")
                                   (gl.clipboard-set address))}))
        ((Flex {:axis 1
                :xalign :stretch
                :yspacing 0
                :xspacing 0.5
                :children [(FlexChild address-text-builder 1)
                           (FlexChild copy-builder 0)]})
         child-ctx))

    (fn balance-row [child-ctx]
        (local text-builder
            (Text {:text "Balance: -"
                   :name "wallet-current-balance"}))
        (fn balance-text-builder [inner-ctx]
            (local element (text-builder inner-ctx))
            (set balance-text element)
            (request-balance options.current-wallet)
            element)
        (local reload-builder
            (Button {:icon "refresh"
                     :variant :ghost
                     :padding [0.2 0.2]
                     :content-spacing 0.35
                     :on-click (fn [_button _event]
                                   (request-balance nil {:force? true}))}))
        ((Flex {:axis 1
                :xalign :stretch
                :yspacing 0
                :xspacing 0.5
                :children [(FlexChild balance-text-builder 1)
                           (FlexChild reload-builder 0)]})
         child-ctx))

    (fn qr-row [child-ctx]
        (local builder
            (QrCodeWidget {:name "wallet-receive-qr"
                           :allow-empty? true
                           :module-size 0.4
                           :quiet-zone 4}))
        (local element (builder child-ctx))
        (set qr-widget element)
        (update-current options.current-wallet)
        element)

    (local content
        (Flex {:axis 2
               :xalign :stretch
               :yspacing 0.5
               :children
               [(FlexChild (make-dialog-content {:on-create handle-open-create
                                                 :on-load handle-open-load
                                                 :on-send handle-open-send}))
                (FlexChild (Text {:text "Current wallet"}))
                (FlexChild name-row)
                (FlexChild coin-row)
                (FlexChild address-row)
                (FlexChild (Text {:text "Receive"}))
                (FlexChild qr-row)
                (FlexChild balance-row)]}))
    (set dialog
         ((DefaultDialog {:title "Wallet"
                          :name (or options.name "wallet-dialog")
                          :on-close options.on-close
                          :child (Padding {:edge-insets [0.6 0.6]
                                           :child content})})
          ctx))
    (when manager
        (manager:load-active)
        (update-current options.current-wallet))
    (request-balance options.current-wallet)
    (when dialog
        (local base-drop dialog.drop)
        (set dialog.drop (fn [self]
                           (disconnect-updates)
                           (when rpc
                               (rpc:drop))
                           (when base-drop
                               (base-drop self)))))
    dialog)

(fn WalletView [opts]
    (local options (or opts {}))
    (fn [ctx]
        (build-wallet-view options ctx)))

(local exports {:WalletView WalletView})

(setmetatable exports {:__call (fn [_ ...]
                                 (WalletView ...))})

exports
