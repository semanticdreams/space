(local glm (require :glm))

(local raster-storage-root "drawing/raster")
(local vec3-magnitude-limit 1000000)

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

(fn default-style []
  {:stroke_color [0.33 0.6 0.96 1.0]
   :fill_color [0.33 0.6 0.96 0.22]
   :thickness 2.0
   :opacity 1.0
   :fill_enabled true})

(fn default-raster-style []
  {:stroke_color [0.96 0.96 0.98 1.0]
   :fill_color [0.33 0.6 0.96 0.22]
   :thickness 6.0
   :opacity 1.0
   :fill_enabled true
   :pressure_size true
   :pressure_opacity true})

(fn legacy-default-style []
  {:stroke_color [0.96 0.96 0.98 1.0]
   :fill_color [0.33 0.6 0.96 0.22]
   :thickness 2.0
   :opacity 1.0
   :fill_enabled false})

(fn default-ui []
  {:active_tool_by_kind {:vector "select"
                         :raster "brush"}
   :active_layer_id nil
   :selection_ids []
   :defaults_by_kind {:vector (default-style)
                      :raster (default-raster-style)}})

(fn empty-document []
  {:version 2
   :next_layer_id 1
   :next_object_id 1
   :layers []})

(fn default-state []
  {:document (empty-document)
   :ui (default-ui)})

(local vector-tools {:select true
                     :rectangle true
                     :ellipse true
                     :line true
                     :pen true
                     :brush true
                     :marker true
                     :eraser true})
(local vector-exclusive-tools {:select true})
(local raster-exclusive-tools {:marquee true
                               :move true
                               :eyedropper true
                               :fill true})
(local raster-tools {:marquee true
                     :move true
                     :eyedropper true
                     :fill true
                     :rectangle true
                     :ellipse true
                     :line true
                     :pen true
                     :brush true
                     :marker true
                     :eraser true})

(fn layer-id [n]
  (string.format "layer-%d" n))

(fn object-id [n]
  (string.format "object-%d" n))

(fn default-layer-name [n]
  (string.format "Layer %d" n))

(fn color-array= [left right]
  (and (= (. left 1) (. right 1))
       (= (. left 2) (. right 2))
       (= (. left 3) (. right 3))
       (= (. left 4) (. right 4))))

(fn style-equals? [left right]
  (and (color-array= left.stroke_color right.stroke_color)
       (color-array= left.fill_color right.fill_color)
       (= left.thickness right.thickness)
       (= left.opacity right.opacity)
       (= left.fill_enabled right.fill_enabled)))

(fn default-tool-for-kind [kind]
  (if (= kind "raster")
      "brush"
      "select"))

(fn tool-allowed-for-kind? [kind tool]
  (if (= kind "vector")
      (. vector-tools tool)
      (= kind "raster")
      (. raster-tools tool)
      false))

(fn normalize-tool-for-kind [kind tool]
  (local fallback (default-tool-for-kind kind))
  (if (and (= (type tool) :string)
           (tool-allowed-for-kind? kind tool))
      tool
      fallback))

(fn validate-tool-for-kind [kind tool]
  (assert (= (type tool) :string)
          (.. "DrawingDocument tool must be a string for kind " kind))
  (assert (tool-allowed-for-kind? kind tool)
          (.. "DrawingDocument invalid tool for kind " kind ": " (tostring tool)))
  tool)

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn optional-table [value label]
  (when (not (= value nil))
    (assert (= (type value) :table)
            (.. "DrawingDocument " label " must be a table")))
  value)

(fn array-table? [value]
  (if (not (= (type value) :table))
      false
      (do
        (local count (length value))
        (var valid? true)
        (each [k _v (pairs value)]
          (when (or (not (= (type k) :number))
                    (not (= k (math.floor k)))
                    (< k 1)
                    (> k count))
            (set valid? false)))
        valid?)))

(fn optional-array-table [value label]
  (when (not (= value nil))
    (assert (array-table? value)
            (.. "DrawingDocument " label " must be an array table")))
  value)

(fn required-array-table [value label]
  (assert (array-table? value)
          (.. "DrawingDocument " label " must be an array table"))
  value)

(fn validate-counter [value label]
  (assert (finite-number? value)
          (.. "DrawingDocument " label " must be a finite number"))
  (assert (= value (math.floor value))
          (.. "DrawingDocument " label " must be an integer"))
  (assert (>= value 1)
          (.. "DrawingDocument " label " must be >= 1"))
  value)

(fn validate-insert-index [idx max-count label]
  (assert (finite-number? idx)
          (.. "DrawingDocument " label " must be a finite number"))
  (assert (= idx (math.floor idx))
          (.. "DrawingDocument " label " must be an integer"))
  (assert (>= idx 1)
          (.. "DrawingDocument " label " must be >= 1"))
  (assert (<= idx (+ max-count 1))
          (.. "DrawingDocument " label " must be <= " (tostring (+ max-count 1))))
  idx)

(fn validate-remove-index [idx count label]
  (assert (finite-number? idx)
          (.. "DrawingDocument " label " must be a finite number"))
  (assert (= idx (math.floor idx))
          (.. "DrawingDocument " label " must be an integer"))
  (assert (>= idx 1)
          (.. "DrawingDocument " label " must be >= 1"))
  (assert (<= idx count)
          (.. "DrawingDocument " label " must be <= " (tostring count)))
  idx)

(fn validate-id-string [value label]
  (assert (= (type value) :string)
          (.. "DrawingDocument " label " must be a string"))
  (assert (not (= value ""))
          (.. "DrawingDocument " label " must be non-empty"))
  value)

(fn validate-layer-name [value label]
  (assert (= (type value) :string)
          (.. "DrawingDocument " label " must be a string"))
  (local trimmed (or (string.match value "^%s*(.-)%s*$") ""))
  (assert (not (= trimmed ""))
          (.. "DrawingDocument " label " must be non-empty"))
  (assert (= trimmed value)
          (.. "DrawingDocument " label " must already be trimmed"))
  value)

(fn validated-vec3-components [x y z label]
  (assert (finite-number? x)
          (.. "DrawingDocument " label " x must be a finite number"))
  (assert (finite-number? y)
          (.. "DrawingDocument " label " y must be a finite number"))
  (assert (finite-number? z)
          (.. "DrawingDocument " label " z must be a finite number"))
  (local magnitude
    (math.sqrt (+ (* x x) (* y y) (* z z))))
  (assert (finite-number? magnitude)
          (.. "DrawingDocument " label " magnitude must be finite"))
  (assert (<= magnitude vec3-magnitude-limit)
          (.. "DrawingDocument " label " magnitude must be <= " (tostring vec3-magnitude-limit)))
  [x y z])

(fn normalize-vec3 [value label]
  (if (and (= (type value) :userdata)
           (glm.is-vec3 value))
      (do
        (local [x y z] (validated-vec3-components value.x value.y value.z label))
        (glm.vec3 x y z))
      (= (type value) :userdata)
      (error (.. "DrawingDocument " label " must be glm.vec3 or a 3-channel array"))
      (do
        (local array (required-array-table value label))
        (assert (= (length array) 3)
                (.. "DrawingDocument " label " must be a 3-channel array"))
        (local [x y z] (validated-vec3-components (. array 1)
                                                   (. array 2)
                                                   (. array 3)
                                                   label))
        (glm.vec3 x y z))))

(fn canonical-selection-ids [ids label]
  (if (= ids nil)
      []
      (do
        (local array (required-array-table ids label))
        (local out [])
        (local seen {})
        (each [idx id (ipairs array)]
          (local validated-id
            (validate-id-string id
                                (.. label "[" (tostring idx) "]")))
          (when (not (. seen validated-id))
            (set (. seen validated-id) true)
            (table.insert out validated-id)))
        out)))

(fn filter-selection-ids-for-layer [ids layer]
  (if (or (= layer nil)
          (not (= layer.kind "vector")))
      []
      (do
        (local allowed {})
        (local out [])
        (each [_ object (ipairs (or layer.objects []))]
          (when object.id
            (set (. allowed object.id) true)))
        (each [_ id (ipairs ids)]
          (when (. allowed id)
            (table.insert out id)))
        out)))

(fn canonical-layer-selection-ids [ids layer label]
  (filter-selection-ids-for-layer (canonical-selection-ids ids label)
                                  layer))

(fn canonical-raster-base-path [value]
  (assert (and (= (type value) :string)
               (not (= value "")))
          "DrawingDocument.normalize-layer raster layers require storage.base_path")
  (local leaf (string.match value "^drawing/raster/([^/]+)$"))
  (assert leaf
          (.. "DrawingDocument raster storage.base_path must be a direct child of "
              raster-storage-root))
  (assert (not (= leaf "."))
          (.. "DrawingDocument raster storage.base_path must be a direct child of "
              raster-storage-root))
  (assert (not (= leaf ".."))
          (.. "DrawingDocument raster storage.base_path must be a direct child of "
              raster-storage-root))
  (.. raster-storage-root "/" leaf))

(fn validate-color-array [kind key value]
  (assert (= (type value) :table)
          (.. "DrawingDocument default " (tostring key) " for kind " kind " must be a color array"))
  (assert (= (length value) 4)
          (.. "DrawingDocument default " (tostring key) " for kind " kind " must have 4 channels"))
  (for [idx 1 4]
    (assert (finite-number? (. value idx))
            (.. "DrawingDocument default " (tostring key) " for kind " kind " channel "
                (tostring idx) " must be a finite number")))
  value)

(fn validate-default-value [kind key value]
  (if (or (= key :stroke_color)
          (= key :fill_color))
      (validate-color-array kind key value)
      (or (= key :thickness)
          (= key :opacity))
      (do
        (assert (finite-number? value)
                (.. "DrawingDocument default " (tostring key) " for kind " kind " must be a finite number"))
        (if (= key :thickness)
            (assert (> value 0)
                    (.. "DrawingDocument default thickness for kind " kind " must be > 0"))
            (do
              (assert (>= value 0)
                      (.. "DrawingDocument default opacity for kind " kind " must be >= 0"))
              (assert (<= value 1)
                      (.. "DrawingDocument default opacity for kind " kind " must be <= 1"))))
        value)
      (or (= key :fill_enabled)
          (= key :pressure_size)
          (= key :pressure_opacity))
      (do
        (assert (= (type value) :boolean)
                (.. "DrawingDocument default " (tostring key) " for kind " kind " must be boolean"))
        value)
      (error (.. "DrawingDocument missing validator for default key " (tostring key)))))

(fn canonical-style [kind merged]
  {:stroke_color (clone-table (validate-default-value kind :stroke_color merged.stroke_color))
   :fill_color (clone-table (validate-default-value kind :fill_color merged.fill_color))
   :thickness (validate-default-value kind :thickness merged.thickness)
   :opacity (validate-default-value kind :opacity merged.opacity)
   :fill_enabled (validate-default-value kind :fill_enabled merged.fill_enabled)})

(fn canonical-raster-style [kind merged]
  {:stroke_color (clone-table (validate-default-value kind :stroke_color merged.stroke_color))
   :fill_color (clone-table (validate-default-value kind :fill_color merged.fill_color))
   :thickness (validate-default-value kind :thickness merged.thickness)
   :opacity (validate-default-value kind :opacity merged.opacity)
   :fill_enabled (validate-default-value kind :fill_enabled merged.fill_enabled)
   :pressure_size (validate-default-value kind :pressure_size merged.pressure_size)
   :pressure_opacity (validate-default-value kind :pressure_opacity merged.pressure_opacity)})

(fn normalize-style [style]
  (local normalized
    (canonical-style "vector"
                     (merge-defaults (default-style) style)))
  (if (style-equals? normalized (legacy-default-style))
      (canonical-style "vector" (default-style))
      normalized))

(fn normalize-raster-style [style]
  (canonical-raster-style "raster"
                          (merge-defaults (default-raster-style) style)))

(fn canonical-raster-storage [storage]
  (local merged
    (merge-defaults {:scheme "png-tile-v1"
                     :tile_size 128
                     :channels 4
                     :base_path nil}
                    (optional-table storage "raster storage")))
  (assert (= merged.scheme "png-tile-v1")
          "DrawingDocument raster storage scheme must be png-tile-v1")
  (assert (finite-number? merged.tile_size)
          "DrawingDocument raster storage tile_size must be a finite number")
  (assert (= merged.tile_size (math.floor merged.tile_size))
          "DrawingDocument raster storage tile_size must be an integer")
  (assert (> merged.tile_size 0)
          "DrawingDocument raster storage tile_size must be > 0")
  (assert (= merged.channels 4)
          "DrawingDocument raster storage channels must be 4")
  {:scheme "png-tile-v1"
   :tile_size merged.tile_size
   :channels 4
   :base_path (canonical-raster-base-path merged.base_path)})

(fn canonical-object-style [style]
  (clone-table (normalize-style (optional-table style "document object.style"))))

(fn validate-layer-object-ids! [objects]
  (local seen {})
  (each [object-idx object (ipairs objects)]
    (assert (not (. seen object.id))
            (.. "DrawingDocument duplicate object id: " object.id
                " at document layer objects[" (tostring object-idx) "]"))
    (set (. seen object.id) true))
  objects)

(fn normalize-object [object]
  (local source (optional-table object "document object"))
  (local normalized-id (validate-id-string source.id "document object.id"))
  (local normalized-style (canonical-object-style source.style))
  (if (= source.kind "rectangle")
      {:id normalized-id
       :kind "rectangle"
       :center (normalize-vec3 source.center "document object.center")
       :size (normalize-vec3 source.size "document object.size")
       :style normalized-style}
      (= source.kind "ellipse")
      {:id normalized-id
       :kind "ellipse"
       :center (normalize-vec3 source.center "document object.center")
       :size (normalize-vec3 source.size "document object.size")
       :style normalized-style}
      (= source.kind "line")
      {:id normalized-id
       :kind "line"
       :start (normalize-vec3 source.start "document object.start")
       :finish (normalize-vec3 source.finish "document object.finish")
       :style normalized-style}
      (= source.kind "stroke")
      (do
        (local points (required-array-table source.points "document object.points"))
        {:id normalized-id
         :kind "stroke"
         :points (icollect [idx point (ipairs points)]
                           (normalize-vec3 point
                                           (.. "document object.points[" (tostring idx) "]")))
         :style normalized-style})
      (error (.. "DrawingDocument.normalize-object unknown object kind: " (tostring source.kind)))))

(fn normalize-layer [layer]
  (local source (optional-table layer "document layer"))
  (local normalized-id (validate-id-string source.id "document layer.id"))
  (local normalized-name (validate-layer-name source.name "document layer.name"))
  (local normalized-kind (or source.kind "vector"))
  (if (= normalized-kind "vector")
      (do
        (assert (= source.storage nil)
                "DrawingDocument vector layers must not define storage")
        (optional-array-table source.objects "document layer objects")
        (local objects
          (icollect [_ object (ipairs (or source.objects []))]
                    (normalize-object object)))
        (validate-layer-object-ids! objects)
        {:id normalized-id
         :name normalized-name
         :kind "vector"
         :objects objects
         :storage nil})
      (= normalized-kind "raster")
      (do
        (optional-array-table source.objects "document layer objects")
        (assert (or (= source.objects nil)
                    (= (length source.objects) 0))
                "DrawingDocument raster layers must not persist vector objects")
        {:id normalized-id
         :name normalized-name
         :kind "raster"
         :objects []
         :storage (canonical-raster-storage source.storage)})
      (error (.. "DrawingDocument.normalize-layer unknown layer kind: " (tostring normalized-kind)))))

(fn validate-document-ids! [document]
  (local seen-layer-ids {})
  (local seen-object-ids {})
  (each [layer-idx layer (ipairs (or document.layers []))]
    (assert (not (. seen-layer-ids layer.id))
            (.. "DrawingDocument duplicate layer id: " layer.id
                " at document.layers[" (tostring layer-idx) "]"))
    (set (. seen-layer-ids layer.id) true)
    (when (= layer.kind "vector")
      (each [object-idx object (ipairs (or layer.objects []))]
        (assert (not (. seen-object-ids object.id))
                (.. "DrawingDocument duplicate object id: " object.id
                    " at document.layers[" (tostring layer-idx) "].objects[" (tostring object-idx) "]"))
        (set (. seen-object-ids object.id) true))))
  document)

(fn validate-raster-storage-paths! [document]
  (local seen-base-paths {})
  (each [layer-idx layer (ipairs (or document.layers []))]
    (when (= layer.kind "raster")
      (local base-path layer.storage.base_path)
      (assert (not (. seen-base-paths base-path))
              (.. "DrawingDocument duplicate raster storage.base_path: " base-path
                  " at document.layers[" (tostring layer-idx) "]"))
      (set (. seen-base-paths base-path) true)))
  document)

(fn next-layer-sequence [document]
  (var next-seq 1)
  (each [_ layer (ipairs (or document.layers []))]
    (local suffix (string.match layer.id "^layer%-(%d+)$"))
    (when suffix
      (local seq (tonumber suffix))
      (when (and seq (>= seq next-seq))
        (set next-seq (+ seq 1))))
    (when (= layer.kind "raster")
      (local storage-suffix
        (and layer.storage
             (string.match layer.storage.base_path "^drawing/raster/layer%-(%d+)$")))
      (when storage-suffix
        (local storage-seq (tonumber storage-suffix))
        (when (and storage-seq (>= storage-seq next-seq))
          (set next-seq (+ storage-seq 1))))))
  next-seq)

(fn next-object-sequence [document]
  (var next-seq 1)
  (each [_ layer (ipairs (or document.layers []))]
    (when (= layer.kind "vector")
      (each [_ object (ipairs (or layer.objects []))]
        (local suffix (string.match object.id "^object%-(%d+)$"))
        (when suffix
          (local seq (tonumber suffix))
          (when (and seq (>= seq next-seq))
            (set next-seq (+ seq 1)))))))
  next-seq)

(fn refresh-document-counters! [document]
  (set document.next_layer_id
       (math.max (or document.next_layer_id 1)
                 (next-layer-sequence document)))
  (set document.next_object_id
       (math.max (or document.next_object_id 1)
                 (next-object-sequence document)))
  document)

(fn ensure-raster-storage-path-available! [document base-path]
  (each [layer-idx layer (ipairs (or document.layers []))]
    (when (and (= layer.kind "raster")
               (= layer.storage.base_path base-path))
      (error (.. "DrawingDocument duplicate raster storage.base_path: " base-path
                 " at document.layers[" (tostring layer-idx) "]"))))
  base-path)

(fn ensure-layer-id-available! [document layer-id]
  (each [layer-idx layer (ipairs (or document.layers []))]
    (when (= layer.id layer-id)
      (error (.. "DrawingDocument duplicate layer id: " layer-id
                 " at document.layers[" (tostring layer-idx) "]"))))
  layer-id)

(fn ensure-object-id-available! [document object-id]
  (each [layer-idx layer (ipairs (or document.layers []))]
    (when (= layer.kind "vector")
      (each [object-idx object (ipairs (or layer.objects []))]
        (when (= object.id object-id)
          (error (.. "DrawingDocument duplicate object id: " object-id
                     " at document.layers[" (tostring layer-idx) "].objects[" (tostring object-idx) "]"))))))
  object-id)

(fn ensure-layer-object-ids-available! [document layer]
  (when (= layer.kind "vector")
    (each [_ object (ipairs (or layer.objects []))]
      (ensure-object-id-available! document object.id)))
  layer)

(fn persisted-tool-for-kind [kind tool]
  (local normalized (normalize-tool-for-kind kind tool))
  (if (and (= kind "raster")
           (= normalized "move"))
      "brush"
      normalized))

(fn resolved-active-layer [state]
  (local layer-id state.ui.active_layer_id)
  (var layer nil)
  (each [_ candidate (ipairs (or state.document.layers []))]
    (when (and (not layer)
               (= candidate.id layer-id))
      (set layer candidate)))
  layer)

(fn resolved-active-kind [state]
  (local layer (resolved-active-layer state))
  (and layer layer.kind))

(fn infer-legacy-tool-kind [state tool]
  (if (. vector-exclusive-tools tool)
      "vector"
      (. raster-exclusive-tools tool)
      "raster"
      (resolved-active-kind state)))

(fn clear-raster-transient-tool! [state]
  (when (= (. state.ui.active_tool_by_kind :raster) "move")
    (set (. state.ui.active_tool_by_kind :raster) "brush"))
  state.ui)

(fn normalize-state [state]
  (local persisted-state (or (optional-table state "state") {}))
  (local persisted-document
    (or (optional-table persisted-state.document "document") {}))
  (optional-array-table persisted-document.layers "document.layers")
  (local merged (merge-defaults (default-state) persisted-state))
  (set merged.document.next_layer_id
       (validate-counter merged.document.next_layer_id "document.next_layer_id"))
  (set merged.document.next_object_id
       (validate-counter merged.document.next_object_id "document.next_object_id"))
  (local persisted-ui (or (optional-table persisted-state.ui "ui") {}))
  (local persisted-selection-ids
    (optional-array-table persisted-ui.selection_ids "ui.selection_ids"))
  (local canonical-persisted-selection-ids
    (canonical-selection-ids persisted-selection-ids "ui.selection_ids"))
  (local persisted-tools
    (or (optional-table persisted-ui.active_tool_by_kind "ui.active_tool_by_kind") {}))
  (local persisted-defaults
    (or (optional-table persisted-ui.defaults_by_kind "ui.defaults_by_kind") {}))
  (local legacy-defaults
    (optional-table persisted-ui.defaults "ui.defaults"))
  (local vector-defaults
    (optional-table (. persisted-defaults :vector) "ui.defaults_by_kind.vector"))
  (local raster-defaults
    (optional-table (. persisted-defaults :raster) "ui.defaults_by_kind.raster"))
  (set merged.document.version (math.max 2 (or merged.document.version 0)))
  (set merged.document.layers
       (icollect [_ layer (ipairs (or merged.document.layers []))]
                 (normalize-layer layer)))
  (validate-document-ids! merged.document)
  (validate-raster-storage-paths! merged.document)
  (set merged.document.next_layer_id
       (math.max merged.document.next_layer_id
                 (next-layer-sequence merged.document)))
  (set merged.document.next_object_id
       (math.max merged.document.next_object_id
                 (next-object-sequence merged.document)))
  (var active-layer (resolved-active-layer merged))
  (var active-repaired? false)
  (when (and (not active-layer)
             (> (length merged.document.layers) 0))
    (set active-repaired? true)
    (set active-layer (. merged.document.layers 1))
    (set merged.ui.active_layer_id (and active-layer active-layer.id)))
  (local legacy-tool merged.ui.active_tool)
  (local legacy-kind
    (and legacy-tool
         (infer-legacy-tool-kind merged legacy-tool)))
  (set merged.ui.active_tool_by_kind
       {:vector (normalize-tool-for-kind
                 "vector"
                 (or (. persisted-tools :vector)
                     (and (= legacy-kind "vector") legacy-tool)))
        :raster (persisted-tool-for-kind
                 "raster"
                 (or (. persisted-tools :raster)
                     (and (= legacy-kind "raster") legacy-tool)))})
  (set merged.ui.defaults_by_kind
       {:vector (normalize-style (or vector-defaults
                                     legacy-defaults))
        :raster (normalize-raster-style raster-defaults)})
  (set merged.ui.selection_ids
       (if (or active-repaired?
               (not active-layer))
           []
           (filter-selection-ids-for-layer canonical-persisted-selection-ids
                                           active-layer)))
  merged)

(fn serialize-object [object]
  (local normalized-style (canonical-object-style object.style))
  (if (= object.kind "rectangle")
      {:id object.id
       :kind "rectangle"
       :center (vec3->array object.center)
       :size (vec3->array object.size)
       :style normalized-style}
      (= object.kind "ellipse")
      {:id object.id
       :kind "ellipse"
       :center (vec3->array object.center)
       :size (vec3->array object.size)
       :style normalized-style}
      (= object.kind "line")
      {:id object.id
       :kind "line"
       :start (vec3->array object.start)
       :finish (vec3->array object.finish)
       :style normalized-style}
      (= object.kind "stroke")
      {:id object.id
       :kind "stroke"
       :points (icollect [_ point (ipairs (or object.points []))]
                         (vec3->array point))
       :style normalized-style}
      (error (.. "DrawingDocument.serialize-object unknown object kind: " (tostring object.kind)))))

(fn serialize-state [state]
  (local normalized (normalize-state state))
  {:document {:version normalized.document.version
              :next_layer_id normalized.document.next_layer_id
              :next_object_id normalized.document.next_object_id
              :layers (icollect [_ layer (ipairs (or normalized.document.layers []))]
                                {:id layer.id
                                 :name layer.name
                                 :kind layer.kind
                                 :objects (if (= layer.kind "vector")
                                              (icollect [_ object (ipairs (or layer.objects []))]
                                                        (serialize-object object))
                                              [])
                                 :storage (clone-table layer.storage)})}
   :ui {:active_tool_by_kind {:vector (persisted-tool-for-kind "vector"
                                                               normalized.ui.active_tool_by_kind.vector)
                              :raster (persisted-tool-for-kind "raster"
                                                               normalized.ui.active_tool_by_kind.raster)}
        :active_layer_id normalized.ui.active_layer_id
        :selection_ids (clone-table normalized.ui.selection_ids)
        :defaults_by_kind {:vector (clone-table normalized.ui.defaults_by_kind.vector)
                           :raster (clone-table normalized.ui.defaults_by_kind.raster)}}})

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
       (do
         (local idx (layer-index document ui.active_layer_id))
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

(fn alloc-layer! [document kind]
  (local seq (or document.next_layer_id 1))
  (set document.next_layer_id (+ seq 1))
  (local resolved-kind (or kind "vector"))
  (if (= resolved-kind "vector")
      {:id (layer-id seq)
       :name (default-layer-name seq)
       :kind "vector"
       :objects []}
      (= resolved-kind "raster")
      {:id (layer-id seq)
       :name (default-layer-name seq)
       :kind "raster"
       :objects []
       :storage {:scheme "png-tile-v1"
                 :tile_size 128
                 :channels 4
                 :base_path (.. "drawing/raster/" (layer-id seq))}}
      (error (.. "DrawingDocument.alloc-layer! unknown kind: " (tostring resolved-kind)))))

(fn alloc-object-id! [document]
  (local seq (or document.next_object_id 1))
  (set document.next_object_id (+ seq 1))
  (object-id seq))

(fn insert-layer! [document layer idx]
  (local normalized-layer (normalize-layer layer))
  (ensure-layer-id-available! document normalized-layer.id)
  (when (= normalized-layer.kind "raster")
    (ensure-raster-storage-path-available! document normalized-layer.storage.base_path))
  (ensure-layer-object-ids-available! document normalized-layer)
  (local target-idx
    (if idx
        (validate-insert-index idx
                               (length document.layers)
                               "insert-layer! idx")
        (+ (length document.layers) 1)))
  (table.insert document.layers target-idx normalized-layer)
  (refresh-document-counters! document)
  target-idx)

(fn remove-layer-at! [document idx]
  (local validated-idx
    (validate-remove-index idx
                           (length document.layers)
                           "remove-layer-at! idx"))
  (table.remove document.layers validated-idx))

(fn set-active-layer! [state layer-id]
  (local idx (layer-index state.document layer-id))
  (assert idx (.. "DrawingDocument.set-active-layer! unknown layer id: " (tostring layer-id)))
  (set state.ui.active_layer_id layer-id)
  (set state.ui.selection_ids [])
  (clear-raster-transient-tool! state)
  layer-id)

(fn active-kind [state]
  (local layer (active-layer state))
  (and layer layer.kind))

(fn active-tool [state]
  (local kind (active-kind state))
  (and kind
       (normalize-tool-for-kind kind (. state.ui.active_tool_by_kind kind))))

(fn current-defaults [state]
  (local kind (active-kind state))
  (if (= kind "raster")
      (normalize-raster-style (. state.ui.defaults_by_kind kind))
      (= kind "vector")
      (normalize-style (. state.ui.defaults_by_kind kind))
      nil))

(fn set-active-tool! [state tool]
  (local kind (active-kind state))
  (assert kind
          "DrawingDocument.set-active-tool! requires an active layer")
  (local validated-tool (validate-tool-for-kind kind tool))
  (set (. state.ui.active_tool_by_kind kind) validated-tool)
  validated-tool)

(local vector-default-keys {:stroke_color true
                            :fill_color true
                            :thickness true
                            :opacity true
                            :fill_enabled true})

(local raster-default-keys {:stroke_color true
                            :fill_color true
                            :thickness true
                            :opacity true
                            :fill_enabled true
                            :pressure_size true
                            :pressure_opacity true})

(fn defaults-key-allowed-for-kind? [kind key]
  (if (= kind "raster")
      (. raster-default-keys key)
      (. vector-default-keys key)))

(fn set-defaults! [state changes]
  (local kind (active-kind state))
  (assert kind
          "DrawingDocument.set-defaults! requires an active layer")
  (local target (. state.ui.defaults_by_kind kind))
  (each [k v (pairs changes)]
    (assert (defaults-key-allowed-for-kind? kind k)
            (.. "DrawingDocument invalid default key for kind " kind ": " (tostring k)))
    (set (. target k) (validate-default-value kind k v)))
  (current-defaults state))

(fn object-index [layer object-id]
  (var resolved nil)
  (each [idx object (ipairs (or layer.objects []))]
    (when (and (not resolved) (= object.id object-id))
      (set resolved idx)))
  resolved)

(fn find-object [layer object-id]
  (local idx (object-index layer object-id))
  (and idx (. layer.objects idx)))

(fn resolve-vector-layer! [document layer label]
  (local layer-source (optional-table layer (.. label " layer")))
  (local target-layer-id
    (validate-id-string layer-source.id (.. label " layer.id")))
  (local target-layer-idx (layer-index document target-layer-id))
  (assert target-layer-idx
          (.. "DrawingDocument " label " unknown layer id: " target-layer-id))
  (local target-layer (. document.layers target-layer-idx))
  (assert (= target-layer.kind "vector")
          (.. "DrawingDocument " label " requires a vector layer"))
  target-layer)

(fn insert-object! [document layer object idx]
  (local target-layer (resolve-vector-layer! document layer "insert-object!"))
  (local normalized-object (normalize-object object))
  (ensure-object-id-available! document normalized-object.id)
  (local target-idx
    (if idx
        (validate-insert-index idx
                               (length target-layer.objects)
                               "insert-object! idx")
        (+ (length target-layer.objects) 1)))
  (table.insert target-layer.objects target-idx normalized-object)
  (refresh-document-counters! document)
  target-idx)

(fn remove-object-at! [document layer idx]
  (local target-layer (resolve-vector-layer! document layer "remove-object-at!"))
  (local validated-idx
    (validate-remove-index idx
                           (length target-layer.objects)
                           "remove-object-at! idx"))
  (table.remove target-layer.objects validated-idx))

(fn clear-selection! [state]
  (set state.ui.selection_ids []))

(fn active-vector-layer-for-selection [state label]
  (local layer (active-layer state))
  (assert layer
          (.. "DrawingDocument " label " requires an active layer"))
  (assert (= layer.kind "vector")
          (.. "DrawingDocument " label " requires active vector layer"))
  layer)

(fn validated-selection-ids [state ids label]
  (local layer (active-vector-layer-for-selection state label))
  (local array (required-array-table ids label))
  (local out [])
  (local seen {})
  (each [idx id (ipairs array)]
    (local validated-id
      (validate-id-string id
                          (.. label "[" (tostring idx) "]")))
    (assert (not (. seen validated-id))
            (.. "DrawingDocument " label " contains duplicate id: " validated-id))
    (assert (find-object layer validated-id)
            (.. "DrawingDocument " label " contains unknown id: " validated-id))
    (set (. seen validated-id) true)
    (table.insert out validated-id))
  out)

(fn set-selection! [state ids]
  (set state.ui.selection_ids
       (validated-selection-ids state ids "selection ids")))

(fn toggle-selection-id! [state object-id]
  (local layer
    (active-vector-layer-for-selection state "toggle-selection-id!"))
  (local validated-id
    (validate-id-string object-id "toggle-selection-id! id"))
  (local next [])
  (var present? false)
  (each [_ id (ipairs (or state.ui.selection_ids []))]
    (if (= id validated-id)
        (set present? true)
        (table.insert next id)))
  (when (not present?)
    (assert (find-object layer validated-id)
            (.. "DrawingDocument toggle-selection-id! unknown id: " validated-id))
    (table.insert next validated-id))
  (set-selection! state next)
  state.ui.selection_ids)

(fn move-layer! [document from-idx to-idx]
  (local validated-from-idx
    (validate-remove-index from-idx
                           (length document.layers)
                           "move-layer! from-idx"))
  (local validated-to-idx
    (validate-remove-index to-idx
                           (length document.layers)
                           "move-layer! to-idx"))
  (when (= validated-from-idx validated-to-idx)
    (lua "return document.layers"))
  (local layer (table.remove document.layers validated-from-idx))
  (table.insert document.layers validated-to-idx layer)
  document.layers)

{:clone-table clone-table
 :merge-defaults merge-defaults
 :default-style default-style
 :default-raster-style default-raster-style
 :default-ui default-ui
 :empty-document empty-document
 :default-state default-state
 :vec3->array vec3->array
 :normalize-vec3 normalize-vec3
 :normalize-style normalize-style
 :normalize-raster-style normalize-raster-style
 :normalize-object normalize-object
 :normalize-layer normalize-layer
 :clear-raster-transient-tool! clear-raster-transient-tool!
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
 :set-active-layer! set-active-layer!
 :active-kind active-kind
 :active-tool active-tool
 :current-defaults current-defaults
 :validate-layer-name validate-layer-name
 :validate-tool-for-kind validate-tool-for-kind
 :set-active-tool! set-active-tool!
 :set-defaults! set-defaults!
 :object-index object-index
 :find-object find-object
 :insert-object! insert-object!
 :remove-object-at! remove-object-at!
 :clear-selection! clear-selection!
 :set-selection! set-selection!
 :toggle-selection-id! toggle-selection-id!
 :move-layer! move-layer!}
