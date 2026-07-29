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
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes)
  (local ctx (BuildContext {:clickables (make-clickables-stub)
                             :hoverables (make-hoverables-stub)
                             :icons (make-icons-stub)}))
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
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes)
  (local ctx (BuildContext {:clickables (make-clickables-stub)
                             :hoverables (make-hoverables-stub)
                             :icons (make-icons-stub)}))
  (local entity (builder ctx))
  (local move-btn (find-entity-by-layout-name entity "sandbox-toolbar-object-move"))
  (assert move-btn
          "Toolbar view must contain a button named sandbox-toolbar-object-move"))

(fn sandbox-toolbar-view-creates-drag-attachment-button []
  "The toolbar view must create a button named sandbox-toolbar-drag-attachment."
  (local state (SandboxToolbarState {}))
  (local builder (SandboxToolbarView state))
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes)
  (local ctx (BuildContext {:clickables (make-clickables-stub)
                             :hoverables (make-hoverables-stub)
                             :icons (make-icons-stub)}))
  (local entity (builder ctx))
  (local drag-btn (find-entity-by-layout-name entity "sandbox-toolbar-drag-attachment"))
  (assert drag-btn
          "Toolbar view must contain a button named sandbox-toolbar-drag-attachment"))

(fn sandbox-toolbar-view-camera-mode-click-toggles-state []
  "Clicking the camera mode button must toggle state.camera-mode."
  (local state (SandboxToolbarState {}))
  (local builder (SandboxToolbarView state))
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes)
  (local ctx (BuildContext {:clickables (make-clickables-stub)
                             :hoverables (make-hoverables-stub)
                             :icons (make-icons-stub)}))
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
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes)
  (local ctx (BuildContext {:clickables (make-clickables-stub)
                             :hoverables (make-hoverables-stub)
                             :icons (make-icons-stub)}))
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
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes)
  (local ctx (BuildContext {:clickables (make-clickables-stub)
                             :hoverables (make-hoverables-stub)
                             :icons (make-icons-stub)}))
  (local entity (builder ctx))
  (local drag-btn (find-entity-by-layout-name entity "sandbox-toolbar-drag-attachment"))
  (assert drag-btn.on-click "Drag attachment button must have on-click handler")
  (assert (= state.drag-attachment :center)
          "Drag attachment must start as :center")
  (drag-btn:on-click {})
  (assert (= state.drag-attachment :anchor)
          "Drag attachment must be :anchor after click"))

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

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "sandbox-toolbar-view"
                       :tests tests})))

{:name "sandbox-toolbar-view"
 :tests tests
 :main main}
