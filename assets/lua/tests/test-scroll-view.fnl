(local glm (require :glm))
(local ScrollView (require :scroll-view))
(local Hoverables (require :hoverables))
(local Intersectables (require :intersectables))
(local TouchGestureTargets (require :touch-gesture-targets))
(local TouchRouter (require :touch-router))
(local Runtime (require :state-runtime))
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

(fn with-inverted-screen-y-ray [body]
  (local original app.screen-pos-ray)
  (set app.screen-pos-ray
       (fn [pointer]
         {:origin (glm.vec3 (or pointer.x 0) (- (or pointer.y 0)) 1)
          :direction (glm.vec3 0 0 -1)}))
  (local (ok result) (pcall body))
  (set app.screen-pos-ray original)
  (when (not ok)
    (error result))
  result)

(fn with-direct-screen-y-ray [body]
  (local original app.screen-pos-ray)
  (set app.screen-pos-ray
       (fn [pointer]
         {:origin (glm.vec3 (or pointer.x 0) (or pointer.y 0) 1)
          :direction (glm.vec3 0 0 -1)}))
  (local (ok result) (pcall body))
  (set app.screen-pos-ray original)
  (when (not ok)
    (error result))
  result)

(fn with-touch-gesture-targets [targets body]
  (local original app.touch-gesture-targets)
  (set app.touch-gesture-targets targets)
  (local (ok result) (pcall body))
  (set app.touch-gesture-targets original)
  (when (not ok)
    (error result))
  result)

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

(fn make-width-sensitive-child []
  (local state {:last-constraint-width nil})
  (fn builder [_ctx]
    (local layout
      (Layout {:name "width-sensitive-scroll-child"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 8 2 0)))
               :constrained-measurer
               (fn [self constraints]
                 (local max-width (and constraints constraints.max constraints.max.x))
                 (set state.last-constraint-width max-width)
                 (if (and max-width (<= max-width 4))
                     (set self.measure (glm.vec3 max-width 10 0))
                     (set self.measure (glm.vec3 8 2 0))))
               :layouter (fn [_self])}))
    {:layout layout
     :drop (fn [_self])})
  {:builder builder :state state})

(fn make-scrollbar-sensitive-child []
  (local state {:constraint-widths []})
  (fn builder [_ctx]
    (local layout
      (Layout {:name "scrollbar-sensitive-scroll-child"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 4 8 0)))
               :constrained-measurer
               (fn [self constraints]
                 (local max-width (and constraints constraints.max constraints.max.x))
                 (table.insert state.constraint-widths max-width)
                 (set self.measure
                      (glm.vec3 (or max-width 0)
                                (if (and max-width (<= max-width 3)) 12 8)
                                0)))
               :layouter (fn [_self])}))
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
        (Runtime.dispatch-mouse-wheel {:x 0 :y 1})
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

(fn scroll-view-continuous-wheel-keeps-moving []
  (local child (make-test-child (glm.vec3 3 20 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 4 4 0))
  (view.layout:layouter)
  (view:set-scroll-offset 2)
  (view.layout:layouter)
  (assert (view:on-mouse-wheel {:x 0
                                :y 0.5
                                :integer-y 0
                                :direction 0
                                :timestamp 100}))
  (local after-wheel view.state.scroll-offset)
  (assert view.state.kinetic)
  (app.engine.events.updated:emit 16)
  (assert (> view.state.scroll-offset after-wheel)
          "Continuous wheel input should continue briefly after release")
  (view:drop))

(fn scroll-view-discrete-wheel-does-not-start-kinetic []
  (local child (make-test-child (glm.vec3 3 20 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 4 4 0))
  (view.layout:layouter)
  (assert (view:on-mouse-wheel {:x 0
                                :y 1
                                :integer-y 1
                                :direction 0
                                :timestamp 100}))
  (assert (= view.state.kinetic nil)
          "Discrete mouse wheels should remain stepped, not kinetic")
  (view:drop))

(fn scroll-view-flipped-discrete-wheel-does-not-start-kinetic []
  (local child (make-test-child (glm.vec3 3 20 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 4 4 0))
  (view.layout:layouter)
  (view:set-scroll-offset 2)
  (assert (view:on-mouse-wheel {:x 0
                                :y -1
                                :integer-y -1
                                :direction 1
                                :timestamp 100}))
  (assert (= view.state.kinetic nil)
          "Natural/flipped discrete wheels should not be treated as continuous input")
  (view:drop))

(fn scroll-view-continuous-wheel-idle-gap-uses-fresh-velocity []
  (local child (make-test-child (glm.vec3 3 40 0)))
  (local view ((ScrollView {:child child.builder
                            :padding false}) (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 4 4 0))
  (view.layout:layouter)
  (view:set-scroll-offset 2)
  (assert (view:on-mouse-wheel {:x 0
                                :y 0.5
                                :integer-y 0
                                :direction 0
                                :timestamp 100}))
  (local first-velocity (and view.state.kinetic view.state.kinetic.velocity))
  (assert first-velocity)
  (while view.state.kinetic
    (app.engine.events.updated:emit 64))
  (assert (view:on-mouse-wheel {:x 0
                                :y 0.5
                                :integer-y 0
                                :direction 0
                                :timestamp 2000}))
  (assert view.state.kinetic
          "Continuous wheel after an idle gap should still get kinetic velocity")
  (assert (approx view.state.kinetic.velocity first-velocity)
          "Idle gap should not dilute the next continuous wheel event velocity")
  (view:drop))

(fn scroll-view-touch-drag-scrolls-content []
  (with-inverted-screen-y-ray
    (fn []
      (local child (make-test-child (glm.vec3 3 10 0)))
      (local view ((ScrollView {:child child.builder
                                :padding false}) (make-context)))
      (view.layout:measurer)
      (set view.layout.size (glm.vec3 4 4 0))
      (view.layout:layouter)
      (view:set-scroll-offset 4)
      (view.layout:layouter)
      (local initial-content-y (+ -10 view.state.scroll-offset))
      (assert (view:on-touch-drag-start {:touch-id 1
                                         :finger-id 2
                                         :x 1
                                         :y 10
                                         :timestamp 100}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 2
                                   :x 1
                                   :y 12
                                   :timestamp 116}))
      (view.layout:layouter)
      (assert (approx view.state.scroll-offset 6))
      (assert (approx (+ -12 view.state.scroll-offset) initial-content-y))
      (assert (view:on-touch-drag-end {:touch-id 1
                                       :finger-id 2
                                       :x 1
                                       :y 12
                                       :timestamp 116}))
      (view:drop))))

(fn scroll-view-touch-router-captures-with-scroll-threshold []
  (with-direct-screen-y-ray
    (fn []
      (local intersector (Intersectables))
      (local touch-targets (TouchGestureTargets {:intersectables intersector}))
      (with-touch-gesture-targets
        touch-targets
        (fn []
          (local child (make-test-child (glm.vec3 3 10 0)))
          (local ctx (BuildContext {:hoverables (assert app.hoverables "test requires app.hoverables")
                                    :touch-gesture-targets touch-targets}))
          (local view ((ScrollView {:child child.builder
                                    :padding false})
                       ctx))
          (local router (TouchRouter {:drag-threshold 20}))
          (local down {:x 1 :y 1 :timestamp 100 :pressure 1.0})
          (local move-under-threshold {:x 1 :y 3 :timestamp 116 :pressure 1.0})
          (local move-at-scroll-threshold {:x 1 :y 4 :timestamp 132 :pressure 1.0})
          (local up {:x 1 :y 4 :timestamp 140 :pressure 1.0})
          (tset down "touch-id" 1)
          (tset down "finger-id" 2)
          (tset move-under-threshold "touch-id" 1)
          (tset move-under-threshold "finger-id" 2)
          (tset move-at-scroll-threshold "touch-id" 1)
          (tset move-at-scroll-threshold "finger-id" 2)
          (tset up "touch-id" 1)
          (tset up "finger-id" 2)
          (view.layout:measurer)
          (set view.layout.size (glm.vec3 4 4 0))
          (view.layout:layouter)
          (view:set-scroll-offset 4)
          (view.layout:layouter)
          (assert (router:on-touch-down {} down))
          (assert (not (router:on-touch-motion {} move-under-threshold)))
          (assert (router:on-touch-motion {} move-at-scroll-threshold))
          (view.layout:layouter)
          (assert (approx view.state.scroll-offset 1))
          (assert (router:on-touch-up {} up))
          (view:drop))))))

(fn scroll-view-touch-release-keeps-moving-and-slows []
  (with-inverted-screen-y-ray
    (fn []
      (local child (make-test-child (glm.vec3 3 100 0)))
      (local view ((ScrollView {:child child.builder
                                :padding false}) (make-context)))
      (view.layout:measurer)
      (set view.layout.size (glm.vec3 4 4 0))
      (view.layout:layouter)
      (view:set-scroll-offset 20)
      (view.layout:layouter)
      (assert (view:on-touch-drag-start {:touch-id 1
                                         :finger-id 2
                                         :x 1
                                         :y 10
                                         :timestamp 100}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 2
                                   :x 1
                                   :y 12
                                   :timestamp 116}))
      (assert (view:on-touch-drag-end {:touch-id 1
                                       :finger-id 2
                                       :x 1
                                       :y 12
                                       :timestamp 116}))
      (local release-offset view.state.scroll-offset)
      (local release-velocity view.state.kinetic.velocity)
      (app.engine.events.updated:emit 16)
      (assert (> view.state.scroll-offset release-offset)
              "Kinetic touch scrolling should continue after a moving release")
      (assert (< view.state.kinetic.velocity release-velocity)
              "Kinetic touch scrolling should decay velocity after each frame")
      (view:drop))))

(fn scroll-view-touch-release-after-stop-stays-put []
  (with-inverted-screen-y-ray
    (fn []
      (local child (make-test-child (glm.vec3 3 100 0)))
      (local view ((ScrollView {:child child.builder
                                :padding false}) (make-context)))
      (view.layout:measurer)
      (set view.layout.size (glm.vec3 4 4 0))
      (view.layout:layouter)
      (view:set-scroll-offset 20)
      (view.layout:layouter)
      (assert (view:on-touch-drag-start {:touch-id 1
                                         :finger-id 2
                                         :x 1
                                         :y 10
                                         :timestamp 100}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 2
                                   :x 1
                                   :y 12
                                   :timestamp 116}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 2
                                   :x 1
                                   :y 12
                                   :timestamp 216}))
      (assert (view:on-touch-drag-end {:touch-id 1
                                       :finger-id 2
                                       :x 1
                                       :y 12
                                       :timestamp 216}))
      (assert (= view.state.kinetic nil)
              "Touch release after stopping should not start kinetic scrolling")
      (local release-offset view.state.scroll-offset)
      (app.engine.events.updated:emit 16)
      (assert (approx view.state.scroll-offset release-offset))
      (view:drop))))

(fn scroll-view-touch-release-jitter-after-stop-is-ignored []
  (with-inverted-screen-y-ray
    (fn []
      (local child (make-test-child (glm.vec3 3 100 0)))
      (local view ((ScrollView {:child child.builder
                                :padding false}) (make-context)))
      (view.layout:measurer)
      (set view.layout.size (glm.vec3 4 4 0))
      (view.layout:layouter)
      (view:set-scroll-offset 20)
      (view.layout:layouter)
      (assert (view:on-touch-drag-start {:touch-id 1
                                         :finger-id 2
                                         :x 1
                                         :y 10
                                         :timestamp 100}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 2
                                   :x 1
                                   :y 12
                                   :timestamp 116}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 2
                                   :x 1
                                   :y 12
                                   :timestamp 216}))
      (local stopped-offset view.state.scroll-offset)
      (assert (view:on-touch-drag-end {:touch-id 1
                                       :finger-id 2
                                       :x 1
                                       :y 13
                                       :timestamp 220}))
      (assert (= view.state.kinetic nil)
              "Touch-up jitter after stopping should not start kinetic scrolling")
      (assert (approx view.state.scroll-offset stopped-offset)
              "Touch-up jitter should not move the scroll offset")
      (view:drop))))

(fn scroll-view-kinetic-stops-without-tail-impulse []
  (with-inverted-screen-y-ray
    (fn []
      (local child (make-test-child (glm.vec3 3 100 0)))
      (local view ((ScrollView {:child child.builder
                                :padding false}) (make-context)))
      (view.layout:measurer)
      (set view.layout.size (glm.vec3 4 4 0))
      (view.layout:layouter)
      (view:set-scroll-offset 20)
      (assert (view:on-touch-drag-start {:touch-id 1
                                         :finger-id 2
                                         :x 1
                                         :y 10
                                         :timestamp 100}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 2
                                   :x 1
                                   :y 12
                                   :timestamp 116}))
      (assert (view:on-touch-drag-end {:touch-id 1
                                       :finger-id 2
                                       :x 1
                                       :y 12
                                       :timestamp 116}))
      (while view.state.kinetic
        (app.engine.events.updated:emit 64))
      (local stopped-offset view.state.scroll-offset)
      (app.engine.events.updated:emit 500)
      (app.engine.events.updated:emit 16)
      (assert (approx view.state.scroll-offset stopped-offset)
              "Stopped kinetic scroll should not move again on later frames")
      (view:drop))))

(fn scroll-view-touch-candidate-carries-kinetic-into-next-swipe []
  (with-inverted-screen-y-ray
    (fn []
      (local child (make-test-child (glm.vec3 3 100 0)))
      (local view ((ScrollView {:child child.builder
                                :padding false}) (make-context)))
      (view.layout:measurer)
      (set view.layout.size (glm.vec3 4 4 0))
      (view.layout:layouter)
      (view:set-scroll-offset 20)
      (assert (view:on-touch-drag-start {:touch-id 1
                                         :finger-id 2
                                         :x 1
                                         :y 10
                                         :timestamp 100}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 2
                                   :x 1
                                   :y 12
                                   :timestamp 116}))
      (assert (view:on-touch-drag-end {:touch-id 1
                                       :finger-id 2
                                       :x 1
                                       :y 12
                                       :timestamp 116}))
      (assert view.state.kinetic)
      (local first-velocity view.state.kinetic.velocity)
      (assert (view:on-touch-drag-candidate-start {:touch-id 1
                                                   :finger-id 3
                                                   :x 1
                                                   :y 12
                                                   :timestamp 140}))
      (assert (= view.state.kinetic nil)
              "Touching a kinetic scroll view should catch the moving content")
      (assert view.state.pending-kinetic)
      (assert (view:on-touch-drag-start {:touch-id 1
                                         :finger-id 3
                                         :x 1
                                         :y 12
                                         :start-x 1
                                         :start-y 12
                                         :timestamp 140}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 3
                                   :x 1
                                   :y 14
                                   :timestamp 156}))
      (assert (view:on-touch-drag-end {:touch-id 1
                                       :finger-id 3
                                       :x 1
                                       :y 14
                                       :timestamp 156}))
      (assert view.state.kinetic)
      (assert (> view.state.kinetic.velocity first-velocity)
              "Repeating a same-direction swipe should carry existing kinetic velocity")
      (view:drop))))

(fn scroll-view-kinetic-long-frame-does-not-catch-up []
  (with-inverted-screen-y-ray
    (fn []
      (local child (make-test-child (glm.vec3 3 100 0)))
      (local view ((ScrollView {:child child.builder
                                :padding false}) (make-context)))
      (view.layout:measurer)
      (set view.layout.size (glm.vec3 4 4 0))
      (view.layout:layouter)
      (view:set-scroll-offset 20)
      (assert (view:on-touch-drag-start {:touch-id 1
                                         :finger-id 2
                                         :x 1
                                         :y 10
                                         :timestamp 100}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 2
                                   :x 1
                                   :y 12
                                   :timestamp 116}))
      (assert (view:on-touch-drag-end {:touch-id 1
                                       :finger-id 2
                                       :x 1
                                       :y 12
                                       :timestamp 116}))
      (local release-offset view.state.scroll-offset)
      (app.engine.events.updated:emit 500)
      (assert (< (- view.state.scroll-offset release-offset) 10)
              "Long frames should not move by the full elapsed kinetic distance")
      (assert (< view.state.kinetic.velocity 0.01)
              "Long frames should still age kinetic velocity by elapsed time")
      (view:drop))))

(fn scroll-view-pending-kinetic-carries-through-next-swipe-threshold []
  (with-inverted-screen-y-ray
    (fn []
      (local child (make-test-child (glm.vec3 3 100 0)))
      (local view ((ScrollView {:child child.builder
                                :padding false}) (make-context)))
      (view.layout:measurer)
      (set view.layout.size (glm.vec3 4 4 0))
      (view.layout:layouter)
      (view:set-scroll-offset 20)
      (assert (view:on-touch-drag-start {:touch-id 1
                                         :finger-id 2
                                         :x 1
                                         :y 10
                                         :timestamp 100}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 2
                                   :x 1
                                   :y 12
                                   :timestamp 116}))
      (assert (view:on-touch-drag-end {:touch-id 1
                                       :finger-id 2
                                       :x 1
                                       :y 12
                                       :timestamp 116}))
      (assert (view:on-touch-drag-candidate-start {:touch-id 1
                                                   :finger-id 3
                                                   :x 1
                                                   :y 12
                                                   :timestamp 140}))
      (assert (view:on-touch-drag-start {:touch-id 1
                                         :finger-id 3
                                         :x 1
                                         :y 12
                                         :start-x 1
                                         :start-y 12
                                         :timestamp 260}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 3
                                   :x 1
                                   :y 14
                                   :timestamp 276}))
      (assert (view:on-touch-drag-end {:touch-id 1
                                       :finger-id 3
                                       :x 1
                                       :y 14
                                       :timestamp 276}))
      (assert view.state.kinetic)
      (assert (> view.state.kinetic.velocity 0.13)
              "A repeated swipe should carry kinetic velocity while crossing the drag threshold")
      (view:drop))))

(fn scroll-view-pending-kinetic-expires-before-late-drag []
  (with-inverted-screen-y-ray
    (fn []
      (local child (make-test-child (glm.vec3 3 100 0)))
      (local view ((ScrollView {:child child.builder
                                :padding false}) (make-context)))
      (view.layout:measurer)
      (set view.layout.size (glm.vec3 4 4 0))
      (view.layout:layouter)
      (view:set-scroll-offset 20)
      (assert (view:on-touch-drag-start {:touch-id 1
                                         :finger-id 2
                                         :x 1
                                         :y 10
                                         :timestamp 100}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 2
                                   :x 1
                                   :y 12
                                   :timestamp 116}))
      (assert (view:on-touch-drag-end {:touch-id 1
                                       :finger-id 2
                                       :x 1
                                       :y 12
                                       :timestamp 116}))
      (assert (view:on-touch-drag-candidate-start {:touch-id 1
                                                   :finger-id 3
                                                   :x 1
                                                   :y 12
                                                   :timestamp 140}))
      (assert (view:on-touch-drag-start {:touch-id 1
                                         :finger-id 3
                                         :x 1
                                         :y 12
                                         :start-x 1
                                         :start-y 12
                                         :timestamp 420}))
      (assert (view:on-touch-drag {:touch-id 1
                                   :finger-id 3
                                   :x 1
                                   :y 14
                                   :timestamp 436}))
      (assert (view:on-touch-drag-end {:touch-id 1
                                       :finger-id 3
                                       :x 1
                                       :y 14
                                       :timestamp 436}))
      (assert view.state.kinetic)
      (assert (< view.state.kinetic.velocity 0.13)
              "A held touch should not carry stale kinetic velocity into a later drag")
      (view:drop))))

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

(fn scroll-view-uses-viewport-width-for-content-measure []
  (local child (make-width-sensitive-child))
  (local view ((ScrollView {:child child.builder
                            :padding false
                            :scrollbar-policy :always-off})
               (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 4 4 0))
  (view.layout:layouter)
  (assert (approx child.state.last-constraint-width 4))
  (assert (approx view.state.max-offset 6))
  (view:drop))

(fn scroll-view-constrained-measure-uses-available-width []
  (local child (make-width-sensitive-child))
  (local view ((ScrollView {:child child.builder
                            :padding false
                            :scrollbar-policy :always-off})
               (make-context)))
  (view.layout:measure-constrained {:max (glm.vec3 4 4 0)})
  (assert (approx child.state.last-constraint-width 4))
  (assert (approx view.layout.measure.x 4))
  (assert (approx view.layout.measure.y 4))
  (view:drop))

(fn scroll-view-as-needed-remeasures-with-scrollbar-width []
  (local child (make-scrollbar-sensitive-child))
  (local view ((ScrollView {:child child.builder
                            :padding false
                            :scrollbar-policy :as-needed
                            :scrollbar-width 1})
               (make-context)))
  (view.layout:measurer)
  (set view.layout.size (glm.vec3 4 4 0))
  (view.layout:layouter)
  (assert (= (length child.state.constraint-widths) 2))
  (assert (approx (. child.state.constraint-widths 1) 4))
  (assert (approx (. child.state.constraint-widths 2) 3))
  (assert (approx view.state.max-offset 8))
  (view:drop))

(fn scroll-view-constrained-measure-reserves-as-needed-scrollbar []
  (local child (make-scrollbar-sensitive-child))
  (local view ((ScrollView {:child child.builder
                            :padding false
                            :scrollbar-policy :as-needed
                            :scrollbar-width 1})
               (make-context)))
  (view.layout:measure-constrained {:max (glm.vec3 4 4 0)})
  (assert (= (length child.state.constraint-widths) 2))
  (assert (approx (. child.state.constraint-widths 1) 4))
  (assert (approx (. child.state.constraint-widths 2) 3))
  (assert (approx view.layout.measure.x 4))
  (assert (approx view.layout.measure.y 4))
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
(table.insert tests {:name "ScrollView continuous wheel keeps moving" :fn scroll-view-continuous-wheel-keeps-moving})
(table.insert tests {:name "ScrollView discrete wheel does not start kinetic"
                     :fn scroll-view-discrete-wheel-does-not-start-kinetic})
(table.insert tests {:name "ScrollView flipped discrete wheel does not start kinetic"
                     :fn scroll-view-flipped-discrete-wheel-does-not-start-kinetic})
(table.insert tests {:name "ScrollView continuous wheel idle gap uses fresh velocity"
                     :fn scroll-view-continuous-wheel-idle-gap-uses-fresh-velocity})
(table.insert tests {:name "ScrollView touch drag scrolls content" :fn scroll-view-touch-drag-scrolls-content})
(table.insert tests {:name "ScrollView touch router captures with scroll threshold"
                     :fn scroll-view-touch-router-captures-with-scroll-threshold})
(table.insert tests {:name "ScrollView touch release keeps moving and slows"
                     :fn scroll-view-touch-release-keeps-moving-and-slows})
(table.insert tests {:name "ScrollView touch release after stop stays put"
                     :fn scroll-view-touch-release-after-stop-stays-put})
(table.insert tests {:name "ScrollView touch release jitter after stop is ignored"
                     :fn scroll-view-touch-release-jitter-after-stop-is-ignored})
(table.insert tests {:name "ScrollView kinetic stops without tail impulse"
                     :fn scroll-view-kinetic-stops-without-tail-impulse})
(table.insert tests {:name "ScrollView touch candidate carries kinetic into next swipe"
                     :fn scroll-view-touch-candidate-carries-kinetic-into-next-swipe})
(table.insert tests {:name "ScrollView kinetic long frame does not catch up"
                     :fn scroll-view-kinetic-long-frame-does-not-catch-up})
(table.insert tests {:name "ScrollView pending kinetic carries through next swipe threshold"
                     :fn scroll-view-pending-kinetic-carries-through-next-swipe-threshold})
(table.insert tests {:name "ScrollView pending kinetic expires before late drag"
                     :fn scroll-view-pending-kinetic-expires-before-late-drag})
(table.insert tests {:name "ScrollView defaults to max offset before layout"
                     :fn scroll-view-defaults-to-max-offset-before-layout})
(table.insert tests {:name "ScrollView uses viewport width for content measure"
                     :fn scroll-view-uses-viewport-width-for-content-measure})
(table.insert tests {:name "ScrollView constrained measure uses available width"
                     :fn scroll-view-constrained-measure-uses-available-width})
(table.insert tests {:name "ScrollView as-needed remeasures with scrollbar width"
                     :fn scroll-view-as-needed-remeasures-with-scrollbar-width})
(table.insert tests {:name "ScrollView constrained measure reserves as-needed scrollbar"
                     :fn scroll-view-constrained-measure-reserves-as-needed-scrollbar})
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
