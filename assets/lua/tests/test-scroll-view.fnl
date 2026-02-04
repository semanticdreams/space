(local glm (require :glm))
(local ScrollView (require :scroll-view))
(local Hoverables (require :hoverables))
(local StateBase (require :state-base))
(local BuildContext (require :build-context))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))
(local {: FocusManager} (require :focus))

(local tests [])

(local approx (. MathUtils :approx))

(fn make-context []
  (BuildContext {:hoverables (assert app.hoverables "test requires app.hoverables")}))

(fn make-focus-context [manager scope]
  (BuildContext {:hoverables (assert app.hoverables "test requires app.hoverables")
                 :focus-manager manager
                 :focus-scope scope}))

(fn make-test-child [size]
  (local state {:last-position nil
                :last-size nil})
  (fn builder [_ctx]
    (local layout
      (Layout {:name "scroll-view-child"
               :measurer (fn [self]
                           (set self.measure size))
               :layouter (fn [self]
                           (set state.last-position self.position)
                           (set state.last-size self.size))}))
    {:layout layout
     :drop (fn [_self])})
  {:builder builder :state state})

(fn make-focus-child [item-position item-size content-size]
  (local state {:focus-node nil
                :item-layout nil})
  (fn builder [ctx]
    (local item-layout
      (Layout {:name "scroll-focus-item"
               :measurer (fn [self]
                           (set self.measure item-size))
               :layouter (fn [_self])}))
    (local content-layout
      (Layout {:name "scroll-focus-content"
               :children [item-layout]
               :measurer (fn [self]
                           (set self.measure content-size))
               :layouter (fn [self]
                           (set item-layout.size item-size)
                           (set item-layout.position
                                (+ self.position (self.rotation:rotate item-position)))
                           (set item-layout.rotation self.rotation)
                           (set item-layout.depth-offset-index self.depth-offset-index)
                           (set item-layout.clip-region self.clip-region)
                           (item-layout:layouter))}))
    (set state.item-layout item-layout)
    (local focus-node (ctx.focus:create-node {:name "scroll-focus-node"}))
    (ctx.focus:attach-bounds focus-node {:layout item-layout})
    (set state.focus-node focus-node)
    {:layout content-layout
     :drop (fn [_self])})
  {:builder builder :state state})

(fn make-multi-focus-child [item-count item-size spacing]
  (local state {:focus-nodes []
                :item-layouts []})
  (fn builder [ctx]
    (local item-layouts [])
    (for [idx 1 item-count]
      (local item-layout
        (Layout {:name (.. "scroll-focus-item-" idx)
                 :measurer (fn [self]
                             (set self.measure item-size))
                 :layouter (fn [_self])}))
      (table.insert item-layouts item-layout)
      (table.insert state.item-layouts item-layout)
      (local focus-node (ctx.focus:create-node {:name (.. "scroll-focus-node-" idx)}))
      (ctx.focus:attach-bounds focus-node {:layout item-layout})
      (table.insert state.focus-nodes focus-node))
    (local content-size
      (glm.vec3 (or item-size.x 0)
                (+ (* spacing (- item-count 1)) (or item-size.y 0))
                (or item-size.z 0)))
    (local content-layout
      (Layout {:name "scroll-focus-content"
               :children item-layouts
               :measurer (fn [self]
                           (set self.measure content-size))
               :layouter (fn [self]
                           (each [idx layout (ipairs item-layouts)]
                             (set layout.size item-size)
                             (set layout.position
                                  (+ self.position
                                     (self.rotation:rotate (glm.vec3 0 (* spacing (- idx 1)) 0))))
                             (set layout.rotation self.rotation)
                             (set layout.depth-offset-index self.depth-offset-index)
                             (set layout.clip-region self.clip-region)
                             (layout:layouter)))}))
    {:layout content-layout
     :drop (fn [_self])})
  {:builder builder :state state})

(fn scroll-view-default-padding-insets-content []
  (local child (make-test-child (glm.vec3 4 2 0)))
  (local view ((ScrollView {:child child.builder}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 5 6 0))
  (set view.layout.position (glm.vec3 0 0 0))
  (view.layout:layouter)
  (local padding 0.15)
  (assert (approx child.state.last-position.x padding))
  (assert (approx child.state.last-position.y padding))
  (local expected-x (- (math.max (+ 4 (* 2 padding)) view.scroll.layout.size.x) (* 2 padding)))
  (local expected-y (- (math.max (+ 2 (* 2 padding)) view.scroll.layout.size.y) (* 2 padding)))
  (assert (approx child.state.last-size.x expected-x))
  (assert (approx child.state.last-size.y expected-y))
  (view:drop))

(fn scroll-view-clamps-scroll-offset []
  (local child (make-test-child (glm.vec3 4 10 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 5 4 0))
  (set view.layout.position (glm.vec3 0 0 0))
  (view.layout:layouter)
  (assert (> view.state.max-offset 5.9))
  (view:set-scroll-offset 3)
  (view.layout:layouter)
  (assert (approx view.state.scroll-offset 3))
  (assert (approx child.state.last-position.y (- view.layout.position.y 3)))
  (view:set-scroll-offset 100)
  (view.layout:layouter)
  (assert (approx view.state.scroll-offset view.state.max-offset))
  (view:drop))

(fn scroll-view-disables-scrollbar-when-content-fits []
  (local child (make-test-child (glm.vec3 4 2 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 5 6 0))
  (view.layout:layouter)
  (assert (= view.state.max-offset 0))
  (assert (not view.state.scroll-enabled?))
  (assert (not view.scrollbar.state.enabled?))
  (view:drop))

(fn scroll-view-updates-scrollbar-value []
  (local child (make-test-child (glm.vec3 3 12 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 4 4 0))
  (view.layout:layouter)
  (view:set-scroll-offset 4)
  (view.layout:layouter)
  (assert (approx view.scrollbar.state.value 0.5))
  (view:drop))

(fn scroll-view-mouse-wheel-scrolls-when-hovered []
  (local original-hoverables app.hoverables)
  (local original-first-person app.first-person-controls)
  (var hoverables nil)
  (var view nil)
  (var first-person-called false)
  (local (ok err)
    (pcall
      (fn []
        (set hoverables (Hoverables))
        (set app.hoverables hoverables)
        (set app.first-person-controls
             {:on-mouse-wheel (fn [_ _]
                                (set first-person-called true))})
        (local child (make-test-child (glm.vec3 3 10 0)))
        (local ctx (make-context))
        (set view ((ScrollView {:child child.builder
                                :padding false}) ctx))
        (view.layout:measurer)
        (set view.layout.size (glm.vec3 4 4 0))
        (view.layout:layouter)
        (view:set-scroll-offset 0)
        (view.layout:layouter)
        (set app.hoverables.active-entry {:object view})
        (StateBase.dispatch-mouse-wheel {:x 0 :y 1})
        (view.layout:layouter)
        (assert (approx view.state.scroll-offset 1.0))
        (assert (not first-person-called)))))
  (when view
    (view:drop))
  (when hoverables
    (hoverables:drop))
  (set app.hoverables original-hoverables)
  (set app.first-person-controls original-first-person)
  (when (not ok)
    (error err)))

(fn scroll-view-wheel-clamps-top []
  (local child (make-test-child (glm.vec3 3 10 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 4 4 0))
  (view.layout:layouter)
  (view:set-scroll-offset 1)
  (view.layout:layouter)
  (view:on-mouse-wheel {:x 0 :y -10})
  (view.layout:layouter)
  (assert (approx view.state.scroll-offset 0))
  (view:drop))

(fn scroll-view-defaults-to-max-offset-before-layout []
  (local child (make-test-child (glm.vec3 3 12 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 4 4 0))
  (view.layout:layouter)
  (assert (approx view.state.scroll-offset view.state.max-offset))
  (local child-layout (. view.scroll.layout.children 1))
  (assert child-layout)
  (assert (approx child-layout.position.y (- view.state.scroll-offset)))
  (view:drop))

(fn scroll-view-scrollbar-policy-as-needed []
  (local child (make-test-child (glm.vec3 4 2 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false
                            :scrollbar-policy :as-needed
                            :scrollbar-width 1.0}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 6 6 0))
  (view.layout:layouter)
  (assert (not view.scrollbar.state.visible?))
  (assert (approx view.scroll.layout.size.x view.layout.size.x))
  (view:drop))

(fn scroll-view-scrollbar-policy-as-needed-shows-when-needed []
  (local child (make-test-child (glm.vec3 4 10 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false
                            :scrollbar-policy :as-needed
                            :scrollbar-width 1.0}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 6 4 0))
  (view.layout:layouter)
  (assert view.scrollbar.state.visible?)
  (assert (approx view.scroll.layout.size.x (- view.layout.size.x 1.0)))
  (view:drop))

(fn scroll-view-scrollbar-policy-always-off []
  (local child (make-test-child (glm.vec3 4 10 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false
                            :scrollbar-policy :always-off
                            :scrollbar-width 1.0}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 6 4 0))
  (view.layout:layouter)
  (assert (not view.scrollbar.state.visible?))
  (assert (approx view.scroll.layout.size.x view.layout.size.x))
  (view:drop))

(fn scroll-view-scrollbar-policy-always-on []
  (local child (make-test-child (glm.vec3 4 2 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false
                            :scrollbar-policy :always-on
                            :scrollbar-width 1.0}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 6 6 0))
  (view.layout:layouter)
  (assert view.scrollbar.state.visible?)
  (assert (approx view.scroll.layout.size.x (- view.layout.size.x 1.0)))
  (view:drop))

(fn scroll-view-scrolls-focused-item-into-view []
  (local manager (FocusManager {:root-name "root"}))
  (local root (manager:get-root-scope))
  (local scope (manager:create-scope {:name "scope"}))
  (manager:attach scope root)
  (local ctx (make-focus-context manager scope))
  (local child
    (make-focus-child (glm.vec3 0 12 0)
                      (glm.vec3 4 2 0)
                      (glm.vec3 4 20 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false}) ctx))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 4 5 0))
  (set view.layout.position (glm.vec3 0 0 0))
  (view.layout:layouter)
  (manager:focus-next {})
  (assert (approx view.state.scroll-offset 12))
  (view.layout:layouter)
  (view:drop)
  (manager:drop))

(fn scroll-view-directional-focus-scrolls-multiple-items []
  (local manager (FocusManager {:root-name "root"}))
  (local root (manager:get-root-scope))
  (local scope (manager:create-scope {:name "scope"}))
  (manager:attach scope root)
  (local ctx (make-focus-context manager scope))
  (local child (make-multi-focus-child 3 (glm.vec3 4 2 0) 3))
  (local view ((ScrollView {:child child.builder
                            :padding false}) ctx))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 4 3 0))
  (set view.layout.position (glm.vec3 0 0 0))
  (view.layout:layouter)
  (local nodes child.state.focus-nodes)
  (local first-node (. nodes 1))
  (first-node:request-focus)
  (manager:focus-direction {:direction (glm.vec3 0 1 0)
                            :frustum-angle (/ math.pi 2)})
  (view.layout:layouter)
  (assert (= (manager:get-focused-node) (. nodes 2)))
  (local item-layouts child.state.item-layouts)
  (local third-layout (. item-layouts 3))
  (set third-layout.clip-visibility :outside)
  (when third-layout.set-self-culled
    (third-layout:set-self-culled true))
  (assert (third-layout:effective-culled?))
  (local first-offset view.state.scroll-offset)
  (manager:focus-direction {:direction (glm.vec3 0 1 0)
                            :frustum-angle (/ math.pi 2)})
  (view.layout:layouter)
  (assert (= (manager:get-focused-node) (. nodes 3)))
  (assert (> view.state.scroll-offset first-offset))
  (view:drop)
  (manager:drop))


(table.insert tests {:name "ScrollView defaults to padding" :fn scroll-view-default-padding-insets-content})
(table.insert tests {:name "ScrollView clamps scroll offset" :fn scroll-view-clamps-scroll-offset})
(table.insert tests {:name "ScrollView disables scrollbar when content fits" :fn scroll-view-disables-scrollbar-when-content-fits})
(table.insert tests {:name "ScrollView updates scrollbar value" :fn scroll-view-updates-scrollbar-value})
(table.insert tests {:name "ScrollView mouse wheel scrolls when hovered" :fn scroll-view-mouse-wheel-scrolls-when-hovered})
(table.insert tests {:name "ScrollView wheel clamps at top" :fn scroll-view-wheel-clamps-top})
(table.insert tests {:name "ScrollView defaults to max offset before layout"
                     :fn scroll-view-defaults-to-max-offset-before-layout})
(table.insert tests {:name "ScrollView scrollbar policy as-needed" :fn scroll-view-scrollbar-policy-as-needed})
(table.insert tests {:name "ScrollView scrollbar policy as-needed shows when needed"
                     :fn scroll-view-scrollbar-policy-as-needed-shows-when-needed})
(table.insert tests {:name "ScrollView scrollbar policy always-off" :fn scroll-view-scrollbar-policy-always-off})
(table.insert tests {:name "ScrollView scrollbar policy always-on" :fn scroll-view-scrollbar-policy-always-on})
(table.insert tests {:name "ScrollView scrolls focused item into view"
                     :fn scroll-view-scrolls-focused-item-into-view})
(table.insert tests {:name "ScrollView directional focus scrolls multiple items"
                     :fn scroll-view-directional-focus-scrolls-multiple-items})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "scroll-view"
                       :tests tests})))

{:name "scroll-view"
 :tests tests
 :main main}
