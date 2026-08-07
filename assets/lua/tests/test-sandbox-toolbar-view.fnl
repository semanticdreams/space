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
  Earlier tests in the fast suite may leave app.themes in an unexpected
  state, so we unconditionally re-initialize the themes system from
  scratch.  This matches the pattern used by test-button.fnl."
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes))

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
        (walk child)))
    ;; Descend through single-child wrappers (e.g. Padding, Card)
    (when (and entity entity.child (not found))
      (walk entity.child)))
  (walk root)
  found)

(local mode-button-specs [{:name "sandbox-toolbar-mode-flight" :mode :flight}
                          {:name "sandbox-toolbar-mode-walk" :mode :walk}
                          {:name "sandbox-toolbar-mode-move" :mode :move}
                          {:name "sandbox-toolbar-mode-grab" :mode :grab}])

(fn sandbox-toolbar-view-clicking-each-mode-selects-mode []
  (local state (SandboxToolbarState {}))
  (local entity ((SandboxToolbarView state) (make-test-ctx)))
  (each [_ pair (ipairs mode-button-specs)]
    (local btn (find-entity-by-layout-name entity pair.name))
    (assert btn (.. "missing button " pair.name))
    (btn:on-click {})
    (assert (= state.interaction-mode pair.mode)
            (.. pair.name " should select " (tostring pair.mode)))))

(fn sandbox-toolbar-view-clicking-active-fly-does-not-emit-change []
  (local state (SandboxToolbarState {}))
  (var changed-count 0)
  (state.changed:connect (fn [_mode]
                           (set changed-count (+ changed-count 1))))
  (local entity ((SandboxToolbarView state) (make-test-ctx)))
  (local flight-btn (find-entity-by-layout-name entity "sandbox-toolbar-mode-flight"))
  (assert flight-btn "missing button sandbox-toolbar-mode-flight")
  (assert (= state.interaction-mode :flight) "initial interaction mode must be :flight")
  (flight-btn:on-click {})
  (assert (= changed-count 0)
          (.. "clicking active Fly must not emit, emitted " (tostring changed-count) " times")))

(fn sandbox-toolbar-view-only-active-mode-button-is-primary []
  (local state (SandboxToolbarState {}))
  (local entity ((SandboxToolbarView state) (make-test-ctx)))
  (each [_ active-pair (ipairs mode-button-specs)]
    (state:set-interaction-mode active-pair.mode)
    (entity:update)
    (each [_ pair (ipairs mode-button-specs)]
      (local btn (find-entity-by-layout-name entity pair.name))
      (assert btn (.. "missing button " pair.name))
      (local expected (if (= pair.mode active-pair.mode) :primary :secondary))
      (assert (= btn.variant expected)
              (.. pair.name " variant should be " (tostring expected)
                  " when active mode is " (tostring active-pair.mode)
                  ", got " (tostring btn.variant))))))

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

(table.insert tests {:name "sandbox toolbar view clicking each mode selects mode"
                      :fn sandbox-toolbar-view-clicking-each-mode-selects-mode})
(table.insert tests {:name "sandbox toolbar view clicking active fly does not emit change"
                      :fn sandbox-toolbar-view-clicking-active-fly-does-not-emit-change})
(table.insert tests {:name "sandbox toolbar view only active mode button is primary"
                      :fn sandbox-toolbar-view-only-active-mode-button-is-primary})
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
