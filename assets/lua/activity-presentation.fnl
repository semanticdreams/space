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

  (fn provider.input-controls [self]
    (if (and app app.canvas-interactive?)
        runtime.canvas-controls
        runtime.first-person-controls))

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
