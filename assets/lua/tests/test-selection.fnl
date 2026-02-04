(local glm (require :glm))
(local _ (require :main))
(local ObjectSelector (require :object-selector))
(local BoxSelector (require :box-selector))
(local BuildContext (require :build-context))
(local Graph (require :graph/init))
(local GraphView (require :graph/view))
(local StateBase (require :state-base))
(local Camera (require :camera))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local {:FocusManager FocusManager} (require :focus))
(local fs (require :fs))

(local tests [])
(local appdirs (require :appdirs))
(local MathUtils (require :math-utils))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "selection-data-tmp"))

(fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "selection-" (os.time) "-" temp-counter)))

(fn with-temp-data-dir [f]
    (local dir (make-temp-dir))
    (when (fs.exists dir)
        (fs.remove-all dir))
    (fs.create-dirs dir)
    (assert appdirs "appdirs module must be available")
    (local original appdirs.user-data-dir)
    (set appdirs.user-data-dir (fn [_appname] dir))
    (local (ok result) (pcall f dir))
    (set appdirs.user-data-dir original)
    (fs.remove-all dir)
    (if ok
        result
        (error result)))

(fn make-ui-context []
    (local focus-manager (FocusManager {:root-name "test-selection"}))
    (local focus-scope (focus-manager:create-scope {:name "test-selection-context"}))
    (local theme {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)}
                  :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}})
    (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                   :hoverables (assert app.hoverables "test requires app.hoverables")
                   :theme theme
                   :focus-manager focus-manager
                   :focus-scope focus-scope}))

(fn object-selector-selects-by-projecting []
    (local selector
      (ObjectSelector {:project (fn [position _opts] position)
                       :enabled? true}))
    (local inside {:position (glm.vec3 5 5 0)})
    (local outside {:position (glm.vec3 20 5 0)})
    (selector:set-selectables [inside outside])
    (selector.box.changed:emit {:p1 {:x 0 :y 0}
                                :p2 {:x 10 :y 10}})
    (assert (= (length selector.selected) 1)
            "Expected one object to be selected")
    (assert (= (. selector.selected 1) inside)
            "Expected inside point to be selected")
    (selector:drop))

(fn selection-input-prefers-selection-only-for-primary-button []
    (local state (StateBase.make-state {:name :selection-test}))
    (local original-selector app.object-selector)
    (local original-first-person app.first-person-controls)
    (local original-clickables app.clickables)
    (local original-movables app.movables)
    (local created-clickables (Clickables))
    (local selector-state {:buttons 0 :motions 0 :active false})
    (local selector
      {:enabled? (fn [_self] true)
       :active? (fn [_self] selector-state.active)
       :on-mouse-button (fn [_self payload]
                          (when (= payload.button 1)
                            (set selector-state.buttons (+ selector-state.buttons 1))
                            (set selector-state.active (= payload.state 1))))
       :on-mouse-motion (fn [_self _payload]
                          (when selector-state.active
                              (set selector-state.motions (+ selector-state.motions 1))))})
    (local fp-state {:buttons 0 :motions 0 :updates 0 :dragging false})
    (local fp {})
    (set (. fp "on-mouse-button-down")
         (fn [_self _payload]
           (set fp-state.buttons (+ fp-state.buttons 1))
           (set fp-state.dragging true)))
    (set (. fp "on-mouse-button-up")
         (fn [_self _payload]
           (set fp-state.buttons (+ fp-state.buttons 1))
           (set fp-state.dragging false)))
    (set (. fp "on-mouse-motion")
         (fn [_self _payload]
           (when fp-state.dragging
             (set fp-state.motions (+ fp-state.motions 1)))))
    (set (. fp "drag-active?")
         (fn [_self] fp-state.dragging))
    (set (. fp "update")
         (fn [_self _delta]
           (set fp-state.updates (+ fp-state.updates 1))))
    (set app.object-selector selector)
    (set app.first-person-controls fp)
    (set app.clickables created-clickables)
    (set app.movables nil)
    (local down state.on-mouse-button-down)
    (local move state.on-mouse-motion)
    (local up state.on-mouse-button-up)
    (local update state.on-updated)
    (assert down "State missing mouse-button-down handler")
    (assert move "State missing mouse-motion handler")
    (assert up "State missing mouse-button-up handler")
    (assert update "State missing update handler")
    (down {:button 1 :state 1 :x 0 :y 0})
    (move {:x 10 :y 10})
    (up {:button 1 :state 0 :x 10 :y 10})
    (down {:button 3 :state 1 :x 20 :y 20})
    (move {:x 25 :y 25})
    (up {:button 3 :state 0 :x 25 :y 25})
    (update 0.016)
    (set app.object-selector original-selector)
    (set app.first-person-controls original-first-person)
    (set app.clickables original-clickables)
    (set app.movables original-movables)
    (created-clickables:drop)
    (assert (= selector-state.buttons 2) "Selection should receive down and up events on the primary button")
    (assert (>= selector-state.motions 1) "Selection should receive drag motion")
    (assert (= fp-state.buttons 2) "First-person controls should still receive non-conflicting mouse buttons")
    (assert (= fp-state.motions 1) "First-person controls should receive drag motion for non-selection buttons")
    (assert (= fp-state.updates 1) "First-person controls should continue updating while selection is enabled"))

(fn box-selector-renders-in-hud-space []
    (local depth 0.5)
    (local hud {:world-units-per-pixel 1
                :half-width 5
                :half-height 5})
    (local viewport {:x 0 :y 0 :width 10 :height 10})
    (local camera {:position (glm.vec3 1 2 3)
                   :rotation (glm.quat (/ math.pi 2) (glm.vec3 0 1 0))})
    (var captured-rectangle nil)
    (local rectangle-builder
      (fn [_ctx]
        (set captured-rectangle {:position (glm.vec3 0 0 0)
                                 :size (glm.vec2 0 0)
                                 :rotation (glm.quat 1 0 0 0)
                                 :visible? true
                                 :set-visible (fn [self visible?]
                                                (set self.visible? (not (not visible?))))
                                 :update (fn [_self] nil)
                                 :drop (fn [_self] nil)})
        captured-rectangle))
    (local unproject
      (fn [point _depth _opts]
        (+ camera.position
           (camera.rotation:rotate (glm.vec3 point.x point.y depth)))))
    (local selector
      (BoxSelector {:ctx (make-ui-context)
                    :camera camera
                    :unproject unproject
                    :hud hud
                    :viewport viewport
                    :rectangle-builder rectangle-builder}))
    (assert (= (type selector) :table) "BoxSelector should return a selector table")
    (selector:on-mouse-button {:button 1 :state 1 :x 0 :y 0})
    (selector:on-mouse-motion {:x 2 :y 1})
    (assert captured-rectangle "Selection rectangle should be created")
    (local epsilon 0.0001)
(local approx (. MathUtils :approx))
    (assert (approx captured-rectangle.rotation.w 1.0)
            "Selection rectangle should not inherit camera rotation")
    (assert (approx captured-rectangle.rotation.x 0.0)
            "Selection rectangle rotation x should be zero")
    (assert (approx captured-rectangle.rotation.y 0.0)
            "Selection rectangle rotation y should be zero")
    (assert (approx captured-rectangle.rotation.z 0.0)
            "Selection rectangle rotation z should be zero")
    (assert (and (approx captured-rectangle.position.x -5)
                 (approx captured-rectangle.position.y 4))
            "Selection rectangle should be placed in HUD coordinates derived from screen pixels")
    (assert (= captured-rectangle.size.x 2)
            "Selection rectangle width should match screen delta")
    (assert (= captured-rectangle.size.y 1)
            "Selection rectangle height should match screen delta")
    (selector:drop))

(fn selection-box-uses-high-depth-offset []
    (var captured-rectangle nil)
    (local rectangle-builder
      (fn [_ctx]
        (set captured-rectangle {:position (glm.vec3 0 0 0)
                                 :size (glm.vec2 0 0)
                                 :rotation (glm.quat 1 0 0 0)
                                 :depth-offset-index 0
                                 :visible? true
                                 :set-visible (fn [self visible?]
                                                (set self.visible? (not (not visible?))))
                                 :update (fn [_self] nil)
                                 :drop (fn [_self] nil)})
        captured-rectangle))
    (local selector
      (BoxSelector {:ctx (make-ui-context)
                    :unproject (fn [point _depth _opts] (glm.vec3 point.x point.y 0))
                    :rectangle-builder rectangle-builder}))
    (assert (= (type selector) :table) "BoxSelector should return a selector table")
    (selector:on-mouse-button {:button 1 :state 1 :x 0 :y 0})
    (selector:on-mouse-motion {:x 1 :y 1})
    (assert captured-rectangle "Selection rectangle should be created")
    (assert (>= captured-rectangle.depth-offset-index 1000)
            "Selection rectangle should render above HUD via depth offset")
    (selector:drop))

(fn selection-can-span-scene-and-hud []
    (local selector
      (ObjectSelector {:project (fn [position _opts] position)
                       :enabled? true}))
    (local scene-object {:position (glm.vec3 2 2 0)})
    (local hud-object {:layout {:position (glm.vec3 2 2 0)}})
    (selector:set-selectables [scene-object hud-object])
    (selector.box.changed:emit {:p1 {:x 0 :y 0}
                                :p2 {:x 3 :y 3}})
    (assert (= (length selector.selected) 2)
            "Selection should include both scene and HUD objects")
    (assert (= (. selector.selected 1) scene-object)
            "Scene object should be selected first")
    (assert (= (. selector.selected 2) hud-object)
            "HUD object should also be selected")
    (selector:drop))

(fn graph-selects-start-node-inside-box []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ui-context))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph
                                    :ctx ctx
                                    :selector selector}))
            (local start (Graph.StartNode))
            (graph:add-node start {:position (glm.vec3 1 1 0)})
            (selector.box.changed:emit {:p1 {:x 0 :y 0}
                                        :p2 {:x 2 :y 2}})
            (assert (= (length view.selected-nodes) 1)
                    "GraphView should select start node inside selection box")
            (assert (= (. view.selected-nodes 1) start)
                    "GraphView selection should contain the start node")
            (view:drop)
            (graph:drop)
            (selector:drop))))

(fn graph-ignores-start-node-outside-box []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ui-context))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph
                                    :ctx ctx
                                    :selector selector}))
            (local start (Graph.StartNode))
            (graph:add-node start {:position (glm.vec3 5 5 0)})
            (selector.box.changed:emit {:p1 {:x 0 :y 0}
                                        :p2 {:x 2 :y 2}})
            (assert (= (length view.selected-nodes) 0)
                    "GraphView should not select start node when outside selection box")
            (view:drop)
            (graph:drop)
            (selector:drop))))

(fn graph-registers-selectables-with-selector []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ui-context))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph
                                    :ctx ctx
                                    :selector selector}))
            (local node (Graph.GraphNode {:key "n" :label "n"}))
            (graph:add-node node {:position (glm.vec3 5 5 0)})
            (assert (= (length selector.selectables) 1)
                    "GraphView should register points as selectables")
            (selector.box.changed:emit {:p1 {:x 0 :y 0}
                                        :p2 {:x 10 :y 10}})
            (assert (= (length view.selected-nodes) 1)
                    "GraphView should mirror selector changes")
            (view:drop)
            (graph:drop)
            (selector:drop))))

(fn graph-selects-with-default-projection []
    (local original-viewport app.viewport)
    (local original-camera app.camera)
    (local original-projection app.projection)
    (set app.viewport {:x 0 :y 0 :width 1600 :height 900})
    (set app.camera (Camera {:position (glm.vec3 0 0 30)}))
    (set app.projection (app.create-default-projection))
    (local selector (ObjectSelector {:enabled? true}))
    (local selectable {:position (glm.vec3 -4.528 -9.146 0)})
    (selector:set-selectables [selectable])
    (selector.box.changed:emit {:p1 {:x -5000 :y -5000}
                                :p2 {:x 5000 :y 5000}})
    (assert (= (length selector.selected) 1)
            "Selector should select nodes with default projection")
    (selector:drop)
    (set app.viewport original-viewport)
    (set app.camera original-camera)
    (set app.projection original-projection))

(table.insert tests {:name "ObjectSelector projects to screen bounds" :fn object-selector-selects-by-projecting})
(table.insert tests {:name "Selection only blocks conflicting first-person input" :fn selection-input-prefers-selection-only-for-primary-button})
(table.insert tests {:name "Selection box renders in HUD space" :fn box-selector-renders-in-hud-space})
(table.insert tests {:name "Selection box renders above HUD" :fn selection-box-uses-high-depth-offset})
(table.insert tests {:name "Selection can span scene and HUD objects" :fn selection-can-span-scene-and-hud})
(table.insert tests {:name "GraphView selects start node when inside selection box" :fn graph-selects-start-node-inside-box})
(table.insert tests {:name "GraphView ignores start node outside selection box" :fn graph-ignores-start-node-outside-box})
(table.insert tests {:name "GraphView registers selectables with selector" :fn graph-registers-selectables-with-selector})
(table.insert tests {:name "GraphView selects nodes using default projection" :fn graph-selects-with-default-projection})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "selection"
                       :tests tests})))

{:name "selection"
 :tests tests
 :main main}
