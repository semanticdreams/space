(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))
(local widget-theme-utils (require :widget-theme-utils))
(local Card (require :card))
(local Padding (require :padding))
(local HudChromeMetrics (require :hud-chrome-metrics))

(fn find-button-text-widget [button]
  "Find the Text widget inside a button's internal structure.
  When buttons have both icon and text, button.text is a Flex whose
  children are metadata wrappers {:flex N :element <entity>}."
  (when button.text
    (if button.text.set-text
        button.text
        (and button.text.children (= (type button.text.children) :table))
        (do
          (var found nil)
          (each [_ child (ipairs button.text.children)]
            (when (and (not found) (= (type child) :table) child.element child.element.set-text)
              (set found child.element)))
          found)
        nil)))

(fn SandboxToolbarView [state]
  (fn build [ctx]
    (var camera-btn nil)
    (var object-move-btn nil)
    (var drag-attachment-btn nil)

    (fn toolbar-button [button-opts capture!]
      (fn [button-ctx]
        (local button ((Button button-opts) button-ctx))
        (capture! button)
        button))

    ;; Camera mode button builder
    (local camera-btn-builder
      (toolbar-button {:icon "flight"
                       :text "Flight"
                       :variant (if (= state.camera-mode :grounded) :primary :secondary)
                       :padding HudChromeMetrics.single-row-button-padding
                       :icon-style HudChromeMetrics.single-row-button-icon-style
                       :on-click (fn [_button _event]
                                   (state:toggle-camera-mode))}
                      (fn [btn] (set camera-btn btn))))

    ;; Object move button builder
    (local object-move-btn-builder
      (toolbar-button {:icon "open_with"
                       :text "Move"
                       :variant (if state.object-move-enabled? :primary :secondary)
                       :padding HudChromeMetrics.single-row-button-padding
                       :icon-style HudChromeMetrics.single-row-button-icon-style
                       :on-click (fn [_button _event]
                                   (state:toggle-object-move-enabled!))}
                      (fn [btn] (set object-move-btn btn))))

    ;; Drag attachment button builder
    (local drag-attachment-btn-builder
      (toolbar-button {:icon "anchor"
                       :text "Anchor"
                       :variant (if (= state.drag-attachment :anchor) :primary :secondary)
                       :padding HudChromeMetrics.single-row-button-padding
                       :icon-style HudChromeMetrics.single-row-button-icon-style
                       :on-click (fn [_button _event]
                                   (state:toggle-drag-attachment))}
                      (fn [btn] (set drag-attachment-btn btn))))

    ;; Build Flex layout
    (local row-builder
      (Flex {:axis 1
             :yalign :center
             :children
             [(FlexChild camera-btn-builder 0)
              (FlexChild object-move-btn-builder 0)
              (FlexChild drag-attachment-btn-builder 0)]}))

    (local root
      ((Card {:child
              (Padding {:edge-insets HudChromeMetrics.single-row-shell-padding
                        :child row-builder})})
       ctx))

    ;; Set layout names on buttons
    (when (and camera-btn camera-btn.layout)
      (set camera-btn.layout.name "sandbox-toolbar-camera-mode"))
    (when (and object-move-btn object-move-btn.layout)
      (set object-move-btn.layout.name "sandbox-toolbar-object-move"))
    (when (and drag-attachment-btn drag-attachment-btn.layout)
      (set drag-attachment-btn.layout.name "sandbox-toolbar-drag-attachment"))

    (fn resolve-and-apply-variant [btn new-variant]
      "Re-resolve button theme colors for a new variant and update the button."
      (when (not (= btn.variant new-variant))
        (set btn.variant new-variant)
        (local resolved (widget-theme-utils.resolve-button-colors ctx {:variant new-variant}))
        (set btn.background-color resolved.background)
        (set btn.hover-background-color resolved.hover)
        (set btn.pressed-background-color resolved.pressed)
        (set btn.foreground-color resolved.foreground)
        (btn:update-background-color {:mark-layout-dirty? true})))

    (fn update-camera-button []
      (when camera-btn
        (local new-label (if (= state.camera-mode :grounded) "Grounded" "Flight"))
        (local text-widget (find-button-text-widget camera-btn))
        (when (and text-widget text-widget.set-text)
          (text-widget:set-text new-label {:mark-measure-dirty? true}))
        ;; Update variant and re-resolve colors
        (resolve-and-apply-variant camera-btn
                                   (if (= state.camera-mode :grounded) :primary :secondary))))

    (fn update-object-move-button []
      (when object-move-btn
        (resolve-and-apply-variant object-move-btn
                                   (if state.object-move-enabled? :primary :secondary))))

    (fn update-drag-attachment-button []
      (when drag-attachment-btn
        (resolve-and-apply-variant drag-attachment-btn
                                   (if (= state.drag-attachment :anchor) :primary :secondary))))

    (fn update [self]
      (update-camera-button)
      (update-object-move-button)
      (update-drag-attachment-button))

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

  build)

SandboxToolbarView
