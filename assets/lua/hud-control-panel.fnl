(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))
(local Button (require :button))
(local VolumeControl (require :volume-control))
(local ThemeActions (require :theme-actions))
(local {: ControlPanelLayout} (require :hud-control-panel-layout))
(local LauncherLaunchable (require :launchables/launcher))
(local WalletLaunchable (require :launchables/wallet))
(local TerminalLaunchable (require :launchables/terminal))

(fn open-wallet []
  (WalletLaunchable.open-panel {:scene app.scene}))

(fn open-terminal []
  (TerminalLaunchable.open-panel {:scene app.scene}))

(fn open-launcher []
  (LauncherLaunchable.open-panel {:hud app.hud}))

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
                                      (ThemeActions.request-toggle-theme))}))
      ]}))

(fn ControlPanel [_opts]
  (local options (or _opts {}))
  (fn build [ctx]
    (local button-row
      (or options.button-row-builder
          (make-button-row {})))
    (local status-builder
      (or options.status-builder
          (fn [child-ctx]
            ((Text {:text "Status: Nominal"}) child-ctx))))
    (local body-builder options.body-builder)
    ((ControlPanelLayout {:status-builder status-builder
                          :body-builder body-builder
                          :button-row-builder button-row})
     ctx))
  build)

(local exports {:ControlPanel ControlPanel})

(setmetatable exports {:__call (fn [_ ...]
                                 (ControlPanel ...))})

exports
