(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn service-state []
  (if app.__runtime_timers
      app.__runtime_timers
      (do
        (set app.__runtime_timers {:next-id 1
                                   :timers {}
                                   :update-handler nil})
        app.__runtime_timers)))

(fn active-timer-count [state]
  (var count 0)
  (each [_ _timer (pairs state.timers)]
    (set count (+ count 1)))
  count)

(fn disconnect-update-handler [state]
  (when (and state.update-handler
             app.engine
             app.engine.events
             app.engine.events.updated)
    (app.engine.events.updated:disconnect state.update-handler true)
    (set state.update-handler nil)))

(fn ensure-update-handler [state]
  (when (and (= (active-timer-count state) 0)
             state.update-handler)
    (disconnect-update-handler state))
  (when (and (> (active-timer-count state) 0)
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
             (local finished [])
             (each [id timer (pairs state.timers)]
               (if (= timer.kind :interval)
                   (do
                     (set timer.remaining_ms (- timer.remaining_ms elapsed))
                     (while (<= timer.remaining_ms 0)
                       (timer.callback)
                       (set timer.remaining_ms (+ timer.remaining_ms timer.interval_ms))))
                   (do
                     (set timer.remaining_ms (- timer.remaining_ms elapsed))
                     (when (<= timer.remaining_ms 0)
                       (timer.callback)
                       (table.insert finished id)))))
             (each [_ id (ipairs finished)]
               (set (. state.timers id) nil))
             (when (= (active-timer-count state) 0)
               (disconnect-update-handler state)))))))

(fn register-timer [timer]
  (local state (service-state))
  (local id state.next-id)
  (set state.next-id (+ state.next-id 1))
  (set timer.id id)
  (set (. state.timers id) timer)
  (ensure-update-handler state)
  id)

(fn unregister-timer [id]
  (when id
    (local state (service-state))
    (set (. state.timers id) nil)
    (ensure-update-handler state)))

(fn Timeout [opts]
  (local options (or opts {}))
  (local delay_ms
    (if (and (finite-number? options.delay-ms)
             (>= options.delay-ms 0))
        options.delay-ms
        0))
  (local callback
    (assert options.callback "RuntimeTimers.Timeout requires :callback"))
  (var id nil)

  (fn cancel [_self]
    (when id
      (unregister-timer id)
      (set id nil))
    true)

  (fn start [_self]
    (when id
      (unregister-timer id))
    (set id
         (register-timer {:kind :timeout
                          :remaining_ms delay_ms
                          :callback (fn []
                                      (set id nil)
                                      (callback))}))
    true)

  {:start start
   :cancel cancel
   :drop cancel})

(fn Interval [opts]
  (local options (or opts {}))
  (assert (and (finite-number? options.interval-ms)
               (> options.interval-ms 0))
          "RuntimeTimers.Interval requires positive :interval-ms")
  (local interval_ms options.interval-ms)
  (local callback
    (assert options.callback "RuntimeTimers.Interval requires :callback"))
  (var id nil)

  (fn cancel [_self]
    (when id
      (unregister-timer id)
      (set id nil))
    true)

  (fn start [_self]
    (when id
      (unregister-timer id))
    (set id
         (register-timer {:kind :interval
                          :remaining_ms interval_ms
                          :interval_ms interval_ms
                          :callback callback}))
    true)

  {:start start
   :cancel cancel
   :drop cancel})

(fn Debouncer [opts]
  (local options (or opts {}))
  (var delay_ms
    (if (and (finite-number? options.delay-ms)
             (>= options.delay-ms 0))
        options.delay-ms
        0))
  (local callback
    (assert options.callback "RuntimeTimers.Debouncer requires :callback"))
  (var id nil)
  (var last-payload nil)

  (fn cancel [_self]
    (when id
      (unregister-timer id)
      (set id nil))
    true)

  (fn set-delay-ms [_self next-delay_ms]
    (assert (and (finite-number? next-delay_ms)
                 (>= next-delay_ms 0))
            "RuntimeTimers.Debouncer.set-delay-ms requires non-negative number")
    (set delay_ms next-delay_ms)
    true)

  (fn trigger [_self payload]
    (set last-payload payload)
    (if (<= delay_ms 0)
        (do
          (cancel nil)
          (callback last-payload))
        (do
          (when id
            (unregister-timer id))
          (set id
               (register-timer {:kind :timeout
                                :remaining_ms delay_ms
                                :callback (fn []
                                            (local payload-to-send last-payload)
                                            (set id nil)
                                            (callback payload-to-send))}))))
    true)

  {:trigger trigger
   :set-delay-ms set-delay-ms
   :cancel cancel
   :drop cancel})

(fn clear []
  (local state (service-state))
  (set state.timers {})
  (disconnect-update-handler state)
  true)

{:Timeout Timeout
 :Interval Interval
 :Debouncer Debouncer
 :clear clear}
