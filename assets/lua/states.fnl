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
  (var self nil)
  (var hud-provider options.hud_provider)
  (var focus-manager-provider options.focus_manager_provider)

  (fn call-hook [state hook]
    (when (and state (. state hook))
      ((. state hook) state)))

  (fn assert-provider [label provider]
    (assert (or (= provider nil)
                (= (type provider) :function))
            (.. "States " label " must be a function")))

  (assert-provider "hud_provider" hud-provider)
  (assert-provider "focus_manager_provider" focus-manager-provider)

  (fn bind-state-host [state]
    (when state
      (assert (or (not state.states_owner)
                  (= state.states_owner self))
              (.. "State "
                   (tostring (or state.name "<unnamed>"))
                   " is already bound to another states host"))
      (set state.states_owner self))
    state)

  (fn add-state [_self name state]
    (assert name "State name is required")
    (assert state "State definition is required")
    (bind-state-host state)
    (set (. registry name) state)
    state)

  (fn get-state [_self name]
    (. registry name))

  (fn push-history [entry]
    (when (> history-limit 0)
      (table.insert history entry)
      (when (> (length history) history-limit)
        (table.remove history 1))))

  (fn set-state [_self name]
    (local next-state (get-state self name))
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

  (fn get-history [_self]
    (local copy [])
    (each [_ entry (ipairs history)]
      (table.insert copy entry))
    copy)

  (fn clear-history [_self]
    (set history [])
    nil)

  (fn drop [_self]
    (call-hook active-state :on-leave)
    (each [_ state (pairs registry)]
      (when (= state.states_owner self)
        (set state.states_owner nil)))
    (changed:clear)
    (set active-state nil)
    (set active-name nil)
    (set history [])
    nil)

  (fn get-hud [_self]
    (and hud-provider
         (hud-provider self)))

  (fn set-hud-provider [_self provider]
    (assert-provider "hud_provider" provider)
    (set hud-provider provider)
    provider)

  (fn get-focus-manager [_self]
    (and focus-manager-provider
         (focus-manager-provider self)))

  (fn set-focus-manager-provider [_self provider]
    (assert-provider "focus_manager_provider" provider)
    (set focus-manager-provider provider)
    provider)

  (set self
       {:add-state add-state
        :set-state set-state
        :get-state get-state
        :active-state (fn [_self] active-state)
        :active-name (fn [_self] active-name)
        :changed changed
        :get-history get-history
        :clear-history clear-history
        :drop drop
        :get-hud get-hud
        :set-hud-provider set-hud-provider
        :get-focus-manager get-focus-manager
        :set-focus-manager-provider set-focus-manager-provider})
  self)
