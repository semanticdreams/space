(local tests [])
(local _ (require :main))
(local BuildContext (require :build-context))
(local HudControlPanel (require :hud-control-panel))
(local HudExtendedSidebar (require :hud-extended-sidebar))
(local HudExtendedSidebarView (require :hud-extended-sidebar-view))
(local {: StatusPanelLayout} (require :hud-status-panel-layout))
(local Text (require :text))
(local MathUtils (require :math-utils))
(local approx (. MathUtils :approx))

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

(fn ensure-themes []
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes))

(fn make-test-ctx []
  (ensure-themes)
  (BuildContext {:theme (app.themes.get-active-theme)
                 :clickables (make-clickables-stub)
                 :hoverables (make-hoverables-stub)
                 :icons (make-icons-stub)
                 :pointer-target {}}))

(fn measure-entity [entity]
  (entity.layout:measurer)
  entity.layout.measure)

(fn make-reference-sidebar []
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                           :icon :test_icon
                           :label "Test"
                           :build-panel (fn [_ctx] nil)})
  sidebar)

(fn reference-rail-width [ctx]
  (local sidebar (make-reference-sidebar))
  (local entity ((HudExtendedSidebarView sidebar) ctx))
  (local measured (measure-entity entity))
  (local width measured.x)
  (entity:drop)
  width)

(fn assert-close [actual expected message]
  (assert (approx actual expected)
          (.. message "; expected " (tostring expected) ", got " (tostring actual))))

(fn text-widget [value]
  (fn [ctx]
    ((Text {:text value}) ctx)))

(fn hud-chrome-control-panel-height-matches-rail-width []
  (local ctx (make-test-ctx))
  (local rail-width (reference-rail-width ctx))
  (local panel (((. HudControlPanel :ControlPanel) {}) ctx))
  (local measured (measure-entity panel))
  (assert-close measured.y rail-width
                "normal control panel natural height should match collapsed rail width")
  (panel:drop))

(fn hud-chrome-status-panel-height-matches-rail-width []
  (local ctx (make-test-ctx))
  (local rail-width (reference-rail-width ctx))
  (local panel
    ((StatusPanelLayout {:commands-builder (text-widget "Ready")
                         :info-builder (text-widget "OK")})
     ctx))
  (local measured (measure-entity panel))
  (assert-close measured.y rail-width
                "normal status panel natural height should match collapsed rail width")
  (panel:drop))

(table.insert tests {:name "HUD chrome control panel height matches rail width"
                     :fn hud-chrome-control-panel-height-matches-rail-width})
(table.insert tests {:name "HUD chrome status panel height matches rail width"
                     :fn hud-chrome-status-panel-height-matches-rail-width})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hud-chrome-uniformity"
                       :tests tests})))

{:name "hud-chrome-uniformity"
 :tests tests
 :main main}
