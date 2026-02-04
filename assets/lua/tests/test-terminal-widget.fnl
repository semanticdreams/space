(local glm (require :glm))
(local TerminalWidget (require :terminal-widget))
(local BuildContext (require :build-context))
(local {: FocusManager} (require :focus))
(local InputState (require :input-state-router))
(local States (require :states))
(local NormalState (require :normal-state))
(local terminal (require :terminal))

(local tests [])

(fn with-terminal-stub [body opts]
  (local original-Terminal terminal.Terminal)
  (local calls {:text [] :keys [] :mouse [] :update [] :scrollback-limit [] :injected []})
  (local default-pty-available? (not (= (and opts (. opts "pty-available?")) false)))
  (set terminal.Terminal (fn [rows cols]
                        (var mutable-rows rows)
                        (var mutable-cols cols)
                        (var alt-screen false)
                        (var scrollback-size 0)
                        (var pty-available? default-pty-available?)
                        (local term {:rows mutable-rows :cols mutable-cols})
                        (set term.get-size (fn [_] {:rows mutable-rows :cols mutable-cols}))
                        (set term.resize (fn [_ r c]
                                           (set mutable-rows r)
                                           (set mutable-cols c)))
                        (set term.get-dirty-regions (fn [_] []))
                        (set term.clear-dirty-regions (fn [_] nil))
                        (set term.get-cursor (fn [_] {:row 0 :col 0 :visible true :blinking false}))
                        (set term.get-cell (fn [_ _ _]
                                             {:codepoint 32
                                              :fg-r 255 :fg-g 255 :fg-b 255
                                             :bg-r 0 :bg-g 0 :bg-b 0
                                              :bold false :underline false :italic false :reverse false}))
                        (set term.send-text (fn [_ text]
                                              (table.insert calls.text text)))
                        (set term.send-key (fn [_ key]
                                              (table.insert calls.keys key)))
                        (set term.send-mouse (fn [_ row col button pressed]
                                               (table.insert calls.mouse
                                           {:row row :col col :button button :pressed pressed})))
                        (set term.update (fn [_]
                                           (table.insert calls.update true)))
                        (set term.set-scrollback-limit (fn [_ lines]
                                                         (table.insert calls.scrollback-limit lines)))
                        (set term.get-scrollback-size (fn [_] scrollback-size))
                        (set term.set_scrollback_size (fn [_ value]
                                                        (set scrollback-size value)))
                        (set term.is-pty-available (fn [_] pty-available?))
                        (set term.set_pty_available (fn [_ value]
                                                      (set pty-available? (not (not value)))))
                        (set term.inject-output (fn [_ data]
                                                  (table.insert calls.injected data)))
                        (set term.is-alt-screen (fn [_] alt-screen))
                        (set term.set_alt_screen (fn [_ value]
                                                   (set alt-screen value)))
                        term))
  (let [result (body calls)]
    (set terminal.Terminal original-Terminal)
    result))

(fn setup-state []
  (reset-engine-events)
  (set app.states (States))
  (app.states.add-state :normal (NormalState))
  (app.states.set-state :normal)
  (local state (app.states.get-state :normal))
  (state.on-enter)
  state)

(fn teardown-state [state]
  (when state
    (state.on-leave)))

(fn make-widget [options]
  (local builder (TerminalWidget options))
  (local ctx (BuildContext {:theme (app.themes.get-active-theme)
                            :clickables (assert app.clickables "test requires app.clickables")}))
  (builder ctx))

(fn terminal-measure-uses-grid []
  (local widget (make-widget {:rows 3 :cols 5 :cell-size {:x 2 :y 4}}))
  (widget.layout:measurer)
  (assert (= widget.layout.measure.x 10))
  (assert (= widget.layout.measure.y 12)))

(fn terminal-layouter-resizes-terminal []
  (local widget (make-widget {:rows 2 :cols 2 :cell-size {:x 1 :y 1}}))
  (widget.layout:measurer)
  (set widget.layout.size (glm.vec3 7 4 0))
  (widget.layout:layouter)
  (local size (widget.term:get-size))
  (assert (= size.cols 7) (.. "cols=" size.cols))
  (assert (= size.rows 4) (.. "rows=" size.rows)))

(fn terminal-focus-connects-input []
  (with-terminal-stub
    (fn [calls]
      (local state (setup-state))
      (local manager (FocusManager {:root-name "root"}))
      (local root (manager:get-root-scope))
      (local scope (manager:create-scope {:name "hud"}))
      (manager:attach scope root)
      (set app.focus manager)
      (local ctx (BuildContext {:focus-manager manager
                                    :focus-scope scope
                                    :theme (app.themes.get-active-theme)
                                    :clickables (assert app.clickables "test requires app.clickables")}))
      (local widget ((TerminalWidget {:rows 2 :cols 3 :cell-size {:x 1 :y 1}}) ctx))
      (widget.layout:measurer)
      (set widget.layout.size (glm.vec3 3 2 0))
      (widget.layout:layouter)
      (assert widget.focus-node)
      (widget.focus-node:request-focus)
      (assert (= (InputState.active-input) widget))
      (app.engine.events.text-input.emit {:text "hi"})
      (app.engine.events.key-down.emit {:key 1073741904})
      (app.engine.events.mouse-button-down.emit {:x 1.2 :y 0.1 :button 1})
      (local other (manager:create-node {:name "other"}))
      (manager:attach other scope)
      (other:request-focus)
      (app.engine.events.text-input.emit {:text "bye"})
      (assert (not (= (InputState.active-input) widget)))
      (assert (= (# calls.text) 2))
      (assert (>= (# calls.keys) 1))
      (assert (>= (# calls.mouse) 1))
      (local mouse-call (. calls.mouse 1))
      (assert (= mouse-call.row 0))
      (assert (= mouse-call.col 1))
      (assert mouse-call.pressed)
      (widget:drop)
      (manager:drop)
      (teardown-state state))))

(fn terminal-updates-on-frame []
  (with-terminal-stub
    (fn [calls]
      (reset-engine-events)
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)
                                :clickables (assert app.clickables "test requires app.clickables")}))
      (local widget ((TerminalWidget {:rows 2 :cols 3 :cell-size {:x 1 :y 1}}) ctx))
      (app.engine.events.updated.emit 0.016)
      (assert (= (# calls.update) 1))
      (widget:drop)
      (app.engine.events.updated.emit 0.016)
      (assert (= (# calls.update) 1)))))

(fn terminal-configures-scrollback-options []
  (with-terminal-stub
    (fn [calls]
      (local widget (make-widget {:rows 2
                                  :cols 2
                                  :cell-size {:x 1 :y 1}
                                  :scrollback-lines 12
                                  :follow-tail? false
                                  :scroll_offset 3}))
      (assert (= (. calls.scrollback-limit 1) 12))
      (assert (= (widget:scroll_offset) 3))
      (assert (not (widget:follow_tail)))
      (widget:drop))))

(fn terminal-shows-placeholder-when-pty-missing []
  (with-terminal-stub
    (fn [calls]
      (local widget (make-widget {:rows 2 :cols 2 :cell-size {:x 1 :y 1}}))
      (assert (= (# calls.injected) 1))
      (assert (string.find (. calls.injected 1) "PTY unavailable"))
      (assert (not (widget:set_scroll_offset 4)))
      (widget:on-mouse-wheel {:y 1})
      (assert (= (widget:scroll_offset) 0))
      (assert (widget:follow_tail))
      (widget:drop))
    {:pty-available? false}))

(fn terminal-input-snap-when-following []
  (with-terminal-stub
    (fn [_calls]
      (reset-engine-events)
      (local events [])
      (local widget (make-widget {:rows 2
                                  :cols 2
                                  :cell-size {:x 1 :y 1}
                                  :on-scroll (fn [payload]
                                               (table.insert events payload))}))
      (widget.term:set_scrollback_size 10)
      (widget:set_scroll_offset 4)
      (widget:set_follow_tail true)
      (assert (= (widget:scroll_offset) 4))
      (widget:on-text-input {:text "z"})
      (assert (= (widget:scroll_offset) 0))
      (assert (>= (# events) 2))
      (local last (. events (# events)))
      (assert (= last.offset 0))
      (assert (. last "follow-tail"))
      (widget:drop))))

(fn terminal-blocks-scrollback-in-alt-screen []
  (with-terminal-stub
    (fn [_calls]
      (reset-engine-events)
      (local widget (make-widget {:rows 2 :cols 2 :cell-size {:x 1 :y 1}}))
      (widget.term:set_scrollback_size 10)
      (widget:set_scroll_offset 2)
      (widget.term:set_alt_screen true)
      (widget:set_scroll_offset 5)
      (assert (= (widget:scroll_offset) 0))
      (widget.term:set_alt_screen false)
      (widget:set_scroll_offset 1)
      (assert (= (widget:scroll_offset) 1))
      (widget:drop))))

(fn terminal-wheel-scrolls-offset []
  (with-terminal-stub
    (fn [calls]
      (reset-engine-events)
      (local widget (make-widget {:rows 3 :cols 1 :cell-size {:x 1 :y 1}}))
      (widget.term:set_scrollback_size 10)
      (widget:on-mouse-wheel {:y 1})
      (assert (= (widget:scroll_offset) 3))
      (assert (not (widget:follow_tail)))
      (widget:on-mouse-wheel {:y -1})
      (assert (= (widget:scroll_offset) 0))
      (assert (widget:follow_tail))
      (assert (= (# calls.mouse) 0))
      (widget:drop))))

(fn terminal-page-keys-navigate-scrollback []
  (with-terminal-stub
    (fn [calls]
      (reset-engine-events)
      (local widget (make-widget {:rows 4 :cols 2 :cell-size {:x 1 :y 1}}))
      (widget.term:set_scrollback_size 20)
      (widget:on-key-down {:key 1073741899})
      (assert (= (widget:scroll_offset) 3))
      (assert (not (widget:follow_tail)))
      (widget:on-key-down {:key 1073741902})
      (assert (= (widget:scroll_offset) 0))
      (assert (widget:follow_tail))
      (assert (= (# calls.keys) 0))
      (widget:drop))))

(fn terminal-wheel-falls-through-in-alt-screen []
  (with-terminal-stub
    (fn [calls]
      (reset-engine-events)
      (local widget (make-widget {:rows 2 :cols 2 :cell-size {:x 1 :y 1}}))
      (widget.term:set_alt_screen true)
      (widget.layout:measurer)
      (set widget.layout.size (glm.vec3 2 2 0))
      (widget.layout:layouter)
      (widget:on-mouse-wheel {:y 1})
      (assert (= (widget:scroll_offset) 0))
      (assert (= (# calls.mouse) 1))
      (widget:drop))))

(table.insert tests {:name "terminal widget measures by grid" :fn terminal-measure-uses-grid})
(table.insert tests {:name "terminal widget layouter resizes terminal" :fn terminal-layouter-resizes-terminal})
(table.insert tests {:name "terminal connects input on focus and routes events" :fn terminal-focus-connects-input})
(table.insert tests {:name "terminal subscribes to frame updates" :fn terminal-updates-on-frame})
(table.insert tests {:name "terminal applies scrollback options and state" :fn terminal-configures-scrollback-options})
(table.insert tests {:name "terminal renders placeholder when PTY unavailable" :fn terminal-shows-placeholder-when-pty-missing})
(table.insert tests {:name "terminal snaps scroll offset when following tail" :fn terminal-input-snap-when-following})
(table.insert tests {:name "terminal blocks scrollback navigation in alt screen" :fn terminal-blocks-scrollback-in-alt-screen})
(table.insert tests {:name "terminal mouse wheel adjusts scroll offset" :fn terminal-wheel-scrolls-offset})
(table.insert tests {:name "terminal page keys adjust scrollback offset" :fn terminal-page-keys-navigate-scrollback})
(table.insert tests {:name "terminal wheel forwards to terminal in alt screen" :fn terminal-wheel-falls-through-in-alt-screen})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "terminal-widget"
                       :tests tests})))

{:name "terminal-widget"
 :tests tests
 :main main}
