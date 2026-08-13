(fn non-empty-string? [value]
  (and (= (type value) :string)
       (> (# value) 0)))

(fn first-non-empty [...]
  (var found nil)
  (each [_ value (ipairs [...])]
    (when (and (not found) (non-empty-string? value))
      (set found value)))
  found)

(fn activity-registry []
  (and app app.activity-registry))

(fn active-world-runtime []
  (and app app.active-world-runtime))

(fn activating-owner-id []
  (local registry (activity-registry))
  (local runtime (active-world-runtime))
  (first-non-empty (and registry registry.activating-activity-id)
                   (and runtime runtime.activating-activity-id)))

(fn active-owner-id []
  (local registry (activity-registry))
  (local runtime (active-world-runtime))
  (first-non-empty (and registry registry.active-activity-id)
                   (and runtime runtime.active-activity-id)
                   (and app app.active-activity-id)))

(fn expected-owner-id []
  (local activating (activating-owner-id))
  (if activating
      activating
      (active-owner-id)))

(fn shallow-copy [source]
  (local copy {})
  (local table-source (if source source {}))
  (each [key value (pairs table-source)]
    (set (. copy key) value))
  copy)

(fn format-value [value]
  (if (non-empty-string? value)
      value
      (= value nil)
      "nil"
      (tostring value)))

(fn assert-slot-owner! [surface action requested-activity-id opts]
  (local options (or opts {}))
  (local expected (expected-owner-id))
  (if (or (not expected)
          options.boundary-internal?
          (= requested-activity-id expected))
      true
      (error (.. "activity surface boundary denied"
                 " surface=" (format-value surface)
                 " action=" (format-value action)
                 " requested=" (format-value requested-activity-id)
                 " active=" (format-value (active-owner-id))
                 " activating=" (format-value (activating-owner-id))))))

(fn authorized-ray-opts [opts slot]
  (local options (shallow-copy opts))
  (when (and slot (not options.activity-slot))
    (set options.activity-slot slot))
  options)

(fn slot-activity-id [slot]
  (and slot slot.activity-id))

(fn ray-owner-id [opts]
  (local activity-slot-id (slot-activity-id (and opts opts.activity-slot)))
  (if activity-slot-id
      activity-slot-id
      (slot-activity-id (and opts opts.pointer-target opts.pointer-target.activity-slot))))

(fn surface-kind? [value expected]
  (if (= value expected)
      true
      (= value (tostring expected))))

(fn assert-screen-ray-authorized! [surface action opts active-slot]
  (local options (authorized-ray-opts opts active-slot))
  (local expected (expected-owner-id))
  (local owner (ray-owner-id options))
  (if (or (and options.view options.projection)
          (not expected)
          (= owner expected))
      true
      (error (.. "ambiguous direct screen ray"
                 " surface=" (format-value surface)
                 " action=" (format-value action)
                 ": use a presentation target/helper, a slot pointer target, or explicit matrices"))))

(fn scene-or-canvas-target? [target]
  (local kind (and target target.kind))
  (local surface (and target target.surface))
  (if (surface-kind? kind :scene)
      true
      (surface-kind? kind :canvas)
      true
      (surface-kind? surface :scene)
      true
      (surface-kind? surface :canvas)))

(fn target-owned-by-active? [target]
  (local expected (expected-owner-id))
  (if (not expected)
      true
      (scene-or-canvas-target? target)
      (= (slot-activity-id target.slot) expected)
      (not (and target target.slot))))

(fn foreign-slot-active? [slot]
  (if (and slot slot.visible?)
      true
      (and slot slot.interactive?)))

(fn deactivate-foreign-slots! [surface active-activity-id]
  (var count 0)
  (local slots (if (and surface surface.activity-slots)
                   surface.activity-slots
                   {}))
  (each [activity-id slot (pairs slots)]
    (when (and (not (= activity-id active-activity-id))
               (foreign-slot-active? slot))
      (surface:deactivate-activity-slot activity-id {:boundary-internal? true})
      (set count (+ count 1))))
  (when (and surface surface.active-activity-slot
             (not (= surface.active-activity-slot.activity-id active-activity-id)))
    (set surface.active-activity-slot nil))
  (when (and surface surface.active-activity-slot-id
             (not (= surface.active-activity-slot-id active-activity-id)))
    (set surface.active-activity-slot-id nil))
  count)

{:active-owner-id active-owner-id
 :activating-owner-id activating-owner-id
 :expected-owner-id expected-owner-id
 :assert-slot-owner! assert-slot-owner!
 :authorized-ray-opts authorized-ray-opts
 :assert-screen-ray-authorized! assert-screen-ray-authorized!
 :target-owned-by-active? target-owned-by-active?
 :deactivate-foreign-slots! deactivate-foreign-slots!}
