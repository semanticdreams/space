(local tests [])
(local _ (require :main))
(local BuildContext (require :build-context))
(local HudControlPanel (require :hud-control-panel))
(local HudExtendedSidebar (require :hud-extended-sidebar))
(local HudExtendedSidebarView (require :hud-extended-sidebar-view))
(local {: StatusPanelLayout} (require :hud-status-panel-layout))
(local SandboxToolbarState (require :sandbox-toolbar-state))
(local SandboxToolbarView (require :sandbox-toolbar-view))
(local Text (require :text))
(local Button (require :button))
(local MathUtils (require :math-utils))
(local approx (. MathUtils :approx))
(local HudChromeMetrics (require :hud-chrome-metrics))

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
  (local font {:metadata {:metrics {:ascender 1.1 :descender -0.1 :lineHeight 1.2}
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

(fn hud-chrome-icon-button-height-matches-rail-width []
  (local ctx (make-test-ctx))
  (local rail-width (reference-rail-width ctx))
  (local button-builder
    (Button {:icon "apps"
             :variant :primary
             :padding HudChromeMetrics.single-row-button-padding
             :icon-style HudChromeMetrics.single-row-button-icon-style}))
  (local button (button-builder ctx))
  (local measured (measure-entity button))
  (assert-close measured.y rail-width
                "single-row icon-only button natural height should match collapsed rail width")
  (button:drop))

(fn hud-chrome-test-stub-line-height-is-material []
  (local ctx (make-test-ctx))
  (local icons (assert ctx.icons "test context must provide icons"))
  (local resolved (icons:resolve "test_icon"))
  (local font (and resolved resolved.font))
  (assert font "test stub must resolve a font")
  (local metrics (and font.metadata font.metadata.metrics))
  (assert metrics "test stub font must expose metrics")
  (assert-close metrics.lineHeight 1.2
                "test stub icon font lineHeight must match real Material icons so square stubs cannot mask bugs"))

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

(fn hud-chrome-sandbox-toolbar-height-matches-rail-width []
  (local ctx (make-test-ctx))
  (local rail-width (reference-rail-width ctx))
  (local state (SandboxToolbarState {}))
  (local toolbar ((SandboxToolbarView state) ctx))
  (local measured (measure-entity toolbar))
  (assert-close measured.y rail-width
                "Sandbox toolbar natural height should match collapsed rail width")
  (toolbar:drop))

(fn hud-chrome-sandbox-toolbar-root-has-card-background []
  (local ctx (make-test-ctx))
  (local state (SandboxToolbarState {}))
  (local toolbar ((SandboxToolbarView state) ctx))
  (assert toolbar.background-color
          "Sandbox toolbar root should expose a Card background color")
  (assert (and toolbar.children (. toolbar.children 1))
          "Sandbox toolbar Card root should include a background rectangle child")
  (toolbar:drop))

(table.insert tests {:name "HUD chrome icon-button height matches rail width"
                      :fn hud-chrome-icon-button-height-matches-rail-width})
(table.insert tests {:name "HUD chrome test stub lineHeight is material-realistic"
                      :fn hud-chrome-test-stub-line-height-is-material})
(table.insert tests {:name "HUD chrome control panel height matches rail width"
                     :fn hud-chrome-control-panel-height-matches-rail-width})
(table.insert tests {:name "HUD chrome status panel height matches rail width"
                     :fn hud-chrome-status-panel-height-matches-rail-width})
(table.insert tests {:name "HUD chrome Sandbox toolbar height matches rail width"
                     :fn hud-chrome-sandbox-toolbar-height-matches-rail-width})
(table.insert tests {:name "HUD chrome Sandbox toolbar root has Card background"
                     :fn hud-chrome-sandbox-toolbar-root-has-card-background})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hud-chrome-uniformity"
                       :tests tests})))

{:name "hud-chrome-uniformity"
 :tests tests
 :main main}
