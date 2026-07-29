(local Signal (require :signal))

(local valid-camera-modes {:flight true :grounded true})
(local valid-drag-attachments {:center true :anchor true})

(fn SandboxToolbarState [opts]
  (local options (or opts {}))
  (var camera-mode (or options.camera-mode :flight))
  (var object-move-enabled? (= options.object-move-enabled? true))
  (var drag-attachment (or options.drag-attachment :center))

  (when (not (. valid-camera-modes camera-mode))
    (error (.. "Invalid camera mode: " (tostring camera-mode))))
  (when (not (. valid-drag-attachments drag-attachment))
    (error (.. "Invalid drag attachment: " (tostring drag-attachment))))

  (local changed (Signal))

  (fn set-camera-mode [self mode]
    (when (not (. valid-camera-modes mode))
      (error (.. "Invalid camera mode: " (tostring mode))))
    (when (not (= camera-mode mode))
      (set camera-mode mode)
      (changed:emit mode))
    mode)

  (fn toggle-camera-mode [self]
    (self:set-camera-mode (if (= camera-mode :flight)
                              :grounded
                              :flight)))

  (fn set-object-move-enabled! [self enabled?]
    (when (not (= (type enabled?) :boolean))
      (error (.. "object-move-enabled? must be boolean, got " (tostring (type enabled?)) ": " (tostring enabled?))))
    (when (not (= object-move-enabled? enabled?))
      (set object-move-enabled? enabled?)
      (changed:emit enabled?))
    enabled?)

  (fn toggle-object-move-enabled! [self]
    (self:set-object-move-enabled! (not object-move-enabled?)))

  (fn set-drag-attachment [self mode]
    (when (not (. valid-drag-attachments mode))
      (error (.. "Invalid drag attachment: " (tostring mode))))
    (when (not (= drag-attachment mode))
      (set drag-attachment mode)
      (changed:emit mode))
    mode)

  (fn toggle-drag-attachment [self]
    (self:set-drag-attachment (if (= drag-attachment :center)
                                  :anchor
                                  :center)))

  (fn capture-state [self]
    {:camera-mode (if (= camera-mode :flight) "flight" "grounded")
     :object-move-enabled? object-move-enabled?
     :drag-attachment (if (= drag-attachment :center) "center" "anchor")})

  (fn restore-state [self payload]
    (when (not (= payload nil))
      (when (not (= (type payload) :table))
        (error (.. "restore-state payload must be a table or nil, got " (type payload))))
      (when (not (= (. payload :camera-mode) nil))
        (let [value (. payload :camera-mode)]
          (self:set-camera-mode (if (= value "flight") :flight
                                    (= value "grounded") :grounded
                                    (error (.. "Invalid camera mode in restore: " (tostring value)))))))
      (when (not (= (. payload :object-move-enabled?) nil))
        (self:set-object-move-enabled! (. payload :object-move-enabled?)))
      (when (not (= (. payload :drag-attachment) nil))
        (let [value (. payload :drag-attachment)]
          (self:set-drag-attachment (if (= value "center") :center
                                        (= value "anchor") :anchor
                                        (error (.. "Invalid drag attachment in restore: " (tostring value))))))))
    true)

  (local state
    {: changed
     : set-camera-mode
     : toggle-camera-mode
     : set-object-move-enabled!
     : toggle-object-move-enabled!
     : set-drag-attachment
     : toggle-drag-attachment
     : capture-state
     : restore-state})

  (fn state-index [self key]
    (if (= key :camera-mode) camera-mode
        (= key :object-move-enabled?) object-move-enabled?
        (= key :drag-attachment) drag-attachment))

  (setmetatable state {:__index state-index})
  state)
