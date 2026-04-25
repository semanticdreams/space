(local Runtime (require :state-runtime))

(local engine-event-order
  [[:pen-proximity-in :pen-proximity-in :on-pen-proximity-in]
   [:pen-proximity-out :pen-proximity-out :on-pen-proximity-out]
   [:pen-motion :pen-motion :on-pen-motion]
   [:pen-down :pen-down :on-pen-down]
   [:pen-up :pen-up :on-pen-up]
   [:pen-button-down :pen-button-down :on-pen-button-down]
   [:pen-button-up :pen-button-up :on-pen-button-up]
   [:pen-axis :pen-axis :on-pen-axis]
   [:touch-down :touch-down :on-touch-down]
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
  {})

(each [_ entry (ipairs engine-event-order)]
  (tset known-route-keys (. entry 1) true))

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

(fn normalize-route-wrappers [wrappers]
  (if (not wrappers)
      []
      (= (type wrappers) :function)
      [wrappers]
      (= (type wrappers) :table)
      (do
        (var count 0)
        (var max-index 0)
        (each [index wrapper (pairs wrappers)]
          (assert (and (= (type index) :number)
                       (>= index 1)
                       (= index (math.floor index)))
                  "State route-wrappers must be a dense list")
          (assert (= (type wrapper) :function)
                  "State route-wrappers entries must be functions")
          (set count (+ count 1))
          (set max-index (math.max max-index index)))
        (assert (= count max-index)
                "State route-wrappers must not contain holes")
        wrappers)
      (error "State route-wrappers must be a function or a list of functions")))

(fn wrap-routes [routes wrappers ctx state]
  (local route-wrappers (normalize-route-wrappers wrappers))
  (if (<= (length route-wrappers) 0)
      routes
      (do
        (local wrapped {})
        (each [_ entry (ipairs engine-event-order)]
          (local route-key (. entry 1))
          (local route (. routes route-key))
          (var current route)
          (each [_ wrapper (ipairs route-wrappers)]
            (set current (wrapper route-key current ctx state)))
          (tset wrapped route-key current))
        wrapped)))

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

(fn state-owner [state]
  (and state state.states_owner))

(fn require-state-owner [state action]
  (local owner (state-owner state))
  (assert owner
          (.. "State " (tostring state.name) " requires a states host for " action))
  owner)

(fn resolve-state-hud [state]
  (if state.hud_provider
      (state.hud_provider state)
      (do
        (local owner (require-state-owner state "ctx.hud"))
        (assert owner.get-hud
                (.. "State " (tostring state.name) " requires a states host with :get-hud"))
        (owner:get-hud))))

(fn resolve-state-focus-manager [state]
  (if state.focus_manager_provider
      (state.focus_manager_provider state)
      (do
        (local owner (require-state-owner state "ctx.focus-manager"))
        (assert owner.get-focus-manager
                (.. "State " (tostring state.name) " requires a states host with :get-focus-manager"))
        (owner:get-focus-manager))))

(fn make-ctx [state]
  (var current-event nil)
  {:app app
   :state state
   :states (fn []
             (require-state-owner state "ctx.states"))
   :hud (fn []
          (resolve-state-hud state))
   :focus-manager (fn []
                    (resolve-state-focus-manager state))
   :set-state (fn [name]
                (local owner (require-state-owner state "ctx.set-state"))
                (owner:set-state name))
   :connect-input Runtime.connect-input
   :disconnect-input Runtime.disconnect-input
   :active-input Runtime.active-input
   :event-consumed? (fn []
                      (and current-event current-event.consumed?))
   :command-executed? (fn []
                        (and current-event current-event.command-executed?))
   :mark-event-consumed! (fn []
                           (when current-event
                             (set current-event.consumed? true))
                           true)
   :mark-command-executed! (fn []
                            (when current-event
                              (set current-event.command-executed? true))
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
  (assert (or (= opts.command_hints_provider nil)
              (= (type opts.command_hints_provider) :function))
          "State command_hints_provider must be a function")
  (assert (or (= opts.hud_provider nil)
              (= (type opts.hud_provider) :function))
          "State hud_provider must be a function")
  (assert (or (= opts.focus_manager_provider nil)
              (= (type opts.focus_manager_provider) :function))
          "State focus_manager_provider must be a function")
  (local base-routes (clone-routes (or opts.routes {})))
  (local state {:name opts.name
                :command_hints_provider opts.command_hints_provider
                :hud_provider opts.hud_provider
                :focus_manager_provider opts.focus_manager_provider})
  (local ctx (make-ctx state))
  (local routes (wrap-routes base-routes opts.route-wrappers ctx state))
  (local active-route-entries (collect-active-route-entries routes))
  (local event-handlers {})
  (var entered? false)
  (local reusable-event {:consumed? false
                         :command-executed? false})

  (fn call-route [event-name payload]
    (local route (and routes (. routes event-name)))
    (if route
        (do
          (set reusable-event.consumed? false)
          (set reusable-event.command-executed? false)
          (local previous-event (ctx.begin-event reusable-event))
          (local route-result (route event-name ctx payload))
          (ctx.end-event previous-event)
          route-result)
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
  (set state.shift-held? Runtime.shift-held?)
  (set state.ctrl-held? Runtime.ctrl-held?)

  state)

State
