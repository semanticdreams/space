(local _ (require :main))
(local WalletView (require :wallet-view))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local Intersectables (require :intersectables))
(local TextUtils (require :text-utils))
(local gl (require :gl))

(local tests [])

(fn make-icons-stub []
    (local glyph {:advance 1
                  :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                  :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {4242 glyph}
                 :advance 1})
    (local stub {:font font
                 :codepoints {:close 4242
                              :move_item 4242
                              :refresh 4242
                              :content_copy 4242}})
    (set stub.get
         (fn [self name]
             (local value (. self.codepoints name))
             (assert value (.. "Missing icon " name))
             value))
    (set stub.resolve
         (fn [self name]
             (local code (self:get name))
             {:type :font
              :codepoint code
              :font self.font}))
    stub)

(fn make-vector-buffer []
    (local state {:allocate 0
                  :delete 0})
    (local buffer {:state state})
    (set buffer.allocate (fn [_self _count]
                           (set state.allocate (+ state.allocate 1))
                           state.allocate))
    (set buffer.delete (fn [_self _handle]
                         (set state.delete (+ state.delete 1))))
    (set buffer.set-glm-vec3 (fn [_self _handle _offset _value]
                               (set state.vec3-writes (+ (or state.vec3-writes 0) 1))))
    (set buffer.set-glm-vec4 (fn [_self _handle _offset _value]
                               (set state.vec4-writes (+ (or state.vec4-writes 0) 1))))
    (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
    (set buffer.set-float (fn [_self _handle _offset _value]
                            (set state.float-writes (+ (or state.float-writes 0) 1))))
    buffer)

(fn make-test-ctx []
    (local intersector (Intersectables))
    (local clickables (Clickables {:intersectables intersector}))
    (local hoverables (Hoverables {:intersectables intersector}))
    (local triangle (make-vector-buffer))
    (local text-buffer (make-vector-buffer))
    (local icons (make-icons-stub))
    (local ctx {:triangle-vector triangle})
    (set ctx.get-text-vector (fn [_self _font] text-buffer))
    (set ctx.clickables clickables)
    (set ctx.hoverables hoverables)
    (set ctx.icons icons)
    ctx)

(fn resolve-dialog-element [dialog]
    (or dialog.__front_widget dialog.front dialog))

(fn resolve-dialog-body [dialog]
    (local target (resolve-dialog-element dialog))
    (local body-meta (. target.children 2))
    (local body body-meta.element)
    (local body-card (or (and body.scroll body.scroll.child) body))
    (var content (. body-card.children 2))
    (while (and content content.layout (= content.layout.name "padding"))
        (set content content.child))
    content)

(fn find-wallet-buttons [dialog]
    (local content (resolve-dialog-body dialog))
    (local flex content)
    (local action-section (. flex.children 1))
    (local action-flex action-section.element)
    (local create-meta (. action-flex.children 2))
    (local load-meta (. action-flex.children 3))
    (local send-meta (. action-flex.children 4))
    {:create create-meta.element
     :load load-meta.element
     :send send-meta.element})

(fn find-address-row [dialog]
    (local content (resolve-dialog-body dialog))
    (local flex content)
    (local address-meta (. flex.children 5))
    (local address-row address-meta.element)
    (local text-meta (. address-row.children 1))
    (local button-meta (. address-row.children 2))
    {:text text-meta.element
     :button button-meta.element})

(fn find-qr-row [dialog]
    (local content (resolve-dialog-body dialog))
    (local flex content)
    (local qr-meta (. flex.children 7))
    (local qr-row qr-meta.element)
    qr-row)

(fn find-balance-row [dialog]
    (local content (resolve-dialog-body dialog))
    (local flex content)
    (local balance-meta (. flex.children 8))
    (local balance-row balance-meta.element)
    (local text-meta (. balance-row.children 1))
    (local button-meta (. balance-row.children 2))
    {:text text-meta.element
     :button button-meta.element})

(fn assert-codepoints-eq [actual expected message]
    (assert (= (# actual) (# expected))
            (or message "codepoints length mismatch"))
    (for [i 1 (# expected)]
        (assert (= (. actual i) (. expected i))
                (or message "codepoints mismatch"))))

(fn wallet-view-buttons-open-callbacks []
    (local ctx (make-test-ctx))
    (local target {:add-panel-child (fn [_self _opts] nil)})
    (local manager {:store nil
                    :get-active (fn [_self] nil)
                    :set-active (fn [_self wallet] wallet)
                    :load-active (fn [_self] nil)})
    (var create-count 0)
    (var load-count 0)
    (var send-count 0)
    (local dialog-create
        ((WalletView {:target target
                      :manager manager
                      :on-open-create (fn [_store] (set create-count (+ create-count 1)))
                      :on-open-load (fn [_store] (set load-count (+ load-count 1)))
                      :on-open-send (fn [_manager] (set send-count (+ send-count 1)))})
         ctx))
    (local create-buttons (find-wallet-buttons dialog-create))
    (local create-button (. create-buttons :create))
    (create-button:on-click {:button 1})
    (local send-button (. create-buttons :send))
    (send-button:on-click {:button 1})

    (local dialog-load
        ((WalletView {:target target
                      :manager manager
                      :on-open-create (fn [_store] (set create-count (+ create-count 1)))
                      :on-open-load (fn [_store] (set load-count (+ load-count 1)))
                      :on-open-send (fn [_manager] (set send-count (+ send-count 1)))})
         ctx))
    (local load-buttons (find-wallet-buttons dialog-load))
    (local load-button (. load-buttons :load))
    (load-button:on-click {:button 1})
    (local send-button-load (. load-buttons :send))
    (send-button-load:on-click {:button 1})
    (assert (= create-count 1) "WalletView should call create callback")
    (assert (= load-count 1) "WalletView should call load callback")
    (assert (= send-count 2) "WalletView should call send callback")
    (dialog-create:drop)
    (dialog-load:drop))

(table.insert tests {:name "WalletView buttons open callbacks" :fn wallet-view-buttons-open-callbacks})

(fn wallet-view-balance-formatting []
    (local ctx (make-test-ctx))
    (local target {:add-panel-child (fn [_self _opts] nil)})
    (local manager {:store nil
                    :get-active (fn [_self] nil)
                    :set-active (fn [_self wallet] wallet)
                    :load-active (fn [_self] nil)})
    (var fetch-count 0)
    (local rpc {:fetch-balance (fn [_self _address]
                                 (set fetch-count (+ fetch-count 1))
                                 {:on-complete (fn [cb]
                                                 (cb true "0x2a" nil "mock"))})
                :poll (fn [_self _max] nil)
                :pending-count (fn [_self] 0)
                :drop (fn [_self] nil)})
    (local wallet {:id "w1"
                   :name "Wallet"
                   :coin "arbitrumnova"
                   :address "0xabc"})
    (local dialog
        ((WalletView {:target target
                      :manager manager
                      :rpc rpc
                      :current-wallet wallet})
         ctx))
    (local balance (find-balance-row dialog))
    (local expected "Balance: 0x2a (0.000000000000000042 ETH)")
    (local expected-codepoints (TextUtils.codepoints-from-text expected))
    (assert (= fetch-count 1) "WalletView should fetch balance on build")
    (assert-codepoints-eq (balance.text:get-codepoints)
                          expected-codepoints
                          "WalletView should format balance in hex and ETH")
    (balance.button:on-click {:button 1})
    (assert (= fetch-count 2) "WalletView reload should refetch balance")
    (dialog:drop))

(table.insert tests {:name "WalletView balance formatting" :fn wallet-view-balance-formatting})

(fn wallet-view-copy-address []
    (local ctx (make-test-ctx))
    (local target {:add-panel-child (fn [_self _opts] nil)})
    (local manager {:store nil
                    :get-active (fn [_self] nil)
                    :set-active (fn [_self wallet] wallet)
                    :load-active (fn [_self] nil)})
    (local wallet {:id "w1"
                   :name "Wallet"
                   :coin "arbitrumnova"
                   :address "0xabc"})
    (gl.clipboard-set "placeholder")
    (local dialog
        ((WalletView {:target target
                      :manager manager
                      :current-wallet wallet})
         ctx))
    (local address-row (find-address-row dialog))
    (address-row.button:on-click {:button 1})
    (assert (= (gl.clipboard-get) "0xabc") "WalletView should copy address")
    (dialog:drop))

(table.insert tests {:name "WalletView copy address" :fn wallet-view-copy-address})

(fn wallet-view-receive-qr []
    (local ctx (make-test-ctx))
    (local target {:add-panel-child (fn [_self _opts] nil)})
    (local manager {:store nil
                    :get-active (fn [_self] nil)
                    :set-active (fn [_self wallet] wallet)
                    :load-active (fn [_self] nil)})
    (local wallet {:id "w1"
                   :name "Wallet"
                   :coin "arbitrumnova"
                   :address "0xabc"})
    (local dialog
        ((WalletView {:target target
                      :manager manager
                      :current-wallet wallet})
         ctx))
    (local qr-row (find-qr-row dialog))
    (assert (qr-row:get-value) "WalletView should expose QR widget")
    (assert (= (qr-row:get-value) "0xabc") "WalletView should set QR value to address")
    (dialog:drop))

(table.insert tests {:name "WalletView receive QR" :fn wallet-view-receive-qr})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "wallet-view"
                           :tests tests})))

{:name "wallet-view"
 :tests tests
 :main main}
