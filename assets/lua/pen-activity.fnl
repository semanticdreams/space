(fn PenActivity [opts]
  (local options (or opts {}))
  (local suppress-touch-when (or options.suppress-touch-when :down))
  (local suppression-timeout-ms (or options.suppression-timeout-ms 150))
  (local allow-touch-during-hover? (not (= options.allow-touch-during-hover? false)))
  (var pen-in-range? false)
  (var pen-down? false)
  (var last-event-timestamp nil)
  (var last-active-timestamp nil)

  (fn payload-timestamp [payload]
    (and payload payload.timestamp))

  (fn set-last-event! [payload]
    (local timestamp (payload-timestamp payload))
    (when timestamp
      (set last-event-timestamp timestamp))
    timestamp)

  (fn mark-active! [payload]
    (local timestamp (set-last-event! payload))
    (when timestamp
      (set last-active-timestamp timestamp))
    timestamp)

  (fn suppression-active? [timestamp]
    (if (= suppress-touch-when :proximity)
        (if pen-in-range?
            true
            (if (and last-active-timestamp
                     timestamp
                     (> suppression-timeout-ms 0))
                (<= (- timestamp last-active-timestamp) suppression-timeout-ms)
                false))
        (if pen-down?
            true
            (if (and last-active-timestamp
                     timestamp
                     (> suppression-timeout-ms 0))
                (<= (- timestamp last-active-timestamp) suppression-timeout-ms)
                false))))

  (fn on-pen-proximity-in [_self payload]
    (set pen-in-range? true)
    (set-last-event! payload)
    (when (= suppress-touch-when :proximity)
      (mark-active! payload))
    true)

  (fn on-pen-proximity-out [_self payload]
    (set pen-in-range? false)
    (set pen-down? false)
    (set-last-event! payload)
    (when (= suppress-touch-when :proximity)
      (mark-active! payload))
    true)

  (fn on-pen-motion [_self payload]
    (set pen-in-range? (not (= (and payload payload.in-range) false)))
    (set pen-down? (not (not (and payload payload.down))))
    (set-last-event! payload)
    (when (or (= suppress-touch-when :proximity) pen-down?)
      (mark-active! payload))
    true)

  (fn on-pen-down [_self payload]
    (set pen-in-range? true)
    (set pen-down? true)
    (mark-active! payload)
    true)

  (fn on-pen-up [_self payload]
    (set pen-in-range? (not (= (and payload payload.in-range) false)))
    (set pen-down? false)
    (mark-active! payload)
    true)

  (fn on-pen-button [_self payload]
    (set pen-in-range? (not (= (and payload payload.in-range) false)))
    (set pen-down? (not (not (and payload payload.down))))
    (set-last-event! payload)
    (when (or (= suppress-touch-when :proximity) pen-down?)
      (mark-active! payload))
    true)

  (fn on-pen-axis [_self payload]
    (set pen-in-range? (not (= (and payload payload.in-range) false)))
    (set pen-down? (not (not (and payload payload.down))))
    (set-last-event! payload)
    (when (or (= suppress-touch-when :proximity) pen-down?)
      (mark-active! payload))
    true)

  (fn pen-active? [_self timestamp]
    (suppression-active? (or timestamp last-event-timestamp last-active-timestamp)))

  (fn touch-allowed? [self payload]
    (local timestamp
      (or (payload-timestamp payload)
          last-event-timestamp
          last-active-timestamp))
    (if (not (self:pen-active? timestamp))
        true
        (if (and allow-touch-during-hover?
                 (= suppress-touch-when :down)
                 (not pen-down?))
            true
            false)))

  (fn reset [_self]
    (set pen-in-range? false)
    (set pen-down? false)
    (set last-event-timestamp nil)
    (set last-active-timestamp nil)
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
