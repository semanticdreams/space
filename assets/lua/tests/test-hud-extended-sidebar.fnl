(global app (or app {}))

(local glm (require :glm))
(local HudExtendedSidebar (require :hud-extended-sidebar))
(local HudExtendedSidebarView (require :hud-extended-sidebar-view))
(local Hud (require :hud))
(local {: Layout} (require :layout))
(local BuildContext (require :build-context))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local Button (require :button))
(local MathUtils (require :math-utils))
(local approx (. MathUtils :approx))
(local HudChromeMetrics (require :hud-chrome-metrics))
(local Stack (require :stack))
(local Rectangle (require :rectangle))

(local tests [])

(fn make-test-theme []
  {:font nil
   :card {:background (glm.vec4 0.1 0.12 0.16 0.96)}})

(fn make-icons-stub []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}
               :advance 1})
  {:font font
   :resolve (fn [_self _name]
              {:type :font
               :codepoint 4242
               :font font})
   :get (fn [_self _name] 4242)})

(fn make-widget-ctx []
  (local intersector (Intersectables))
  (local clickables (assert (Clickables {:intersectables intersector}) "HUD extended sidebar test context requires clickables"))
  (local hoverables (assert (Hoverables {:intersectables intersector}) "HUD extended sidebar test context requires hoverables"))
  (BuildContext {:clickables clickables
                 :hoverables hoverables
                 :icons (make-icons-stub)
                 :theme (make-test-theme)}))

(fn vec4-approx [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)
       (approx a.w b.w)))

(fn make-spy-quad-batcher []
  (var entries {})
  (var active-count 0)
  {   :upsert-quad (fn [self key opts]
                  (when (not (. entries key))
                    (set active-count (+ active-count 1)))
                  (set (. entries key) {:color (or (and opts opts.color) (glm.vec4 0 0 0 0))})
                  nil)
   :remove-quad (fn [self key]
                  (when (. entries key)
                    (set active-count (- active-count 1))
                    (set (. entries key) nil))
                  nil)
   :color-active? (fn [self color]
                    (each [_ entry (pairs entries)]
                      (when (and entry entry.color (vec4-approx entry.color color))
                        (lua "return true")))
                    false)
   :get-instance-count (fn [self] active-count)
   :begin-frame (fn [self]) :end-frame (fn [self])
   :clear (fn [self] (set entries {}) (set active-count 0))
   :get-vector (fn [self] nil) :get-batches (fn [self] [])
   :get-clip-vector (fn [self] nil) :get-clip-group-vector (fn [self] nil)
   :drop (fn [self])})

(fn make-widget-ctx-with-spy []
  (local ctx (make-widget-ctx))
  (local spy (make-spy-quad-batcher))
  (set ctx.get-rectangle-quad-batcher (fn [_] spy))
  (values ctx spy))

(fn make-rect-panel [color]
  (fn [ctx]
    (local entity
      ((Stack {:children [(fn [inner-ctx]
                            ((Rectangle {:color color}) inner-ctx))]})
       ctx))
    {:layout entity.layout
     :drop (fn [self] (entity:drop))}))

(fn make-test-panel [name size]
  (var dropped? false)
  (var update-count 0)
  (fn [ctx]
    (local layout
      (Layout {:name name
               :measurer (fn [self]
                           (set self.measure size))
               :layouter (fn [self]
                           (set self.size (or self.size self.measure)))}))
    {:layout layout
     :dropped? dropped?
     :update-count update-count
     :update (fn [self]
               (set self.update-count (+ (or self.update-count 0) 1)))
     :drop (fn [self]
             (set self.dropped? true)
             (layout:drop))}))

(fn sidebar-register-entry-rejects-missing-fields []
  (local sidebar (HudExtendedSidebar))
  (local (ok _err) (pcall (fn []
                             (sidebar:register-entry {}))))
  (assert (not ok) "register-entry should reject empty entry")
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [_ctx] nil)})
  (assert (= (sidebar:get-entry :unknown) nil)
          "get-entry for unknown id returns nil"))

(fn sidebar-select-switches-active-id-and-expands []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :a
                            :icon :icon_a
                            :label "A"
                            :build-panel (fn [_ctx] nil)})
  (sidebar:register-entry {:id :b
                            :icon :icon_b
                            :label "B"
                            :build-panel (fn [_ctx] nil)})
  (sidebar:select :a)
  (assert (= sidebar.active-id :a) "select should set active-id")
  (assert sidebar.expanded? "select should expand")
  (sidebar:select :b)
  (assert (= sidebar.active-id :b) "select should switch active-id")
  (assert sidebar.expanded? "select should keep expanded"))

(fn sidebar-toggle-flips-expanded []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :a
                            :icon :icon_a
                            :label "A"
                            :build-panel (fn [_ctx] nil)})
  (sidebar:select :a)
  (assert sidebar.expanded? "starts expanded")
  (sidebar:toggle)
  (assert (not sidebar.expanded?) "toggle should collapse")
  (sidebar:toggle)
  (assert sidebar.expanded? "toggle should re-expand"))

(fn sidebar-collapse-only-when-expanded []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :a
                            :icon :icon_a
                            :label "A"
                            :build-panel (fn [_ctx] nil)})
  (sidebar:select :a)
  (assert sidebar.expanded? "starts expanded")
  (sidebar:collapse)
  (assert (not sidebar.expanded?) "collapse sets expanded? to false")
  (sidebar:collapse)
  (assert (not sidebar.expanded?) "collapse is idempotent when already collapsed"))

(fn sidebar-entry-clicked-selects-or-toggles []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :a
                            :icon :icon_a
                            :label "A"
                            :build-panel (fn [_ctx] nil)})
  (sidebar:register-entry {:id :b
                            :icon :icon_b
                            :label "B"
                            :build-panel (fn [_ctx] nil)})
  (sidebar:entry-clicked :a)
  (assert (= sidebar.active-id :a) "first click selects")
  (assert sidebar.expanded? "first click expands")
  (sidebar:entry-clicked :a)
  (assert (not sidebar.expanded?) "second click on same entry toggles collapse")
  (sidebar:entry-clicked :b)
  (assert (= sidebar.active-id :b) "click on different entry switches")
  (assert sidebar.expanded? "switch re-expands"))

(fn sidebar-capture-restore-roundtrip []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :a
                            :icon :icon_a
                            :label "A"
                            :build-panel (fn [_ctx] nil)})
  (sidebar:select :a)
  (sidebar:toggle)
  (local state (sidebar:capture-state))
  (assert (= state.active-id :a) "capture should include active-id")
  (assert (= state.expanded? false) "capture should include expanded?")
  (local sidebar2 (HudExtendedSidebar))
  (sidebar2:register-entry {:id :a
                             :icon :icon_a
                             :label "A"
                             :build-panel (fn [_ctx] nil)})
  (sidebar2:restore-state state)
  (assert (= sidebar2.active-id :a) "restore should set active-id")
  (assert (= sidebar2.expanded? false) "restore should set expanded?"))

(fn sidebar-signal-emits-on-select []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :a
                            :icon :icon_a
                            :label "A"
                            :build-panel (fn [_ctx] nil)})
  (var emitted? false)
  (sidebar.changed:connect (fn [_] (set emitted? true)))
  (sidebar:select :a)
  (assert emitted? "changed signal should fire on select"))

(fn sidebar-signal-emits-on-toggle []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :a
                            :icon :icon_a
                            :label "A"
                            :build-panel (fn [_ctx] nil)})
  (sidebar:select :a)
  (var emitted? false)
  (sidebar.changed:connect (fn [_] (set emitted? true)))
  (sidebar:toggle)
  (assert emitted? "changed signal should fire on toggle"))

(fn sidebar-no-toggle-when-no-active []
  (local sidebar (HudExtendedSidebar))
  (sidebar:toggle)
  (assert (not sidebar.expanded?) "toggle with no active entry does nothing")
  (assert (= sidebar.active-id nil) "active-id stays nil"))

(fn view-lazy-builds-panel []
  (local sidebar (HudExtendedSidebar))
  (var build-count 0)
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           (set build-count (+ build-count 1))
                                           ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))})
  (local ctx (make-widget-ctx))
  (assert (= build-count 0) "panel not built before select")
  (sidebar:select :test)
  (local view (HudExtendedSidebarView sidebar))
  (local entity (view ctx))
  (entity:update)
  (entity:update)
  (assert (= build-count 1) "panel should be built on first expand")
  (sidebar:toggle)
  (entity:update)
  (entity:update)
  (sidebar:toggle)
  (entity:update)
  (entity:update)
  (assert (= build-count 1) "panel should not be rebuilt on re-expand (cached)")
  (entity:drop))

(fn view-panel-survives-collapse []
  (local sidebar (HudExtendedSidebar))
  (var built-panel nil)
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           (set built-panel ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))
                                           built-panel)})
  (local ctx (make-widget-ctx))
  (sidebar:select :test)
  (local view (HudExtendedSidebarView sidebar))
  (local entity (view ctx))
  (entity:update)
  (entity:update)
  (local panel-instance built-panel)
  (assert panel-instance "panel should be built on expand")
  (sidebar:toggle)
  (entity:update)
  (entity:update)
  (assert (not panel-instance.dropped?) "panel should not be dropped on collapse")
  (sidebar:toggle)
  (entity:update)
  (entity:update)
  (assert (= built-panel panel-instance) "same panel instance should be reused")
  (entity:drop))

(fn view-panel-survives-switch []
  (local sidebar (HudExtendedSidebar))
  (var panel-a nil)
  (var panel-b nil)
  (sidebar:register-entry {:id :a
                            :icon :icon_a
                            :label "A"
                            :build-panel (fn [ctx]
                                           (set panel-a ((make-test-panel "panel-a" (glm.vec3 1 1 0)) ctx))
                                           panel-a)})
  (sidebar:register-entry {:id :b
                            :icon :icon_b
                            :label "B"
                            :build-panel (fn [ctx]
                                           (set panel-b ((make-test-panel "panel-b" (glm.vec3 1 1 0)) ctx))
                                           panel-b)})
  (local ctx (make-widget-ctx))
  (sidebar:select :a)
  (local view (HudExtendedSidebarView sidebar))
  (local entity (view ctx))
  (entity:update)
  (assert panel-a "panel A should be built")
  (assert (not panel-b) "panel B should not be built yet")
  (sidebar:select :b)
  (entity:update)
  (entity:update)
  (assert panel-b "panel B should be built after switch")
  (local saved-panel-a panel-a)
  (sidebar:select :a)
  (entity:update)
  (entity:update)
  (assert (= panel-a saved-panel-a) "panel A should be reused from cache")
  (entity:drop))

(fn view-hidden-panel-not-updated []
  (local sidebar (HudExtendedSidebar))
  (var update-count 0)
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           (local panel ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))
                                           (set panel.update
                                                (fn [self]
                                                  (set update-count (+ update-count 1))))
                                           panel)})
  (local ctx (make-widget-ctx))
  (sidebar:select :test)
  (local view (HudExtendedSidebarView sidebar))
  (local entity (view ctx))
  (entity:update)
  (entity:update)
  (local after-visible update-count)
  (assert (> after-visible 0) "should update while visible")
  (sidebar:toggle)
  (entity:update)
  (entity:update)
  (entity:update)
  (assert (= update-count after-visible) "hidden panel should not receive updates")
  (entity:drop))

(fn view-hidden-panel-layout-is-not-in-tree []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))})
  (local ctx (make-widget-ctx))
  (sidebar:select :test)
  (local view (HudExtendedSidebarView sidebar))
  (local entity (view ctx))
  (entity:update)
  (entity:update)
  (sidebar:toggle)
  (entity:update)
  (entity:update)
  (var panel-layout nil)
  (each [_ child (ipairs entity.layout.children)]
    (when (= child.name "test-panel")
      (set panel-layout child)))
  (assert (not panel-layout) "collapsed panel layout should not be in layout tree")
  (entity:drop))

(fn hud-capture-includes-extended-sidebar []
  (local sidebar (HudExtendedSidebar))
  (set app.extended-sidebar sidebar)
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [_ctx] nil)})
  (sidebar:select :test)
  (sidebar:toggle)
  (local hud (Hud.Hud {}))
  (hud:build-default {:control-builder (fn [ctx]
                                         ((make-test-panel "control" (glm.vec3 8 3 0)) ctx))
                      :status-builder (fn [ctx]
                                        ((make-test-panel "status" (glm.vec3 8 2 0)) ctx))})
  (hud:update-projection {:width 1920 :height 1080})
  (hud:update)
  (local state (hud:capture-state))
  (assert (= (type state.extended-sidebar) :table) "capture-state should include extended-sidebar")
  (assert (= state.extended-sidebar.active-id :test) "extended-sidebar state should preserve active-id")
  (assert (= state.extended-sidebar.expanded? false) "extended-sidebar state should preserve expanded?")
  (hud:drop)
  (set app.extended-sidebar nil))

(fn hud-restore-includes-extended-sidebar []
  (local sidebar (HudExtendedSidebar))
  (set app.extended-sidebar sidebar)
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [_ctx] nil)})
  (local hud (Hud.Hud {}))
  (hud:build-default {:control-builder (fn [ctx]
                                         ((make-test-panel "control" (glm.vec3 8 3 0)) ctx))
                      :status-builder (fn [ctx]
                                        ((make-test-panel "status" (glm.vec3 8 2 0)) ctx))})
  (hud:update-projection {:width 1920 :height 1080})
  (hud:update)
  (hud:restore-state {:extended-sidebar {:active-id :test :expanded? true}})
  (assert (= sidebar.active-id :test) "restore-state should set active-id on sidebar")
  (assert sidebar.expanded? "restore-state should set expanded? on sidebar")
  (hud:drop)
  (set app.extended-sidebar nil))

(fn view-rail-is-always-visible []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))})
  (local ctx (make-widget-ctx))
  (local view (HudExtendedSidebarView sidebar))
  (local entity (view ctx))
  (entity:update)
  (entity:update)
  (assert (> (length entity.layout.children) 0) "rail should be present even with no active entry")
  (entity:drop))

(fn view-drop-cleans-up []
  (local sidebar (HudExtendedSidebar))
  (var panel-dropped? false)
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           (local p ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))
                                           (local orig-drop p.drop)
                                           (set p.drop (fn [self]
                                                         (set panel-dropped? true)
                                                         (orig-drop self)))
                                           p)})
  (local ctx (make-widget-ctx))
  (sidebar:select :test)
  (local view (HudExtendedSidebarView sidebar))
  (local entity (view ctx))
  (entity:update)
  (entity:update)
  (assert (not panel-dropped?) "panel should not be dropped before view drop")
  (entity:drop)
  (assert panel-dropped? "panel should be dropped when view is dropped"))

(fn sidebar-register-entry-emits-changed []
  (local sidebar (HudExtendedSidebar))
  (var emitted? false)
  (sidebar.changed:connect (fn [_] (set emitted? true)))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [_ctx] nil)})
  (assert emitted? "register-entry should emit changed signal"))

(fn sidebar-select-rejects-invalid-id []
  (local sidebar (HudExtendedSidebar))
  (local (ok _err) (pcall (fn []
                             (sidebar:select :bogus))))
  (assert (not ok) "select should reject an unknown id"))

(fn sidebar-restore-ignores-invalid-active-id []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :valid
                            :icon :icon_a
                            :label "Valid"
                            :build-panel (fn [_ctx] nil)})
  (sidebar:restore-state {:active-id :bogus :expanded? true})
  (assert (= sidebar.active-id nil) "restore should ignore invalid active-id")
  (assert (not sidebar.expanded?) "restore should not expand with invalid active-id"))

(fn sidebar-entries-ordered-by-registration []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :first
                            :icon :icon_a
                            :label "First"
                            :build-panel (fn [_ctx] nil)})
  (sidebar:register-entry {:id :second
                            :icon :icon_b
                            :label "Second"
                            :build-panel (fn [_ctx] nil)})
  (sidebar:register-entry {:id :third
                            :icon :icon_c
                            :label "Third"
                            :build-panel (fn [_ctx] nil)})
  (assert (= (. sidebar.entry-ids 1) :first) "first entry-id should be :first")
  (assert (= (. sidebar.entry-ids 2) :second) "second entry-id should be :second")
  (assert (= (. sidebar.entry-ids 3) :third) "third entry-id should be :third")
  ;; Re-registering an existing entry should not duplicate in order
  (sidebar:register-entry {:id :first
                            :icon :icon_a
                            :label "First Updated"
                            :build-panel (fn [_ctx] nil)})
  (assert (= (length sidebar.entry-ids) 3) "re-registration should not grow entry-ids")
  (assert (= (. sidebar.entry-ids 1) :first) "first entry-id should remain :first"))

(fn view-hidden-panel-layout-does-not-intersect []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))})
  (local ctx (make-widget-ctx))
  (sidebar:select :test)
  (local view (HudExtendedSidebarView sidebar))
  (local entity (view ctx))
  (entity:update)
  (entity:update)
  ;; Cache the layout while it's still in the tree (visible).
  (var panel-layout nil)
  (each [_ child (ipairs entity.layout.children)]
    (when (= child.name "test-panel")
      (set panel-layout child)))
  (assert panel-layout "panel layout should be in tree while visible")
  (sidebar:toggle)
  (entity:update)
  (entity:update)
  ;; After toggling, the panel is removed from the layout tree entirely.
  (var panel-in-tree-after-toggle? false)
  (each [_ child (ipairs entity.layout.children)]
    (when (= child.name "test-panel")
      (set panel-in-tree-after-toggle? true)))
  (assert (not panel-in-tree-after-toggle?) "hidden panel should not be in layout tree")
  (entity:drop))

(fn hud-capture-restore-pending-sidebar-state []
  (set app.extended-sidebar nil)
  (set app.pending-extended-sidebar-state nil)
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [_ctx] nil)})
  (local hud (Hud.Hud {}))
  (hud:build-default {:control-builder (fn [ctx]
                                         ((make-test-panel "control" (glm.vec3 8 3 0)) ctx))
                      :status-builder (fn [ctx]
                                        ((make-test-panel "status" (glm.vec3 8 2 0)) ctx))})
  (hud:update-projection {:width 1920 :height 1080})
  (hud:update)
  (hud:restore-state {:extended-sidebar {:active-id :test :expanded? true}})
  (assert (= (type app.pending-extended-sidebar-state) :table) "should cache pending state")
  (assert (= app.pending-extended-sidebar-state.active-id :test) "pending state should have active-id")
  (assert app.pending-extended-sidebar-state.expanded? "pending state should have expanded?")
  (set app.extended-sidebar sidebar)
  (app.extended-sidebar:restore-state app.pending-extended-sidebar-state)
  (assert (= sidebar.active-id :test) "replayed pending state should set active-id")
  (assert sidebar.expanded? "replayed pending state should set expanded?")
  (set app.pending-extended-sidebar-state nil)
  (hud:drop)
  (set app.extended-sidebar nil))

(table.insert tests {:name "sidebar register-entry rejects missing fields" :fn sidebar-register-entry-rejects-missing-fields})
(table.insert tests {:name "sidebar select switches active-id and expands" :fn sidebar-select-switches-active-id-and-expands})
(table.insert tests {:name "sidebar toggle flips expanded" :fn sidebar-toggle-flips-expanded})
(table.insert tests {:name "sidebar collapse only when expanded" :fn sidebar-collapse-only-when-expanded})
(table.insert tests {:name "sidebar entry-clicked selects or toggles" :fn sidebar-entry-clicked-selects-or-toggles})
(table.insert tests {:name "sidebar capture-restore roundtrip" :fn sidebar-capture-restore-roundtrip})
(table.insert tests {:name "sidebar signal emits on select" :fn sidebar-signal-emits-on-select})
(table.insert tests {:name "sidebar signal emits on toggle" :fn sidebar-signal-emits-on-toggle})
(table.insert tests {:name "sidebar no toggle when no active" :fn sidebar-no-toggle-when-no-active})
(table.insert tests {:name "view lazy-builds panel" :fn view-lazy-builds-panel})
(table.insert tests {:name "view panel survives collapse" :fn view-panel-survives-collapse})
(table.insert tests {:name "view panel survives switch" :fn view-panel-survives-switch})
(table.insert tests {:name "view hidden panel not updated" :fn view-hidden-panel-not-updated})
(table.insert tests {:name "view hidden panel layout is not in tree" :fn view-hidden-panel-layout-is-not-in-tree})
(table.insert tests {:name "hud capture includes extended-sidebar" :fn hud-capture-includes-extended-sidebar})
(table.insert tests {:name "hud restore includes extended-sidebar" :fn hud-restore-includes-extended-sidebar})
(table.insert tests {:name "view rail is always visible" :fn view-rail-is-always-visible})
(table.insert tests {:name "view drop cleans up" :fn view-drop-cleans-up})
(table.insert tests {:name "sidebar register-entry emits changed" :fn sidebar-register-entry-emits-changed})
(table.insert tests {:name "sidebar select rejects invalid id" :fn sidebar-select-rejects-invalid-id})
(table.insert tests {:name "sidebar restore ignores invalid active-id" :fn sidebar-restore-ignores-invalid-active-id})
(table.insert tests {:name "sidebar entries ordered by registration" :fn sidebar-entries-ordered-by-registration})
(table.insert tests {:name "view hidden panel layout does not intersect" :fn view-hidden-panel-layout-does-not-intersect})
(fn hud-capture-restore-pending-retained-on-mismatch []
  (set app.extended-sidebar nil)
  (set app.pending-extended-sidebar-state nil)
  (local hud (Hud.Hud {}))
  (hud:build-default {:control-builder (fn [ctx]
                                         ((make-test-panel "control" (glm.vec3 8 3 0)) ctx))
                      :status-builder (fn [ctx]
                                        ((make-test-panel "status" (glm.vec3 8 2 0)) ctx))})
  (hud:update-projection {:width 1920 :height 1080})
  (hud:update)
  (hud:restore-state {:extended-sidebar {:active-id :pending-agent :expanded? true}})
  (assert (= app.pending-extended-sidebar-state.active-id :pending-agent) "should cache pending")
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :other
                            :icon :icon_a
                            :label "Other"
                            :build-panel (fn [_ctx] nil)})
  (set app.extended-sidebar sidebar)
  (app.extended-sidebar:restore-state app.pending-extended-sidebar-state)
  (assert (= sidebar.active-id nil) "active-id should not be applied for unknown entry")
  (when (or (not app.pending-extended-sidebar-state.active-id)
            (= app.extended-sidebar.active-id app.pending-extended-sidebar-state.active-id))
    (set app.pending-extended-sidebar-state nil))
  (assert (= (type app.pending-extended-sidebar-state) :table) "pending should be retained on mismatch")
  (sidebar:register-entry {:id :pending-agent
                            :icon :icon_b
                            :label "Pending Agent"
                            :build-panel (fn [_ctx] nil)})
  (app.extended-sidebar:restore-state app.pending-extended-sidebar-state)
  (assert (= sidebar.active-id :pending-agent) "should apply after entry registered")
  (when (or (not app.pending-extended-sidebar-state.active-id)
            (= app.extended-sidebar.active-id app.pending-extended-sidebar-state.active-id))
    (set app.pending-extended-sidebar-state nil))
  (assert (= app.pending-extended-sidebar-state nil) "pending cleared after successful restore")
  (hud:drop)
  (set app.extended-sidebar nil))

(fn view-rail-button-matches-activity-button-metrics []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))})
  (local ctx (make-widget-ctx))
  (local entity ((HudExtendedSidebarView sidebar) ctx))
  (entity.layout:measurer)
  (local rail-button (. ctx.clickables.left-click-objects 1))
  (assert rail-button "right rail should register a clickable button")
  (assert (= rail-button.icon :test_icon) "right rail button should keep the entry icon")
  (assert (= rail-button.text.child.style.scale HudChromeMetrics.rail-button-icon-style.scale)
          "right rail icon style should match the shared HUD rail icon scale")
  (local reference-button
    ((Button {:padding HudChromeMetrics.rail-button-padding
              :focusable? false
              :icon :test_icon
              :icon-style HudChromeMetrics.rail-button-icon-style
              :name "reference-extended-sidebar-test"
              :focus-name "Test"
              :on-click (fn [_button _event] nil)
              :variant :secondary})
     ctx))
  (reference-button.layout:measurer)
  (assert (approx rail-button.layout.measure.x reference-button.layout.measure.x)
          "right rail button width should match the activity-style reference button")
  (assert (approx rail-button.layout.measure.y reference-button.layout.measure.y)
          "right rail button height should match the activity-style reference button")
  (reference-button:drop)
  (entity:drop))

(fn view-collapsed-width-equals-measured-rail-width []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))})
  (local ctx (make-widget-ctx))
  (local entity ((HudExtendedSidebarView sidebar) ctx))
  (entity.layout:measurer)
  (local rail-layout (. entity.layout.children 1))
  (assert rail-layout "collapsed sidebar should contain the rail layout")
  (assert (approx entity.layout.measure.x rail-layout.measure.x)
          "collapsed sidebar width should equal measured rail width")
  (entity:drop))

(fn view-expanded-width-equals-panel-plus-measured-rail-width []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))})
  (sidebar:select :test)
  (local ctx (make-widget-ctx))
  (local entity ((HudExtendedSidebarView sidebar) ctx))
  (entity.layout:measurer)
  (local panel-layout (. entity.layout.children 1))
  (local rail-layout (. entity.layout.children 2))
  (assert panel-layout "expanded sidebar should contain the active panel layout")
  (assert rail-layout "expanded sidebar should contain the rail layout")
  (assert (approx entity.layout.measure.x (+ 38 rail-layout.measure.x))
          "expanded sidebar width should equal panel width plus measured rail width")
  (entity:drop))

(fn view-expanded-layout-anchors-rail-to-right-edge []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 1 1 0)) ctx))})
  (sidebar:select :test)
  (local ctx (make-widget-ctx))
  (local entity ((HudExtendedSidebarView sidebar) ctx))
  (entity.layout:measurer)
  (local panel-layout (. entity.layout.children 1))
  (local rail-layout (. entity.layout.children 2))
  (local allocated-width (+ entity.layout.measure.x 5))
  (set entity.layout.position (glm.vec3 10 20 0))
  (set entity.layout.size (glm.vec3 allocated-width 12 0))
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)
  (local rail-width rail-layout.measure.x)
  (local expected-rail-x (+ 10 (- allocated-width rail-width)))
  (local expected-panel-x (- expected-rail-x 38))
  (assert (approx rail-layout.position.x expected-rail-x)
          "rail should be positioned at the right edge of the allocated sidebar area")
  (assert (approx rail-layout.size.x rail-width)
          "rail layout width should equal measured rail width")
  (assert (approx panel-layout.position.x expected-panel-x)
          "panel should be immediately left of the rail")
  (assert (approx panel-layout.size.x 38)
          "expanded panel width should remain fixed at 38 HUD units")
  (entity:drop))

(fn view-collapse-removes-panel-render-resources []
  (local sidebar (HudExtendedSidebar))
  (local panel-color (glm.vec4 0.9 0.1 0.1 1.0))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (make-rect-panel panel-color)})
  (local (ctx spy) (make-widget-ctx-with-spy))
  (sidebar:select :test)
  (local view (HudExtendedSidebarView sidebar))
  (local entity (view ctx))
  (entity:update)
  (entity:update)
  ;; Run a full measure + layout pass so the panel Rectangle writes to the batcher.
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 0 0 0))
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.size (glm.vec3 200 100 0))
  (entity.layout:layouter)
  (assert (spy:color-active? panel-color)
          "panel Rectangle should be in batcher after expand and layout")
  ;; Collapse.
  (sidebar:toggle)
  (entity:update)
  (entity:update)
  (entity.layout:measurer)
  (entity.layout:layouter)
  (assert (not (spy:color-active? panel-color))
          "panel Rectangle should be removed from batcher after collapse")
  (entity:drop))

(fn view-switch-removes-previous-panel-render-resources []
  (local sidebar (HudExtendedSidebar))
  (local color-a (glm.vec4 0.9 0.1 0.1 1.0))
  (local color-b (glm.vec4 0.1 0.9 0.1 1.0))
  (sidebar:register-entry {:id :a
                            :icon :icon_a
                            :label "A"
                            :build-panel (make-rect-panel color-a)})
  (sidebar:register-entry {:id :b
                            :icon :icon_b
                            :label "B"
                            :build-panel (make-rect-panel color-b)})
  (local (ctx spy) (make-widget-ctx-with-spy))
  (sidebar:select :a)
  (local view (HudExtendedSidebarView sidebar))
  (local entity (view ctx))
  (entity:update)
  (entity:update)
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 0 0 0))
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.size (glm.vec3 200 100 0))
  (entity.layout:layouter)
  (assert (spy:color-active? color-a)
          "panel A Rectangle should be in batcher")
  (assert (not (spy:color-active? color-b))
          "panel B Rectangle should NOT be in batcher yet")
  ;; Switch to B.
  (sidebar:select :b)
  (entity:update)
  (entity:update)
  (entity.layout:measurer)
  (entity.layout:layouter)
  (assert (not (spy:color-active? color-a))
          "panel A Rectangle should be removed from batcher after switch")
  (assert (spy:color-active? color-b)
          "panel B Rectangle should be in batcher after switch")
  (entity:drop))

(fn view-collapsed-panel-remains-effectively-culled []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 38 10 0)) ctx))})
  (local ctx (make-widget-ctx))
  (sidebar:select :test)
  (local view (HudExtendedSidebarView sidebar))
  (local entity (view ctx))
  (entity:update)
  (entity:update)
  ;; Capture the panel layout reference while visible.
  (var panel-layout nil)
  (each [_ child (ipairs entity.layout.children)]
    (when (= child.name "test-panel")
      (set panel-layout child)))
  (assert panel-layout "panel layout should be in tree while visible")
  (assert (not (panel-layout:effective-culled?))
          "panel should not be effectively culled while visible")
  ;; Verify intersect works while visible.
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 0 0 0))
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.size (glm.vec3 200 100 0))
  (entity.layout:layouter)
  ;; Use the panel's computed position for intersection.
  (local px panel-layout.position.x)
  (local py panel-layout.position.y)
  (local test-ray {:origin (glm.vec3 px py 1) :direction (glm.vec3 0 0 -1)})
  (local (hit _ _) (panel-layout:intersect test-ray))
  (assert hit "panel should intersect while visible")
  ;; Collapse.
  (sidebar:toggle)
  (entity:update)
  (entity:update)
  (entity.layout:measurer)
  (entity.layout:layouter)
  ;; The cached panel should remain effectively culled.
  (assert (panel-layout:effective-culled?)
          "cached panel should be effectively culled after collapse")
  ;; Intersect should return no hit when effectively culled.
  (local (hit2 _ _) (panel-layout:intersect test-ray))
  (assert (not hit2) "cached panel should not intersect after collapse")
  (entity:drop))

(table.insert tests {:name "hud capture-restore pending sidebar state" :fn hud-capture-restore-pending-sidebar-state})
(table.insert tests {:name "hud pending retained on active-id mismatch" :fn hud-capture-restore-pending-retained-on-mismatch})
(table.insert tests {:name "view rail button matches activity button metrics"
                     :fn view-rail-button-matches-activity-button-metrics})
(table.insert tests {:name "view collapsed width equals measured rail width"
                     :fn view-collapsed-width-equals-measured-rail-width})
(table.insert tests {:name "view expanded width equals panel plus measured rail width"
                     :fn view-expanded-width-equals-panel-plus-measured-rail-width})
(table.insert tests {:name "view expanded layout anchors rail to right edge"
                     :fn view-expanded-layout-anchors-rail-to-right-edge})
(table.insert tests {:name "view collapse removes panel render resources"
                     :fn view-collapse-removes-panel-render-resources})
(table.insert tests {:name "view switch removes previous panel render resources"
                     :fn view-switch-removes-previous-panel-render-resources})
(table.insert tests {:name "view collapsed panel remains effectively culled"
                     :fn view-collapsed-panel-remains-effectively-culled})

(fn expanded-panel-below-toolbar-bottom-anchored-full-rail []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fn [ctx]
                                           ((make-test-panel "test-panel" (glm.vec3 38 10 0)) ctx))})
  (sidebar:select :test)
  (local ctx (make-widget-ctx))
  (local entity ((HudExtendedSidebarView sidebar {:top-reserve-height-provider (fn [] 4)}) ctx))
  (entity:update)
  (entity:update)
  (entity.layout:measurer)
  (set entity.layout.position (glm.vec3 10 0 0))
  (set entity.layout.size (glm.vec3 100 30 0))
  (set entity.layout.rotation (glm.quat 1 0 0 0))
  (set entity.layout.clip-region nil)
  (set entity.layout.depth-offset-index 0)
  (entity.layout:layouter)
  ;; The first child is the active panel, the second is the rail
  (local panel-layout (. entity.layout.children 1))
  (local rail-layout (. entity.layout.children 2))
  (assert rail-layout "rail should be present")
  (assert (approx rail-layout.size.y 30)
          (.. "rail should remain full-height 30, got " rail-layout.size.y))
  (assert panel-layout "panel should be present when expanded")
  (assert (approx panel-layout.position.y 0)
          (.. "panel should be bottom-anchored at root y=0 (below toolbar reserve), got " panel-layout.position.y))
  (assert (approx panel-layout.size.y 26)
          (.. "panel height should be 26 (= 30 - 4), got " panel-layout.size.y))
  (entity:drop))

(table.insert tests {:name "Expanded panel below toolbar bottom-anchored, rail full-height"
                     :fn expanded-panel-below-toolbar-bottom-anchored-full-rail})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hud-extended-sidebar"
                       :tests tests})))

{:name "hud-extended-sidebar"
 :tests tests
 :main main}
