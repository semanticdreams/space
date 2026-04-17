(fn PenToolOverrideHandlers [opts]
  (local options (or opts {}))
  (local active? (or options.active? (fn [] true)))
  (local get-tool (assert options.get-tool
                          "PenToolOverrideHandlers requires :get-tool"))
  (local set-tool (assert options.set-tool
                          "PenToolOverrideHandlers requires :set-tool"))
  (local override-tool (or options.override-tool "eraser"))
  (var saved-tool nil)
  (var override-active? false)

  (fn eraser-active? [payload]
    (not (not (and payload payload.eraser))))

  (fn apply-payload! [payload]
    (if (not (active?))
        false
        (if (eraser-active? payload)
            (if override-active?
                true
                (do
                  (set saved-tool (get-tool))
                  (when (not (= saved-tool override-tool))
                    (set-tool override-tool))
                  (set override-active? true)
                  true))
            (if override-active?
                (do
                  (when saved-tool
                    (set-tool saved-tool))
                  (set saved-tool nil)
                  (set override-active? false)
                  true)
                false))))

  (fn reset-override! []
    (when override-active?
      (when saved-tool
        (set-tool saved-tool))
      (set saved-tool nil)
      (set override-active? false))
    true)

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
