(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))
(local widget-theme-utils (require :widget-theme-utils))
(local Card (require :card))
(local Padding (require :padding))
(local HudChromeMetrics (require :hud-chrome-metrics))

(local mode-button-specs [{:mode :flight
                           :text "Fly"
                           :icon "flight"
                           :layout-name "sandbox-toolbar-mode-flight"}
                          {:mode :walk
                           :text "Walk"
                           :icon "directions_walk"
                           :layout-name "sandbox-toolbar-mode-walk"}
                          {:mode :move
                           :text "Move"
                           :icon "open_with"
                           :layout-name "sandbox-toolbar-mode-move"}
                          {:mode :grab
                           :text "Grab"
                           :icon "pan_tool"
                           :layout-name "sandbox-toolbar-mode-grab"}])

(fn mode-button-variant [state mode]
  (if (= state.interaction-mode mode) :primary :secondary))

(fn resolve-and-apply-variant [ctx btn new-variant]
  "Re-resolve button theme colors for a new variant and update the button."
  (when (not (= btn.variant new-variant))
    (set btn.variant new-variant)
    (local resolved (widget-theme-utils.resolve-button-colors ctx {:variant new-variant}))
    (set btn.background-color resolved.background)
    (set btn.hover-background-color resolved.hover)
    (set btn.pressed-background-color resolved.pressed)
    (set btn.foreground-color resolved.foreground)
    (btn:update-background-color {:mark-layout-dirty? true})))

(fn make-mode-button-builder [state mode-buttons spec]
  (fn handle-click [_button _event]
    (state:set-interaction-mode spec.mode))
  (fn build-mode-button [button-ctx]
    (local button
      ((Button {:icon spec.icon
                :text spec.text
                :variant (mode-button-variant state spec.mode)
                :padding HudChromeMetrics.single-row-button-padding
                :icon-style HudChromeMetrics.single-row-button-icon-style
                :on-click handle-click})
       button-ctx))
    (tset mode-buttons spec.mode button)
    button))

(fn mode-button-flex-children [state mode-buttons]
  (icollect [_ spec (ipairs mode-button-specs)]
    (FlexChild (make-mode-button-builder state mode-buttons spec) 0)))

(fn name-mode-button-layouts [mode-buttons]
  (each [_ spec (ipairs mode-button-specs)]
    (local btn (. mode-buttons spec.mode))
    (when (and btn btn.layout)
      (set btn.layout.name spec.layout-name))))

(fn update-mode-button [ctx state mode-buttons spec]
  (local btn (. mode-buttons spec.mode))
  (when btn
    (resolve-and-apply-variant ctx btn (mode-button-variant state spec.mode))))

(fn update-mode-buttons [ctx state mode-buttons]
  (each [_ spec (ipairs mode-button-specs)]
    (update-mode-button ctx state mode-buttons spec)))

(fn build-toolbar [state ctx]
  (local mode-buttons {})

  (local row-builder
    (Flex {:axis 1
           :yalign :center
           :children (mode-button-flex-children state mode-buttons)}))

  (local root
    ((Card {:child
            (Padding {:edge-insets HudChromeMetrics.button-owned-shell-padding
                      :child row-builder})})
     ctx))

  (name-mode-button-layouts mode-buttons)

  (fn update [self]
    (update-mode-buttons ctx state mode-buttons))

  ;; Wire state change signal to update
  (local changed-handler (fn [] (update root)))
  (state.changed:connect changed-handler)

  (set root.update update)

  ;; Wrap root.drop to disconnect from state.changed before delegating to
  ;; the original Card drop, preventing stale callbacks on rebuilt toolbars.
  (local original-drop root.drop)
  (set root.drop (fn [self]
                   (state.changed:disconnect changed-handler true)
                   (when original-drop
                     (original-drop self))))

  root)

(fn SandboxToolbarView [state]
  (fn build [ctx]
    (build-toolbar state ctx))

  build)

SandboxToolbarView
