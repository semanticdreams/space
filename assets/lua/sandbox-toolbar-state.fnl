(local Signal (require :signal))

(local valid-interaction-modes {:flight true
                                :walk true
                                :move true
                                :grab true})

(fn assert-valid-interaction-mode [mode]
  (when (not (. valid-interaction-modes mode))
    (error (.. "Invalid interaction mode: " (tostring mode))))
  mode)

(fn assert-canonical-options [options]
  (each [key _ (pairs options)]
    (when (not (= key :interaction-mode))
      (error (.. "Invalid SandboxToolbarState option: " (tostring key))))))

(fn legacy-payload-mode [payload]
  (when (and (not (= payload.object-move-enabled? nil))
             (not (= (type payload.object-move-enabled?) :boolean)))
    (error (.. "object-move-enabled? must be boolean in restore payload, got "
               (tostring (type payload.object-move-enabled?))
               ": " (tostring payload.object-move-enabled?))))
  (when (and (not (= payload.drag-attachment nil))
             (not (= payload.drag-attachment "center"))
             (not (= payload.drag-attachment "anchor")))
    (error (.. "Invalid drag-attachment in restore payload: "
               (tostring payload.drag-attachment))))
  (when (and (not (= payload.camera-mode nil))
             (not (= payload.camera-mode "flight"))
             (not (= payload.camera-mode "grounded")))
    (error (.. "Invalid camera-mode in restore payload: "
               (tostring payload.camera-mode))))
  (if (= payload.object-move-enabled? true)
      (if (= payload.drag-attachment "anchor")
          :grab
          :move)
      (= payload.camera-mode "grounded")
      :walk
      :flight))

(fn SandboxToolbarState [opts]
  (local options (if (= opts nil) {} opts))
  (when (not (= (type options) :table))
    (error (.. "SandboxToolbarState opts must be a table or nil, got " (type options))))
  (assert-canonical-options options)
  (var interaction-mode
    (assert-valid-interaction-mode
      (if (= options.interaction-mode nil) :flight options.interaction-mode)))
  (local changed (Signal))

  (fn set-interaction-mode [self mode]
    (assert-valid-interaction-mode mode)
    (when (not (= interaction-mode mode))
      (set interaction-mode mode)
      (changed:emit mode))
    mode)

  (fn navigation-mode [self]
    (if (= interaction-mode :flight)
        interaction-mode
        (= interaction-mode :walk)
        interaction-mode
        nil))

  (fn object-drag-mode [self]
    (if (= interaction-mode :move)
        interaction-mode
        (= interaction-mode :grab)
        interaction-mode
        nil))

  (fn capture-state [self]
    {:interaction-mode (tostring interaction-mode)})

  (fn restore-state [self payload]
    (when (not (= payload nil))
      (when (not (= (type payload) :table))
        (error (.. "restore-state payload must be a table or nil, got " (type payload))))
      (self:set-interaction-mode
        (if (not (= payload.interaction-mode nil))
            (assert-valid-interaction-mode payload.interaction-mode)
            (legacy-payload-mode payload))))
    true)

  (local state
    {: changed
     : set-interaction-mode
     : navigation-mode
     : object-drag-mode
     : capture-state
     : restore-state})

  (fn state-index [self key]
    (if (= key :interaction-mode) interaction-mode))

  (setmetatable state {:__index state-index})
  state)

SandboxToolbarState
