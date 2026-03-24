(fn HeightfieldTargetCapture [opts]
  (local options (or opts {}))
  (local scene (assert (or options.scene app.scene)
                       "HeightfieldTargetCapture requires a scene"))
  (local terrain-id (assert options.terrain-id
                            "HeightfieldTargetCapture requires :terrain-id"))
  (local ray-opts options.ray-opts)
  (local on-target (or options.on-target (fn [_target _result] nil)))
  (local on-preview-target (or options.on-preview-target (fn [_target _result] nil)))
  (local on-invalid-target (or options.on-invalid-target (fn [] nil)))
  (local on-active-changed (or options.on-active-changed (fn [_active?] nil)))
  (var active? false)
  (var start-pos nil)
  (var last-valid-pos nil)
  (var start-hit nil)
  (var last-valid-hit nil)
  (var drag-active? false)
  (var pending-start? false)

  (fn terrain-hit [pos]
    (local hit (scene:screen-pos-terrain-domain-hit pos ray-opts))
    (if (and hit (= hit.terrain-id terrain-id))
        hit
        nil))

  (fn update-last-valid-hit! [pos]
    (local hit (terrain-hit pos))
    (when hit
      (set last-valid-hit hit)
      (set last-valid-pos pos))
    hit)

  (fn emit-preview-target! []
    (when (and start-pos last-valid-pos)
      (local result (scene:screen-drag-terrain-target start-pos last-valid-pos ray-opts))
      (when (and result (= result.terrain-id terrain-id))
        (on-preview-target result.target result))))

  (fn resolve-target! [end-pos]
    (local end-hit (terrain-hit end-pos))
    (local resolved-end-pos (if end-hit end-pos last-valid-pos))
    (local result
      (and start-pos
           resolved-end-pos
           (scene:screen-drag-terrain-target start-pos resolved-end-pos ray-opts)))
    (if (and result (= result.terrain-id terrain-id))
        (on-target result.target result)
        (on-invalid-target))
    (set start-pos nil)
    (set last-valid-pos nil)
    (set start-hit nil)
    (set last-valid-hit nil)
    (set drag-active? false)
    (set pending-start? false)
    (set active? false)
    (on-active-changed false))

  (fn finish []
    (when active?
      (set active? false)
      (set start-pos nil)
      (set last-valid-pos nil)
      (set start-hit nil)
      (set last-valid-hit nil)
      (set drag-active? false)
      (set pending-start? false)
      (on-active-changed false)))

  (fn begin-drag [pos]
    (local hit (terrain-hit pos))
    (set start-pos (and hit pos))
    (set last-valid-pos (and hit pos))
    (set start-hit hit)
    (set last-valid-hit hit)
    (set drag-active? (not (not hit)))
    (set pending-start? (not drag-active?))
    (when drag-active?
      (emit-preview-target!))
    drag-active?)

  (fn update-drag [pos]
    (if pending-start?
        (do
          (local hit (terrain-hit pos))
          (when hit
            (set start-pos pos)
            (set last-valid-pos pos)
            (set start-hit hit)
            (set last-valid-hit hit)
            (set drag-active? true)
            (set pending-start? false)
            (emit-preview-target!)))
        (when drag-active?
          (update-last-valid-hit! pos)
          (emit-preview-target!)))
    drag-active?)

  (fn end-drag [pos]
    (if drag-active?
        (resolve-target! pos)
        (do
          (set start-pos nil)
          (set last-valid-pos nil)
          (set start-hit nil)
          (set last-valid-hit nil)
          (set drag-active? false)
          (set pending-start? false)))
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
                       (set start-pos nil)
                       (set last-valid-pos nil)
                       (set start-hit nil)
                       (set last-valid-hit nil)
                       (set drag-active? false)
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
