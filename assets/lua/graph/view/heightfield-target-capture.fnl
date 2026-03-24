(local TerrainQuery (require :terrain-query))


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
      (set last-valid-hit hit))
    hit)

  (fn emit-preview-target! []
    (when (and start-hit last-valid-hit)
      (local record start-hit.terrain-record)
      (local target
        (and record
             (TerrainQuery.target-between-hits record start-hit last-valid-hit)))
      (when target
        (on-preview-target target {:terrain-record record
                                   :terrain-id start-hit.terrain-id
                                   :terrain-kind start-hit.terrain-kind
                                   :start-hit start-hit
                                   :end-hit last-valid-hit
                                   :target target}))))

  (fn resolve-target! [end-pos]
    (local resolved-start-hit (or start-hit (terrain-hit end-pos)))
    (local resolved-end-hit (or last-valid-hit (terrain-hit end-pos)))
    (if (and resolved-start-hit
             resolved-end-hit
             (= resolved-start-hit.terrain-id resolved-end-hit.terrain-id)
             (= resolved-start-hit.terrain-kind resolved-end-hit.terrain-kind))
        (do
          (local record resolved-start-hit.terrain-record)
          (local target
            (and record
                 (TerrainQuery.target-between-hits
                   record
                   resolved-start-hit
                   resolved-end-hit)))
          (if target
              (do
                (on-target target {:terrain-record record
                                 :terrain-id resolved-start-hit.terrain-id
                                 :terrain-kind resolved-start-hit.terrain-kind
                                 :start-hit resolved-start-hit
                                 :end-hit resolved-end-hit
                                 :target target}))
              (do
                (on-invalid-target))))
        (do
          (on-invalid-target)))
    (set start-hit nil)
    (set last-valid-hit nil)
    (set drag-active? false)
    (set pending-start? false)
    (set active? false)
    (on-active-changed false))

  (fn finish []
    (when active?
      (set active? false)
      (set start-hit nil)
      (set last-valid-hit nil)
      (set drag-active? false)
      (set pending-start? false)
      (on-active-changed false)))

  (fn begin-drag [pos]
    (local hit (terrain-hit pos))
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
