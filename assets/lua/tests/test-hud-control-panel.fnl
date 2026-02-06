(local BuildContext (require :build-context))
(local HudControlPanel (require :hud-control-panel))

(local tests [])

(fn make-clickables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  (set stub.register-right-click (fn [_self _obj] nil))
  (set stub.unregister-right-click (fn [_self _obj] nil))
  (set stub.register-double-click (fn [_self _obj] nil))
  (set stub.unregister-double-click (fn [_self _obj] nil))
  (set stub.register-left-click-void-callback (fn [_self _cb] nil))
  (set stub.unregister-left-click-void-callback (fn [_self _cb] nil))
  (set stub.register-right-click-void-callback (fn [_self _cb] nil))
  (set stub.unregister-right-click-void-callback (fn [_self _cb] nil))
  stub)

(fn make-hoverables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  stub)

(fn make-icons-stub []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}
               :advance 1})
  (local stub {:font font})
  (set stub.resolve
       (fn [_self _name]
         {:type :font
          :codepoint 4242
          :font font}))
  stub)

(fn find-table [root pred]
  (local visited {})
  (local queue [root])
  (var found nil)
  (while (> (length queue) 0)
    (local node (table.remove queue 1))
    (when (and (= found nil) (= (type node) :table))
      (when (not (. visited node))
        (set (. visited node) true)
        (if (pred node)
            (set found node)
            (each [_ value (pairs node)]
              (when (= (type value) :table)
                (table.insert queue value)))))))
  found)

(fn control-panel-has-apps-button []
  (local original-hud app.hud)
  (local original-engine app.engine)
  (local original-scene app.scene)
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local icons (make-icons-stub))
  (local ctx
    (BuildContext {:clickables clickables
                   :hoverables hoverables
                   :icons icons
                   :pointer-target {}}))
  (local builder (HudControlPanel.ControlPanel {}))
  (local panel (builder ctx))
  (local apps-button
    (find-table panel
                (fn [node]
                  (= (. node :icon) "apps"))))
  (assert apps-button "Control panel should include an apps icon button")
  (var opened 0)
  (var wallet-opened 0)
  (var terminal-opened 0)
  (set app.engine {:get-asset-path (fn [path]
                                    (if (= path "lua/launchables")
                                        (.. (or (os.getenv "SPACE_ASSETS_PATH") ".") "/lua/launchables")
                                        path))})
  (set app.hud {:add-panel-child (fn [_self _opts]
                                  (set opened (+ opened 1))
                                  {:set-items (fn [_view _items] nil)
                                   :set-query (fn [_view _query] nil)})
                :remove-panel-child (fn [_self _element] true)})
  (apps-button:on-click {:source :test})
  (assert (= opened 1) "Apps button should open launcher")

  (local wallet-button
    (find-table panel
                (fn [node]
                  (= (. node :icon) "wallet"))))
  (assert wallet-button "Control panel should include a wallet icon button")
  (set app.scene {:add-panel-child (fn [_self _opts]
                                     (set wallet-opened (+ wallet-opened 1))
                                     true)})
  (wallet-button:on-click {:source :test})
  (assert (= wallet-opened 1) "Wallet button should open wallet panel")

  (local terminal-button
    (find-table panel
                (fn [node]
                  (= (. node :icon) "terminal"))))
  (assert terminal-button "Control panel should include a terminal icon button")
  (set app.scene {:add-panel-child (fn [_self _opts]
                                     (set terminal-opened (+ terminal-opened 1))
                                     true)})
  (terminal-button:on-click {:source :test})
  (assert (= terminal-opened 1) "Terminal button should open terminal panel")

  (local settings-button
    (find-table panel
                (fn [node]
                  (= (. node :icon) "settings"))))
  (assert settings-button "Control panel should include a settings icon button")
  (settings-button:on-click {:source :test})
  (assert (= opened 1) "Settings button should not open launcher")

  (panel:drop)
  (set app.scene original-scene)
  (set app.hud original-hud)
  (set app.engine original-engine))

(table.insert tests {:name "Control panel apps button opens launcher"
                     :fn control-panel-has-apps-button})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hud-control-panel"
                       :tests tests})))

{:name "hud-control-panel"
 :tests tests
 :main main}
