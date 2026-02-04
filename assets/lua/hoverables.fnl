(local Intersectables (require :intersectables))

(fn contains? [items target]
  (var found false)
  (each [_ item (ipairs items)]
    (when (and item (= item target))
      (set found true)))
  found)

(fn add-unique! [items target]
  (when (and target (not (contains? items target)))
    (table.insert items target)))

(fn remove-first! [items target]
  (var idx nil)
  (each [i item (ipairs items)]
    (when (and (not idx) (= item target))
      (set idx i)))
  (when idx
    (table.remove items idx)))

(fn Hoverables [opts]
  (local intersector
         (or (and opts opts.intersectables)
             app.intersectables
             (Intersectables)))
  (local self {:objects []
               :active-entry nil
               :mouse-pos nil})

  (fn pointer-pos [payload]
    (intersector:pointer payload))

  (fn set-active-entry [self entry]
    (local previous (and self.active-entry self.active-entry.object))
    (local next (and entry entry.object))
    (local changed? (not (= previous next)))
    (when changed?
      (when previous
        (local handler previous.on-hovered)
        (when handler
          (previous:on-hovered false))))
    (set self.active-entry entry)
    (when (and next changed?)
      (local handler next.on-hovered)
      (when handler
        (next:on-hovered true))))

  (fn clear-active [self]
    (when self.active-entry
      (set-active-entry self nil)))

  (fn apply-pointer [self pointer]
    (set self.mouse-pos pointer)
    (local entry (intersector:select-entry self.objects pointer {}))
    (if entry
        (set-active-entry self entry)
        (clear-active self)))

  (fn on-mouse-motion [self payload]
    (when payload
      (apply-pointer self (pointer-pos payload))))

  (fn register [self obj]
    (add-unique! self.objects obj)
    obj)

  (fn unregister [self obj]
    (remove-first! self.objects obj)
    (when (and self.active-entry (= self.active-entry.object obj))
      (clear-active self)))

  (fn on-enter [self]
    (when self.mouse-pos
      (apply-pointer self self.mouse-pos)))

  (fn update-from-input [self]
    (local mouse (and app.engine app.engine.input app.engine.input.mouse))
    (when mouse
      (apply-pointer self (pointer-pos {:x mouse.x :y mouse.y}))))

  (fn on-leave [self]
    (clear-active self))

  (fn get-active-entry [self]
    self.active-entry)

  (fn get-active-object [self]
    (local entry (self:get-active-entry))
    (and entry entry.object))

  (fn drop [self]
    (self:on-leave)
    (set self.objects [])
    (set self.mouse-pos nil))

  (set self.register register)
  (set self.unregister unregister)
  (set self.on-mouse-motion on-mouse-motion)
  (set self.on-enter on-enter)
  (set self.on-leave on-leave)
  (set self.update-from-input update-from-input)
  (set self.get-active-entry get-active-entry)
  (set self.get-active-object get-active-object)
  (set self.drop drop)
  self)

Hoverables
