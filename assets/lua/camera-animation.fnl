;; CameraAnimation — minimal scalar smoothing channel.
;; Provides exponential-decay approach with clamping and snap-at-epsilon.
(local CameraAnimation {})

(local snap-epsilon 1e-5)

(fn clamp [value min-value max-value]
  (if (< value min-value) min-value
      (> value max-value) max-value
      value))

(fn CameraAnimation.scalar-channel [opts]
  (local options (or opts {}))
  (when (not (= (type options.value) :number))
    (error (.. "scalar-channel :value must be a number, got "
               (tostring (type options.value))
               ": " (tostring options.value))))
  (when (not (= (type options.target) :number))
    (error (.. "scalar-channel :target must be a number, got "
               (tostring (type options.target))
               ": " (tostring options.target))))
  (when (not (= (type options.smoothing-rate) :number))
    (error (.. "scalar-channel :smoothing-rate must be a number, got "
               (tostring (type options.smoothing-rate))
               ": " (tostring options.smoothing-rate))))
  (var value options.value)
  (var target options.target)
  (var smoothing-rate options.smoothing-rate)

  (fn value-fn [self]
    value)

  (fn set-target [self new-target]
    (when (not (= (type new-target) :number))
      (error (.. "set-target expects a number, got "
                 (tostring (type new-target))
                 ": " (tostring new-target))))
    (set target new-target)
    true)

  (fn snap [self new-value]
    (when (not (= (type new-value) :number))
      (error (.. "snap expects a number, got "
                 (tostring (type new-value))
                 ": " (tostring new-value))))
    (set value new-value)
    (set target new-value)
    true)

  (fn update [self delta-seconds]
    (when (not (= (type delta-seconds) :number))
      (error (.. "update expects a number for delta-seconds, got "
                 (tostring (type delta-seconds))
                 ": " (tostring delta-seconds))))
    (local distance (- target value))
    (if (< (math.abs distance) snap-epsilon)
        (do
          (set value target)
          value)
        (do
          (local alpha (clamp (- 1 (math.exp (* -1 smoothing-rate delta-seconds)))
                              0.0 1.0))
          (set value (+ value (* distance alpha)))
          ;; Double-check after update: snap if within epsilon
          (if (< (math.abs (- target value)) snap-epsilon)
              (set value target))
          value)))

  (local channel
    {:value value-fn
     :set-target set-target
     :snap snap
     :update update})

  channel)

CameraAnimation
