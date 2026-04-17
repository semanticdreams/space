(fn PenActivity [opts]
  (local options (or opts {}))
  (local suppress-touch-when (or options.suppress-touch-when :down))
  (local suppression-timeout-ms (or options.suppression-timeout-ms 150))
  (local allow-touch-during-hover? (not (= options.allow-touch-during-hover? false)))
  (local pen-states {})

  (fn pen-id-from-payload [payload]
    (and payload payload.pen-id))

  (fn payload-timestamp [payload]
    (and payload payload.timestamp))

  (fn ensure-pen-state [payload]
    (local pen-id (pen-id-from-payload payload))
    (assert pen-id "PenActivity requires payload.pen-id")
    (if (. pen-states pen-id)
        (. pen-states pen-id)
        (do
          (local state {:in-range? false
                        :down? false
                        :last-event-timestamp nil
                        :last-active-timestamp nil})
          (set (. pen-states pen-id) state)
          state)))

  (fn set-last-event! [state payload]
    (local timestamp (payload-timestamp payload))
    (when timestamp
      (set state.last-event-timestamp timestamp))
    timestamp)

  (fn mark-active! [state payload]
    (local timestamp (set-last-event! state payload))
    (when timestamp
      (set state.last-active-timestamp timestamp))
    timestamp)

  (fn any-pen-matches? [predicate]
    (var matched? false)
    (each [_ state (pairs pen-states)]
      (when (predicate state)
        (set matched? true)))
    matched?)

  (fn most-recent-timestamp []
    (var timestamp nil)
    (each [_ state (pairs pen-states)]
      (when (and state.last-event-timestamp
                 (or (= timestamp nil)
                     (> state.last-event-timestamp timestamp)))
        (set timestamp state.last-event-timestamp))
      (when (and state.last-active-timestamp
                 (or (= timestamp nil)
                     (> state.last-active-timestamp timestamp)))
        (set timestamp state.last-active-timestamp)))
    timestamp)

  (fn suppression-active? [timestamp]
    (if (= suppress-touch-when :proximity)
        (if (any-pen-matches? (fn [state] state.in-range?))
            true
            (any-pen-matches?
              (fn [state]
                (and state.last-active-timestamp
                     timestamp
                     (> suppression-timeout-ms 0)
                     (<= (- timestamp state.last-active-timestamp) suppression-timeout-ms)))))
        (if (any-pen-matches? (fn [state] state.down?))
            true
            (any-pen-matches?
              (fn [state]
                (and state.last-active-timestamp
                     timestamp
                     (> suppression-timeout-ms 0)
                     (<= (- timestamp state.last-active-timestamp) suppression-timeout-ms)))))))

  (fn on-pen-proximity-in [_self payload]
    (local state (ensure-pen-state payload))
    (set state.in-range? true)
    (set-last-event! state payload)
    (when (= suppress-touch-when :proximity)
      (mark-active! state payload))
    true)

  (fn on-pen-proximity-out [_self payload]
    (local state (ensure-pen-state payload))
    (set state.in-range? false)
    (set state.down? false)
    (set-last-event! state payload)
    (when (= suppress-touch-when :proximity)
      (mark-active! state payload))
    true)

  (fn on-pen-motion [_self payload]
    (local state (ensure-pen-state payload))
    (set state.in-range? (not (= (and payload payload.in-range) false)))
    (set state.down? (not (not (and payload payload.down))))
    (set-last-event! state payload)
    (when (or (= suppress-touch-when :proximity) state.down?)
      (mark-active! state payload))
    true)

  (fn on-pen-down [_self payload]
    (local state (ensure-pen-state payload))
    (set state.in-range? true)
    (set state.down? true)
    (mark-active! state payload)
    true)

  (fn on-pen-up [_self payload]
    (local state (ensure-pen-state payload))
    (set state.in-range? (not (= (and payload payload.in-range) false)))
    (set state.down? false)
    (mark-active! state payload)
    true)

  (fn on-pen-button [_self payload]
    (local state (ensure-pen-state payload))
    (set state.in-range? (not (= (and payload payload.in-range) false)))
    (set state.down? (not (not (and payload payload.down))))
    (set-last-event! state payload)
    (when (or (= suppress-touch-when :proximity) state.down?)
      (mark-active! state payload))
    true)

  (fn on-pen-axis [_self payload]
    (local state (ensure-pen-state payload))
    (set state.in-range? (not (= (and payload payload.in-range) false)))
    (set state.down? (not (not (and payload payload.down))))
    (set-last-event! state payload)
    (when (or (= suppress-touch-when :proximity) state.down?)
      (mark-active! state payload))
    true)

  (fn pen-active? [_self timestamp]
    (suppression-active? (or timestamp (most-recent-timestamp))))

  (fn touch-allowed? [self payload]
    (local timestamp
      (or (payload-timestamp payload)
          (most-recent-timestamp)))
    (if (not (self:pen-active? timestamp))
        true
        (if (and allow-touch-during-hover?
                 (= suppress-touch-when :down)
                 (not (any-pen-matches? (fn [state] state.down?))))
            true
            false)))

  (fn reset [_self]
    (each [pen-id _ (pairs pen-states)]
      (set (. pen-states pen-id) nil))
    true)

  {:on-pen-proximity-in on-pen-proximity-in
   :on-pen-proximity-out on-pen-proximity-out
   :on-pen-motion on-pen-motion
   :on-pen-down on-pen-down
   :on-pen-up on-pen-up
   :on-pen-button on-pen-button
   :on-pen-axis on-pen-axis
   :pen-active? pen-active?
   :touch-allowed? touch-allowed?
   :reset reset})

PenActivity
