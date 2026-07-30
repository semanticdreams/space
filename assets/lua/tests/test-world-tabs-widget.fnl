(local glm (require :glm))
(local _ (require :main))
(local WorldTabsWidget (require :world-tabs-widget))
(local BuildContext (require :build-context))
(local Signal (require :signal))

(local tests [])

(fn make-clickables-stub []
  (local state {:left []
                :right []
                :double []})
  (local stub {:state state})
  (set stub.register (fn [_self obj]
                       (table.insert state.left obj)))
  (set stub.unregister (fn [_self _obj] nil))
  (set stub.register-right-click (fn [_self obj]
                                   (table.insert state.right obj)))
  (set stub.unregister-right-click (fn [_self _obj] nil))
  (set stub.register-double-click (fn [_self obj]
                                    (table.insert state.double obj)))
  (set stub.unregister-double-click (fn [_self _obj] nil))
  stub)

(fn make-hoverables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  stub)

(fn make-test-ctx [opts]
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes)
  (local options (or opts {}))
  (BuildContext {:clickables (assert options.clickables "world tabs widget test context requires clickables")
                 :hoverables (assert options.hoverables "world tabs widget test context requires hoverables")
                 :theme (and app app.themes (app.themes.get-active-theme))}))

(fn world-tabs-right-click-opens-delete-menu []
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables
                             :hoverables hoverables}))
  (var tabs [{:index 1 :id "alpha" :name "home" :active? true}
             {:index 2 :id "beta" :name "home-2" :active? false}])
  (local changed (Signal))
  (local closes [])
  (local activated [])
  (local world-manager
    {:changed changed
     :list-tabs (fn [_self] tabs)
     :activate-index (fn [_self idx]
                       (table.insert activated idx))
     :close-world-index (fn [_self idx]
                          (table.insert closes idx))})
  (var opened nil)
  (local menu-manager
    {:open (fn [_self payload]
             (set opened payload))})

  (local widget
    ((WorldTabsWidget {:world-manager world-manager
                       :get-menu-manager (fn [] menu-manager)})
     ctx))

  (assert (= (length clickables.state.right) 3)
          "Expected two tab buttons plus add button to register for right click")

  (local first-tab-button (. clickables.state.right 1))
  (assert first-tab-button "Expected first tab button to be registered")
  (first-tab-button:on-right-click {:point (glm.vec3 2 3 0)
                                    :button 3})

  (assert opened "World tab right click should open a menu")
  (assert (= (length opened.actions) 1)
          "World tab menu should only include delete action")
  (local action (. opened.actions 1))
  (assert (= action.name "Delete world")
          "World tab menu action should be named 'Delete world'")

  ;; Validate delete resolves by world id at click time, not stale tab index.
  (set tabs [{:index 1 :id "beta" :name "home-2" :active? true}
             {:index 2 :id "alpha" :name "home" :active? false}])
  (action.on-click nil {})
  (assert (= (length closes) 1) "Delete action should close exactly one world")
  (assert (= (. closes 1) 2)
          "Delete action should resolve the current index for the tab id")

  (local second-tab-button (. clickables.state.left 2))
  (second-tab-button:on-click {:button 1})
  (assert (= (length activated) 1) "Tab click should activate a world")

  (widget:drop))

(table.insert tests {:name "WorldTabsWidget opens delete context menu on tab right click"
                     :fn world-tabs-right-click-opens-delete-menu})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "world-tabs-widget"
                       :tests tests})))

{:name "test-world-tabs-widget"
 :tests tests
 :main main}
