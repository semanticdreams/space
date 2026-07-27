(local Presentation {})

(fn Presentation.for-runtime [runtime]
  (local provider {})

  (fn provider.render-targets [self]
    (local targets [])
    ;; Scene target
    (when (and runtime runtime.scene runtime.scene.presentation-target)
      (let [target (runtime.scene:presentation-target)]
        (when target
          (table.insert targets target))))
    ;; Canvas target
    (when (and runtime runtime.canvas runtime.canvas.presentation-target)
      (let [target (runtime.canvas:presentation-target)]
        (when target
          (table.insert targets target))))
    targets)

  (fn provider.default-screen-ray-target [self opts]
    (local options (or opts {}))
    (or (when options.target
          options.target)
        (when options.surface
          (if (= options.surface :scene)
              (when (and runtime runtime.scene runtime.scene.presentation-target)
                (runtime.scene:presentation-target))
              (= options.surface :canvas)
              (when (and runtime runtime.canvas runtime.canvas.presentation-target)
                (runtime.canvas:presentation-target))))
        (let [active-surface (and app app.active-interaction-surface)]
          (when active-surface
            (if (or (= active-surface :scene) (= active-surface "scene"))
                (when (and runtime runtime.scene runtime.scene.presentation-target)
                  (runtime.scene:presentation-target))
                (or (= active-surface :canvas) (= active-surface "canvas"))
                (when (and runtime runtime.canvas runtime.canvas.presentation-target)
                  (runtime.canvas:presentation-target)))))))

  (fn provider.screen-pos-ray [self pos opts]
    (local target (or (and opts opts.target)
                      (self:default-screen-ray-target opts)))
    (assert target "screen ray target is required: no render target with a camera is available")
    (assert target.screen-pos-ray
            "screen ray target does not support screen-pos-ray")
    (target:screen-pos-ray pos opts))

  (fn resolve-active-slot-controls [surface-key]
    "Return the controls stored for the currently active slot on the given surface."
    (let [surface (and runtime runtime.activity-controls (. runtime.activity-controls surface-key))]
      (when surface
        (let [slot-id (if (= surface-key :scene)
                         (and runtime runtime.scene runtime.scene.active-activity-slot-id)
                         (and runtime runtime.canvas runtime.canvas.active-activity-slot-id))]
          (when slot-id
            (. surface slot-id))))))

  (fn provider.input-controls [self]
    (if (and app app.canvas-interactive?)
        (or (resolve-active-slot-controls :canvas)
            runtime.canvas-controls)
        (or (resolve-active-slot-controls :scene)
            runtime.first-person-controls)))

  (fn provider.camera [self opts]
    (local options (or opts {}))
    (local target (self:default-screen-ray-target options))
    (if (and target target.camera)
        target.camera
        options.required?
        (error "presentation camera not available: no render target with a camera is available")
        nil))

  (fn provider.audio-listener-camera [self]
    (self:camera {:required? false}))

  (fn provider.update [self delta]
    true)

  provider)

Presentation
