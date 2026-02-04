(local Signal (require :signal))

(fn States [opts]
  (local options (or opts {}))
  (local registry {})
  (var active-state nil)
  (var active-name nil)
  (local changed (Signal))
  (var history [])
  (local history-limit (math.max 0 (math.floor (or options.history-limit 50))))
  (var history-seq 0)

  (fn call-hook [state hook]
    (when (and state (. state hook))
      ((. state hook) state)))

  (fn add-state [name state]
    (assert name "State name is required")
    (assert state "State definition is required")
    (set (. registry name) state)
    state)

  (fn get-state [name]
    (. registry name))

  (fn push-history [entry]
    (when (> history-limit 0)
      (table.insert history entry)
      (when (> (length history) history-limit)
        (table.remove history 1))))

  (fn set-state [name]
    (local next-state (get-state name))
    (assert next-state (.. "Unknown state " (tostring name)))
    (if (= next-state active-state)
        next-state
        (do
          (local previous-name active-name)
          (call-hook active-state :on-leave)
          (set active-state next-state)
          (set active-name name)
          (call-hook active-state :on-enter)
          (set history-seq (+ history-seq 1))
          (push-history {:seq history-seq
                         :previous previous-name
                         :current name})
          (changed:emit {:previous previous-name
                         :current name
                         :state next-state})
          next-state)))

  (fn get-history []
    (local copy [])
    (each [_ entry (ipairs history)]
      (table.insert copy entry))
    copy)

  (fn clear-history []
    (set history [])
    nil)

  {:add-state add-state
   :set-state set-state
   :get-state get-state
   :active-state (fn [] active-state)
   :active-name (fn [] active-name)
   :changed changed
   :get-history get-history
   :clear-history clear-history}
  )
