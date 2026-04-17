(local Runtime (require :state-runtime))

(local engine-event-order
  [[:touch-down :touch-down :on-touch-down]
   [:touch-motion :touch-motion :on-touch-motion]
   [:touch-up :touch-up :on-touch-up]
   [:touch-canceled :touch-canceled :on-touch-canceled]
   [:text-input :text-input :on-text-input]
   [:text-editing :text-editing :on-text-editing]
   [:key-down :key-down :on-key-down]
   [:key-up :key-up :on-key-up]
   [:mouse-button-down :mouse-button-down :on-mouse-button-down]
   [:mouse-button-up :mouse-button-up :on-mouse-button-up]
   [:mouse-motion :mouse-motion :on-mouse-motion]
   [:mouse-wheel :mouse-wheel :on-mouse-wheel]
   [:gamepad-button-down :gamepad-button-down :on-gamepad-button-down]
   [:gamepad-axis-motion :gamepad-axis-motion :on-gamepad-axis-motion]
   [:gamepad-removed :gamepad-removed :on-gamepad-removed]
   [:updated :updated :on-updated]])

(local known-route-keys
  (let [keys {}]
    (each [_ entry (ipairs engine-event-order)]
      (tset keys (. entry 1) true))
    keys))

(fn assert-known-route-keys [routes]
  (when routes
    (each [route-key _ (pairs routes)]
      (assert (. known-route-keys route-key)
              (.. "State received unknown route key: " (tostring route-key))))))

(fn clone-routes [routes]
  (local copy {})
  (each [_ entry (ipairs engine-event-order)]
    (local route-key (. entry 1))
    (tset copy route-key (and routes (. routes route-key))))
  copy)

(fn collect-active-route-entries [routes]
  (local entries [])
  (each [_ entry (ipairs engine-event-order)]
    (local route-key (. entry 1))
    (when (. routes route-key)
      (table.insert entries entry)))
  entries)

(fn require-engine-events [state-name]
  (assert (and app app.engine app.engine.events)
          (.. "State " (tostring state-name) " requires app.engine.events"))
  app.engine.events)

(fn make-ctx [state]
  (var current-event nil)
  {:app app
   :state state
   :set-state (fn [name]
                (assert (and app.states app.states.set-state)
                        (.. "State " (tostring state.name) " requires app.states.set-state"))
                (app.states.set-state name))
   :connect-input Runtime.connect-input
   :disconnect-input Runtime.disconnect-input
   :active-input Runtime.active-input
   :event-consumed? (fn []
                      (and current-event current-event.consumed?))
   :mark-event-consumed! (fn []
                           (when current-event
                             (set current-event.consumed? true))
                           true)
   :begin-event (fn [event]
                  (local previous-event current-event)
                  (set current-event event)
                  previous-event)
   :end-event (fn [previous-event]
                (set current-event previous-event))})

(fn run-lifecycle [handlers event-name ctx]
  (when handlers
    (each [_ handler (ipairs handlers)]
      (local lifecycle
        (if (= (type handler) :function)
            handler
            (and handler (. handler event-name))))
      (when lifecycle
        (lifecycle ctx)))))

(fn resolve-payload [maybe-self maybe-payload]
  (if (= maybe-payload nil)
      maybe-self
      maybe-payload))

(fn State [opts]
  (assert opts "State requires options")
  (assert-known-route-keys opts.routes)
  (local routes (clone-routes (or opts.routes {})))
  (local active-route-entries (collect-active-route-entries routes))
  (local state {:name opts.name})
  (local ctx (make-ctx state))
  (local event-handlers {})
  (var entered? false)
  (local reusable-event {:consumed? false})

  (fn call-route [event-name payload]
    (local route (and routes (. routes event-name)))
    (if route
        (do
          (set reusable-event.consumed? false)
          (local previous-event (ctx.begin-event reusable-event))
          (local result (route event-name ctx payload))
          (ctx.end-event previous-event)
          result)
        false))

  (each [_ entry (ipairs engine-event-order)]
    (local route-key (. entry 1))
    (local method-key (. entry 3))
    (tset event-handlers route-key
          (fn [maybe-self maybe-payload]
            (call-route route-key (resolve-payload maybe-self maybe-payload))))
    (tset state method-key (. event-handlers route-key)))

  (fn on-enter []
    (when (not entered?)
      (local events (require-engine-events state.name))
      (each [_ entry (ipairs active-route-entries)]
        (local route-key (. entry 1))
        (local signal-key (. entry 2))
        (local signal (. events signal-key))
        (assert signal
                (.. "State " (tostring state.name) " requires engine event signal " (tostring signal-key)))
        (signal.connect (. event-handlers route-key)))
      (set entered? true)
      (run-lifecycle opts.enter :enter ctx)))

  (fn on-leave []
    (when entered?
      (local events (require-engine-events state.name))
      (each [_ entry (ipairs active-route-entries)]
        (local route-key (. entry 1))
        (local signal-key (. entry 2))
        (local signal (. events signal-key))
        (assert signal
                (.. "State " (tostring state.name) " requires engine event signal " (tostring signal-key)))
        (signal.disconnect (. event-handlers route-key)))
      (set entered? false)
      (run-lifecycle opts.leave :leave ctx)))

  (set state.on-enter on-enter)
  (set state.on-leave on-leave)
  (set state.ctx ctx)
  (set state.connect-input Runtime.connect-input)
  (set state.disconnect-input Runtime.disconnect-input)
  (set state.active-input Runtime.active-input)
  (set state.handle-focus-tab Runtime.handle-focus-tab)
  (set state.shift-held? Runtime.shift-held?)
  (set state.ctrl-held? Runtime.ctrl-held?)

  state)

State
