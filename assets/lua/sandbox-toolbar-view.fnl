(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))

(fn SandboxToolbarView [state]
  (fn build [ctx]
    (var camera-btn nil)
    (var object-move-btn nil)
    (var drag-attachment-btn nil)

    ;; Camera mode button builder
    (local camera-btn-builder
      (Button {:icon "flight"
               :text "Camera"
               :variant (if (= state.camera-mode :grounded) :primary :secondary)
               :padding [0.4 0.4]
               :on-click (fn [_button _event]
                           (state:toggle-camera-mode))}))

    ;; Object move button builder
    (local object-move-btn-builder
      (Button {:icon "open_with"
               :text "Move"
               :variant (if state.object-move-enabled? :primary :secondary)
               :padding [0.4 0.4]
               :on-click (fn [_button _event]
                           (state:toggle-object-move-enabled!))}))

    ;; Drag attachment button builder
    (local drag-attachment-btn-builder
      (Button {:icon "anchor"
               :text "Anchor"
               :variant (if (= state.drag-attachment :anchor) :primary :secondary)
               :padding [0.4 0.4]
               :on-click (fn [_button _event]
                           (state:toggle-drag-attachment))}))

    ;; Build Flex layout
    (local flex (Flex {:axis 1
                       :yalign :center
                       :children
                       [(FlexChild camera-btn-builder 0)
                        (FlexChild object-move-btn-builder 0)
                        (FlexChild drag-attachment-btn-builder 0)]}))

    (local root (flex ctx))

    ;; Extract button entities from Flex metadata wrappers
    (set camera-btn (. root.children 1 :element))
    (set object-move-btn (. root.children 2 :element))
    (set drag-attachment-btn (. root.children 3 :element))

    ;; Set layout names on buttons
    (when (and camera-btn camera-btn.layout)
      (set camera-btn.layout.name "sandbox-toolbar-camera-mode"))
    (when (and object-move-btn object-move-btn.layout)
      (set object-move-btn.layout.name "sandbox-toolbar-object-move"))
    (when (and drag-attachment-btn drag-attachment-btn.layout)
      (set drag-attachment-btn.layout.name "sandbox-toolbar-drag-attachment"))

    (fn update [self]
      ;; Update camera mode button variant
      (when camera-btn
        (local new-variant (if (= state.camera-mode :grounded) :primary :secondary))
        (when (not (= camera-btn.variant new-variant))
          (set camera-btn.variant new-variant)
          (camera-btn:update-background-color {:mark-layout-dirty? true})))

      ;; Update object move button variant
      (when object-move-btn
        (local new-variant (if state.object-move-enabled? :primary :secondary))
        (when (not (= object-move-btn.variant new-variant))
          (set object-move-btn.variant new-variant)
          (object-move-btn:update-background-color {:mark-layout-dirty? true})))

      ;; Update drag attachment button variant
      (when drag-attachment-btn
        (local new-variant (if (= state.drag-attachment :anchor) :primary :secondary))
        (when (not (= drag-attachment-btn.variant new-variant))
          (set drag-attachment-btn.variant new-variant)
          (drag-attachment-btn:update-background-color {:mark-layout-dirty? true}))))

    ;; Wire state change signal to update
    (state.changed:connect (fn [] (update root)))

    (set root.update update)
    root)

  build)

SandboxToolbarView
