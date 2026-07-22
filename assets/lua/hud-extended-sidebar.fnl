(local Signal (require :signal))

(fn HudExtendedSidebar []
  (local changed (Signal))
  (local self {})

  (set self.entries {})
  (set self.entry-ids [])
  (set self.active-id nil)
  (set self.expanded? false)
  (set self.changed changed)

  (fn emit-changed []
    (changed:emit))

  (fn self.register-entry [_self entry]
    (assert entry.id "entry requires id")
    (assert entry.icon "entry requires icon")
    (assert entry.label "entry requires label")
    (assert entry.build-panel "entry requires build-panel")
    (local existing? (not (not (. self.entries entry.id))))
    (set (. self.entries entry.id) entry)
    (when (not existing?)
      (table.insert self.entry-ids entry.id))
    (emit-changed)
    true)

  (fn self.get-entry [_self id]
    (. self.entries id))

  (fn self.get-active-entry [_self]
    (and self.active-id (. self.entries self.active-id)))

  (fn self.select [_self id]
    (assert (. self.entries id) (.. "Sidebar has no entry: " (tostring id)))
    (when (not (= self.active-id id))
      (set self.active-id id)
      (set self.expanded? true)
      (emit-changed)))

  (fn self.toggle [_self]
    (when self.active-id
      (set self.expanded? (not self.expanded?))
      (emit-changed)))

  (fn self.collapse [_self]
    (when (and self.active-id self.expanded?)
      (set self.expanded? false)
      (emit-changed)))

  (fn self.entry-clicked [_self id]
    (assert (. self.entries id) (.. "Sidebar has no entry: " (tostring id)))
    (if (= self.active-id id)
        (self:toggle)
        (self:select id)))

  (fn self.capture-state [_self]
    {:active-id self.active-id
     :expanded? self.expanded?})

  (fn self.restore-state [_self state]
    (set self.active-id (and state.active-id (. self.entries state.active-id) state.active-id))
    (set self.expanded? (if (= state.expanded? nil) false
                           self.active-id state.expanded?
                           false))
    (emit-changed)
    true)

  self)

HudExtendedSidebar
