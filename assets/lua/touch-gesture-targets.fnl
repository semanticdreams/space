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

(fn TouchGestureTargets [opts]
  (local intersector
         (or (and opts opts.intersectables)
             app.intersectables
             (Intersectables)))
  (local objects [])

  (fn register [_self object]
    (add-unique! objects object)
    object)

  (fn unregister [_self object]
    (remove-first! objects object)
    object)

  (fn select-entry [_self payload opts]
    (local pointer (intersector:pointer payload))
    (intersector:select-entry objects pointer (or opts {})))

  (fn select-object [self payload opts]
    (local entry (self:select-entry payload opts))
    (local object (and entry entry.object))
    (local method-name (and opts opts.method))
    (if (and object method-name (not (. object method-name)))
        nil
        object))

  (fn drop [_self]
    (set objects []))

  {:register register
   :unregister unregister
   :select-entry select-entry
   :select-object select-object
   :drop drop})

TouchGestureTargets
