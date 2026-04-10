(local glm (require :glm))
(local _ (require :main))
(local DrawingDocument (require :drawing/document))
(local DrawingController (require :drawing/controller))

(local tests [])

(fn normalize-state-creates-default-layer []
  (local state (DrawingDocument.normalize-state {}))
  (DrawingDocument.ensure-default-layer! state)
  (assert (= (length state.document.layers) 1))
  (local layer (. state.document.layers 1))
  (assert (= layer.name "Layer 1"))
  (assert (= state.ui.active_layer_id layer.id))
  (assert (= state.ui.defaults.fill_enabled true))
  (assert (= (. state.ui.defaults.stroke_color 1) 0.33))
  (assert (= (. state.ui.defaults.stroke_color 2) 0.6))
  (assert (= (. state.ui.defaults.stroke_color 3) 0.96)))

(fn normalize-state-upgrades-legacy-default-style []
  (local state
    (DrawingDocument.normalize-state
      {:ui {:defaults {:stroke_color [0.96 0.96 0.98 1.0]
                       :fill_color [0.33 0.6 0.96 0.22]
                       :thickness 2.0
                       :opacity 1.0
                       :fill_enabled false}}}))
  (assert (= state.ui.defaults.fill_enabled true))
  (assert (= (. state.ui.defaults.stroke_color 1) 0.33))
  (assert (= (. state.ui.defaults.stroke_color 2) 0.6))
  (assert (= (. state.ui.defaults.stroke_color 3) 0.96)))

(fn controller-creates-rectangle-and-supports-undo-redo []
  (local controller (DrawingController {}))
  (controller:set-active-tool "rectangle")
  (controller:begin-gesture "rectangle" (glm.vec3 0 0 0))
  (controller:update-gesture (glm.vec3 10 5 0) false)
  (assert (controller:commit-gesture))
  (local layer (controller:active-layer))
  (assert (= (length layer.objects) 1))
  (local object (. layer.objects 1))
  (assert (= object.kind "rectangle"))
  (assert (= object.center.x 5))
  (assert (= object.center.y 2.5))
  (assert (= object.style.fill_enabled true))
  (assert (= (. object.style.stroke_color 1) 0.33))
  (assert (= (. object.style.stroke_color 2) 0.6))
  (assert (= (. object.style.stroke_color 3) 0.96))
  (assert (controller:on-undo))
  (assert (= (length layer.objects) 0))
  (assert (controller:on-redo))
  (assert (= (length layer.objects) 1)))

(fn snapshot-serializes-glm-vectors []
  (local controller (DrawingController {}))
  (controller:set-active-tool "line")
  (controller:begin-gesture "line" (glm.vec3 1 2 0))
  (controller:update-gesture (glm.vec3 6 8 0) false)
  (assert (controller:commit-gesture))
  (local snapshot (controller:snapshot))
  (local layer (. snapshot.document.layers 1))
  (local object (. layer.objects 1))
  (assert (= (type object.start) :table))
  (assert (= (. object.start 1) 1))
  (assert (= (. object.finish 2) 8)))

(fn controller-renames-layers-with-undo-redo []
  (local controller (DrawingController {}))
  (local layer (controller:active-layer))
  (assert (= layer.name "Layer 1"))
  (assert (controller:rename-active-layer "Sketch"))
  (assert (= (. (controller:active-layer) :name) "Sketch"))
  (assert (controller:on-undo))
  (assert (= (. (controller:active-layer) :name) "Layer 1"))
  (assert (controller:on-redo))
  (assert (= (. (controller:active-layer) :name) "Sketch")))

(fn controller-layer-structure-edits-undo-cleanly []
  (local controller (DrawingController {}))
  (assert (= (controller:layer-count) 1))
  (controller:add-layer)
  (assert (= (controller:layer-count) 2))
  (assert (= (. (controller:active-layer) :name) "Layer 2"))
  (assert (controller:rename-active-layer "Foreground"))
  (controller:move-active-layer -1)
  (assert (= (. (. controller.state.document.layers 1) :name) "Foreground"))
  (assert (controller:delete-active-layer))
  (assert (= (controller:layer-count) 1))
  (assert (controller:on-undo))
  (assert (= (controller:layer-count) 2))
  (assert (= (. (. controller.state.document.layers 1) :name) "Foreground"))
  (assert (controller:on-undo))
  (assert (= (. (. controller.state.document.layers 2) :name) "Foreground"))
  (assert (controller:on-undo))
  (assert (= (. (. controller.state.document.layers 2) :name) "Layer 2")))

(table.insert tests {:name "Drawing document ensures a default layer"
                     :fn normalize-state-creates-default-layer})
(table.insert tests {:name "Drawing document upgrades the legacy default style"
                     :fn normalize-state-upgrades-legacy-default-style})
(table.insert tests {:name "Drawing controller creates rectangle objects with undo/redo"
                     :fn controller-creates-rectangle-and-supports-undo-redo})
(table.insert tests {:name "Drawing controller snapshots serialize vector data"
                     :fn snapshot-serializes-glm-vectors})
(table.insert tests {:name "Drawing controller renames layers with undo/redo"
                     :fn controller-renames-layers-with-undo-redo})
(table.insert tests {:name "Drawing controller undoes layer structure edits cleanly"
                     :fn controller-layer-structure-edits-undo-cleanly})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-document"
                       :tests tests})))

{:name "drawing-document"
 :tests tests
 :main main}
