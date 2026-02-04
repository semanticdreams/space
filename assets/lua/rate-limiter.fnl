(local math math)

(fn now-ms []
  (* (os.clock) 1000.0))

(fn RateLimiter [opts]
  (assert opts "RateLimiter expects options")
  (local limit opts.limit)
  (assert (and limit (> limit 0)) "RateLimiter requires :limit > 0")
  (local window-ms (or opts.window_ms 1000))
  (var timestamps [])

  (fn prune [now]
    (while (and (> (# timestamps) 0)
                (> (- now (. timestamps 1)) window-ms))
      (table.remove timestamps 1)))

  (fn acquire []
    (local now (now-ms))
    (prune now)
    (if (< (# timestamps) limit)
        (do
          (table.insert timestamps now)
          0)
        (do
          (local earliest (. timestamps 1))
          (local target (+ earliest window-ms))
          (local delay (math.max 0 (- target now)))
          (table.insert timestamps (+ now delay))
          delay)))

  (fn reset []
    (set timestamps []))

  {:acquire acquire
   :reset reset
   :window_ms (fn [] window-ms)
   :limit (fn [] limit)})

RateLimiter
