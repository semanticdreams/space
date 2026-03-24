(fn HeightfieldPaintCapture [opts]
  (local options (or opts {}))
  (local scene (assert (or options.scene app.scene)
                       "HeightfieldPaintCapture requires a scene"))
  (local terrain-id (assert options.terrain-id
                            "HeightfieldPaintCapture requires :terrain-id"))
  (local ray-opts options.ray-opts)
  (local on-stamp-batch (or options.on-stamp-batch (fn [_targets _hit] nil)))
  (local on-invalid-target (or options.on-invalid-target (fn [] nil)))
  (local on-active-changed (or options.on-active-changed (fn [_active?] nil)))
  (var active? false)
  (var stroke-active? false)
  (var pending-start? false)
  (var last-target-key nil)
  (var last-target nil)
  (var visited-keys {})

  (fn target-key [target]
    (and target
         (.. (tostring target.mode) ":"
             (tostring target.x0) ":"
             (tostring target.z0) ":"
             (tostring target.x1) ":"
             (tostring target.z1))))

  (fn single-sample-target [x z]
    {:mode :samples
     :shape :rect
     :x0 x
     :z0 z
     :x1 x
     :z1 z
     :sample-count 1
     :width 1
     :length 1})

  (fn bresenham-targets [from-target to-target]
    (local x0 from-target.x0)
    (local z0 from-target.z0)
    (local x1 to-target.x0)
    (local z1 to-target.z0)
    (local dx (math.abs (- x1 x0)))
    (local sx (if (< x0 x1) 1 -1))
    (local dz (- (math.abs (- z1 z0))))
    (local sz (if (< z0 z1) 1 -1))
    (var err (+ dx dz))
    (var x x0)
    (var z z0)
    (var done? false)
    (local targets [])
    (while (not done?)
      (table.insert targets (single-sample-target x z))
      (when (and (= x x1) (= z z1))
        (set done? true))
      (when (not done?)
        (local e2 (* 2 err))
        (when (>= e2 dz)
          (set err (+ err dz))
          (set x (+ x sx)))
        (when (<= e2 dx)
          (set err (+ err dx))
          (set z (+ z sz)))))
    targets)

  (fn reset-stroke-state []
    (set last-target-key nil)
    (set last-target nil)
    (set visited-keys {})
    (set stroke-active? false)
    (set pending-start? false))

  (fn flush-targets [targets hit]
    (local fresh [])
    (each [_ target (ipairs (or targets []))]
      (local key (target-key target))
      (when (and key (not (. visited-keys key)))
        (set (. visited-keys key) true)
        (table.insert fresh target)))
    (when (> (length fresh) 0)
      (on-stamp-batch fresh hit)))

  (fn maybe-stamp [point]
    (local hit (scene:screen-pos-terrain-domain-hit point ray-opts))
    (if (and hit (= hit.terrain-id terrain-id))
        (do
          (local current-target hit.target)
          (local current-key (target-key current-target))
          (when (and current-key (not (= current-key last-target-key)))
            (local targets
              (if last-target
                  (bresenham-targets last-target current-target)
                  [current-target]))
            (flush-targets targets hit)
            (set last-target current-target)
            (set last-target-key current-key))
          true)
        (do
          (on-invalid-target)
          false)))

  (fn finish []
    (when active?
      (reset-stroke-state)
      (set active? false)
      (on-active-changed false)))

  (fn begin-stroke [point]
    (set stroke-active? (maybe-stamp point))
    (set pending-start? (not stroke-active?))
    stroke-active?)

  (fn update-stroke [point]
    (if pending-start?
        (when (maybe-stamp point)
          (set stroke-active? true)
          (set pending-start? false))
        (when stroke-active?
          (maybe-stamp point)))
    stroke-active?)

  (fn end-stroke [_point]
    (set stroke-active? false)
    (set pending-start? false)
    (finish)
    true)

  {:active? (fn [_self] active?)
   :begin (fn [_self]
            (when (not active?)
              (reset-stroke-state)
              (set active? true)
              (on-active-changed true))
            true)
   :finish (fn [_self]
             (finish))
   :cancel-selection (fn [_self]
                       (finish))
   :begin-stroke (fn [_self point]
                   (begin-stroke point))
   :update-stroke (fn [_self point]
                    (update-stroke point))
   :end-stroke (fn [_self point]
                 (end-stroke point))
   :on-key-down (fn [self payload]
                  (when (and active? (= payload.key 27))
                    (self:cancel-selection)))
   :drop (fn [self]
           (self:cancel-selection))})

HeightfieldPaintCapture
