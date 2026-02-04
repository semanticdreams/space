(local table table)
(local rawget rawget)
(local rawset rawset)
(local logging (require :logging))

(fn now-ms []
  (* (os.clock) 1000.0))

(fn FrameProfiler [opts]
  (local options (or opts {}))
  (var enabled (if (= options.enabled nil) true options.enabled))
  (var threshold-ms (or options.threshold-ms 20.0))
  (var log-interval (or options.log-interval options.sample-frames 240))
  (local log-fn
    (or options.log-fn
        (fn [fields message]
          (logging.info fields (or message "")))))
  (local section-order (or options.section-order ["events" "scene" "hud" "renderers" "other"]))
  (var frame-start nil)
  (var frame-dt 0)
  (var recorded {})
  (var frames-since-log 0)

  (fn begin-frame [dt]
    (when enabled
      (set frame-dt dt)
      (set frame-start (now-ms))
      (set recorded {})
      (set frames-since-log (+ frames-since-log 1))))

  (fn measure [label thunk]
    (if enabled
        (let [start (now-ms)]
          (local result (thunk))
          (local elapsed (- (now-ms) start))
          (rawset recorded label (+ (or (rawget recorded label) 0) elapsed))
          result)
        (thunk)))

  (fn log-frame [total-ms]
    (local fields {:event "frame_profile"
                   :dt_ms frame-dt
                   :total_ms total-ms})
    (local seen {})
    (each [_ label (ipairs section-order)]
      (local duration (rawget recorded label))
      (when duration
        (tset fields label duration)
        (tset seen label true)))
    (each [label duration (pairs recorded)]
      (when (not (rawget seen label))
        (tset fields label duration)))
    (log-fn fields "frame profile"))

  (fn end-frame []
    (when (and enabled frame-start)
      (local total (- (now-ms) frame-start))
      (var accounted 0.0)
      (each [_ duration (pairs recorded)]
        (set accounted (+ accounted duration)))
      (local other (math.max (- total accounted) 0))
      (when (> other 0.01)
        (rawset recorded "other" (+ (or (rawget recorded "other") 0) other)))
      (local threshold-hit (and threshold-ms (> total threshold-ms)))
      (local interval-hit (and log-interval (> log-interval 0)
                               (>= frames-since-log log-interval)))
      (when (or threshold-hit interval-hit)
        (log-frame total)
        (set frames-since-log 0))
      (set frame-start nil)))

  (fn set-enabled [value]
    (set enabled (not (= value false)))
    (when (not enabled)
      (set recorded {})
      (set frame-start nil)
      (set frames-since-log 0)))

  {:begin-frame begin-frame
   :measure measure
   :end-frame end-frame
   :set_enabled set-enabled
   :enabled? (fn [] enabled)
   :set_threshold (fn [ms] (set threshold-ms ms))
   :set_log_interval (fn [frames] (set log-interval frames))})

FrameProfiler
