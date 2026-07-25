(local glm (require :glm))
(local json (require :json))
(local DrawingDocument (require :drawing/document))
(local VectorGeometry (require :drawing/vector-geometry))

(local canvas-coordinate-contract
       (.. "Coordinates are canvas/world coordinates with OpenGL orientation: "
           "+x moves right, +y moves up, and the origin is the drawing canvas origin. "
           "Do not invert y values or use screen-space y-down coordinates."))

(fn point [x y]
  (assert (= (type x) "number") "drawing point x must be a number")
  (assert (= (type y) "number") "drawing point y must be a number")
  (glm.vec3 x y 0))

(fn hex-channel [value start-index]
  (/ (tonumber (string.sub value start-index (+ start-index 1)) 16) 255.0))

(fn parse-hex-color [value]
  (assert (= (type value) "string") "drawing color must be a string")
  (local trimmed (string.gsub value "^#" ""))
  (assert (= (# trimmed) 6) "drawing color must be #RRGGBB")
  (assert (string.match trimmed "^[0-9a-fA-F]+$")
          "drawing color must contain only hex digits")
  [(hex-channel trimmed 1) (hex-channel trimmed 3) (hex-channel trimmed 5) 1.0])

(fn require-controller [app tool-name]
  (assert app.drawing-controller (.. tool-name " requires app.drawing-controller")))

(fn color-array->hex [color]
  (if (not color)
      nil
      (string.format "#%02X%02X%02X"
                     (math.floor (+ 0.5 (* (or (. color 1) 0) 255)))
                     (math.floor (+ 0.5 (* (or (. color 2) 0) 255)))
                     (math.floor (+ 0.5 (* (or (. color 3) 0) 255))))))

(fn inspect-options [args]
  (local max-points (or args.max_points 32))
  (assert (= (type max-points) "number")
          "space_drawing_inspect max_points must be a number")
  (assert (>= max-points 0)
          "space_drawing_inspect max_points must be non-negative")
  {:include-points? (= args.include_points true)
   :max-points (math.floor max-points)})

(fn limited-points [points max-points]
  (local out [])
  (local count (math.min (length (or points [])) max-points))
  (for [i 1 count]
    (table.insert out (DrawingDocument.vec3->array (. points i))))
  out)

(fn radians->degrees [value]
  (* value (/ 180 math.pi)))

(fn object-position-summary [object opts]
  (local options (or opts {}))
  (if (or (= object.kind "rectangle")
          (= object.kind "ellipse"))
      (do
        (local out {:center (DrawingDocument.vec3->array object.center)
                    :size (DrawingDocument.vec3->array object.size)})
        (when object.rotation
          (set out.rotation object.rotation)
          (set out.rotation_degrees (radians->degrees object.rotation)))
        out)
      (= object.kind "line")
      {:start (DrawingDocument.vec3->array object.start)
       :finish (DrawingDocument.vec3->array object.finish)}
      (= object.kind "stroke")
      (do
        (local point-count (length (or object.points [])))
        (local out {:point_count point-count})
        (when options.include-points?
          (set out.points (limited-points object.points options.max-points))
          (set out.points_truncated (> point-count options.max-points)))
        out)
      {}))

(fn object-summary [object selected? opts]
  (local style (or object.style {}))
  (local out {:id object.id
              :kind object.kind
              :selected selected?
              :style {:stroke_color (color-array->hex style.stroke_color)
                      :fill_color (color-array->hex style.fill_color)
                      :fill_enabled style.fill_enabled
                      :thickness style.thickness
                      :opacity style.opacity}})
  (each [k v (pairs (object-position-summary object opts))]
    (set (. out k) v))
  out)

(fn selected-set [controller]
  (local out {})
  (each [_ id (ipairs (controller:selection-ids))]
    (set (. out id) true))
  out)

(fn layer-summary [controller layer include-objects? opts]
  (local selected (selected-set controller))
  {:id layer.id
   :name layer.name
   :kind layer.kind
   :active (= layer.id controller.state.ui.active_layer_id)
   :object_count (length (or layer.objects []))
   :objects (if (and include-objects? (= layer.kind "vector"))
                (icollect [_ object (ipairs (or layer.objects []))]
                          (object-summary object (. selected object.id) opts))
                [])})

(fn inspect-drawing [controller args]
  (local include-objects? (not (= args.include_objects false)))
  (local options (inspect-options args))
  (local state controller.state)
  (local active-layer (controller:active-layer))
  (json.dumps
    {:active_layer_id state.ui.active_layer_id
     :active_tool (controller:active-tool)
     :selection_ids (controller:selection-ids)
     :defaults (controller:current-defaults)
     :layers (icollect [_ layer (ipairs (or state.document.layers []))]
                       (layer-summary controller layer include-objects? options))
     :active_layer (and active-layer
                        (layer-summary controller active-layer include-objects? options))}))

(fn resolve-layer-id [controller layer-ref tool-name]
  (if (= layer-ref nil)
      (and (controller:active-layer) (. (controller:active-layer) :id))
      (= (type layer-ref) "number")
      (do
        (local layer (. controller.state.document.layers layer-ref))
        (assert layer (.. tool-name " unknown layer index: " (tostring layer-ref)))
        layer.id)
      (= (type layer-ref) "string")
      (do
        (var found nil)
        (each [_ layer (ipairs (or controller.state.document.layers []))]
          (when (and (not found)
                     (or (= layer.id layer-ref)
                         (= layer.name layer-ref)))
            (set found layer)))
        (assert found (.. tool-name " unknown layer: " layer-ref))
        found.id)
      (error (.. tool-name " layer must be a name, id, or index"))))

(fn run-gesture [controller tool start-point end-point]
  (controller:begin-gesture tool start-point {})
  (controller:update-gesture end-point false {})
  (assert (controller:commit-gesture)
          (.. "drawing gesture produced no committed object for tool " tool))
  "inserted")

(fn bounds-from-points [points]
  (var left nil)
  (var right nil)
  (var bottom nil)
  (var top nil)
  (each [_ p (ipairs points)]
    (set left (if left (math.min left p.x) p.x))
    (set right (if right (math.max right p.x) p.x))
    (set bottom (if bottom (math.min bottom p.y) p.y))
    (set top (if top (math.max top p.y) p.y)))
  {:left (or left 0) :right (or right 0) :bottom (or bottom 0) :top (or top 0)})

(fn object-bound-points [object]
  (if (= object.kind "rectangle")
      (do
        (local corners (VectorGeometry.rectangle-corners object))
        [corners.a corners.b corners.c corners.d])
      (= object.kind "ellipse")
      (VectorGeometry.ellipse-points object)
      (= object.kind "line")
      [object.start object.finish]
      (= object.kind "stroke")
      (or object.points [])
      (error (.. "space_drawing_select unsupported object kind: " (tostring object.kind)))))

(fn object-bounds [object]
  (bounds-from-points (object-bound-points object)))

(fn normalize-bound-edges [left right bottom top]
  (assert (= (type left) "number") "drawing bounds left/x must be a number")
  (assert (= (type right) "number") "drawing bounds right/width must be a number")
  (assert (= (type bottom) "number") "drawing bounds bottom/y must be a number")
  (assert (= (type top) "number") "drawing bounds top/height must be a number")
  {:left (math.min left right)
   :right (math.max left right)
   :bottom (math.min bottom top)
   :top (math.max bottom top)})

(fn normalize-bounds [bounds]
  (when bounds
    (if (not (= bounds.width nil))
        (do
          (assert (= (type bounds.x) "number") "drawing bounds x must be a number")
          (assert (= (type bounds.y) "number") "drawing bounds y must be a number")
          (assert (= (type bounds.width) "number") "drawing bounds width must be a number")
          (assert (= (type bounds.height) "number") "drawing bounds height must be a number")
          (normalize-bound-edges bounds.x (+ bounds.x bounds.width)
                                 bounds.y (+ bounds.y bounds.height)))
        (normalize-bound-edges bounds.left bounds.right bounds.bottom bounds.top))))

(fn bounds-intersect? [a b]
  (or (= b nil)
      (and (<= a.left b.right)
           (>= a.right b.left)
           (<= a.bottom b.top)
           (>= a.top b.bottom))))

(fn select-drawing [controller args]
  (local layer-id (resolve-layer-id controller args.layer "space_drawing_select"))
  (when (not (= layer-id controller.state.ui.active_layer_id))
    (controller:set-active-layer layer-id))
  (local layer (controller:active-layer))
  (assert layer "space_drawing_select requires an active layer")
  (assert (= layer.kind "vector")
          "space_drawing_select requires an active vector layer")
  (local bounds (normalize-bounds args.bounds))
  (local kind args.kind)
  (local ids
    (if args.ids
        args.ids
        (do
          (assert (or args.all kind bounds)
                  "space_drawing_select requires ids, all, kind, or bounds")
          (local out [])
          (each [_ object (ipairs (or layer.objects []))]
            (when (and (or args.all (not kind) (= object.kind kind))
                       (bounds-intersect? (object-bounds object) bounds))
              (table.insert out object.id)))
          out)))
  (local mode (or args.mode "replace"))
  (local current (controller:selection-ids))
  (local next [])
  (local included {})
  (fn insert-id [id]
    (when (not (. included id))
      (set (. included id) true)
      (table.insert next id)))
  (if (= mode "replace")
      (each [_ id (ipairs ids)]
        (insert-id id))
      (= mode "add")
      (do
        (each [_ id (ipairs current)]
          (insert-id id))
        (each [_ id (ipairs ids)]
          (insert-id id)))
      (= mode "remove")
      (do
        (local removed {})
        (each [_ id (ipairs ids)]
          (set (. removed id) true))
        (each [_ id (ipairs current)]
          (when (not (. removed id))
            (insert-id id))))
      (error (.. "space_drawing_select unsupported mode: " (tostring mode))))
  (controller:set-selection! next)
  (.. "selected " (length next) " objects"))

(fn style-changes [args]
  (local changes (DrawingDocument.clone-table (or args.changes {})))
  (when args.stroke_color
    (set changes.stroke_color (parse-hex-color args.stroke_color)))
  (when args.fill_color
    (set changes.fill_color (parse-hex-color args.fill_color)))
  (when (not (= args.fill_enabled nil))
    (set changes.fill_enabled args.fill_enabled))
  (when (not (= args.thickness nil))
    (set changes.thickness args.thickness))
  (when (not (= args.opacity nil))
    (set changes.opacity args.opacity))
  changes)

(fn table-empty? [t]
  (var empty? true)
  (each [_ _ (pairs t)]
    (set empty? false))
  empty?)

(fn register-drawing-presets [mgr]
  (mgr:register
    {:name "drawing-shape-tools"
     :group "drawing"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :activity "drawing"}]
     :tool-ids ["drawing.inspect" "drawing.set-tool" "drawing.insert-shape" "drawing.insert-line" "drawing.insert-stroke"]
     :system-prompt (.. "The user is editing vector drawing content. Use drawing tools for shape and stroke operations. "
                        canvas-coordinate-contract)})

  (mgr:register
    {:name "drawing-layer-tools"
     :group "drawing"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :activity "drawing"}]
     :tool-ids ["drawing.add-layer" "drawing.duplicate-layer" "drawing.rename-layer" "drawing.set-active-layer"]
     :system-prompt "Use drawing layer tools to manage layer organization."})

  (mgr:register
    {:name "drawing-layer-destructive-tools"
     :group "drawing"
     :default-state :auto
     :risk :destructive
     :contexts [{:surface :canvas :activity "drawing"}]
     :tool-ids ["drawing.delete-layer"]})

  (mgr:register
    {:name "drawing-color-tools"
     :group "drawing"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :activity "drawing"}]
     :tool-ids ["drawing.set-defaults" "drawing.update-selection-style" "drawing.sample-color"]})

  (mgr:register
    {:name "drawing-history-tools"
     :group "drawing"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :activity "drawing"}]
     :tool-ids ["drawing.undo" "drawing.redo"]})

  (mgr:register
    {:name "drawing-selection-tools"
     :group "drawing"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :activity "drawing"}]
     :tool-ids ["drawing.select" "drawing.transform-selection" "drawing.clear-selection"]})

  (mgr:register
    {:name "drawing-selection-destructive-tools"
     :group "drawing"
     :default-state :auto
     :risk :destructive
     :contexts [{:surface :canvas :activity "drawing"}]
     :tool-ids ["drawing.delete-selected"]}))

(fn register-drawing-adapters [adapters]
  (local empty-schema {:type "object" :properties {}})

  (adapters:register
    {:id "drawing.inspect"
     :mcp-name "space_drawing_inspect"
     :description (.. "Inspect drawing state, including layers, active layer/tool, selection, defaults, and vector objects. "
                      "Returned object coordinates use canvas/world coordinates: +y is up.")
     :inputSchema {:type "object"
                   :properties {:include_objects {:type "boolean"
                                                  :description "Include vector object properties in the response (default true)"}
                                :include_points {:type "boolean"
                                                 :description "Include stroke point samples (default false)"}
                                :max_points {:type "number"
                                             :description "Maximum stroke points per object when include_points is true (default 32)"}}
                   :required []}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_inspect"))
                   (inspect-drawing controller (or args {}))))})

  (adapters:register
    {:id "drawing.set-tool"
     :mcp-name "space_drawing_set_tool"
     :description "Switch the active drawing tool."
     :inputSchema {:type "object" :properties {:tool {:type "string" :description "Tool name to activate"}} :required ["tool"]}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_set_tool"))
                   (controller:set-active-tool args.tool)
                   (.. "tool: " args.tool)))})

  (adapters:register
    {:id "drawing.insert-shape"
     :mcp-name "space_drawing_insert_shape"
     :description (.. "Insert a shape into the drawing. "
                      canvas-coordinate-contract)
     :inputSchema {:type "object"
                   :properties {:shape {:type "string" :description "Shape type (rectangle or ellipse)"}
                                :x {:type "number" :description "Start x in canvas/world coordinates"}
                                :y {:type "number" :description "Start y in canvas/world coordinates (+y is up)"}
                                :width {:type "number" :description "Shape width; positive extends right, negative extends left"}
                                :height {:type "number" :description "Shape height; positive extends up, negative extends down"}}
                   :required ["shape" "x" "y" "width" "height"]}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_insert_shape"))
                   (local tool (if (= args.shape "circle") "ellipse" args.shape))
                   (assert (or (= tool "rectangle") (= tool "ellipse"))
                           (.. "unsupported drawing shape: " (tostring args.shape)))
                   (run-gesture controller tool
                                (point args.x args.y)
                                (point (+ args.x args.width) (+ args.y args.height)))))})

  (adapters:register
    {:id "drawing.insert-line"
     :mcp-name "space_drawing_insert_line"
     :description (.. "Insert a line into the drawing. "
                      canvas-coordinate-contract)
     :inputSchema {:type "object"
                   :properties {:x1 {:type "number" :description "Start x in canvas/world coordinates"}
                                :y1 {:type "number" :description "Start y in canvas/world coordinates (+y is up)"}
                                :x2 {:type "number" :description "End x in canvas/world coordinates"}
                                :y2 {:type "number" :description "End y in canvas/world coordinates (+y is up)"}}
                   :required ["x1" "y1" "x2" "y2"]}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_insert_line"))
                   (run-gesture controller "line"
                                (point args.x1 args.y1)
                                (point args.x2 args.y2))))})

  (adapters:register
    {:id "drawing.insert-stroke"
     :mcp-name "space_drawing_insert_stroke"
     :description (.. "Insert a freehand stroke into the drawing. "
                      canvas-coordinate-contract)
     :inputSchema {:type "object"
                   :properties {:tool {:type "string" :description "Stroke tool (pen, brush, or marker)"}
                                :points {:type "array" :items {:type "object"
                                                               :properties {:x {:type "number" :description "Point x in canvas/world coordinates"}
                                                                            :y {:type "number" :description "Point y in canvas/world coordinates (+y is up)"}}}}}
                   :required ["points"]}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_insert_stroke"))
                   (local tool (or args.tool "pen"))
                   (assert (or (= tool "pen") (= tool "brush") (= tool "marker"))
                           (.. "unsupported stroke tool: " (tostring tool)))
                   (assert (>= (# args.points) 2)
                           "space_drawing_insert_stroke requires at least two points")
                   (local first (. args.points 1))
                   (controller:begin-gesture tool (point first.x first.y) {})
                   (for [i 2 (# args.points)]
                     (local p (. args.points i))
                     (controller:update-gesture (point p.x p.y) false {}))
                   (assert (controller:commit-gesture)
                           "drawing stroke produced no committed object")
                   "inserted"))})

  (adapters:register
    {:id "drawing.add-layer"
     :mcp-name "space_drawing_add_layer"
     :description "Add a new layer to the drawing."
     :inputSchema {:type "object" :properties {:kind {:type "string" :description "Layer kind (vector or raster)"}} :required []}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_add_layer"))
                   (controller:add-layer (or args.kind "vector"))
                   "added"))})

  (adapters:register
    {:id "drawing.duplicate-layer"
     :mcp-name "space_drawing_duplicate_layer"
     :description "Duplicate the active layer."
     :inputSchema empty-schema
     :make-run (fn [app]
                 (fn [_args]
                   (local controller (require-controller app "space_drawing_duplicate_layer"))
                   (controller:duplicate-active-layer)
                   "duplicated"))})

  (adapters:register
    {:id "drawing.rename-layer"
     :mcp-name "space_drawing_rename_layer"
     :description "Rename a drawing layer."
     :inputSchema {:type "object" :properties {:name {:type "string" :description "New layer name"}} :required ["name"]}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_rename_layer"))
                   (controller:rename-active-layer args.name)
                   "renamed"))})

  (adapters:register
    {:id "drawing.set-active-layer"
     :mcp-name "space_drawing_set_active_layer"
     :description "Set the active drawing layer."
     :inputSchema {:type "object" :properties {:layer {:description "Layer name, id, or 1-based index"}} :required ["layer"]}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_set_active_layer"))
                   (controller:set-active-layer
                    (resolve-layer-id controller args.layer "space_drawing_set_active_layer"))
                   "active layer set"))})

  (adapters:register
    {:id "drawing.delete-layer"
     :mcp-name "space_drawing_delete_layer"
     :description "Delete the active drawing layer. This is destructive but can be undone from drawing history."
     :inputSchema empty-schema
     :make-run (fn [app]
                 (fn [_args]
                   (local controller (require-controller app "space_drawing_delete_layer"))
                   (assert (controller:delete-active-layer)
                           "space_drawing_delete_layer requires an active layer")
                   "deleted"))})

  (adapters:register
    {:id "drawing.set-defaults"
     :mcp-name "space_drawing_set_defaults"
     :description "Set default drawing properties such as color and stroke width."
     :inputSchema {:type "object"
                   :properties {:changes {:type "object" :description "Canonical drawing default changes"}
                                :color {:type "string" :description "Hex color #RRGGBB for stroke and fill"}
                                :stroke-width {:type "number" :description "Default stroke thickness"}}
                   :required []}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_set_defaults"))
                   (local changes (DrawingDocument.clone-table (or args.changes {})))
                   (when args.color
                     (local color (parse-hex-color args.color))
                     (set changes.stroke_color color)
                     (set changes.fill_color color))
                   (when args.stroke-width
                     (set changes.thickness args.stroke-width))
                   (controller:set-defaults! changes)
                   "updated"))})

  (adapters:register
    {:id "drawing.sample-color"
     :mcp-name "space_drawing_sample_color"
     :description (.. "Sample a color from the drawing at the given canvas/world position. "
                      "+y is up.")
     :inputSchema {:type "object"
                   :properties {:x {:type "number" :description "X position in canvas/world coordinates"}
                                :y {:type "number" :description "Y position in canvas/world coordinates (+y is up)"}}
                   :required ["x" "y"]}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_sample_color"))
                   (controller:sample-point! (point args.x args.y))
                   "sampled"))})

  (adapters:register
    {:id "drawing.update-selection-style"
     :mcp-name "space_drawing_update_selection_style"
     :description "Patch selected vector objects' style fields such as stroke color, fill color, fill enabled, thickness, and opacity."
     :inputSchema {:type "object"
                   :properties {:changes {:type "object" :description "Canonical style changes"}
                                :stroke_color {:type "string" :description "Stroke color as #RRGGBB"}
                                :fill_color {:type "string" :description "Fill color as #RRGGBB"}
                                :fill_enabled {:type "boolean" :description "Whether shapes render their fill"}
                                :thickness {:type "number" :description "Stroke thickness"}
                                :opacity {:type "number" :description "Opacity from 0 to 1"}}
                   :required []}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_update_selection_style"))
                   (local changes (style-changes (or args {})))
                   (assert (not (table-empty? changes))
                           "space_drawing_update_selection_style requires at least one style change")
                   (assert (controller:update-selection-style changes)
                           "space_drawing_update_selection_style requires a non-empty vector selection")
                   (.. "updated " (length (controller:selection-ids)) " selected objects")))})

  (adapters:register
    {:id "drawing.undo"
     :mcp-name "space_drawing_undo"
     :description "Undo the last drawing operation."
     :inputSchema empty-schema
     :make-run (fn [app]
                 (fn [_args]
                   (local controller (require-controller app "space_drawing_undo"))
                   (controller:on-undo)
                   "undone"))})

  (adapters:register
    {:id "drawing.redo"
     :mcp-name "space_drawing_redo"
     :description "Redo the last undone drawing operation."
     :inputSchema empty-schema
     :make-run (fn [app]
                 (fn [_args]
                   (local controller (require-controller app "space_drawing_redo"))
                   (controller:on-redo)
                   "redone"))})

  (adapters:register
    {:id "drawing.select"
     :mcp-name "space_drawing_select"
     :description (.. "Select vector drawing objects by id, kind, bounds, or all objects on a layer. "
                      "Bounds use canvas/world coordinates: +y is up.")
     :inputSchema {:type "object"
                   :properties {:ids {:type "array" :items {:type "string"} :description "Object ids to select"}
                                :all {:type "boolean" :description "Select all objects"}
                                :kind {:type "string" :description "Object kind filter (rectangle, ellipse, line, stroke)"}
                                :bounds {:type "object" :description "Selection bounds as left/right/bottom/top or x/y/width/height"}
                                :layer {:description "Layer id, name, or 1-based index"}
                                :mode {:type "string" :description "replace, add, or remove"}}
                   :required []}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_select"))
                   (select-drawing controller (or args {}))))})

  (adapters:register
    {:id "drawing.transform-selection"
     :mcp-name "space_drawing_transform_selection"
     :description (.. "Transform selected vector drawing objects by translation, rotation, and scaling in canvas/world coordinates; "
                     "+y moves up. Positive rotation_degrees turns counterclockwise around origin, or the selection center when origin is omitted.")
     :inputSchema {:type "object"
                   :properties {:dx {:type "number" :description "X translation"}
                                :dy {:type "number" :description "Y translation; positive moves up, negative moves down"}
                                :rotation_degrees {:type "number" :description "Counterclockwise rotation in degrees"}
                                :scale {:type "number" :description "Uniform scale factor greater than zero"}
                                :scale_x {:type "number" :description "Non-uniform X scale factor greater than zero; use uniform scale for already rotated shapes"}
                                :scale_y {:type "number" :description "Non-uniform Y scale factor greater than zero; use uniform scale for already rotated shapes"}
                                :origin {:type "object"
                                         :description "Optional transform origin in canvas/world coordinates"
                                         :properties {:x {:type "number"}
                                                      :y {:type "number"}}
                                         :required ["x" "y"]}}
                   :required []}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_transform_selection"))
                   (local options (or args {}))
                   (local count (length (controller:selection-ids)))
                   (assert (controller:transform-selection
                             {:dx options.dx
                              :dy options.dy
                              :rotation (if options.rotation_degrees
                                            (* options.rotation_degrees (/ math.pi 180))
                                            nil)
                              :scale options.scale
                              :scale-x options.scale_x
                              :scale-y options.scale_y
                              :origin options.origin})
                           "space_drawing_transform_selection requires a non-empty vector selection")
                   (.. "transformed " count " selected objects")))})

  (adapters:register
    {:id "drawing.clear-selection"
     :mcp-name "space_drawing_clear_selection"
     :description "Clear the current drawing selection."
     :inputSchema empty-schema
     :make-run (fn [app]
                 (fn [_args]
                   (local controller (require-controller app "space_drawing_clear_selection"))
                   (controller:clear-selection!)
                   "cleared"))})

  (adapters:register
    {:id "drawing.delete-selected"
     :mcp-name "space_drawing_delete_selected"
     :description "Delete the current drawing selection. This is destructive but can be undone from drawing history."
     :inputSchema empty-schema
     :make-run (fn [app]
                 (fn [_args]
                   (local controller (require-controller app "space_drawing_delete_selected"))
                   (assert (controller:on-delete-selection)
                           "space_drawing_delete_selected requires a non-empty selection")
                   "deleted"))})

  true)

(fn register [mgr]
  (local adapters (. mgr :tool-adapters))
  (when adapters
    (register-drawing-adapters adapters))
  (register-drawing-presets mgr)
  true)

{:register register}
