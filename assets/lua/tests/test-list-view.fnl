(local glm (require :glm))
(local ListView (require :list-view))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))
(local BuildContext (require :build-context))
(local {: FocusManager} (require :focus))
(local Button (require :button))
(local NormalState (require :normal-state))
(local States (require :states))
(local StateSystemBindings (require :state-system-bindings))

(local tests [])

(local approx (. MathUtils :approx))

(fn command-hints-hud-provider [_self]
  {:command-hints
   {:handle-toggle-key (fn [_manager _payload] true)
    :close-on-handled-event (fn [_manager _route-key _payload] false)}})

(fn ensure-command-hints-hud! [states]
  (when (and states states.get-hud states.set-hud-provider (not (states:get-hud)))
    (states:set-hud-provider command-hints-hud-provider))
  states)

(fn set-app-states! [states]
  (ensure-command-hints-hud! states)
  (StateSystemBindings.bind-states-host states)
  (set app.states states)
  states)

(fn color= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)
       (approx a.w b.w)))

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate (fn [_self _count] 1))
  (set buffer.delete (fn [_self _handle] nil))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-test-ctx []
  (local triangle (make-vector-buffer))
  (local text-buffer (make-vector-buffer))
  (local ctx {:triangle-vector triangle})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
  (set ctx.get-text-ssbo-batcher
       (fn [_self]
         {:upsert-text (fn [_batcher _key _opts] nil)
          :update-text-transform (fn [_batcher _key _opts] nil)
          :remove-text (fn [_batcher _key] nil)}))
  (set ctx.clickables (assert app.clickables "test requires app.clickables"))
  (set ctx.hoverables (assert app.hoverables "test requires app.hoverables"))
  ctx)

(fn make-item-builder [measures states]
  (var index 0)
  (fn builder [item _ctx]
    (set index (+ index 1))
    (local measure (or (. measures index) (glm.vec3 1 1 0)))
    (local state {:item item :measure measure :index index
                  :dropped false :layouter-called false})
    (table.insert states state)
    (local layout
      (Layout {:name (.. "list-item-" index)
               :measurer (fn [self]
                           (set state.measure-called true)
                           (set self.measure (glm.vec3 measure.x measure.y measure.z)))
               :layouter (fn [self]
                           (set state.layouter-called true)
                           (set state.received-size (glm.vec3 self.size.x self.size.y self.size.z))
                           (set state.received-position (glm.vec3 self.position.x self.position.y self.position.z))
                           (set state.received-rotation self.rotation))}))
    (local widget {:layout layout :state state})
    (set widget.drop (fn [_]
                       (set state.dropped true)))
    widget))

(fn make-header-builder [state]
  (fn [_ctx]
    (set state.built (+ state.built 1))
    (local layout
      (Layout {:name "list-header"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 1 0.5 0)))
               :layouter (fn [_self] nil)}))
    (local widget {:layout layout})
     (set widget.drop (fn [_]
                        (set state.dropped (+ state.dropped 1))))
     widget))

(fn make-wrapping-item-builder [measures states]
  "Items have a constrained-measurer that reports taller height when X is narrow
(simulating wrapped text)."
  (var index 0)
  (fn builder [item _ctx]
    (set index (+ index 1))
    (local base-measure (or (. measures index) (glm.vec3 10 1 0)))
    (local state {:item item :index index :dropped false})
    (table.insert states state)
    (local layout
      (Layout {:name (.. "wrap-item-" index)
               :measurer (fn [self]
                           (set self.measure base-measure))
               :constrained-measurer (fn [self constraints]
                                       (local max-x (and constraints constraints.max (. constraints.max 1)))
                                       ;; If constrained to < 5 width, "wrap" to 5 lines
                                       (local height (if (and max-x (< max-x 5))
                                                        5
                                                        base-measure.y))
                                       (set self.measure (glm.vec3 (or max-x base-measure.x) height base-measure.z)))
               :layouter (fn [self] nil)}))
    (local widget {:layout layout :state state})
    (set widget.drop (fn [_] (set state.dropped true)))
    widget))

(fn list-view-measurer-includes-spacing []
  (local states [])
  (local builder (make-item-builder [(glm.vec3 2 1 0) (glm.vec3 3 3 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:alpha :beta]
                          :builder builder
                          :item-spacing 0.5
                          :show-head false}) ctx))
  (list.content-layout:measurer)
  (assert (= list.content-layout.measure.x 3))
  (assert (= list.content-layout.measure.y 4.5))
  (assert (= list.content-layout.measure.z 0))
  (list:drop))

(fn list-view-layouter-stacks-from-top []
  (local states [])
  (local builder (make-item-builder [(glm.vec3 2 1 0) (glm.vec3 3 2 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:one :two]
                          :builder builder
                          :item-spacing 0.25
                          :show-head false}) ctx))
  (list.content-layout:measurer)
  (set list.content-layout.size (glm.vec3 5 6 0))
  (list.content-layout:set-position (glm.vec3 0 0 0))
  (list.content-layout:layouter)
  (local first (. states 1))
  (local second (. states 2))
  (assert (= first.received-size.x 5))
  (assert (= first.received-size.y 1))
  (assert (= first.received-position.y 5))
  (assert (= second.received-position.y 2.75))
  (list:drop))

(fn list-view-set-items-drops-previous-widgets []
  (local states [])
  (local builder (make-item-builder [(glm.vec3 1 1 0) (glm.vec3 1 1 0) (glm.vec3 1 1 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:first :second]
                          :builder builder
                          :show-head false}) ctx))
  (list:set-items [:third])
  (local first (. states 1))
  (local second (. states 2))
  (local third (. states 3))
  (assert first.dropped)
  (assert second.dropped)
  (assert (not third.dropped))
  (list:drop))

(fn list-view-parks-focus-on-refresh []
  (local manager (FocusManager {:root-name "list-view-focus"}))
  (local root (manager:get-root-scope))
  (local scope (manager:create-scope {:name "list-scope"}))
  (manager:attach scope root)
  (local ctx
    (BuildContext {:focus-manager manager
                       :focus-scope scope
                       :clickables (assert app.clickables "test requires app.clickables")
                       :hoverables (assert app.hoverables "test requires app.hoverables")}))
  (local builder
    (fn [_value child-ctx]
      ((Button {:text "Item"}) child-ctx)))
  (local list ((ListView {:items [:one :two]
                          :builder builder
                          :show-head false
                          :scroll false}) ctx))
  (local first-item (. list.item-widgets 1))
  (assert first-item "ListView should build item widgets")
  (first-item:request-focus)
  (list:set-items [:three :four])
  (local refreshed-item (. list.item-widgets 1))
  (assert refreshed-item "ListView should rebuild items")
  (assert (= (manager:get-focused-node) refreshed-item.focus-node)
          "ListView should restore focus to first item")
  (list:drop)
  (manager:drop))

(fn list-view-set-title-rebuilds-header []
  (local header-state {:built 0 :dropped 0})
  (local ctx (make-test-ctx))
  (local list ((ListView {:items []
                          :show-head true
                          :header-builder (make-header-builder header-state)}) ctx))
  (assert (= header-state.built 1))
  (list:set-title "Updated")
  (assert (= header-state.built 2))
  (assert (= header-state.dropped 1))
  (list:drop))

(fn list-view-set-items-keeps-header []
  (local header-state {:built 0 :dropped 0})
  (local states [])
  (local builder (make-item-builder [(glm.vec3 1 1 0) (glm.vec3 1 1 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:first]
                          :builder builder
                          :show-head true
                          :header-builder (make-header-builder header-state)}) ctx))
  (assert (= header-state.built 1))
  (list:set-items [:second])
  (assert (= header-state.built 1) "set-items should not rebuild the header")
  (assert (= header-state.dropped 0) "set-items should keep the existing header")
  (list:drop))

(fn list-view-update-item-keeps-focus-order []
  (local manager (FocusManager {:root-name "list-view-order"}))
  (local root (manager:get-root-scope))
  (local scope (manager:create-scope {:name "list-scope"}))
  (manager:attach scope root)
  (local ctx
    (BuildContext {:focus-manager manager
                       :focus-scope scope
                       :clickables (assert app.clickables "test requires app.clickables")
                       :hoverables (assert app.hoverables "test requires app.hoverables")}))
  (local builder
    (fn [value child-ctx]
      ((Button {:text (tostring value)}) child-ctx)))
  (local list ((ListView {:items [:a :b :c :d]
                          :builder builder
                          :show-head false
                          :scroll false}) ctx))
  (list:update-item 2 :b2)
  (list:update-item 4 :d2)
  (local nodes
    (icollect [_ widget (ipairs list.item-widgets)]
      widget.focus-node))
  (manager:focus-next {})
  (assert (= (manager:get-focused-node) (. nodes 1))
          "Focus should start at first item")
  (manager:focus-next {})
  (assert (= (manager:get-focused-node) (. nodes 2))
          "Focus should advance to second item after update")
  (manager:focus-next {})
  (assert (= (manager:get-focused-node) (. nodes 3))
          "Focus should advance to third item after update")
  (manager:focus-next {})
  (assert (= (manager:get-focused-node) (. nodes 4))
          "Focus should advance to fourth item after update")
  (list:drop)
  (manager:drop))

(fn list-view-pagination-builds-current-page []
  (local states [])
  (local builder (make-item-builder [(glm.vec3 1 1 0) (glm.vec3 1 1 0)
                                     (glm.vec3 1 1 0) (glm.vec3 1 1 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:alpha :beta :gamma :delta]
                          :builder builder
                          :paginate true
                          :items-per-page 2}) ctx))
  (assert (= (length list.item-widgets) 2))
  (var page-first (. list.item-widgets 1))
  (var page-second (. list.item-widgets 2))
  (assert (= page-first.state.item :alpha))
  (assert (= page-second.state.item :beta))
  (list.pagination:set-page 1)
  (assert (= (length list.item-widgets) 2))
  (set page-first (. list.item-widgets 1))
  (set page-second (. list.item-widgets 2))
  (assert (= page-first.state.item :gamma))
  (assert (= page-second.state.item :delta))
  (list:drop))

(fn list-view-enter-activates-focused-item []
  (local manager (FocusManager {:root-name "list-view-test"}))
  (local root (manager:get-root-scope))
  (local scope (manager:create-scope {:name "list-scope"}))
  (manager:attach scope root)
  (local ctx
    (BuildContext {:focus-manager manager
                       :focus-scope scope
                       :clickables (assert app.clickables "test requires app.clickables")
                       :hoverables (assert app.hoverables "test requires app.hoverables")}))
  (var clicks 0)
  (local builder
    (fn [_value child-ctx]
      ((Button {:text "Item"
                :on-click (fn [_button _event]
                            (set clicks (+ clicks 1)))})
       child-ctx)))
  (local list ((ListView {:items [:one]
                          :builder builder
                          :show-head false
                          :scroll false}) ctx))
  (local item (. list.item-widgets 1))
  (assert item "ListView should build an item widget")
  (item:request-focus)
  (local original-focus app.focus)
  (local original-states app.states)
  (local states
    (States {:focus_manager_provider (fn [_self]
                                       app.focus)
             :hud_provider command-hints-hud-provider}))
  (set app.focus manager)
  (set-app-states! states)
  (local state (NormalState))
  (states:add-state :normal state)
  (state.on-key-down {:key 13})
  (assert (= clicks 1) "Enter should activate focused list item")
  (set-app-states! original-states)
  (set app.focus original-focus)
  (list:drop)
  (manager:drop))

(fn list-view-pagination-drops-previous-page []
  (local states [])
  (local builder (make-item-builder [(glm.vec3 1 1 0) (glm.vec3 1 1 0)
                                     (glm.vec3 1 1 0) (glm.vec3 1 1 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:alpha :beta :gamma :delta]
                          :builder builder
                          :paginate true
                          :items-per-page 2}) ctx))
  (list.pagination:set-page 1)
  (local first (. states 1))
  (local second (. states 2))
  (assert first.dropped)
  (assert second.dropped)
  (list:drop))

(fn list-view-pagination-set-items-respects-clamping []
  (local states [])
  (local builder (make-item-builder [(glm.vec3 1 1 0) (glm.vec3 1 1 0)
                                     (glm.vec3 1 1 0) (glm.vec3 1 1 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:a :b :c :d :e]
                          :builder builder
                          :paginate true
                          :items-per-page 2}) ctx))
  (list.pagination:set-page 2)
  (local current-item (. list.item-widgets 1))
  (assert (= current-item.state.item :e))
  (list:set-items [:one :two])
  (assert (= (length list.item-widgets) 2))
  (local page-first (. list.item-widgets 1))
  (local page-second (. list.item-widgets 2))
  (assert (= page-first.state.item :one))
  (assert (= page-second.state.item :two))
  (list:drop))

(fn list-view-header-title-uses-theme-color []
  (local ctx (make-test-ctx))
  (local theme-color (glm.vec4 0.35 0.62 0.88 1))
  (local theme {:text {:foreground (glm.vec4 1 0 0 1)}
                :list-view {:header {:foreground theme-color}}})
  (set ctx.theme theme)
  (local list ((ListView {:items []
                          :title "Checklist"
                          :show-head true}) ctx))
  (assert list.header)
  (local header list.header)
  (local title-span header.child)
  (assert title-span)
  (assert (color= title-span.style.color theme-color))
  (list:drop))

(fn list-view-defaults-to-scroll []
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:a :b]}) ctx))
  (assert list.scroll-view)
  (assert (= list.layout list.scroll-view.layout))
  (assert list.content-layout)
  (list:drop))

(fn list-view-scroll-can-be-disabled []
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:a :b]
                          :scroll false}) ctx))
  (assert (not list.scroll-view))
  (assert (= list.layout list.content-layout))
  (list:drop))

(fn list-view-pagination-disables-scroll []
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:alpha :beta]
                          :paginate true
                          :scroll true
                          :scroll-items-per-page 2}) ctx))
  (assert (not list.scroll-view))
  (assert (= list.layout list.content-layout))
  (list:drop))

(fn list-view-scroll-items-limit-viewport []
  (local states [])
  (local builder (make-item-builder [(glm.vec3 1 1 0)
                                     (glm.vec3 1 2 0)
                                     (glm.vec3 1 3 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:a :b :c]
                          :builder builder
                          :scroll true
                          :scroll-items-per-page 2
                          :item-spacing 0.4
                          :show-head false}) ctx))
  (local scroll-state (and list.scroll-view list.scroll-view.state))
  (assert scroll-state)
  (assert (= scroll-state.viewport-height 3.4))
  (list:drop))

(fn list-view-scroll-items-include-header []
  (local states [])
  (local header-state {:built 0 :dropped 0})
  (local builder (make-item-builder [(glm.vec3 2 1 0)
                                     (glm.vec3 2 1 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:a :b]
                          :builder builder
                          :scroll true
                          :scroll-items-per-page 1
                          :item-spacing 0.25
                          :show-head true
                          :header-builder (make-header-builder header-state)}) ctx))
  (local scroll-state (and list.scroll-view list.scroll-view.state))
  (assert scroll-state)
  (assert (= scroll-state.viewport-height 1.75))
  (list:drop))

(fn list-view-scroll-viewport-constrained-when-width-known []
  "When scroll-view.layout.size.x is available from a previous frame,
scroll-items-per-page should use constrained measurement so wrapping
children report correct height. When no prior width is available,
a deferred correction schedules re-measure after the first layout."
  (local states [])
  (local builder (make-wrapping-item-builder [(glm.vec3 10 1 0)
                                               (glm.vec3 10 1 0)
                                               (glm.vec3 10 1 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:a :b :c]
                          :builder builder
                          :scroll true
                          :scroll-items-per-page 2
                          :item-spacing 0
                          :fill-width true
                          :show-head false}) ctx))
  (local scroll-state (and list.scroll-view list.scroll-view.state))
  (assert scroll-state)
  ;; First construction: no prior width -> uses unconstrained measurement initially
  (assert (approx scroll-state.viewport-height 2)
          (.. "First viewport without width should fall back to unconstrained (2 items * 1), got "
              (tostring scroll-state.viewport-height)))
  ;; Simulate a prior layout: set scroll-view viewport-size to a narrow width
  (set list.scroll-view.state.viewport-size (glm.vec3 3 20 0))
  ;; set-items triggers update-scroll-viewport which now sees known viewport width=3
  (list:set-items [:x :y :z])
  (assert (approx scroll-state.viewport-height 10)
          (.. "Second viewport with known viewport width=3 (< 5) should use constrained (2 items * 5 lines), got "
              (tostring scroll-state.viewport-height)))
  ;; After no prior width (first construction), the deferred check on layout
  ;; schedules a one-frame correction via app.next-frame.  Verify it arrives.
  (local list2 ((ListView {:items [:a :b :c]
                           :builder builder
                           :scroll true
                           :scroll-items-per-page 2
                           :item-spacing 0
                           :fill-width true
                           :show-head false}) ctx))
  ;; Measure + layout to trigger deferred correction check
  (local queue-length-before (or (and app app.next-frame-queue
                                      (length app.next-frame-queue))
                                 0))
  (list2.content-layout:measurer)
  (set list2.scroll-view.layout.size (glm.vec3 3 20 0))
  (set list2.content-layout.size (glm.vec3 3 20 0))
  (list2.content-layout:layouter)
  ;; After layout, viewport-height should be corrected immediately
  (local scroll-state2 (and list2.scroll-view list2.scroll-view.state))
  (assert (approx scroll-state2.viewport-height 10)
          (.. "After layout with known width, deferred check should correct viewport to 10, got "
              (tostring scroll-state2.viewport-height)))
  ;; The deferred callback should be queued
  (assert (and app app.next-frame-queue (> (length app.next-frame-queue) queue-length-before))
          "Deferred viewport correction should schedule app.next-frame callback")
  ;; Run the queued callback and verify it marks the scroll-view layout dirty
  (local sv-layout list2.scroll-view.layout)
  ;; Clear any pre-existing dirt so we can detect the callback's effect
  (set sv-layout.measure-dirty false)
  (local total-queued (length app.next-frame-queue))
  (for [i 1 (- total-queued queue-length-before)]
    (local cb (table.remove app.next-frame-queue))
    (when cb (cb)))
  (assert sv-layout.measure-dirty
          "Scroll-view layout should be marked measure-dirty after deferred callback")
  (list:drop)
  (list2:drop))

(fn list-view-scroll-viewport-prefers-content-width []
  "When both content-layout.size.x and scroll-view.state.viewport-size.x are set
and differ, update-scroll-viewport should prefer the narrower content-layout width
for constrained measurement (viewport includes internal padding)."
  (local states [])
  (local builder (make-wrapping-item-builder [(glm.vec3 10 1 0)
                                               (glm.vec3 10 1 0)
                                               (glm.vec3 10 1 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:a :b :c]
                          :builder builder
                          :scroll true
                          :scroll-items-per-page 2
                          :item-spacing 0
                          :fill-width true
                          :show-head false}) ctx))
  (local scroll-state (and list.scroll-view list.scroll-view.state))
  (assert scroll-state)
  ;; Set viewport-size wider than content-layout to simulate ScrollView padding
  (set list.scroll-view.state.viewport-size (glm.vec3 10 20 0))
  (set list.content-layout.size (glm.vec3 3 20 0))
  ;; set-items triggers update-scroll-viewport; content-layout.size wins
  (list:set-items [:x :y :z])
  ;; With content-layout width=3 (< 5), wrapping items report height=5 each
  ;; 2 items * 5 = 10
  (assert (approx scroll-state.viewport-height 10)
          (.. "Should use content-layout width 3 (< 5) -> wrapped height 10, got "
              (tostring scroll-state.viewport-height)))
  ;; Now keep the same viewport-size but widen content-layout beyond wrap threshold
  (set list.content-layout.size (glm.vec3 10 20 0))
  (list:set-items [:a :b :c])
  ;; With content-layout width=10 (> 5), items report natural height=1 each
  ;; 2 items * 1 = 2
  (assert (approx scroll-state.viewport-height 2)
          (.. "Should use content-layout width 10 (> 5) -> natural height 2, got "
              (tostring scroll-state.viewport-height)))
  (list:drop))

(fn list-view-set-items-resets-scroll []
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:a :b :c]
                          :scroll true
                          :scroll-items-per-page 2}) ctx))
  (list:set-scroll-offset 3)
  (assert (> (list:get-scroll-offset) 0))
  (list:set-items [:x :y])
  (local scroll-state (and list.scroll-view list.scroll-view.state))
  (assert scroll-state)
  (assert (= (list:get-scroll-offset) scroll-state.max-offset))
  (assert (not scroll-state.user-set-offset?))
  (list:drop))

(fn list-view-set-items-resets-pagination []
  (local states [])
  (local builder (make-item-builder [(glm.vec3 1 1 0)
                                     (glm.vec3 1 1 0)
                                     (glm.vec3 1 1 0)
                                     (glm.vec3 1 1 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:a :b :c :d]
                          :builder builder
                          :paginate true
                          :items-per-page 2}) ctx))
  (list.pagination:set-page 1)
  (assert (= list.pagination.current-page 1))
  (list:set-items [:alpha :beta :gamma])
  (assert (= list.pagination.current-page 0))
  (assert (= (length list.item-widgets) 2))
  (local first (. list.item-widgets 1))
  (local second (. list.item-widgets 2))
  (assert (= first.state.item :alpha))
  (assert (= second.state.item :beta))
  (list:drop))

(table.insert tests {:name "ListView measurer sums spacing" :fn list-view-measurer-includes-spacing})
(table.insert tests {:name "ListView layouter stacks top-down" :fn list-view-layouter-stacks-from-top})
(table.insert tests {:name "ListView set-items drops previous children" :fn list-view-set-items-drops-previous-widgets})
(table.insert tests {:name "ListView parks focus during refresh" :fn list-view-parks-focus-on-refresh})
(table.insert tests {:name "ListView set-title rebuilds header" :fn list-view-set-title-rebuilds-header})
(table.insert tests {:name "ListView set-items keeps header" :fn list-view-set-items-keeps-header})
(table.insert tests {:name "ListView update-item keeps focus order" :fn list-view-update-item-keeps-focus-order})
(table.insert tests {:name "ListView pagination builds visible page" :fn list-view-pagination-builds-current-page})
(table.insert tests {:name "ListView enter activates focused item" :fn list-view-enter-activates-focused-item})
(table.insert tests {:name "ListView pagination drops previous page widgets" :fn list-view-pagination-drops-previous-page})
(table.insert tests {:name "ListView pagination clamps when items shrink" :fn list-view-pagination-set-items-respects-clamping})
(table.insert tests {:name "ListView header title uses theme color" :fn list-view-header-title-uses-theme-color})
(table.insert tests {:name "ListView defaults to scroll behavior" :fn list-view-defaults-to-scroll})
(table.insert tests {:name "ListView can disable scroll wrapper" :fn list-view-scroll-can-be-disabled})
(table.insert tests {:name "ListView pagination disables scroll wrapper" :fn list-view-pagination-disables-scroll})
(table.insert tests {:name "ListView scroll items clamp viewport" :fn list-view-scroll-items-limit-viewport})
(table.insert tests {:name "ListView scroll viewport includes header" :fn list-view-scroll-items-include-header})
(fn list-view-scroll-viewport-corrects-on-width-change []
  "When auto-scroll-viewport is active and the content-layout width changes
between layouts (e.g. window resize), the viewport height should be recalculated."
  (local states [])
  (local builder (make-wrapping-item-builder [(glm.vec3 10 1 0)
                                               (glm.vec3 10 1 0)
                                               (glm.vec3 10 1 0)] states))
  (local ctx (make-test-ctx))
  (local list ((ListView {:items [:a :b :c]
                          :builder builder
                          :scroll true
                          :scroll-items-per-page 2
                          :item-spacing 0
                          :fill-width true
                          :show-head false}) ctx))
  (local scroll-state (and list.scroll-view list.scroll-view.state))
  (assert scroll-state)
  ;; First layout at wide width: no wrapping, viewport height = 2
  (list.content-layout:measurer)
  (set list.scroll-view.layout.size (glm.vec3 10 20 0))
  (set list.content-layout.size (glm.vec3 10 20 0))
  (list.content-layout:layouter)
  (assert (approx scroll-state.viewport-height 2)
          (.. "First layout wide -> viewport height 2 (no wrap), got "
              (tostring scroll-state.viewport-height)))
  ;; Resize to narrow: wrapping should increase viewport height
  (set list.scroll-view.layout.size (glm.vec3 3 20 0))
  (set list.content-layout.size (glm.vec3 3 20 0))
  (list.content-layout:layouter)
  (assert (approx scroll-state.viewport-height 10)
          (.. "Resize to narrow (3 < 5) -> viewport height 10 (wrapped), got "
              (tostring scroll-state.viewport-height)))
  ;; Resize back to wide: viewport height should shrink
  (set list.scroll-view.layout.size (glm.vec3 10 20 0))
  (set list.content-layout.size (glm.vec3 10 20 0))
  (list.content-layout:layouter)
  (assert (approx scroll-state.viewport-height 2)
          (.. "Resize back to wide -> viewport height 2 (no wrap), got "
              (tostring scroll-state.viewport-height)))
  (list:drop))

(table.insert tests {:name "ListView scroll viewport uses constrained when width known" :fn list-view-scroll-viewport-constrained-when-width-known})
(table.insert tests {:name "ListView scroll viewport prefers content-layout width over viewport" :fn list-view-scroll-viewport-prefers-content-width})
(table.insert tests {:name "ListView scroll viewport corrects on width change" :fn list-view-scroll-viewport-corrects-on-width-change})
(table.insert tests {:name "ListView set-items resets scroll offset" :fn list-view-set-items-resets-scroll})
(table.insert tests {:name "ListView set-items resets pagination page" :fn list-view-set-items-resets-pagination})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "list-view"
                       :tests tests})))

{:name "list-view"
 :tests tests
 :main main}
