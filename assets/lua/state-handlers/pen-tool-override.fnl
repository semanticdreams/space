(fn PenToolOverrideHandlers [opts]
  (local options (or opts {}))
  (local active? (or options.active? (fn [] true)))
  (local get-tool (assert options.get-tool
                          "PenToolOverrideHandlers requires :get-tool"))
  (local set-tool (assert options.set-tool
                          "PenToolOverrideHandlers requires :set-tool"))
  (local override-tool (or options.override-tool "eraser"))
  (var saved-tool nil)
  (local eraser-pens {})

  (fn eraser-active? [payload]
    (not (not (and payload payload.eraser))))

  (fn pen-id [payload]
    (and payload (rawget payload "pen-id")))

  (fn any-eraser-pen-active? []
    (var active? false)
    (each [_ pen-active? (pairs eraser-pens)]
      (when pen-active?
        (set active? true)))
    active?)

  (fn override-active? []
    (not (= saved-tool nil)))

  (fn reset-override! []
    (when (override-active?)
      (when saved-tool
        (set-tool saved-tool))
      (set saved-tool nil))
    (each [current-pen-id _ (pairs eraser-pens)]
      (set (. eraser-pens current-pen-id) nil))
    true)

  (fn sync-override! []
    (if (not (active?))
        (reset-override!)
        (if (any-eraser-pen-active?)
            (if (override-active?)
                true
                (do
                  (set saved-tool (get-tool))
                  (when (not (= saved-tool override-tool))
                    (set-tool override-tool))
                  true))
            (reset-override!))))

  (fn apply-payload! [payload]
    (local current-pen-id (pen-id payload))
    (when current-pen-id
      (set (. eraser-pens current-pen-id) (eraser-active? payload)))
    (sync-override!))

  (local PenToolOverride
    {:pen-proximity-in (fn [_ctx payload]
                         (apply-payload! payload))
     :pen-proximity-out (fn [_ctx payload]
                          (apply-payload! payload))
     :pen-motion (fn [_ctx payload]
                   (apply-payload! payload))
     :pen-down (fn [_ctx payload]
                 (apply-payload! payload))
     :pen-up (fn [_ctx payload]
               (apply-payload! payload))
     :pen-button-down (fn [_ctx payload]
                        (apply-payload! payload))
     :pen-button-up (fn [_ctx payload]
                      (apply-payload! payload))
     :pen-axis (fn [_ctx payload]
                 (apply-payload! payload))
     :enter (fn [_ctx]
              (reset-override!))
     :leave (fn [_ctx]
              (reset-override!))})

  {:PenToolOverride PenToolOverride})

{:PenToolOverrideHandlers PenToolOverrideHandlers}
