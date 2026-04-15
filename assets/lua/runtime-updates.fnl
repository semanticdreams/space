(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn service-state []
  (if app.__runtime_updates
      app.__runtime_updates
      (do
        (set app.__runtime_updates {:next-id 1
                                    :callbacks {}
                                    :update-handler nil})
        app.__runtime_updates)))

(fn active-callback-count [state]
  (var count 0)
  (each [_ _callback (pairs state.callbacks)]
    (set count (+ count 1)))
  count)

(fn callback-ids [state]
  (var ids [])
  (each [id _callback (pairs state.callbacks)]
    (table.insert ids id))
  ids)

(fn disconnect-update-handler [state]
  (when (and state.update-handler
             app.engine
             app.engine.events
             app.engine.events.updated)
    (app.engine.events.updated:disconnect state.update-handler true)
    (set state.update-handler nil)))

(fn ensure-update-handler [state]
  (when (and (= (active-callback-count state) 0)
             state.update-handler)
    (disconnect-update-handler state))
  (when (and (> (active-callback-count state) 0)
             (not state.update-handler)
             app.engine
             app.engine.events
             app.engine.events.updated)
    (set state.update-handler
         (app.engine.events.updated:connect
           (fn [delta]
             (local elapsed
               (if (finite-number? delta)
                   (math.max delta 0)
                   0))
             (each [_ id (ipairs (callback-ids state))]
               (local registration (. state.callbacks id))
               (when registration
                 (registration.callback elapsed)))
             (when (= (active-callback-count state) 0)
               (disconnect-update-handler state)))))))

(fn register-callback [callback]
  (local state (service-state))
  (local id state.next-id)
  (set state.next-id (+ state.next-id 1))
  (set (. state.callbacks id) {:callback callback})
  (ensure-update-handler state)
  id)

(fn unregister-callback [id]
  (when id
    (local state (service-state))
    (set (. state.callbacks id) nil)
    (ensure-update-handler state)))

(fn FrameSubscription [opts]
  (local options (or opts {}))
  (local callback
    (assert options.callback "RuntimeUpdates.FrameSubscription requires :callback"))
  (var id nil)

  (fn cancel [_self]
    (when id
      (unregister-callback id)
      (set id nil))
    true)

  (fn start [_self]
    (when id
      (unregister-callback id))
    (set id (register-callback callback))
    true)

  {:start start
   :cancel cancel
   :drop cancel})

(fn clear []
  (local state (service-state))
  (set state.callbacks {})
  (disconnect-update-handler state)
  true)

{:FrameSubscription FrameSubscription
 :clear clear}
