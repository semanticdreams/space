(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))
(local Button (require :button))
(local VolumeControl (require :volume-control))
(local ThemeActions (require :theme-actions))
(local {: ControlPanelLayout} (require :hud-control-panel-layout))
(local HudChromeMetrics (require :hud-chrome-metrics))
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
  (local button-padding HudChromeMetrics.single-row-button-padding)
  (local button-icon-style HudChromeMetrics.single-row-button-icon-style)
  (local volume-button (VolumeControl.make-volume-button {:padding button-padding
                                                           :icon-style button-icon-style}))
  (Flex
    {:axis 1
     :xspacing HudChromeMetrics.control-row-spacing
     :yalign :largest
     :children
     [
      (FlexChild (Button {:icon "apps"
                          :variant :primary
                          :padding button-padding
                          :icon-style button-icon-style
                          :on-click (fn [_button _event]
                                      (open-launcher))}))
      (FlexChild volume-button)
      (FlexChild (Button {:icon "wallet"
                          :variant :primary
                          :padding button-padding
                          :icon-style button-icon-style
                          :on-click (fn [_button _event]
                                      (open-wallet))}))
      (FlexChild (Button {:icon "terminal"
                          :variant :primary
                          :padding button-padding
                          :icon-style button-icon-style
                          :on-click (fn [_button _event]
                                      (open-terminal))}))
      (FlexChild (Button {:icon "settings"
                          :variant :primary
                          :padding button-padding
                          :icon-style button-icon-style}))
      (FlexChild (Button {:icon "contrast"
                          :variant :primary
                          :padding button-padding
                          :icon-style button-icon-style
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
