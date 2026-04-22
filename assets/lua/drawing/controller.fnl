(local fs (require :fs))
(local glm (require :glm))
(local Signal (require :signal))
(local DrawingDocument (require :drawing/document))
(local DrawingHistory (require :drawing/history))
(local HitTest (require :drawing/hit-test))
(local DrawingSample (require :drawing/sample))
(local {:RasterLayerRuntime RasterLayerRuntime} (require :drawing/raster-layer))

(fn clone-table [value]
  (DrawingDocument.clone-table value))

(fn object-empty? [object]
  (if (= object.kind "rectangle")
      (or (< (math.abs object.size.x) 0.001)
          (< (math.abs object.size.y) 0.001))
      (= object.kind "ellipse")
      (or (< (math.abs object.size.x) 0.001)
          (< (math.abs object.size.y) 0.001))
      (= object.kind "line")
      (< (glm.length (- object.finish object.start)) 0.001)
      (= object.kind "stroke")
      (< (length (or object.points [])) 2)
      true))

(fn center-size-from-points [start finish square?]
  (local dx (- finish.x start.x))
  (local dy (- finish.y start.y))
  (if square?
      (do
        (local extent (math.max (math.abs dx) (math.abs dy)))
        (local signed-dx (if (< dx 0) (- extent) extent))
        (local signed-dy (if (< dy 0) (- extent) extent))
        (local resolved-finish (glm.vec3 (+ start.x signed-dx)
                                         (+ start.y signed-dy)
                                         0))
        {:center (* (+ start resolved-finish) 0.5)
         :size (glm.vec3 (math.abs signed-dx) (math.abs signed-dy) 0)
         :finish resolved-finish})
      {:center (* (+ start finish) 0.5)
       :size (glm.vec3 (math.abs dx) (math.abs dy) 0)
       :finish finish}))

(fn stroke-style-for-tool [defaults tool]
  (local base (DrawingDocument.normalize-style defaults))
  (if (= tool "brush")
      (do
        (set base.thickness (math.max 4.0 (* (or base.thickness 2.0) 1.8)))
        (set base.opacity (math.min 1.0 (* (or base.opacity 1.0) 0.65)))
        base)
      (= tool "marker")
      (do
        (set base.thickness (math.max 7.0 (* (or base.thickness 2.0) 2.8)))
        (set base.opacity (math.min 1.0 (* (or base.opacity 1.0) 0.35)))
        base)
      base))

(fn raster-style-for-tool [defaults tool]
  (local base (DrawingDocument.normalize-raster-style defaults))
  (if (= tool "brush")
      (do
        (set base.thickness (math.max 6.0 (* (or base.thickness 6.0) 1.4)))
        (set base.opacity (math.min 1.0 (* (or base.opacity 1.0) 0.8)))
        base)
      (= tool "marker")
      (do
        (set base.thickness (math.max 10.0 (* (or base.thickness 6.0) 2.0)))
        (set base.opacity (math.min 1.0 (* (or base.opacity 1.0) 0.35)))
        base)
      base))

(fn gesture-needs-samples? [kind tool]
  (and (= kind "raster")
       (or (= tool "rectangle")
           (= tool "ellipse")
           (= tool "line")
           (= tool "pen")
           (= tool "brush")
           (= tool "marker")
           (= tool "eraser"))))

(fn gesture-needs-points? [tool]
  (or (= tool "pen")
      (= tool "brush")
      (= tool "marker")))

(fn tool-produces-preview? [tool]
  (or (= tool "rectangle")
      (= tool "ellipse")
      (= tool "line")
      (= tool "pen")
      (= tool "brush")
      (= tool "marker")
      (= tool "marquee")))

(fn make-shape-object [controller tool start finish shift? opts]
  (local options (or opts {}))
  (local defaults (clone-table (controller:current-defaults)))
  (local object-id
    (if options.preview?
        "__preview__"
        (DrawingDocument.alloc-object-id! controller.state.document)))
  (if (= tool "rectangle")
      (do
        (local geometry (center-size-from-points start finish shift?))
        {:id object-id
         :kind "rectangle"
         :center geometry.center
         :size geometry.size
         :style (DrawingDocument.normalize-style defaults)})
      (= tool "ellipse")
      (do
        (local geometry (center-size-from-points start finish shift?))
        {:id object-id
         :kind "ellipse"
         :center geometry.center
         :size geometry.size
         :style (DrawingDocument.normalize-style defaults)})
      (= tool "line")
      (do
        (local resolved-finish
          (if shift?
              (HitTest.constrain-line start finish)
              finish))
        {:id object-id
         :kind "line"
         :start start
         :finish resolved-finish
         :style (DrawingDocument.normalize-style defaults)})
      nil))

(fn DrawingController [opts]
  (local options (or opts {}))
  (local data-dir
    (assert options.data_dir
            "DrawingController requires non-empty :data_dir"))
  (assert (= (type data-dir) :string)
          "DrawingController requires non-empty :data_dir")
  (assert (not (= data-dir ""))
          "DrawingController requires non-empty :data_dir")
  (local initial-state
    (DrawingDocument.normalize-state
      {:document (or options.document (DrawingDocument.empty-document))
       :ui (or options.ui (DrawingDocument.default-ui))}))
  (local changed (Signal))
  (local history (DrawingHistory))
  (each [_ layer (ipairs (or initial-state.document.layers []))]
    (when (= layer.kind "raster")
      (assert data-dir "DrawingController raster documents require non-empty :data_dir")))
  (var gesture nil)
  (var raster-selection nil)
  (local raster-layers {})

  (local self {:state initial-state
               :changed changed
               :history history})

  (fn normalize-change-payload [payload default-reason]
    (if (and payload (= (type payload) :table))
        (do
          (assert (= (type payload.reason) :string)
                  "DrawingController change payload requires string :reason")
          payload)
        {:reason (or payload default-reason)}))

  (fn emit-changed [payload]
    (changed:emit (normalize-change-payload payload "drawing-controller"))
    true)

  (fn selection-payload [kind]
    {:reason (if (= kind "raster")
                 "raster-selection"
                 (= kind "vector")
                 "vector-selection"
                 "selection")})

  (fn command-payload [command fallback]
    (if (and command command.change-payload)
        (normalize-change-payload command.change-payload "history")
        (normalize-change-payload fallback "history")))

  (fn active-layer []
    (DrawingDocument.active-layer self.state))

  (fn active-kind []
    (DrawingDocument.active-kind self.state))

  (fn current-defaults []
    (DrawingDocument.current-defaults self.state))

  (fn ensure-raster-runtime [layer]
    (assert layer "DrawingController ensure-raster-runtime requires layer")
    (assert (= layer.kind "raster") "DrawingController ensure-raster-runtime requires raster layer")
    (when (= (. raster-layers layer.id) nil)
      (set (. raster-layers layer.id)
           (RasterLayerRuntime {:layer layer
                                :data_dir data-dir})))
    (. raster-layers layer.id))

  (fn clone-raster-selection [selection]
    (if selection
        (clone-table selection)
        nil))

  (fn set-raster-selection! [selection emit?]
    (set raster-selection (clone-raster-selection selection))
    (when emit?
      (emit-changed (selection-payload "raster")))
    raster-selection)

  (fn clear-raster-selection-state! []
    (set raster-selection nil)
    (DrawingDocument.clear-raster-transient-tool! self.state)
    nil)

  (fn drop-raster-runtime! [layer-id]
    (set (. raster-layers layer-id) nil))

  (fn prune-stale-raster-storage! []
    (local raster-root (fs.join-path data-dir "drawing/raster"))
    (when (fs.exists raster-root)
      (local active-paths {})
      (each [_ layer (ipairs (or self.state.document.layers []))]
        (when (and (= layer.kind "raster")
                   layer.storage
                   layer.storage.base_path)
          (set (. active-paths (fs.join-path data-dir layer.storage.base_path)) true)))
      (each [_ entry (ipairs (fs.list-dir raster-root))]
        (when (= entry.type "directory")
          (local path (fs.join-path raster-root entry.name))
          (when (not (. active-paths path))
            (local (ok err) (pcall fs.remove-all path))
            (when (not ok)
              (error (.. "DrawingController failed to remove stale raster storage " path ": " err))))))))

  (fn unpremultiply-rgba [rgba]
    (local alpha-byte (or (. rgba 4) 0))
    (if (<= alpha-byte 0)
        [0 0 0 0]
        (do
          (local alpha (/ alpha-byte 255.0))
          [(math.min 255 (math.floor (+ 0.5 (/ (or (. rgba 1) 0) alpha))))
           (math.min 255 (math.floor (+ 0.5 (/ (or (. rgba 2) 0) alpha))))
           (math.min 255 (math.floor (+ 0.5 (/ (or (. rgba 3) 0) alpha))))
           alpha-byte])))

  (fn selection-ids []
    (or self.state.ui.selection_ids []))

  (fn active-raster-selection []
    (if (and raster-selection
             (= raster-selection.layer_id self.state.ui.active_layer_id))
        raster-selection
        nil))

  (fn can-activate-tool? [tool]
    (local kind (active-kind))
    (if (or (not kind)
            (not (= (type tool) :string)))
        false
        (do
          (DrawingDocument.validate-tool-for-kind kind tool)
          (if (and (= kind "raster")
                   (= tool "move"))
              (not (= (active-raster-selection) nil))
              true))))

  (fn can-add-raster-layer? []
    true)

  (fn active-tool []
    (DrawingDocument.active-tool self.state))

  (fn persistent-tool []
    (local tool (active-tool))
    (if (and (= (active-kind) "raster")
             (= tool "move"))
        "brush"
        tool))

  (fn refresh-raster-selection-fragment! [runtime]
    (when (and raster-selection
               runtime
               (= raster-selection.layer_id runtime.runtime.layer-id))
      (set raster-selection
           {:layer_id raster-selection.layer_id
            :bounds (clone-table raster-selection.bounds)
            :fragment (runtime:capture-fragment raster-selection.bounds)}))
    raster-selection)

  (fn set-selection! [ids]
    (DrawingDocument.set-selection! self.state ids)
    (emit-changed (selection-payload "vector")))

  (fn clear-selection! []
    (DrawingDocument.clear-selection! self.state)
    (clear-raster-selection-state!)
    (emit-changed (selection-payload (active-kind))))

  (fn activate-object-command-layer! [layer-id]
    (DrawingDocument.set-active-layer! self.state layer-id)
    (local layer (active-layer))
    (assert layer "DrawingController object command missing layer")
    (assert (= layer.kind "vector")
            "DrawingController object command requires vector layer")
    layer)

  (fn perform! [command reason]
    (local committed-command (history:perform command))
    (if committed-command
        (emit-changed (command-payload committed-command reason))
        false))

  (fn add-layer-command [layer index]
    {:change-payload {:reason "layer-structure"}
     :apply (fn [_cmd]
              (DrawingDocument.insert-layer! self.state.document layer index)
              (set self.state.ui.active_layer_id layer.id)
              (clear-raster-selection-state!)
              (DrawingDocument.clear-selection! self.state))
     :revert (fn [_cmd]
               (local idx (DrawingDocument.layer-index self.state.document layer.id))
               (when idx
                 (DrawingDocument.remove-layer-at! self.state.document idx))
               (drop-raster-runtime! layer.id)
               (DrawingDocument.ensure-active-layer-id! self.state))})

  (fn delete-layer-command [layer index previous-active previous-selection previous-raster-selection]
    (var raster-bytes nil)
    {:change-payload {:reason "layer-structure"}
     :apply (fn [_cmd]
              (when (= layer.kind "raster")
                (when (= raster-bytes nil)
                  (do
                    (local runtime (ensure-raster-runtime layer))
                    (set raster-bytes (runtime:tile-records)))))
              (local idx (DrawingDocument.layer-index self.state.document layer.id))
              (when idx
                (DrawingDocument.remove-layer-at! self.state.document idx))
              (drop-raster-runtime! layer.id)
              (local next-layer (. self.state.document.layers (math.max 1 (math.min index (length self.state.document.layers)))))
              (set self.state.ui.active_layer_id (and next-layer next-layer.id))
              (clear-raster-selection-state!)
              (DrawingDocument.clear-selection! self.state))
     :revert (fn [_cmd]
               (DrawingDocument.insert-layer! self.state.document layer index)
               (when (= layer.kind "raster")
                 (do
                   (local runtime (ensure-raster-runtime layer))
                   (runtime:apply-captured-bytes! raster-bytes)))
               (set self.state.ui.active_layer_id previous-active)
               (set-raster-selection! previous-raster-selection false)
               (if (= (DrawingDocument.active-kind self.state) "vector")
                   (DrawingDocument.set-selection! self.state previous-selection)
                   (DrawingDocument.clear-selection! self.state)))})

  (fn reorder-layer-command [layer-id from-index to-index]
    {:change-payload {:reason "layer-structure"}
     :apply (fn [_cmd]
              (DrawingDocument.move-layer! self.state.document from-index to-index))
     :revert (fn [_cmd]
               (DrawingDocument.move-layer! self.state.document to-index from-index))})

  (fn rename-layer-command [layer-id previous-name next-name]
    {:change-payload {:reason "layer-meta"}
     :apply (fn [_cmd]
              (local idx (DrawingDocument.layer-index self.state.document layer-id))
              (local layer (and idx (. self.state.document.layers idx)))
              (when layer
                (set layer.name next-name)))
     :revert (fn [_cmd]
               (local idx (DrawingDocument.layer-index self.state.document layer-id))
               (local layer (and idx (. self.state.document.layers idx)))
               (when layer
                 (set layer.name previous-name)))})

  (fn add-objects-command [layer-id objects]
    (local object-copies
      (icollect [_ object (ipairs objects)]
                (clone-table object)))
    (local previous-selection (clone-table self.state.ui.selection_ids))
    {:change-payload {:reason "vector-content"}
     :apply (fn [_cmd]
              (local layer (activate-object-command-layer! layer-id))
              (each [_ object (ipairs object-copies)]
                (DrawingDocument.insert-object! self.state.document layer object nil))
              (DrawingDocument.set-selection! self.state
                                             (icollect [_ object (ipairs object-copies)]
                                                       object.id)))
     :revert (fn [_cmd]
               (local layer (activate-object-command-layer! layer-id))
               (for [idx (length object-copies) 1 -1]
                 (local object (. object-copies idx))
                 (local object-idx (DrawingDocument.object-index layer object.id))
                 (when object-idx
                   (DrawingDocument.remove-object-at! self.state.document layer object-idx)))
               (DrawingDocument.set-selection! self.state previous-selection))})

  (fn delete-objects-command [layer-id ids]
    (local layer (. self.state.document.layers (DrawingDocument.layer-index self.state.document layer-id)))
    (assert layer "DrawingController delete-objects missing layer")
    (assert (= layer.kind "vector")
            "DrawingController delete-objects requires vector layer")
    (local removed
      (icollect [_ object-id (ipairs ids)]
                (do
                  (local idx (DrawingDocument.object-index layer object-id))
                  (local object (and idx (. layer.objects idx)))
                  (and object {:id object-id
                               :index idx
                               :object (clone-table object)}))))
    (local filtered [])
    (each [_ record (ipairs removed)]
      (when record
        (table.insert filtered record)))
    (local previous-selection (clone-table self.state.ui.selection_ids))
    {:change-payload {:reason "vector-content"}
     :apply (fn [_cmd]
              (local target-layer (activate-object-command-layer! layer-id))
              (for [idx (length filtered) 1 -1]
                (local record (. filtered idx))
                (local object-idx (DrawingDocument.object-index target-layer record.id))
                (when object-idx
                  (DrawingDocument.remove-object-at! self.state.document target-layer object-idx)))
              (DrawingDocument.clear-selection! self.state))
     :revert (fn [_cmd]
               (local target-layer (activate-object-command-layer! layer-id))
               (each [_ record (ipairs filtered)]
                 (DrawingDocument.insert-object! self.state.document
                                                target-layer
                                                (clone-table record.object)
                                                record.index))
               (DrawingDocument.set-selection! self.state previous-selection))})

  (fn set-active-tool [tool]
    (assert (can-activate-tool? tool)
            (.. "DrawingController cannot activate tool without required state: " tool))
    (DrawingDocument.set-active-tool! self.state tool)
    (emit-changed {:reason "tool"}))

  (fn add-layer [kind]
    (local layer (DrawingDocument.alloc-layer! self.state.document kind))
    (perform! (add-layer-command layer nil) "layer-structure"))

  (fn delete-active-layer []
    (local document self.state.document)
    (local layer (active-layer))
    (local index (and layer (DrawingDocument.layer-index document layer.id)))
    (if (and layer index)
        (perform! (delete-layer-command (clone-table layer)
                                       index
                                       self.state.ui.active_layer_id
                                       (clone-table self.state.ui.selection_ids)
                                       (clone-raster-selection raster-selection))
                  "layer-structure")
        false))

  (fn move-active-layer [delta]
    (local layer (active-layer))
    (local from-index (and layer (DrawingDocument.layer-index self.state.document layer.id)))
    (local to-index (and from-index (+ from-index delta)))
    (if (and from-index
             to-index
             (>= to-index 1)
             (<= to-index (length self.state.document.layers)))
        (perform! (reorder-layer-command layer.id from-index to-index) "layer-structure")
        false))

  (fn set-active-layer [layer-id]
    (DrawingDocument.set-active-layer! self.state layer-id)
    (clear-raster-selection-state!)
    (emit-changed {:reason "active-layer"}))

  (fn rename-active-layer [value]
    (local layer (active-layer))
    (if (not layer)
        false
        (do
          (local next-name (DrawingDocument.validate-layer-name value
                                                               "rename-active-layer value"))
          (if (= next-name layer.name)
              false
              (perform! (rename-layer-command layer.id layer.name next-name) "layer-meta")))))

  (fn set-defaults! [changes]
    (DrawingDocument.set-defaults! self.state changes)
    (emit-changed {:reason "defaults"}))

  (fn sample-document-rgba [point]
    (var rgba [0 0 0 0])
    (each [_ layer (ipairs (or self.state.document.layers []))]
      (local layer-rgba
        (if (= layer.kind "raster")
            (do
              (local runtime (ensure-raster-runtime layer))
              (runtime:get-pixel-rgba
               (math.floor (+ point.x 0.5))
               (math.floor (+ point.y 0.5))))
            (DrawingSample.sample-vector-layer layer point)))
      (set rgba (DrawingSample.blend-rgba rgba layer-rgba)))
    rgba)

  (fn sample-point! [point]
    (local rgba (unpremultiply-rgba (sample-document-rgba point)))
    (local normalized [(/ (. rgba 1) 255.0)
                       (/ (. rgba 2) 255.0)
                       (/ (. rgba 3) 255.0)
                       (/ (. rgba 4) 255.0)])
    (set-defaults! {:stroke_color normalized
                    :fill_color normalized})
    true)

  (fn begin-gesture [tool point opts]
    (local options (or opts {}))
    (local kind (active-kind))
    (if (or (not kind)
            (not (= (type tool) :string))
            (not (can-activate-tool? tool)))
        false
        (do
          (DrawingDocument.validate-tool-for-kind kind tool)
          (local base-gesture {:tool tool
                               :start point
                               :current point
                               :touched_ids {}})
          (when (gesture-needs-points? tool)
            (set base-gesture.points [point]))
          (when (gesture-needs-samples? kind tool)
            (set base-gesture.samples
                 [{:point point
                   :pressure (or options.pressure 1.0)}]))
          (when (and (= (active-kind) "raster")
                     (= tool "move"))
            (do
              (local selection (active-raster-selection))
              (set base-gesture.selection selection)))
          (set gesture base-gesture)
          (emit-changed {:reason "gesture"}))))

  (fn gesture-active? []
    (not (= gesture nil)))

  (fn preview-object []
    (if (not gesture)
        nil
        (do
          (local tool gesture.tool)
          (local start gesture.start)
          (local current gesture.current)
          (local kind (active-kind))
          (if (not kind)
              nil
              (if (or (= tool "rectangle") (= tool "ellipse") (= tool "line"))
                  (make-shape-object self
                                     tool
                                     start
                                     current
                                     gesture.shift?
                                     {:preview? true})
                  (if (or (= tool "pen") (= tool "brush") (= tool "marker"))
                      {:id "__preview__"
                       :kind "stroke"
                       :points gesture.points
                       :preset tool
                       :style (if (= kind "raster")
                                  (raster-style-for-tool (current-defaults) tool)
                                  (stroke-style-for-tool (current-defaults) tool))}
                      (= tool "marquee")
                      (do
                        (local bounds ((ensure-raster-runtime (active-layer)):normalize-bounds start current))
                        {:id "__preview__"
                         :kind "rectangle"
                         :center (glm.vec3 (* (+ bounds.left bounds.right) 0.5)
                                           (* (+ bounds.bottom bounds.top) 0.5)
                                           0)
                         :size (glm.vec3 bounds.width bounds.height 0)
                         :style {:stroke_color [1.0 0.72 0.22 1.0]
                                 :fill_color [0 0 0 0]
                                 :thickness 1.5
                                 :opacity 1.0
                                 :fill_enabled false}})
                      nil))))))

  (fn preview-active? []
    (and gesture
         (tool-produces-preview? gesture.tool)))

  (fn cancel-gesture []
    (if gesture
        (do
          (set gesture nil)
          (emit-changed {:reason "gesture"}))
        false))

  (fn select-object [object-id ctrl?]
    (if ctrl?
        (do
          (DrawingDocument.toggle-selection-id! self.state object-id)
          (emit-changed (selection-payload "vector")))
        (set-selection! [object-id])))

  (fn select-at-point [object-id ctrl?]
    (if object-id
        (select-object object-id ctrl?)
        (if ctrl?
            false
            (clear-selection!))))

  (var raster-patch-command nil)

  (fn on-select [object ctrl?]
    (if (= (active-kind) "vector")
        (select-at-point (and object object.id) ctrl?)
        (not (active-kind))
        false
        (do
          (when (not ctrl?)
            (clear-raster-selection-state!)
            (emit-changed (selection-payload "raster")))
          false)))

  (fn on-delete-selection []
    (if (not (active-kind))
        false
        (if (not (= (active-kind) "vector"))
            (do
              (local selection (active-raster-selection))
              (if (not selection)
                  false
                  (perform! (raster-patch-command
                              selection.layer_id
                              (fn [runtime _layer]
                                (local moved (runtime:clear-selection! selection))
                                (clear-raster-selection-state!)
                                moved))
                            {:reason "raster-selection-content"})))
            (do
              (local ids (icollect [_ object-id (ipairs (selection-ids))]
                                   object-id))
              (if (= (length ids) 0)
                  false
                  (perform! (delete-objects-command self.state.ui.active_layer_id ids) "objects"))))))

  (fn on-undo []
    (local command (history:undo))
    (if command
        (emit-changed (command-payload command "history"))
        false))

  (fn on-redo []
    (local command (history:redo))
    (if command
        (emit-changed (command-payload command "history"))
        false))

  (fn update-gesture [point shift? opts]
    (local options (or opts {}))
    (when gesture
      (set gesture.current point)
      (set gesture.shift? (not (not shift?)))
      (when (= gesture.tool "move")
        (local dx (- (math.floor (+ point.x 0.5))
                     (math.floor (+ gesture.start.x 0.5))))
        (local dy (- (math.floor (+ point.y 0.5))
                     (math.floor (+ gesture.start.y 0.5))))
        (set gesture.offset {:x dx :y dy}))
      (when gesture.samples
        (table.insert gesture.samples {:point point
                                       :pressure (or options.pressure 1.0)}))
      (when gesture.points
        (local last-point (. gesture.points (length gesture.points)))
        (when (> (glm.length (- point last-point)) 0.35)
          (table.insert gesture.points point)))
      (emit-changed {:reason "gesture"})))

  (fn touch-erase-id! [object-id]
    (when (and gesture object-id)
      (set (. gesture.touched_ids object-id) true)
      true))

  (fn gesture-delete-ids []
    (local ids [])
    (local source
      (if gesture
          gesture.touched_ids
          {}))
    (each [object-id included? (pairs source)]
      (when included?
        (table.insert ids object-id)))
    ids)

  (fn commit-shape-gesture [layer]
    (local object
      (make-shape-object self
                         gesture.tool
                         gesture.start
                         gesture.current
                         gesture.shift?))
    (if (and object (not (object-empty? object)))
        (perform! (add-objects-command layer.id [object]) "objects")
        false))

  (fn commit-stroke-gesture [layer]
    (local points
      (icollect [_ point (ipairs gesture.points)]
                point))
    (local object {:id (DrawingDocument.alloc-object-id! self.state.document)
                   :kind "stroke"
                   :points points
                   :preset gesture.tool
                   :style (stroke-style-for-tool (current-defaults) gesture.tool)})
    (if (object-empty? object)
        false
        (perform! (add-objects-command layer.id [object]) "objects")))

  (fn commit-eraser-gesture [layer]
    (local ids (gesture-delete-ids))
    (if (> (length ids) 0)
        (perform! (delete-objects-command layer.id ids) "objects")
        false))

  (set raster-patch-command
       (fn [layer-id compute payload]
         (local command {:noop? false
                         :change-payload (normalize-change-payload payload "raster-content")})
         (var patches nil)
         (var selection-before nil)
         (var selection-after nil)
         (set command.apply
              (fn [_cmd]
                (local layer (. self.state.document.layers (DrawingDocument.layer-index self.state.document layer-id)))
                (assert layer "DrawingController raster command missing layer")
                (local runtime (ensure-raster-runtime layer))
                (if patches
                    (do
                      (runtime:apply-captured-bytes! patches.after)
                      (refresh-raster-selection-fragment! runtime)
                      (set-raster-selection! selection-after false)
                      (set command.noop? false))
                    (do
                      (set selection-before (clone-raster-selection raster-selection))
                      (set patches (compute runtime layer))
                      (refresh-raster-selection-fragment! runtime)
                      (set selection-after (clone-raster-selection raster-selection))
                      (set command.noop? (= patches.changed? false))))))
         (set command.revert
              (fn [_cmd]
                (local layer (. self.state.document.layers (DrawingDocument.layer-index self.state.document layer-id)))
                (when (and layer patches)
                  (local runtime (ensure-raster-runtime layer))
                  (runtime:apply-captured-bytes! patches.before)
                  (refresh-raster-selection-fragment! runtime)
                  (set-raster-selection! selection-before false))))
         command))

  (fn commit-raster-gesture [layer]
    (local tool gesture.tool)
    (if (= tool "marquee")
        (do
          (local runtime (ensure-raster-runtime layer))
          (local bounds (runtime:normalize-bounds gesture.start gesture.current))
          (set-raster-selection! {:layer_id layer.id
                                  :bounds bounds
                                  :fragment (runtime:capture-fragment bounds)}
                                 true)
          true)
        (= tool "move")
        (do
          (local selection (active-raster-selection))
          (local offset (or gesture.offset {:x 0 :y 0}))
          (if (or (not selection)
                  (and (= offset.x 0) (= offset.y 0)))
              false
              (perform! (raster-patch-command
                          layer.id
                          (fn [runtime _layer]
                            (local moved (runtime:move-selection! selection offset.x offset.y))
                            (set-raster-selection! {:layer_id layer.id
                                                    :bounds moved.bounds
                                                    :fragment (runtime:capture-fragment moved.bounds)}
                                                   false)
                            moved))
                        {:reason "raster-selection-content"})))
        (= tool "eyedropper")
        (sample-point! gesture.current)
        (= tool "fill")
        (do
          (local point gesture.current)
          (local style (raster-style-for-tool (current-defaults) tool))
          (perform! (raster-patch-command
                      layer.id
                      (fn [runtime _layer]
                        (runtime:fill! point style {:tolerance 24})))
                    {:reason "raster-content"}))
        (do
          (local samples (icollect [_ sample (ipairs (or gesture.samples []))]
                                   sample))
          (if (= (length samples) 0)
              false
              (do
                (local style (raster-style-for-tool (current-defaults) tool))
                (perform! (raster-patch-command
                            layer.id
                            (fn [runtime _layer]
                              (runtime:stroke! tool samples style)))
                          {:reason "raster-content"}))))))

  (fn commit-gesture []
    (if (not gesture)
        false
        (do
          (local tool gesture.tool)
          (local layer (active-layer))
          (local result
            (if (not layer)
                false
                (if (= layer.kind "raster")
                    (commit-raster-gesture layer)
                    (if (or (= tool "rectangle") (= tool "ellipse") (= tool "line"))
                        (commit-shape-gesture layer)
                        (if (or (= tool "pen") (= tool "brush") (= tool "marker"))
                            (commit-stroke-gesture layer)
                            (if (= tool "eraser")
                                (commit-eraser-gesture layer)
                                false))))))
          (set gesture nil)
          (emit-changed {:reason "gesture"})
          result)))

  (fn snapshot []
    (each [_ layer (ipairs (or self.state.document.layers []))]
      (when (= layer.kind "raster")
        (local runtime (ensure-raster-runtime layer))
        (runtime:save!)))
    (prune-stale-raster-storage!)
    (DrawingDocument.serialize-state self.state))

  (fn raster-overlay []
    (local selection (active-raster-selection))
    (if (not selection)
        nil
        (do
          (local overlay {:selection selection})
          (when (and gesture (= gesture.tool "move") gesture.offset)
            (set overlay.layer_id selection.layer_id)
            (set overlay.fragment selection.fragment)
            (set overlay.position {:x (+ selection.bounds.left gesture.offset.x)
                                   :y (+ selection.bounds.bottom gesture.offset.y)}))
          overlay)))

  (set self.emit-changed (fn [_self payload] (emit-changed payload)))
  (set self.active-layer (fn [_self] (active-layer)))
  (set self.active-tool (fn [_self] (active-tool)))
  (set self.persistent-tool (fn [_self] (persistent-tool)))
  (set self.can-activate-tool? (fn [_self tool] (can-activate-tool? tool)))
  (set self.can-add-raster-layer? (fn [_self] (can-add-raster-layer?)))
  (set self.current-defaults (fn [_self] (current-defaults)))
  (set self.selection-ids (fn [_self] (selection-ids)))
  (set self.set-selection! (fn [_self ids] (set-selection! ids)))
  (set self.clear-selection! (fn [_self] (clear-selection!)))
  (set self.set-active-tool (fn [_self tool] (set-active-tool tool)))
  (set self.add-layer (fn [_self kind] (add-layer kind)))
  (set self.delete-active-layer (fn [_self] (delete-active-layer)))
  (set self.move-active-layer (fn [_self delta] (move-active-layer delta)))
  (set self.set-active-layer (fn [_self layer-id] (set-active-layer layer-id)))
  (set self.rename-active-layer (fn [_self value] (rename-active-layer value)))
  (set self.layer-count (fn [_self] (length self.state.document.layers)))
  (set self.can-undo? (fn [_self] (history:can-undo?)))
  (set self.can-redo? (fn [_self] (history:can-redo?)))
  (set self.selection-count
       (fn [_self]
         (local kind (active-kind))
         (if (not kind)
             0
             (= kind "raster")
             (if (active-raster-selection) 1 0)
             (length (selection-ids)))))
  (set self.set-defaults! (fn [_self changes] (set-defaults! changes)))
  (set self.sample-point! (fn [_self point] (sample-point! point)))
  (set self.gesture-active? (fn [_self] (gesture-active?)))
  (set self.preview-active? (fn [_self] (preview-active?)))
  (set self.begin-gesture (fn [_self tool point opts] (begin-gesture tool point opts)))
  (set self.preview-object (fn [_self] (preview-object)))
  (set self.cancel-gesture (fn [_self] (cancel-gesture)))
  (set self.on-select (fn [_self object ctrl?] (on-select object ctrl?)))
  (set self.on-delete-selection (fn [_self] (on-delete-selection)))
  (set self.on-undo (fn [_self] (on-undo)))
  (set self.on-redo (fn [_self] (on-redo)))
  (set self.update-gesture (fn [_self point shift? opts] (update-gesture point shift? opts)))
  (set self.touch-erase-id! (fn [_self object-id] (touch-erase-id! object-id)))
  (set self.commit-gesture (fn [_self] (commit-gesture)))
  (set self.snapshot (fn [_self] (snapshot)))
  (set self.ensure-raster-runtime (fn [_self layer] (ensure-raster-runtime layer)))
  (set self.raster-selection (fn [_self] (active-raster-selection)))
  (set self.raster-overlay (fn [_self] (raster-overlay)))
  self)

DrawingController
