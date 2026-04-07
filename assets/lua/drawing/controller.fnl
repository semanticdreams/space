(local glm (require :glm))
(local Signal (require :signal))
(local DrawingDocument (require :drawing/document))
(local DrawingHistory (require :drawing/history))
(local HitTest (require :drawing/hit-test))

(fn clone-table [value]
  (DrawingDocument.clone-table value))

(fn trim-name [value]
  (if (not (= (type value) :string))
      ""
      (let [trimmed (string.match value "^%s*(.-)%s*$")]
        (or trimmed ""))))

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

(fn make-shape-object [controller tool start finish shift? opts]
  (local options (or opts {}))
  (local defaults (clone-table controller.state.ui.defaults))
  (local object-id
    (if options.preview?
        "__preview__"
        (DrawingDocument.alloc-object-id! controller.state.document)))
  (if (= tool "rectangle")
      (let [geometry (center-size-from-points start finish shift?)]
        {:id object-id
         :kind "rectangle"
         :center geometry.center
         :size geometry.size
         :style (DrawingDocument.normalize-style defaults)})
      (= tool "ellipse")
      (let [geometry (center-size-from-points start finish shift?)]
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
  (local initial-state
    (DrawingDocument.normalize-state
      {:document (or options.document (DrawingDocument.empty-document))
       :ui (or options.ui (DrawingDocument.default-ui))}))
  (DrawingDocument.ensure-default-layer! initial-state)
  (local changed (Signal))
  (local history (DrawingHistory))
  (var gesture nil)

  (local self {:state initial-state
               :changed changed
               :history history})

  (fn emit-changed [payload]
    (changed:emit (or payload {:reason "drawing-controller"}))
    true)

  (fn active-layer []
    (DrawingDocument.ensure-default-layer! self.state)
    (DrawingDocument.active-layer self.state))

  (fn selection-ids []
    (or self.state.ui.selection_ids []))

  (fn set-selection! [ids]
    (DrawingDocument.set-selection! self.state ids)
    (emit-changed {:reason "selection"}))

  (fn clear-selection! []
    (DrawingDocument.clear-selection! self.state)
    (emit-changed {:reason "selection"}))

  (fn perform! [command reason]
    (history:perform command)
    (emit-changed {:reason (or reason "history")}))

  (fn add-layer-command [layer index]
    {:apply (fn [_cmd]
              (DrawingDocument.insert-layer! self.state.document layer index)
              (set self.state.ui.active_layer_id layer.id)
              (DrawingDocument.clear-selection! self.state))
     :revert (fn [_cmd]
               (local idx (DrawingDocument.layer-index self.state.document layer.id))
               (when idx
                 (DrawingDocument.remove-layer-at! self.state.document idx))
               (DrawingDocument.ensure-default-layer! self.state))})

  (fn delete-layer-command [layer index previous-active previous-selection]
    {:apply (fn [_cmd]
              (local idx (DrawingDocument.layer-index self.state.document layer.id))
              (when idx
                (DrawingDocument.remove-layer-at! self.state.document idx))
              (local next-layer (. self.state.document.layers (math.max 1 (math.min index (length self.state.document.layers)))))
              (set self.state.ui.active_layer_id (and next-layer next-layer.id))
              (DrawingDocument.clear-selection! self.state))
     :revert (fn [_cmd]
               (DrawingDocument.insert-layer! self.state.document layer index)
               (set self.state.ui.active_layer_id previous-active)
               (DrawingDocument.set-selection! self.state previous-selection))})

  (fn reorder-layer-command [layer-id from-index to-index]
    {:apply (fn [_cmd]
              (DrawingDocument.move-layer! self.state.document from-index to-index))
     :revert (fn [_cmd]
               (DrawingDocument.move-layer! self.state.document to-index from-index))})

  (fn rename-layer-command [layer-id previous-name next-name]
    {:apply (fn [_cmd]
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
    {:apply (fn [_cmd]
              (local layer (. self.state.document.layers (DrawingDocument.layer-index self.state.document layer-id)))
              (assert layer "DrawingController add-objects missing layer")
              (each [_ object (ipairs object-copies)]
                (DrawingDocument.insert-object! layer object nil))
              (set self.state.ui.selection_ids
                   (icollect [_ object (ipairs object-copies)]
                             object.id)))
     :revert (fn [_cmd]
               (local layer (. self.state.document.layers (DrawingDocument.layer-index self.state.document layer-id)))
               (when layer
                 (for [idx (length object-copies) 1 -1]
                   (local object (. object-copies idx))
                   (local object-idx (DrawingDocument.object-index layer object.id))
                   (when object-idx
                     (DrawingDocument.remove-object-at! layer object-idx))))
               (DrawingDocument.clear-selection! self.state))})

  (fn delete-objects-command [layer-id ids]
    (local layer (. self.state.document.layers (DrawingDocument.layer-index self.state.document layer-id)))
    (assert layer "DrawingController delete-objects missing layer")
    (local removed
      (icollect [_ object-id (ipairs ids)]
                (let [idx (DrawingDocument.object-index layer object-id)
                      object (and idx (. layer.objects idx))]
                  (and object {:id object-id
                               :index idx
                               :object (clone-table object)}))))
    (local filtered [])
    (each [_ record (ipairs removed)]
      (when record
        (table.insert filtered record)))
    (local previous-selection (clone-table self.state.ui.selection_ids))
    {:apply (fn [_cmd]
              (local target-layer (. self.state.document.layers (DrawingDocument.layer-index self.state.document layer-id)))
              (when target-layer
                (for [idx (length filtered) 1 -1]
                  (local record (. filtered idx))
                  (local object-idx (DrawingDocument.object-index target-layer record.id))
                  (when object-idx
                    (DrawingDocument.remove-object-at! target-layer object-idx))))
              (DrawingDocument.clear-selection! self.state))
     :revert (fn [_cmd]
               (local target-layer (. self.state.document.layers (DrawingDocument.layer-index self.state.document layer-id)))
               (when target-layer
                 (each [_ record (ipairs filtered)]
                   (DrawingDocument.insert-object! target-layer (clone-table record.object) record.index)))
               (DrawingDocument.set-selection! self.state previous-selection))})

  (fn set-active-tool [tool]
    (set self.state.ui.active_tool tool)
    (emit-changed {:reason "tool"}))

  (fn add-layer []
    (local layer (DrawingDocument.alloc-layer! self.state.document))
    (perform! (add-layer-command layer nil) "layer"))

  (fn delete-active-layer []
    (local document self.state.document)
    (if (<= (length document.layers) 1)
        false
        (let [layer (active-layer)
              index (and layer (DrawingDocument.layer-index document layer.id))]
          (if (and layer index)
              (perform! (delete-layer-command (clone-table layer)
                                             index
                                             self.state.ui.active_layer_id
                                             (clone-table self.state.ui.selection_ids))
                        "layer")
              false))))

  (fn move-active-layer [delta]
    (local layer (active-layer))
    (local from-index (and layer (DrawingDocument.layer-index self.state.document layer.id)))
    (local to-index (and from-index (+ from-index delta)))
    (if (and from-index
             to-index
             (>= to-index 1)
             (<= to-index (length self.state.document.layers)))
        (perform! (reorder-layer-command layer.id from-index to-index) "layer")
        false))

  (fn set-active-layer [layer-id]
    (DrawingDocument.set-active-layer! self.state layer-id)
    (emit-changed {:reason "layer"}))

  (fn rename-active-layer [value]
    (local layer (active-layer))
    (if (not layer)
        false
        (let [next-name (trim-name value)]
          (if (or (= next-name "")
                  (= next-name layer.name))
              false
              (perform! (rename-layer-command layer.id layer.name next-name) "layer")))))

  (fn set-defaults! [changes]
    (each [k v (pairs changes)]
      (set (. self.state.ui.defaults k) v))
    (emit-changed {:reason "defaults"}))

  (fn begin-gesture [tool point]
    (set gesture {:tool tool
                  :start point
                  :current point
                  :points [point]
                  :touched_ids {}})
    (emit-changed {:reason "gesture"}))

  (fn gesture-active? []
    (not (= gesture nil)))

  (fn preview-object []
    (if (not gesture)
        nil
        (let [tool gesture.tool
              start gesture.start
              current gesture.current]
          (if (or (= tool "rectangle") (= tool "ellipse") (= tool "line"))
              (make-shape-object self tool start current gesture.shift? {:preview? true})
              (if (or (= tool "pen") (= tool "brush") (= tool "marker"))
                  {:id "__preview__"
                   :kind "stroke"
                   :points gesture.points
                   :preset tool
                   :style (stroke-style-for-tool self.state.ui.defaults tool)}
                  nil)))))

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
          (emit-changed {:reason "selection"}))
        (set-selection! [object-id])))

  (fn select-at-point [object-id ctrl?]
    (if object-id
        (select-object object-id ctrl?)
        (if ctrl?
            false
            (clear-selection!))))

  (fn on-select [object ctrl?]
    (select-at-point (and object object.id) ctrl?))

  (fn on-delete-selection []
    (local ids
      (icollect [_ object-id (ipairs (selection-ids))]
                object-id))
    (if (= (length ids) 0)
        false
        (perform! (delete-objects-command self.state.ui.active_layer_id ids) "objects")))

  (fn on-undo []
    (if (history:undo)
        (emit-changed {:reason "undo"})
        false))

  (fn on-redo []
    (if (history:redo)
        (emit-changed {:reason "redo"})
        false))

  (fn update-gesture [point shift?]
    (when gesture
      (set gesture.current point)
      (set gesture.shift? (not (not shift?)))
      (if (or (= gesture.tool "pen")
              (= gesture.tool "brush")
              (= gesture.tool "marker"))
          (let [last-point (. gesture.points (length gesture.points))]
            (when (> (glm.length (- point last-point)) 0.35)
              (table.insert gesture.points point))))
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
                   :style (stroke-style-for-tool self.state.ui.defaults gesture.tool)})
    (if (object-empty? object)
        false
        (perform! (add-objects-command layer.id [object]) "objects")))

  (fn commit-eraser-gesture [layer]
    (local ids (gesture-delete-ids))
    (if (> (length ids) 0)
        (perform! (delete-objects-command layer.id ids) "objects")
        false))

  (fn commit-gesture []
    (if (not gesture)
        false
        (do
          (local tool gesture.tool)
          (local layer (active-layer))
          (local result
            (if (or (= tool "rectangle") (= tool "ellipse") (= tool "line"))
                (commit-shape-gesture layer)
                (if (or (= tool "pen") (= tool "brush") (= tool "marker"))
                    (commit-stroke-gesture layer)
                    (if (= tool "eraser")
                        (commit-eraser-gesture layer)
                        false))))
          (set gesture nil)
          (emit-changed {:reason "gesture"})
          result)))

  (fn snapshot []
    (DrawingDocument.serialize-state self.state))

  (set self.emit-changed (fn [_self payload] (emit-changed payload)))
  (set self.active-layer (fn [_self] (active-layer)))
  (set self.selection-ids (fn [_self] (selection-ids)))
  (set self.set-selection! (fn [_self ids] (set-selection! ids)))
  (set self.clear-selection! (fn [_self] (clear-selection!)))
  (set self.set-active-tool (fn [_self tool] (set-active-tool tool)))
  (set self.add-layer (fn [_self] (add-layer)))
  (set self.delete-active-layer (fn [_self] (delete-active-layer)))
  (set self.move-active-layer (fn [_self delta] (move-active-layer delta)))
  (set self.set-active-layer (fn [_self layer-id] (set-active-layer layer-id)))
  (set self.rename-active-layer (fn [_self value] (rename-active-layer value)))
  (set self.layer-count (fn [_self] (length self.state.document.layers)))
  (set self.can-undo? (fn [_self] (history:can-undo?)))
  (set self.can-redo? (fn [_self] (history:can-redo?)))
  (set self.selection-count (fn [_self] (length (selection-ids))))
  (set self.set-defaults! (fn [_self changes] (set-defaults! changes)))
  (set self.gesture-active? (fn [_self] (gesture-active?)))
  (set self.begin-gesture (fn [_self tool point] (begin-gesture tool point)))
  (set self.preview-object (fn [_self] (preview-object)))
  (set self.cancel-gesture (fn [_self] (cancel-gesture)))
  (set self.on-select (fn [_self object ctrl?] (on-select object ctrl?)))
  (set self.on-delete-selection (fn [_self] (on-delete-selection)))
  (set self.on-undo (fn [_self] (on-undo)))
  (set self.on-redo (fn [_self] (on-redo)))
  (set self.update-gesture (fn [_self point shift?] (update-gesture point shift?)))
  (set self.touch-erase-id! (fn [_self object-id] (touch-erase-id! object-id)))
  (set self.commit-gesture (fn [_self] (commit-gesture)))
  (set self.snapshot (fn [_self] (snapshot)))
  self)

DrawingController
