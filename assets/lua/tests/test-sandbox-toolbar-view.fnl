(local tests [])
(local _ (require :main))
(local BuildContext (require :build-context))
(local SandboxToolbarState (require :sandbox-toolbar-state))
(local SandboxToolbarView (require :sandbox-toolbar-view))

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
  "Ensure app.themes is initialized with a known-good active theme.
  Other tests in the fast suite may leave app.themes in an unexpected state,
  so we re-apply the dark theme regardless of initialization status."
  (when (not (and app.themes app.themes.get-active-theme))
    (local AppBootstrap (require :app-bootstrap))
    (AppBootstrap.init-themes))
  ;; Force dark theme so button variant colors differ between primary/secondary
  (when app.themes.set-theme
    (pcall app.themes.set-theme :dark)))

(fn make-test-ctx []
  "Create a BuildContext with theme, clickables, hoverables, and icons."
  (ensure-themes)
  (BuildContext {:theme (app.themes.get-active-theme)
                 :clickables (make-clickables-stub)
                 :hoverables (make-hoverables-stub)
                 :icons (make-icons-stub)}))

(fn find-entity-by-layout-name [root layout-name]
  "Walk the entity tree looking for a layout with the given name."
  (var found nil)
  (fn walk [entity]
    (when (and entity entity.layout (= entity.layout.name layout-name))
      (set found entity))
    ;; Walk entity children (e.g. Flex metadata wrappers)
    (when (and entity entity.children (not found))
      (each [_ child (ipairs entity.children)]
        ;; Flex wraps children in {:flex N :element <entity>}
        (when (and (= (type child) :table) child.element)
          (walk child.element))
        (walk child))))
  (walk root)
  found)

(fn sandbox-toolbar-view-creates-camera-mode-button []
  "The toolbar view must create a button named sandbox-toolbar-camera-mode."
  (local state (SandboxToolbarState {}))
  (local builder (SandboxToolbarView state))
  (local ctx (make-test-ctx))
  (local entity (builder ctx))
  (assert entity "Toolbar view must return an entity")
  (assert entity.children "Toolbar view must have children")
  (local camera-btn (find-entity-by-layout-name entity "sandbox-toolbar-camera-mode"))
  (assert camera-btn
          "Toolbar view must contain a button named sandbox-toolbar-camera-mode"))

(fn sandbox-toolbar-view-creates-object-move-button []
  "The toolbar view must create a button named sandbox-toolbar-object-move."
  (local state (SandboxToolbarState {}))
  (local builder (SandboxToolbarView state))
  (local ctx (make-test-ctx))
  (local entity (builder ctx))
  (local move-btn (find-entity-by-layout-name entity "sandbox-toolbar-object-move"))
  (assert move-btn
          "Toolbar view must contain a button named sandbox-toolbar-object-move"))

(fn sandbox-toolbar-view-creates-drag-attachment-button []
  "The toolbar view must create a button named sandbox-toolbar-drag-attachment."
  (local state (SandboxToolbarState {}))
  (local builder (SandboxToolbarView state))
  (local ctx (make-test-ctx))
  (local entity (builder ctx))
  (local drag-btn (find-entity-by-layout-name entity "sandbox-toolbar-drag-attachment"))
  (assert drag-btn
          "Toolbar view must contain a button named sandbox-toolbar-drag-attachment"))

(fn sandbox-toolbar-view-camera-mode-click-toggles-state []
  "Clicking the camera mode button must toggle state.camera-mode."
  (local state (SandboxToolbarState {}))
  (local builder (SandboxToolbarView state))
  (local ctx (make-test-ctx))
  (local entity (builder ctx))
  (local camera-btn (find-entity-by-layout-name entity "sandbox-toolbar-camera-mode"))
  (assert camera-btn.on-click "Camera mode button must have on-click handler")
  (assert (= state.camera-mode :flight)
          "Camera mode must start as :flight")
  (camera-btn:on-click {})
  (assert (= state.camera-mode :grounded)
          "Camera mode must be :grounded after click"))

(fn sandbox-toolbar-view-object-move-click-toggles-state []
  "Clicking the object move button must toggle state.object-move-enabled?."
  (local state (SandboxToolbarState {}))
  (local builder (SandboxToolbarView state))
  (local ctx (make-test-ctx))
  (local entity (builder ctx))
  (local move-btn (find-entity-by-layout-name entity "sandbox-toolbar-object-move"))
  (assert move-btn.on-click "Object move button must have on-click handler")
  (assert (= state.object-move-enabled? false)
          "Object move must start as false")
  (move-btn:on-click {})
  (assert (= state.object-move-enabled? true)
          "Object move must be true after click"))

(fn sandbox-toolbar-view-drag-attachment-click-toggles-state []
  "Clicking the drag attachment button must toggle state.drag-attachment."
  (local state (SandboxToolbarState {}))
  (local builder (SandboxToolbarView state))
  (local ctx (make-test-ctx))
  (local entity (builder ctx))
  (local drag-btn (find-entity-by-layout-name entity "sandbox-toolbar-drag-attachment"))
  (assert drag-btn.on-click "Drag attachment button must have on-click handler")
  (assert (= state.drag-attachment :center)
          "Drag attachment must start as :center")
  (drag-btn:on-click {})
  (assert (= state.drag-attachment :anchor)
          "Drag attachment must be :anchor after click"))

(fn find-text-widget [widget]
  "Walk from a widget to find a Text widget with set-text method."
  (when widget
    (if widget.set-text
        widget
        (= widget.__type :text-widget) ;; next-app text widget
        widget
        (and widget.children (= (type widget.children) :table))
        (do
          (var found nil)
          (each [_ child (ipairs widget.children)]
            (when (not found)
              (local candidate
                (if (and (= (type child) :table) child.element)
                    (find-text-widget child.element)
                    (find-text-widget child)))
              (when candidate
                (set found candidate))))
          found)
        nil)))

(fn sandbox-toolbar-view-camera-button-text-updates-on-toggle []
  "Camera mode button text must show Flight or Grounded based on state."
  (local state (SandboxToolbarState {}))
  (local builder (SandboxToolbarView state))
  (local ctx (make-test-ctx))
  (local entity (builder ctx))
  (local camera-btn (find-entity-by-layout-name entity "sandbox-toolbar-camera-mode"))
  (local text-widget (find-text-widget camera-btn.text))
  (assert text-widget "Camera button must have a text widget")
  ;; Codepoints for "Flight": [70, 108, 105, 103, 104, 116]
  (local initial-cp (text-widget:get-codepoints))
  (assert (= (. initial-cp 1) 70)
          (.. "Camera button text must start with 'Flight', got first codepoint " (tostring (. initial-cp 1))))
  ;; Toggle to grounded and update — text must change to "Grounded"
  (state:toggle-camera-mode)
  (entity:update)
  (local updated-cp (text-widget:get-codepoints))
  (assert (= (. updated-cp 1) 71)
          (.. "Camera button text must change to 'Grounded' after toggle, got first codepoint " (tostring (. updated-cp 1)))))

(fn sandbox-toolbar-view-variant-changes-background-color []
  "Variant changes must update background-color and related color fields."
  (local state (SandboxToolbarState {}))
  (local builder (SandboxToolbarView state))
  (local ctx (make-test-ctx))
  (local entity (builder ctx))
  (local camera-btn (find-entity-by-layout-name entity "sandbox-toolbar-camera-mode"))
  (assert camera-btn.variant "Camera button must have a variant")
  (local initial-background camera-btn.background-color)
  (assert initial-background "Camera button must have background-color")
  ;; Toggle camera mode and update
  (state:toggle-camera-mode)
  (entity:update)
  ;; Variant must have changed
  (assert (not (= camera-btn.variant (if (= state.camera-mode :grounded) :secondary :primary)))
          "Camera button variant must have changed")
  ;; Background color must have changed (variant re-resolution)
  (assert (not (= camera-btn.background-color initial-background))
          "Camera button background-color must change when variant changes"))

(fn sandbox-toolbar-view-drop-disconnects-from-state-changed []
  "Calling root:drop() must disconnect from state.changed so stale callbacks
  do not fire after the UI is dropped."
  (local state (SandboxToolbarState {}))
  ;; Wrap state.changed:connect to capture the handler the view registers
  (var captured-handler nil)
  (local real-connect state.changed.connect)
  (set state.changed.connect (fn [self handler]
                               (set captured-handler handler)
                               (real-connect self handler)))
  (local builder (SandboxToolbarView state))
  (local ctx (make-test-ctx))
  (local entity (builder ctx))
  (assert captured-handler "View must connect a handler to state.changed")
  ;; Restore original connect (not strictly needed but clean)
  (set state.changed.connect real-connect)
  ;; Drop the entity (should disconnect the captured handler)
  (entity:drop)
  ;; Verify: the handler is no longer connected. disconnect with
  ;; not-connected-ok?=false should error because the handler was already removed.
  (local (ok err) (pcall state.changed.disconnect state.changed captured-handler false))
  (assert (not ok)
          (.. "After drop, state.changed handler must be disconnected, but disconnect succeeded. Error: " (tostring err))))

(table.insert tests {:name "sandbox toolbar view creates camera mode button"
                      :fn sandbox-toolbar-view-creates-camera-mode-button})
(table.insert tests {:name "sandbox toolbar view creates object move button"
                      :fn sandbox-toolbar-view-creates-object-move-button})
(table.insert tests {:name "sandbox toolbar view creates drag attachment button"
                      :fn sandbox-toolbar-view-creates-drag-attachment-button})
(table.insert tests {:name "sandbox toolbar view camera mode click toggles state"
                      :fn sandbox-toolbar-view-camera-mode-click-toggles-state})
(table.insert tests {:name "sandbox toolbar view object move click toggles state"
                      :fn sandbox-toolbar-view-object-move-click-toggles-state})
(table.insert tests {:name "sandbox toolbar view drag attachment click toggles state"
                      :fn sandbox-toolbar-view-drag-attachment-click-toggles-state})
(table.insert tests {:name "sandbox toolbar view camera button text updates on toggle"
                      :fn sandbox-toolbar-view-camera-button-text-updates-on-toggle})
(table.insert tests {:name "sandbox toolbar view variant changes background color"
                      :fn sandbox-toolbar-view-variant-changes-background-color})
(table.insert tests {:name "sandbox toolbar view drop disconnects from state changed"
                      :fn sandbox-toolbar-view-drop-disconnects-from-state-changed})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "sandbox-toolbar-view"
                       :tests tests})))

{:name "sandbox-toolbar-view"
 :tests tests
 :main main}
