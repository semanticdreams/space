(local glm (require :glm))
(local _ (require :main))
(local TabView (require :tab-view))
(local BuildContext (require :build-context))
(local {: FocusManager} (require :focus))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local {: Layout} (require :layout))

(local tests [])

(fn make-focus-build-ctx []
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes)
  (local intersector (Intersectables))
  (local clickables (Clickables {:intersectables intersector}))
  (local hoverables (Hoverables {:intersectables intersector}))
  (local manager (FocusManager {:root-name "tab-view-test"}))
  (local root (manager:get-root-scope))
  (local scope (manager:create-scope {:name "tab-view-scope"}))
  (manager:attach scope root)
  {:ctx (BuildContext {:focus-manager manager
                       :focus-scope scope
                       :clickables clickables
                       :hoverables hoverables
                       :theme (and app app.themes (app.themes.get-active-theme))})
   :manager manager})

(fn make-dummy-content-builder [name counters]
  (fn [_ctx]
    (set counters.builds (+ (or counters.builds 0) 1))
    (local layout
      (Layout {:name (.. "dummy-" name)
               :measurer (fn [self]
                           (set self.measure (glm.vec3 1 1 0)))
               :layouter (fn [_self] nil)}))
    (fn drop [self]
      (set counters.drops (+ (or counters.drops 0) 1))
      (self.layout:drop))
    {:layout layout
     :drop drop}))

(fn tabview-switching-rebuilds-and-drops []
  (local counters {:builds 0 :drops 0})
  (local {:ctx ctx :manager manager} (make-focus-build-ctx))
  (local items
    [["One" (make-dummy-content-builder "one" counters)]
     ["Two" (make-dummy-content-builder "two" counters)]
     ["Three" (make-dummy-content-builder "three" counters)]])
  (local view ((TabView {:items items
                         :horizontal? true
                         :active-variant :solid
                         :inactive-variant :ghost}) ctx))

  (assert (= view.current-tab-index 1))
  (assert (= counters.builds 1))
  (assert (= (length view.layout.children) 2))
  (assert (= (. view.layout.children 2) view.current-tab.layout))
  (local button1 (. view.buttons 1))
  (local button2 (. view.buttons 2))
  (local button3 (. view.buttons 3))
  (assert (and button1 (not button1.ghost?)))
  (assert (and button2 button2.ghost?))
  (assert (and button3 button3.ghost?))

  (view:set-current-tab 2)
  (assert (= view.current-tab-index 2))
  (assert (= counters.builds 2))
  (assert (= counters.drops 1))
  (assert (= (length view.layout.children) 2))
  (assert (= (. view.layout.children 2) view.current-tab.layout))
  (local updated1 (. view.buttons 1))
  (local updated2 (. view.buttons 2))
  (local updated3 (. view.buttons 3))
  (assert (and updated1 updated1.ghost?))
  (assert (and updated2 (not updated2.ghost?)))
  (assert (and updated3 updated3.ghost?))

  (view:reload-current-tab)
  (assert (= view.current-tab-index 2))
  (assert (= counters.builds 3))
  (assert (= counters.drops 2))

  (view:drop)
  (manager:drop))

(fn tabview-index-normalization []
  (local counters {:builds 0 :drops 0})
  (local {:ctx ctx :manager manager} (make-focus-build-ctx))
  (local items
    [["One" (make-dummy-content-builder "one" counters)]
     ["Two" (make-dummy-content-builder "two" counters)]
     ["Three" (make-dummy-content-builder "three" counters)]])
  (local view ((TabView {:items items
                         :initial-tab -1}) ctx))
  (assert (= view.current-tab-index 3))
  (view:set-current-tab 0)
  (assert (= view.current-tab-index 1))
  (view:drop)
  (manager:drop))

(table.insert tests {:name "TabView switching rebuilds and drops content" :fn tabview-switching-rebuilds-and-drops})
(table.insert tests {:name "TabView normalizes 0/-1 indices" :fn tabview-index-normalization})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "tab-view"
                       :tests tests})))

{:name "test-tab-view"
 :tests tests
 :main main}
