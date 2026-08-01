(local _ (require :main))
(local WalletRecoverDialog (require :wallet-recover-dialog))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local Intersectables (require :intersectables))
(local fs (require :fs))
(local Wallet (require :wallet))
(local WalletStore (require :wallet-store))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "wallet-recover-dialog"))

(fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "wallet-recover-dialog-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
    (local dir (make-temp-dir))
    (fs.create-dirs dir)
    (f dir))

(fn make-keyring-stub []
    (local secrets {})
    (fn make-key [service account]
        (.. service ":" account))
    {:set-password (fn [service account secret]
                     (tset secrets (make-key service account) secret)
                     true)
     :get-password (fn [service account]
                     (. secrets (make-key service account)))
     :delete-password (fn [service account]
                        (local key (make-key service account))
                        (local existing (. secrets key))
                        (set (. secrets key) nil)
                        (not (= existing nil)))})

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
                              :wallet 4242}})
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
    (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
    (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
    (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
    (set buffer.set-float (fn [_self _handle _offset _value] nil))
    buffer)

(fn make-test-ctx []
    (local intersector (Intersectables))
    (local clickables (assert (Clickables {:intersectables intersector}) "wallet recover dialog test context requires clickables"))
    (local hoverables (assert (Hoverables {:intersectables intersector}) "wallet recover dialog test context requires hoverables"))
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

(fn codepoints->text [codepoints]
    (table.concat
        (icollect [_ codepoint (ipairs codepoints)]
                  (utf8.char codepoint))))

(fn text-entity-text [entity]
    (codepoints->text (entity:get-codepoints)))

(fn with-wallet-bindings [opts body]
    (local options (or opts {}))
    (local original-validate Wallet.validate-mnemonic)
    (local original-create Wallet.create-arbitrumnova)
    (when options.validate
        (set Wallet.validate-mnemonic options.validate))
    (when options.create
        (set Wallet.create-arbitrumnova options.create))
    (local (ok result) (pcall body))
    (set Wallet.validate-mnemonic original-validate)
    (set Wallet.create-arbitrumnova original-create)
    (if ok
        result
        (error result)))

(fn find-recover-elements [dialog]
    (local content (resolve-dialog-body dialog))
    {:mnemonic (. (. content.children 5) :element)
     :button (. (. content.children 6) :element)
     :derived (. (. content.children 7) :element)
     :error (. (. content.children 8) :element)})

(fn wallet-recover-dialog-restores-wallet []
    (with-wallet-bindings
        {:validate (fn [_mnemonic] true)
         :create (fn [opts]
                     {:address "0xa21A2f2502fA54F194283246C2bd96e5b8f2Aa53"
                      :mnemonic opts.mnemonic})}
        (fn []
            (with-temp-dir
                (fn [root]
                    (local keyring (make-keyring-stub))
                    (local store (WalletStore {:data-dir root
                                               :keyring keyring
                                               :service "space-wallet-test"}))
                    (local record
                        (store:save-wallet {:coin "arbitrumnova"
                                            :address "0xa21A2f2502fA54F194283246C2bd96e5b8f2Aa53"
                                            :mnemonic "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
                                            :name "Recoverable"}))
                    ((. keyring :delete-password) "space-wallet-test" record.id)
                    (local wallet (store:describe-wallet record.id))
                    (var recovered nil)
                    (local dialog
                        ((WalletRecoverDialog {:store store
                                               :wallet wallet
                                               :on-recovered (fn [loaded]
                                                               (set recovered loaded))})
                         (make-test-ctx)))
                    (local elements (find-recover-elements dialog))
                    (elements.mnemonic:set-text "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
                    (elements.button:on-click {:button 1})
                    (assert recovered "WalletRecoverDialog should return the recovered wallet")
                    (assert (= recovered.id wallet.id)
                            "WalletRecoverDialog should recover the saved wallet id")
                    (assert (= recovered.mnemonic "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
                            "WalletRecoverDialog should write the mnemonic back into the keyring"))))))

(fn wallet-recover-dialog-rejects-mismatch []
    (with-wallet-bindings
        {:validate (fn [_mnemonic] true)
         :create (fn [opts]
                     {:address "0x0000000000000000000000000000000000000001"
                      :mnemonic opts.mnemonic})}
        (fn []
            (with-temp-dir
                (fn [root]
                    (local keyring (make-keyring-stub))
                    (local store (WalletStore {:data-dir root
                                               :keyring keyring
                                               :service "space-wallet-test"}))
                    (local record
                        (store:save-wallet {:coin "arbitrumnova"
                                            :address "0xa21A2f2502fA54F194283246C2bd96e5b8f2Aa53"
                                            :mnemonic "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
                                            :name "Recoverable"}))
                    ((. keyring :delete-password) "space-wallet-test" record.id)
                    (local wallet (store:describe-wallet record.id))
                    (var recovered nil)
                    (local dialog
                        ((WalletRecoverDialog {:store store
                                               :wallet wallet
                                               :on-recovered (fn [loaded]
                                                               (set recovered loaded))})
                         (make-test-ctx)))
                    (local elements (find-recover-elements dialog))
                    (elements.mnemonic:set-text "legal winner thank year wave sausage worth useful legal winner thank yellow")
                    (elements.button:on-click {:button 1})
                    (assert (not recovered)
                            "WalletRecoverDialog should reject a recovery phrase for a different address")
                    (assert (= (text-entity-text elements.derived) "Derived address: -")
                            "WalletRecoverDialog should clear derived address after mismatch")
                    (assert (= (text-entity-text elements.error)
                               "Recovery phrase does not match 0xa21A2f2502fA54F194283246C2bd96e5b8f2Aa53")
                            "WalletRecoverDialog should explain address mismatch")
                    (dialog:drop))))))

(fn wallet-recover-dialog-rejects-invalid-mnemonic []
    (with-wallet-bindings
        {:validate (fn [_mnemonic] false)
         :create (fn [_opts]
                     (error "WalletRecoverDialog should not derive an address for invalid recovery phrases"))}
        (fn []
            (with-temp-dir
                (fn [root]
                    (local keyring (make-keyring-stub))
                    (local store (WalletStore {:data-dir root
                                               :keyring keyring
                                               :service "space-wallet-test"}))
                    (local record
                        (store:save-wallet {:coin "arbitrumnova"
                                            :address "0xa21A2f2502fA54F194283246C2bd96e5b8f2Aa53"
                                            :mnemonic "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
                                            :name "Recoverable"}))
                    ((. keyring :delete-password) "space-wallet-test" record.id)
                    (local wallet (store:describe-wallet record.id))
                    (var recovered nil)
                    (local dialog
                        ((WalletRecoverDialog {:store store
                                               :wallet wallet
                                               :on-recovered (fn [loaded]
                                                               (set recovered loaded))})
                         (make-test-ctx)))
                    (local elements (find-recover-elements dialog))
                    (elements.mnemonic:set-text "bad phrase")
                    (elements.button:on-click {:button 1})
                    (assert (not recovered)
                            "WalletRecoverDialog should reject invalid recovery phrases")
                    (assert (= (text-entity-text elements.derived) "Derived address: -")
                            "WalletRecoverDialog should not show a derived address for invalid input")
                    (assert (= (text-entity-text elements.error) "Invalid recovery phrase")
                            "WalletRecoverDialog should explain invalid recovery phrases")
                    (dialog:drop))))))

(table.insert tests {:name "WalletRecoverDialog restores wallet" :fn wallet-recover-dialog-restores-wallet})
(table.insert tests {:name "WalletRecoverDialog rejects mismatch" :fn wallet-recover-dialog-rejects-mismatch})
(table.insert tests {:name "WalletRecoverDialog rejects invalid mnemonic"
                     :fn wallet-recover-dialog-rejects-invalid-mnemonic})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "wallet-recover-dialog"
                           :tests tests})))

{:name "wallet-recover-dialog"
 :tests tests
 :main main}
