(local glm (require :glm))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn merge-defaults [defaults persisted]
  (if (not (= (type defaults) :table))
      (if (= persisted nil) defaults persisted)
      (do
        (local out {})
        (local source
          (if (= (type persisted) :table)
              persisted
              {}))
        (each [k v (pairs defaults)]
          (set (. out k) (merge-defaults v (. source k))))
        (each [k v (pairs source)]
          (when (= (. out k) nil)
            (set (. out k) (clone-table v))))
        out)))

(fn vec3->array [value]
  (if value
      [value.x value.y value.z]
      nil))

(fn normalize-vec3 [value fallback]
  (if (= value nil)
      fallback
      (= (type value) :userdata)
      value
      (= (type value) :table)
      (glm.vec3 (or (. value 1) value.x (and fallback fallback.x) 0)
                (or (. value 2) value.y (and fallback fallback.y) 0)
                (or (. value 3) value.z (and fallback fallback.z) 0))
      fallback))

(fn default-style []
  {:stroke_color [0.96 0.96 0.98 1.0]
   :fill_color [0.33 0.6 0.96 0.22]
   :thickness 2.0
   :opacity 1.0
   :fill_enabled false})

(fn default-ui []
  {:active_tool "select"
   :active_layer_id nil
   :selection_ids []
   :defaults (default-style)})

(fn empty-document []
  {:version 1
   :next_layer_id 1
   :next_object_id 1
   :layers []})

(fn default-state []
  {:document (empty-document)
   :ui (default-ui)})

(fn layer-id [n]
  (string.format "layer-%d" n))

(fn object-id [n]
  (string.format "object-%d" n))

(fn default-layer-name [n]
  (string.format "Layer %d" n))

(fn normalize-style [style]
  (merge-defaults (default-style) style))

(fn normalize-object [object]
  (local normalized (clone-table object))
  (set normalized.style (normalize-style (and normalized normalized.style)))
  (if (= normalized.kind "rectangle")
      (do
        (set normalized.center (normalize-vec3 normalized.center (glm.vec3 0 0 0)))
        (set normalized.size (normalize-vec3 normalized.size (glm.vec3 0 0 0))))
      (= normalized.kind "ellipse")
      (do
        (set normalized.center (normalize-vec3 normalized.center (glm.vec3 0 0 0)))
        (set normalized.size (normalize-vec3 normalized.size (glm.vec3 0 0 0))))
      (= normalized.kind "line")
      (do
        (set normalized.start (normalize-vec3 normalized.start (glm.vec3 0 0 0)))
        (set normalized.finish (normalize-vec3 normalized.finish (glm.vec3 0 0 0))))
      (= normalized.kind "stroke")
      (set normalized.points
           (icollect [_ point (ipairs (or normalized.points []))]
                     (normalize-vec3 point (glm.vec3 0 0 0)))))
  normalized)

(fn normalize-layer [layer]
  (local normalized (clone-table layer))
  (set normalized.kind (or normalized.kind "vector"))
  (set normalized.objects
       (icollect [_ object (ipairs (or normalized.objects []))]
                 (normalize-object object)))
  normalized)

(fn normalize-state [state]
  (local merged (merge-defaults (default-state) state))
  (set merged.ui.defaults (normalize-style merged.ui.defaults))
  (set merged.document.layers
       (icollect [_ layer (ipairs (or merged.document.layers []))]
                 (normalize-layer layer)))
  merged)

(fn serialize-object [object]
  (local serialized (clone-table object))
  (if (= serialized.kind "rectangle")
      (do
        (set serialized.center (vec3->array serialized.center))
        (set serialized.size (vec3->array serialized.size)))
      (= serialized.kind "ellipse")
      (do
        (set serialized.center (vec3->array serialized.center))
        (set serialized.size (vec3->array serialized.size)))
      (= serialized.kind "line")
      (do
        (set serialized.start (vec3->array serialized.start))
        (set serialized.finish (vec3->array serialized.finish)))
      (= serialized.kind "stroke")
      (set serialized.points
           (icollect [_ point (ipairs (or serialized.points []))]
                     (vec3->array point))))
  serialized)

(fn serialize-state [state]
  (local normalized (normalize-state state))
  {:document {:version normalized.document.version
              :next_layer_id normalized.document.next_layer_id
              :next_object_id normalized.document.next_object_id
              :layers (icollect [_ layer (ipairs (or normalized.document.layers []))]
                                {:id layer.id
                                 :name layer.name
                                 :kind layer.kind
                                 :objects (icollect [_ object (ipairs (or layer.objects []))]
                                                    (serialize-object object))})}
   :ui (clone-table normalized.ui)})

(fn layer-index [document layer-id]
  (var resolved nil)
  (each [idx layer (ipairs (or document.layers []))]
    (when (and (not resolved) (= layer.id layer-id))
      (set resolved idx)))
  resolved)

(fn layer-at [document idx]
  (. document.layers idx))

(fn active-layer [state]
  (local document state.document)
  (local ui state.ui)
  (and ui.active_layer_id
       (let [idx (layer-index document ui.active_layer_id)]
         (and idx (. document.layers idx)))))

(fn ensure-active-layer-id! [state]
  (local document state.document)
  (local ui state.ui)
  (local active-id ui.active_layer_id)
  (local idx (and active-id (layer-index document active-id)))
  (if idx
      active-id
      (do
        (local first-layer (. document.layers 1))
        (set ui.active_layer_id (and first-layer first-layer.id))
        ui.active_layer_id)))

(fn alloc-layer! [document]
  (local seq (or document.next_layer_id 1))
  (set document.next_layer_id (+ seq 1))
  {:id (layer-id seq)
   :name (default-layer-name seq)
   :kind "vector"
   :objects []})

(fn alloc-object-id! [document]
  (local seq (or document.next_object_id 1))
  (set document.next_object_id (+ seq 1))
  (object-id seq))

(fn insert-layer! [document layer idx]
  (local target-idx
    (if idx
        (math.max 1 (math.min idx (+ (length document.layers) 1)))
        (+ (length document.layers) 1)))
  (table.insert document.layers target-idx layer)
  target-idx)

(fn remove-layer-at! [document idx]
  (table.remove document.layers idx))

(fn ensure-default-layer! [state]
  (local document state.document)
  (local ui state.ui)
  (if (> (length document.layers) 0)
      (ensure-active-layer-id! state)
      (do
        (local layer (alloc-layer! document))
        (insert-layer! document layer 1)
        (set ui.active_layer_id layer.id)
        layer.id)))

(fn set-active-layer! [state layer-id]
  (local idx (layer-index state.document layer-id))
  (assert idx (.. "DrawingDocument.set-active-layer! unknown layer id: " (tostring layer-id)))
  (set state.ui.active_layer_id layer-id)
  (set state.ui.selection_ids [])
  layer-id)

(fn object-index [layer object-id]
  (var resolved nil)
  (each [idx object (ipairs (or layer.objects []))]
    (when (and (not resolved) (= object.id object-id))
      (set resolved idx)))
  resolved)

(fn find-object [layer object-id]
  (let [idx (object-index layer object-id)]
    (and idx (. layer.objects idx))))

(fn insert-object! [layer object idx]
  (local target-idx
    (if idx
        (math.max 1 (math.min idx (+ (length layer.objects) 1)))
        (+ (length layer.objects) 1)))
  (table.insert layer.objects target-idx object)
  target-idx)

(fn remove-object-at! [layer idx]
  (table.remove layer.objects idx))

(fn clear-selection! [state]
  (set state.ui.selection_ids []))

(fn set-selection! [state ids]
  (set state.ui.selection_ids
       (icollect [_ id (ipairs (or ids []))]
                 id)))

(fn toggle-selection-id! [state object-id]
  (local next [])
  (var present? false)
  (each [_ id (ipairs (or state.ui.selection_ids []))]
    (if (= id object-id)
        (set present? true)
        (table.insert next id)))
  (when (not present?)
    (table.insert next object-id))
  (set state.ui.selection_ids next)
  next)

(fn move-layer! [document from-idx to-idx]
  (when (= from-idx to-idx)
    (lua "return document.layers"))
  (local layer (table.remove document.layers from-idx))
  (table.insert document.layers to-idx layer)
  document.layers)

{:clone-table clone-table
 :merge-defaults merge-defaults
 :default-style default-style
 :default-ui default-ui
 :empty-document empty-document
 :default-state default-state
 :vec3->array vec3->array
 :normalize-vec3 normalize-vec3
 :normalize-style normalize-style
 :normalize-object normalize-object
 :normalize-layer normalize-layer
 :normalize-state normalize-state
 :serialize-object serialize-object
 :serialize-state serialize-state
 :layer-index layer-index
 :layer-at layer-at
 :active-layer active-layer
 :ensure-active-layer-id! ensure-active-layer-id!
 :alloc-layer! alloc-layer!
 :alloc-object-id! alloc-object-id!
 :insert-layer! insert-layer!
 :remove-layer-at! remove-layer-at!
 :ensure-default-layer! ensure-default-layer!
 :set-active-layer! set-active-layer!
 :object-index object-index
 :find-object find-object
 :insert-object! insert-object!
 :remove-object-at! remove-object-at!
 :clear-selection! clear-selection!
 :set-selection! set-selection!
 :toggle-selection-id! toggle-selection-id!
 :move-layer! move-layer!}
