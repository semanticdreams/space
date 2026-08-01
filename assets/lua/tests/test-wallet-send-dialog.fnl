(local _ (require :main))
(local wallet-core (require :wallet-core))
(local WalletSendDialog (require :wallet-send-dialog))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local Intersectables (require :intersectables))
(local RuntimeTimers (require :runtime-timers))
(local TextUtils (require :text-utils))
(local Wallet (require :wallet))
(local WalletTxUtils (require :wallet-tx-utils))

(if (= (. wallet-core :available) false)
    {:name "wallet-send-dialog"
     :tests []
     :main (fn []
             (print "wallet-core unavailable; skipping tests"))}
    (do
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
                                      :move_item 4242}})
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
            (local clickables (assert (Clickables {:intersectables intersector}) "wallet send dialog test context requires clickables"))
            (local hoverables (assert (Hoverables {:intersectables intersector}) "wallet send dialog test context requires hoverables"))
            (local triangle (make-vector-buffer))
            (local text-buffer (make-vector-buffer))
            (local icons (make-icons-stub))
            (local ctx {:triangle-vector triangle})
            (set ctx.get-text-vector (fn [_self _font] text-buffer))
  (set ctx.get-text-ssbo-batcher
       (fn [_self]
         {:upsert-text (fn [_batcher _key _opts] nil)
          :update-text-transform (fn [_batcher _key _opts] nil)
          :remove-text (fn [_batcher _key] nil)}))
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

        (fn find-send-elements [dialog]
            (local content (resolve-dialog-body dialog))
            (local flex content)
            (fn at [index]
                (local meta (. flex.children index))
                meta.element)
            {:to-input (at 3)
             :amount-input (at 4)
             :data-input (at 5)
             :send-button (at 6)
             :status-text (at 7)
             :nonce-text (at 8)
             :gas-price-text (at 9)
             :gas-limit-text (at 10)
             :tx-text (at 11)})

        (fn make-future [value]
            {:on-complete (fn [cb]
                            (cb true value nil "mock"))})

        (fn assert-codepoints-eq [actual expected message]
            (assert (= (# actual) (# expected))
                    (or message "codepoints length mismatch"))
            (for [i 1 (# expected)]
                (assert (= (. actual i) (. expected i))
                        (or message "codepoints mismatch"))))

        (fn wallet-send-dialog-sends []
            (local ctx (make-test-ctx))
            (local wallet {:id "arbitrumnova:0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
                           :name "Primary"
                           :coin "arbitrumnova"
                           :address "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
                           :mnemonic "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"})
            (local manager {:get-active (fn [_self] wallet)})
            (local calls {:nonce nil
                          :gas-price 0
                          :estimate nil
                          :send nil})
            (local rpc {:fetch-nonce (fn [_self address]
                                       (set calls.nonce address)
                                       (make-future "0x1"))
                        :fetch-gas-price (fn [_self]
                                           (set calls.gas-price (+ calls.gas-price 1))
                                           (make-future "0x2a"))
                        :estimate-gas (fn [_self opts]
                                        (set calls.estimate opts)
                                        (make-future "0x5208"))
                        :send-raw-transaction (fn [_self raw]
                                                (set calls.send raw)
                                                (make-future "0xabc123"))
                        :poll (fn [_self _max] nil)
                        :pending-count (fn [_self] 0)
                        :drop (fn [_self] nil)})
            (local recipient "0x7d8bf18C7cE84b3E175b339c4Ca93aEd1dD166F1")
            (local dialog
                ((WalletSendDialog {:manager manager
                                    :rpc rpc})
                 ctx))
            (local elements (find-send-elements dialog))
            (local to-input (. elements :to-input))
            (local amount-input (. elements :amount-input))
            (local data-input (. elements :data-input))
            (local send-button (. elements :send-button))
            (to-input:set-text recipient)
            (amount-input:set-text "1")
            (data-input:set-text "")
            (local (sign-ok sign-result)
                   (pcall
                     (fn []
                         (Wallet.sign-arbitrumnova-transfer
                           {:wallet wallet
                            :to recipient
                            :amount-eth "1"
                            :nonce "0x1"
                            :gas-price "0x2a"
                            :gas-limit "0x5208"}))))
            (assert sign-ok (.. "Wallet.sign-arbitrumnova-transfer should sign: " sign-result))
            (send-button:on-click {:button 1})

            (assert (= calls.nonce wallet.address) "WalletSendDialog should fetch nonce for active address")
            (assert (= calls.gas-price 1) "WalletSendDialog should fetch gas price")
            (local expected-value (WalletTxUtils.decimal-to-hex (WalletTxUtils.eth-to-wei "1")))
            (assert (= (. calls.estimate :from) wallet.address)
                    "WalletSendDialog should estimate gas from active address")
            (assert (= (. calls.estimate :to) recipient)
                    "WalletSendDialog should estimate gas to recipient")
            (assert (= (. calls.estimate :value) expected-value)
                    "WalletSendDialog should estimate gas with value")
            (assert (string.match calls.send "^0x")
                    "WalletSendDialog should send raw transaction with 0x prefix")

            (local status-text (. elements :status-text))
            (local tx-text (. elements :tx-text))
            (local status-expected (TextUtils.codepoints-from-text "Status: Transaction sent"))
            (assert-codepoints-eq (status-text:get-codepoints)
                                  status-expected
                                  "WalletSendDialog should update status text")
            (local tx-expected (TextUtils.codepoints-from-text "Tx hash: 0xabc123"))
            (assert-codepoints-eq (tx-text:get-codepoints)
                                  tx-expected
                                  "WalletSendDialog should update tx hash text")
            (dialog:drop))

        (table.insert tests {:name "WalletSendDialog sends transaction" :fn wallet-send-dialog-sends})

        (fn wallet-send-dialog-drop-preserves-injected-rpc-and-cancels-polling []
            (RuntimeTimers.clear)
            (local ctx (make-test-ctx))
            (local wallet {:id "arbitrumnova:0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
                           :name "Primary"
                           :coin "arbitrumnova"
                           :address "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
                           :mnemonic "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"})
            (local manager {:get-active (fn [_self] wallet)})
            (var pending 3)
            (var poll-count 0)
            (var drop-count 0)
            (local future {:on-complete (fn [_cb] nil)})
            (local rpc {:fetch-nonce (fn [_self _address] future)
                        :fetch-gas-price (fn [_self] future)
                        :estimate-gas (fn [_self _opts] future)
                        :send-raw-transaction (fn [_self _raw] future)
                        :poll (fn [_self _max]
                                (set poll-count (+ poll-count 1)))
                        :pending-count (fn [_self]
                                         pending)
                        :drop (fn [_self]
                                (set drop-count (+ drop-count 1)))})
            (local dialog
                ((WalletSendDialog {:manager manager
                                    :rpc rpc})
                 ctx))
            (local elements (find-send-elements dialog))
            ((. elements :to-input):set-text "0x7d8bf18C7cE84b3E175b339c4Ca93aEd1dD166F1")
            ((. elements :amount-input):set-text "1")
            ((. elements :data-input):set-text "")
            ((. elements :send-button):on-click {:button 1})
            (app.engine.events.updated:emit 16)
            (assert (= poll-count 1)
                    "WalletSendDialog should poll while mounted when RPC work is pending")
            (dialog:drop)
            (assert (= drop-count 0)
                    "WalletSendDialog must not drop an injected RPC client")
            (app.engine.events.updated:emit 16)
            (assert (= poll-count 1)
                    "WalletSendDialog drop should cancel RPC polling")
            (RuntimeTimers.clear))

        (table.insert tests {:name "WalletSendDialog drop preserves injected RPC and cancels polling"
                             :fn wallet-send-dialog-drop-preserves-injected-rpc-and-cancels-polling})

        (fn wallet-send-dialog-late-callbacks-after-drop-are-ignored []
            (RuntimeTimers.clear)
            (local ctx (make-test-ctx))
            (local wallet {:id "arbitrumnova:0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
                           :name "Primary"
                           :coin "arbitrumnova"
                           :address "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
                           :mnemonic "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"})
            (local manager {:get-active (fn [_self] wallet)})
            (var pending-count-calls 0)
            (var nonce-callback nil)
            (var gas-price-callback nil)
            (var estimate-callback nil)
            (local rpc {:fetch-nonce (fn [_self _address]
                                       {:on-complete (fn [cb]
                                                       (set nonce-callback cb))})
                        :fetch-gas-price (fn [_self]
                                           {:on-complete (fn [cb]
                                                           (set gas-price-callback cb))})
                        :estimate-gas (fn [_self _opts]
                                        {:on-complete (fn [cb]
                                                        (set estimate-callback cb))})
                        :send-raw-transaction (fn [_self _raw]
                                                {:on-complete (fn [_cb] nil)})
                        :poll (fn [_self _max] nil)
                        :pending-count (fn [_self]
                                         (set pending-count-calls (+ pending-count-calls 1))
                                         0)
                        :drop (fn [_self] nil)})
            (local dialog
                ((WalletSendDialog {:manager manager
                                    :rpc rpc})
                 ctx))
            (local elements (find-send-elements dialog))
            ((. elements :to-input):set-text "0x7d8bf18C7cE84b3E175b339c4Ca93aEd1dD166F1")
            ((. elements :amount-input):set-text "1")
            ((. elements :data-input):set-text "")
            ((. elements :send-button):on-click {:button 1})
            (assert nonce-callback "WalletSendDialog test requires a captured nonce callback")
            (assert gas-price-callback "WalletSendDialog test requires a captured gas-price callback")
            (assert estimate-callback "WalletSendDialog test requires a captured estimate callback")
            (dialog:drop)
            (local calls-before pending-count-calls)
            (local (ok err)
                (pcall (fn []
                         (nonce-callback true "0x1" nil "mock")
                         (gas-price-callback true "0x2a" nil "mock")
                         (estimate-callback true "0x5208" nil "mock"))))
            (assert ok (or err "WalletSendDialog late callbacks should be ignored after drop"))
            (assert (= pending-count-calls calls-before)
                    "WalletSendDialog late callbacks should not touch RPC state after drop")
            (RuntimeTimers.clear))

        (table.insert tests {:name "WalletSendDialog late callbacks after drop are ignored"
                             :fn wallet-send-dialog-late-callbacks-after-drop-are-ignored})

        (local main
            (fn []
                (local runner (require :tests/runner))
                (runner.run-tests {:name "wallet-send-dialog"
                                   :tests tests})))

        {:name "wallet-send-dialog"
         :tests tests
         :main main}))
