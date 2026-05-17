(local glm (require :glm))

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
  [(hex-channel trimmed 1) (hex-channel trimmed 3) (hex-channel trimmed 5) 1.0])

(fn require-controller [app tool-name]
  (assert app.drawing-controller (.. tool-name " requires app.drawing-controller")))

(fn run-gesture [controller tool start-point end-point]
  (controller:begin-gesture tool start-point {})
  (controller:update-gesture end-point false {})
  (assert (controller:commit-gesture)
          (.. "drawing gesture produced no committed object for tool " tool))
  "inserted")

(fn select-objects [controller args]
  (local layer (assert (controller:active-layer)
                       "space_drawing_select_objects requires an active layer"))
  (assert (= layer.kind "vector")
          "space_drawing_select_objects requires an active vector layer")
  (local ids [])
  (each [_ object (ipairs (or layer.objects []))]
    (when (or args.all (= object.kind args.type))
      (table.insert ids object.id)))
  (controller:set-selection! ids)
  (.. "selected " (# ids) " objects"))

(fn register-drawing-presets [mgr]
  (mgr:register
    {:name "drawing-shape-tools"
     :group "drawing"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :mode "drawing"}]
     :tool-ids ["drawing.set-tool" "drawing.insert-shape" "drawing.insert-line" "drawing.insert-stroke"]
     :system-prompt "The user is editing vector drawing content. Use drawing tools for shape and stroke operations."})

  (mgr:register
    {:name "drawing-layer-tools"
     :group "drawing"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :mode "drawing"}]
     :tool-ids ["drawing.add-layer" "drawing.duplicate-layer" "drawing.rename-layer" "drawing.set-active-layer"]
     :system-prompt "Use drawing layer tools to manage layer organization."})

  (mgr:register
    {:name "drawing-layer-destructive-tools"
     :group "drawing"
     :default-state :off
     :risk :destructive
     :contexts [{:surface :canvas :mode "drawing"}]
     :tool-ids ["drawing.delete-layer"]})

  (mgr:register
    {:name "drawing-color-tools"
     :group "drawing"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :mode "drawing"}]
     :tool-ids ["drawing.set-defaults" "drawing.sample-color"]})

  (mgr:register
    {:name "drawing-history-tools"
     :group "drawing"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :mode "drawing"}]
     :tool-ids ["drawing.undo" "drawing.redo"]})

  (mgr:register
    {:name "drawing-selection-tools"
     :group "drawing"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :mode "drawing"}]
     :tool-ids ["drawing.select-objects" "drawing.clear-selection"]})

  (mgr:register
    {:name "drawing-selection-destructive-tools"
     :group "drawing"
     :default-state :off
     :risk :destructive
     :contexts [{:surface :canvas :mode "drawing"}]
     :tool-ids ["drawing.delete-selected"]}))

(fn register-drawing-adapters [adapters]
  (local empty-schema {:type "object" :properties {}})

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
     :description "Insert a shape into the drawing."
     :inputSchema {:type "object"
                   :properties {:shape {:type "string" :description "Shape type (rectangle or ellipse)"}
                                :x {:type "number" :description "X position"}
                                :y {:type "number" :description "Y position"}
                                :width {:type "number" :description "Shape width"}
                                :height {:type "number" :description "Shape height"}}
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
     :description "Insert a line into the drawing."
     :inputSchema {:type "object"
                   :properties {:x1 {:type "number"} :y1 {:type "number"}
                                :x2 {:type "number"} :y2 {:type "number"}}
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
     :description "Insert a freehand stroke into the drawing."
     :inputSchema {:type "object"
                   :properties {:tool {:type "string" :description "Stroke tool (pen, brush, or marker)"}
                                :points {:type "array" :items {:type "object"
                                                               :properties {:x {:type "number"} :y {:type "number"}}}}}
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
     :inputSchema {:type "object" :properties {:layer {:type "string" :description "Layer name or index"}} :required ["layer"]}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_set_active_layer"))
                   (controller:set-active-layer args.layer)
                   "active layer set"))})

  (adapters:register
    {:id "drawing.delete-layer"
     :mcp-name "space_drawing_delete_layer"
     :description "Delete a drawing layer. This is destructive and cannot be undone."
     :inputSchema empty-schema
     :make-run (fn [app]
                 (fn [_args]
                   (local controller (require-controller app "space_drawing_delete_layer"))
                   (controller:delete-active-layer)
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
                   (local changes (or args.changes {}))
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
     :description "Sample a color from the drawing at the given position."
     :inputSchema {:type "object" :properties {:x {:type "number"} :y {:type "number"}} :required ["x" "y"]}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_sample_color"))
                   (controller:sample-point! (point args.x args.y))
                   "sampled"))})

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
    {:id "drawing.select-objects"
     :mcp-name "space_drawing_select_objects"
     :description "Select drawing objects by type or properties."
     :inputSchema {:type "object"
                   :properties {:type {:type "string" :description "Object type filter"}
                                :all {:type "boolean" :description "Select all objects"}}
                   :required []}
     :make-run (fn [app]
                 (fn [args]
                   (local controller (require-controller app "space_drawing_select_objects"))
                   (select-objects controller args)))})

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
     :description "Delete the currently selected drawing objects. This is destructive and cannot be undone."
     :inputSchema empty-schema
     :make-run (fn [app]
                 (fn [_args]
                   (local controller (require-controller app "space_drawing_delete_selected"))
                   (controller:on-delete-selection)
                   "deleted"))})

  true)

(fn register [mgr]
  (local adapters (. mgr :tool-adapters))
  (when adapters
    (register-drawing-adapters adapters))
  (register-drawing-presets mgr)
  true)

{:register register}
