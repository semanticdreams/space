(local MathUtils (require :math-utils))

(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn default-panel-location [target]
  (or (and target target.default-panel-location)
      (and target target.default-panel-layer)
      "tiles"))

(fn panel-placement-options [target panel]
  (local entry (or panel {}))
  (local layer (or entry.layer
                   entry.location
                   (default-panel-location target)))
  (if (or (= layer :float) (= layer "float"))
      {:location :float
       :position (array->vec3 (and entry entry.position))
       :rotation (array->quat (and entry entry.rotation))
       :size (array->vec3 (and entry entry.size))}
      (if (or (= layer :tiles) (= layer "tiles"))
          {:location :tiles
           :align-x (and entry entry.align-x)
           :align-y (and entry entry.align-y)}
          (error (.. "Unsupported panel layer: " (tostring layer))))))

(fn assert-string-field [panel field label]
  (local value (. panel field))
  (assert (= (type value) :string) label)
  value)

(fn metadata-panel-element [metadata]
  (local element (and metadata metadata.element))
  (if (and element element.__hud_inner)
      element.__hud_inner
      element))

(fn collect-persistent-panels [target opts]
  (local options (or opts {}))
  (local kind options.kind)
  (local panels [])

  (fn maybe-collect [metadata]
    (local persistence (and metadata metadata.persistence))
    (when (and persistence
               (or (= kind nil)
                   (= persistence.kind kind)))
      (table.insert panels {:element (metadata-panel-element metadata)
                            :metadata metadata
                            :persistence (clone-table persistence)})))

  (when (and target target.tiles target.tiles.children)
    (each [_ metadata (ipairs target.tiles.children)]
      (maybe-collect metadata)))
  (when (and target target.float target.float.children)
    (each [_ metadata (ipairs target.float.children)]
      (maybe-collect metadata)))
  (when (and target target.scene-children)
    (each [_ metadata (ipairs target.scene-children)]
      (maybe-collect metadata)))

  panels)

{:default-panel-location default-panel-location
 :panel-placement-options panel-placement-options
 :assert-string-field assert-string-field
 :clone-table clone-table
 :persistent-panels collect-persistent-panels}
