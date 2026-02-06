(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))
(local Button (require :button))
(local VolumeControl (require :volume-control))
(local ThemeActions (require :theme-actions))
(local {: ControlPanelLayout} (require :hud-control-panel-layout))
(local LauncherView (require :launcher-view))
(local WalletView (require :wallet-view))
(local LaunchablesHelpers (require :launchables-helpers))

(fn open-wallet []
  (local scene app.scene)
  (assert (and scene scene.add-panel-child) "Wallet button requires app.scene.add-panel-child")
  (scene:add-panel-child {:builder (WalletView {})}))

(fn open-terminal []
  (local scene app.scene)
  (assert (and scene scene.add-panel-child) "Terminal button requires app.scene.add-panel-child")
  (scene:add-panel-child {:builder (LaunchablesHelpers.make-terminal-dialog {})}))

(fn open-launcher []
  (assert (and app app.hud app.hud.add-panel-child)
          "Apps button requires app.hud:add-panel-child")
  (var element nil)
  (set element
       (app.hud:add-panel-child
         {:builder (LauncherView {:title "Launcher"})
          :builder-options {:on-close (fn [_dialog _button _event]
                                        (when (and element app.hud)
                                          (app.hud:remove-panel-child element)))}}))
  element)

(fn make-button-row [_opts]
  (local volume-button (VolumeControl.make-volume-button))
  (Flex
    {:axis 1
     :yalign :largest
     :children
     [
      (FlexChild (Button {:icon "apps"
                          :variant :primary
                          :padding [0.4 0.4]
                          :on-click (fn [_button _event]
                                      (open-launcher))}))
      (FlexChild volume-button)
      (FlexChild (Button {:icon "wallet"
                          :variant :primary
                          :padding [0.4 0.4]
                          :on-click (fn [_button _event]
                                      (open-wallet))}))
      (FlexChild (Button {:icon "terminal"
                          :variant :primary
                          :padding [0.4 0.4]
                          :on-click (fn [_button _event]
                                      (open-terminal))}))
      (FlexChild (Button {:icon "settings"
                          :variant :primary
                          :padding [0.4 0.4]}))
      (FlexChild (Button {:icon "contrast"
                          :variant :primary
                          :padding [0.4 0.4]
                          :on-click (fn [_button _event]
                                      (ThemeActions.toggle-theme))}))
      ]}))

(fn ControlPanel [_opts]
  (fn build [ctx]
    (local button-row
      (make-button-row
        {}))
    (local title-builder
      (fn [child-ctx]
        ((Text {:text "CONTROL PANEL"}) child-ctx)))
    (local status-builder
      (fn [child-ctx]
        ((Text {:text "Status: Nominal"}) child-ctx)))
    ((ControlPanelLayout {:title-builder title-builder
                          :status-builder status-builder
                          :button-row-builder button-row})
     ctx))
  build)

(local exports {:ControlPanel ControlPanel})

(setmetatable exports {:__call (fn [_ ...]
                                 (ControlPanel ...))})

exports
