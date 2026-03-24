(fn HeightfieldTargetCapture [opts]
  (local options (or opts {}))
  (local scene (assert (or options.scene app.scene)
                       "HeightfieldTargetCapture requires a scene"))
  (local terrain-id (assert options.terrain-id
                            "HeightfieldTargetCapture requires :terrain-id"))
  (local ray-opts options.ray-opts)
  (local on-target (or options.on-target (fn [_target _result] nil)))
  (local on-target-updated (or options.on-target-updated (fn [_target _result] nil)))
  (local on-invalid-target (or options.on-invalid-target (fn [] nil)))
  (local on-drag-began (or options.on-drag-began (fn [] nil)))
  (local on-canceled (or options.on-canceled (fn [] nil)))
  (local on-active-changed (or options.on-active-changed (fn [_active?] nil)))
  (var active? false)
  (var start-pos nil)
  (var last-pos nil)
  (var drag-active? false)

  (fn reset-drag-state []
    (set start-pos nil)
    (set last-pos nil)
    (set drag-active? false))

  (fn target-result [end-pos]
    (and start-pos
         end-pos
         (scene:screen-rect-terrain-target terrain-id start-pos end-pos ray-opts)))

  (fn emit-target-updated! []
    (when (and start-pos last-pos)
      (local result (target-result last-pos))
      (if result
          (on-target-updated result.target result)
          (on-target-updated nil nil))))

  (fn resolve-target! []
    (local result (target-result last-pos))
    (if result
        (on-target result.target result)
        (on-invalid-target))
    (reset-drag-state)
    (set active? false)
    (on-active-changed false))

  (fn finish []
    (when active?
      (set active? false)
      (reset-drag-state)
      (on-active-changed false)))

  (fn begin-drag [pos]
    (on-drag-began)
    (set start-pos pos)
    (set last-pos pos)
    (set drag-active? true)
    drag-active?)

  (fn update-drag [pos]
    (when drag-active?
      (set last-pos pos)
      (emit-target-updated!))
    drag-active?)

  (fn end-drag [pos]
    (if drag-active?
        (do
          (when (and (not last-pos) pos)
            (set last-pos pos))
          (resolve-target!))
        (reset-drag-state))
    true)

  {:active? (fn [_self] active?)
   :drag-active? (fn [_self] drag-active?)
   :hud (or options.hud app.hud)
   :begin (fn [_self]
            (when (not active?)
              (set active? true)
              (on-active-changed true))
            true)
   :finish (fn [_self]
             (finish))
   :cancel-selection (fn [_self]
                       (reset-drag-state)
                       (on-canceled)
                       (finish))
   :begin-drag (fn [_self pos]
                 (begin-drag pos))
   :update-drag (fn [_self pos]
                  (update-drag pos))
   :end-drag (fn [_self pos]
               (end-drag pos))
   :on-key-down (fn [self payload]
                  (when (and active? (= payload.key 27))
                    (self:cancel-selection)))
   :drop (fn [self]
           (self:cancel-selection))})

HeightfieldTargetCapture
