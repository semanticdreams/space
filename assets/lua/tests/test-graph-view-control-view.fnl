(local _ (require :main))
(local GraphViewControlView (require :graph-view-control-view))
(local glm (require :glm))
(local Signal (require :signal))

(local tests [])

(fn make-vector-buffer []
    (local buffer {})
    (set buffer.allocate (fn [_self _count] 1))
    (set buffer.delete (fn [_self _handle] nil))
    (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
    (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
    (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
    (set buffer.set-float (fn [_self _handle _offset _value] nil))
    buffer)

(fn make-icons-stub []
    (local glyph {:advance 1
                  :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                  :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {4242 glyph}
                 :advance 1})
    (local stub {:font font
                 :codepoints {:move_item 4242
                              :add 4242
                              :close 4242}})
    (set stub.get
         (fn [self name]
             (local value (. self.codepoints name))
             (assert value (.. "Missing icon " name))
             value))
    (set stub.resolve
         (fn [self name]
             (local code (self:get name))
             {:type :font
              :codepoint code
              :font self.font}))
    stub)

(fn make-clickables-stub []
    (local stub {})
    (set stub.register (fn [_self _obj] nil))
    (set stub.unregister (fn [_self _obj] nil))
    (set stub.register-right-click (fn [_self _obj] nil))
    (set stub.unregister-right-click (fn [_self _obj] nil))
    (set stub.register-double-click (fn [_self _obj] nil))
    (set stub.unregister-double-click (fn [_self _obj] nil))
    stub)

(fn make-hoverables-stub []
    (local stub {})
    (set stub.register (fn [_self _obj] nil))
    (set stub.unregister (fn [_self _obj] nil))
    stub)

(fn make-system-cursors-stub []
    (local stub {})
    (set stub.set-cursor (fn [_self _name] nil))
    (set stub.reset (fn [_self] nil))
    stub)

(fn make-mock-layout []
    (local layout {:active false
                   :stabilized (Signal)
                   :changed (Signal)
                   :center-force 0.0001})
    (set layout.start (fn [self]
                          (set self.active true)
                          (self.changed:emit)))
    (set layout.stop (fn [self]
                         (set self.active false)
                         (self.changed:emit)))
    layout)

(fn make-mock-graph-view []
    (local layout (make-mock-layout))
    {:layout layout})

(fn make-test-ctx []
    (local triangle (make-vector-buffer))
    (local text-buffer (make-vector-buffer))
    (local ctx {:triangle-vector triangle
                :pointer-target {}})
    (set ctx.get-text-vector (fn [_self _font] text-buffer))
    (set ctx.track-text-handle (fn [_self _font _handle _clip] nil))
    (set ctx.untrack-text-handle (fn [_self _font _handle] nil))
    (set ctx.clickables (make-clickables-stub))
    (set ctx.hoverables (make-hoverables-stub))
    (set ctx.system-cursors (make-system-cursors-stub))
    (set ctx.icons (make-icons-stub))
    ctx)

(fn graph-view-control-view-loads []
    (local graph-view (make-mock-graph-view))
    (local ctx (make-test-ctx))
    (local dialog ((GraphViewControlView {:graph-view graph-view}) ctx))
    (assert dialog "GraphViewControlView should return a dialog")
    (local view dialog.__control-view)
    (assert view "GraphViewControlView should expose control view state")
    (assert view.status-text "GraphViewControlView should have status text")
    (assert view.toggle-button "GraphViewControlView should have toggle button")
    (assert view.center-force-input "GraphViewControlView should have center force input")
    (assert view.center-force-apply-button "GraphViewControlView should have center force apply button")
    (local input-value (tonumber (view.center-force-input:get-text)))
    (assert (< (math.abs (- input-value (. graph-view.layout :center-force))) 1e-9)
            "Center force input should reflect current layout center force")
    (dialog:drop))

(table.insert tests {:name "GraphViewControlView loads"
                     :fn graph-view-control-view-loads})

(fn approx=? [a b eps]
    (< (math.abs (- a b)) (or eps 1e-12)))

(fn graph-view-control-view-applies-center-force []
    (local graph-view (make-mock-graph-view))
    (local layout graph-view.layout)
    (local ctx (make-test-ctx))
    (local dialog ((GraphViewControlView {:graph-view graph-view}) ctx))
    (local view dialog.__control-view)
    (assert (= layout.active false) "Apply should start layout from stabilized state")
    (view.center-force-input:set-text "0.0002" {:reset-cursor? true})
    (view.center-force-apply-button:on-click {})
    (assert (approx=? (. layout :center-force) 0.0002 1e-9)
            "Apply should update layout center force")
    (assert layout.active "Apply should start layout even if stabilized")
    (assert (approx=? (tonumber (view.center-force-input:get-text)) (. layout :center-force) 1e-9)
            "Apply should normalize input text to accepted value")
    (dialog:drop))

(table.insert tests {:name "GraphViewControlView applies center force"
                     :fn graph-view-control-view-applies-center-force})

(fn graph-view-control-view-rejects-invalid-center-force []
    (local graph-view (make-mock-graph-view))
    (local layout graph-view.layout)
    (local ctx (make-test-ctx))
    (local dialog ((GraphViewControlView {:graph-view graph-view}) ctx))
    (local view dialog.__control-view)
    (set (. layout :center-force) 0.00025)
    (view.center-force-input:set-text "-1" {:reset-cursor? true})
    (view.center-force-apply-button:on-click {})
    (assert (approx=? (. layout :center-force) 0.00025 1e-9)
            "Invalid center force should not be applied")
    (assert (= layout.active false) "Invalid apply should not start layout")
    (assert (approx=? (tonumber (view.center-force-input:get-text)) (. layout :center-force) 1e-9)
            "Invalid center force should reset input to accepted value")
    (view.center-force-input:set-text "1.0" {:reset-cursor? true})
    (view.center-force-apply-button:on-click {})
    (assert (approx=? (. layout :center-force) 0.00025 1e-9)
            "Out of range center force should not be applied")
    (assert (= layout.active false) "Out of range apply should not start layout")
    (assert (approx=? (tonumber (view.center-force-input:get-text)) (. layout :center-force) 1e-9)
            "Out of range center force should reset input to accepted value")
    (dialog:drop))

(table.insert tests {:name "GraphViewControlView rejects invalid center force"
                     :fn graph-view-control-view-rejects-invalid-center-force})

(fn graph-view-control-view-toggles-continuous []
    (local graph-view (make-mock-graph-view))
    (local ctx (make-test-ctx))
    (local dialog ((GraphViewControlView {:graph-view graph-view}) ctx))
    (local view dialog.__control-view)
    (assert (= view.continuous? false) "Should start with continuous disabled")
    (view.toggle-button:on-click {})
    (assert view.continuous? "Clicking should enable continuous mode")
    (assert graph-view.layout.active "Layout should be active after start")
    (view.toggle-button:on-click {})
    (assert (= view.continuous? false) "Clicking again should disable continuous mode")
    (dialog:drop))

(table.insert tests {:name "GraphViewControlView toggles continuous mode"
                     :fn graph-view-control-view-toggles-continuous})

(fn graph-view-control-view-restarts-on-stabilize []
    (local graph-view (make-mock-graph-view))
    (local layout graph-view.layout)
    (local ctx (make-test-ctx))
    (local dialog ((GraphViewControlView {:graph-view graph-view}) ctx))
    (local view dialog.__control-view)
    (view.toggle-button:on-click {})
    (assert view.continuous? "Should be in continuous mode")
    (assert layout.active "Layout should be active")
    (set layout.active false)
    (layout.stabilized:emit)
    (assert layout.active "Layout should restart when stabilized in continuous mode")
    (dialog:drop))

(table.insert tests {:name "GraphViewControlView restarts layout on stabilize in continuous mode"
                     :fn graph-view-control-view-restarts-on-stabilize})

(fn graph-view-control-view-does-not-restart-when-stopped []
    (local graph-view (make-mock-graph-view))
    (local layout graph-view.layout)
    (local ctx (make-test-ctx))
    (local dialog ((GraphViewControlView {:graph-view graph-view}) ctx))
    (local view dialog.__control-view)
    (assert (= view.continuous? false) "Should not be in continuous mode")
    (set layout.active false)
    (layout.stabilized:emit)
    (assert (= layout.active false) "Layout should not restart when not in continuous mode")
    (dialog:drop))

(table.insert tests {:name "GraphViewControlView does not restart when continuous is off"
                     :fn graph-view-control-view-does-not-restart-when-stopped})

(fn graph-view-control-view-disconnects-on-drop []
    (local graph-view (make-mock-graph-view))
    (local layout graph-view.layout)
    (local ctx (make-test-ctx))
    (local dialog ((GraphViewControlView {:graph-view graph-view}) ctx))
    (local view dialog.__control-view)
    (view.toggle-button:on-click {})
    (assert view.continuous? "Should be in continuous mode")
    (local handlers-count (length view.handlers))
    (assert (> handlers-count 0) "Should have registered handlers")
    (dialog:drop)
    (set layout.active false)
    (layout.stabilized:emit)
    (assert (= layout.active false) "Layout should not restart after drop"))

(table.insert tests {:name "GraphViewControlView disconnects signals on drop"
                     :fn graph-view-control-view-disconnects-on-drop})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "graph-view-control-view"
                           :tests tests})))

{:name "graph-view-control-view"
 :tests tests
 :main main}
