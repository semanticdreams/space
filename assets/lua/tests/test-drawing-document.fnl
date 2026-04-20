(local glm (require :glm))
(local _ (require :main))
(local fs (require :fs))
(local DrawingDocument (require :drawing/document))
(local DrawingController (require :drawing/controller))

(local tests [])

(local temp-root (fs.join-path "/tmp/space/tests" "drawing-raster"))
(var temp-counter 0)

(fn with-temp-dir [f]
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "drawing-raster-" (os.time) "-" temp-counter)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (when (not ok)
    (error result))
  result)

(fn normalize-state-creates-default-layer []
  (local state (DrawingDocument.normalize-state {}))
  (DrawingDocument.ensure-default-layer! state)
  (assert (= (length state.document.layers) 1))
  (local layer (. state.document.layers 1))
  (local defaults (DrawingDocument.current-defaults state))
  (assert (= layer.name "Layer 1"))
  (assert (= state.ui.active_layer_id layer.id))
  (assert (= defaults.fill_enabled true))
  (assert (= (. defaults.stroke_color 1) 0.33))
  (assert (= (. defaults.stroke_color 2) 0.6))
  (assert (= (. defaults.stroke_color 3) 0.96)))

(fn normalize-state-upgrades-legacy-default-style []
  (local state
    (DrawingDocument.normalize-state
      {:ui {:defaults {:stroke_color [0.96 0.96 0.98 1.0]
                       :fill_color [0.33 0.6 0.96 0.22]
                       :thickness 2.0
                       :opacity 1.0
                       :fill_enabled false}}}))
  (local defaults (DrawingDocument.current-defaults state))
  (assert (= defaults.fill_enabled true))
  (assert (= (. defaults.stroke_color 1) 0.33))
  (assert (= (. defaults.stroke_color 2) 0.6))
  (assert (= (. defaults.stroke_color 3) 0.96)))

(fn normalize-state-keeps-legacy-defaults-out-of-raster-style []
  (local state
    (DrawingDocument.normalize-state
      {:document {:layers [{:id "layer-1"
                            :name "Layer 1"
                            :kind "vector"
                            :objects []}
                           {:id "layer-2"
                            :name "Layer 2"
                            :kind "raster"
                            :objects []
                            :storage {:scheme "png-tile-v1"
                                      :tile_size 128
                                      :channels 4
                                      :base_path "drawing/raster/layer-2"}}]}
       :ui {:active_layer_id "layer-1"
            :defaults {:stroke_color [0.96 0.96 0.98 1.0]
                       :fill_color [0.33 0.6 0.96 0.22]
                       :thickness 2.0
                       :opacity 1.0
                       :fill_enabled false}}}))
  (assert (= state.ui.defaults_by_kind.vector.fill_enabled true)
          "legacy shared defaults should still migrate the vector style")
  (assert (= state.ui.defaults_by_kind.raster.thickness 6.0)
          "legacy shared defaults should not overwrite canonical raster thickness")
  (assert (= state.ui.defaults_by_kind.raster.fill_enabled true)
          "legacy shared defaults should not turn raster fill off"))

(fn normalize-state-migrates-legacy-active-tool-by-active-kind []
  (local vector-state
    (DrawingDocument.normalize-state
      {:document {:layers [{:id "layer-1"
                            :name "Layer 1"
                            :kind "vector"
                            :objects []}]}
       :ui {:active_layer_id "layer-1"
            :active_tool "rectangle"}}))
  (assert (= vector-state.ui.active_tool_by_kind.vector "rectangle")
          "legacy shared tools should stay on the active vector kind when reopening old state")
  (assert (= vector-state.ui.active_tool_by_kind.raster "brush")
          "legacy vector state should leave raster tools at their default")
  (local raster-state
    (DrawingDocument.normalize-state
      {:document {:layers [{:id "layer-1"
                            :name "Layer 1"
                            :kind "raster"
                            :objects []
                            :storage {:scheme "png-tile-v1"
                                      :tile_size 128
                                      :channels 4
                                      :base_path "drawing/raster/layer-1"}}]}
       :ui {:active_layer_id "layer-1"
            :active_tool "rectangle"}}))
  (assert (= raster-state.ui.active_tool_by_kind.raster "rectangle")
          "legacy shared tools should stay on the active raster kind when reopening old state")
  (assert (= raster-state.ui.active_tool_by_kind.vector "select")
          "legacy raster state should leave vector tools at their default"))

(fn normalize-state-rejects-unknown-tools []
  (local state
    (DrawingDocument.normalize-state
      {:document {:layers [{:id "layer-1"
                            :name "Layer 1"
                            :kind "vector"
                            :objects []}
                           {:id "layer-2"
                            :name "Layer 2"
                            :kind "raster"
                            :objects []
                            :storage {:scheme "png-tile-v1"
                                      :tile_size 128
                                      :channels 4
                                      :base_path "drawing/raster/layer-2"}}]}
       :ui {:active_layer_id "layer-2"
            :active_tool_by_kind {:vector "banana"
                                  :raster "mystery"}}}))
  (assert (= state.ui.active_tool_by_kind.vector "select")
          "unknown vector tools should normalize to the canonical vector default")
  (assert (= state.ui.active_tool_by_kind.raster "brush")
          "unknown raster tools should normalize to the canonical raster default"))

(fn normalize-state-rejects-raster-layers-without-storage-path []
  (local (ok err)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "raster"
                                 :objects []
                                 :storage {:scheme "png-tile-v1"
                                           :tile_size 128
                                           :channels 4}}]}}))
  (assert (not ok)
          "raster layers without storage.base_path should fail during normalization")
  (assert (string.find err "storage.base_path")
          "normalization should explain the missing raster storage path")
  (local (ok-tile-size err-tile-size)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "raster"
                                 :objects []
                                 :storage {:scheme "png-tile-v1"
                                           :tile_size 0
                                           :channels 4
                                           :base_path "drawing/raster/layer-1"}}]}}))
  (assert (not ok-tile-size)
          "raster layers with invalid tile_size should fail during normalization")
  (assert (string.find err-tile-size "tile_size")
          "normalization should identify invalid raster tile sizes")
  (local (ok-base-path err-base-path)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "raster"
                                 :objects []
                                 :storage {:scheme "png-tile-v1"
                                           :tile_size 128
                                           :channels 4
                                           :base_path "../outside"}}]}}))
  (assert (not ok-base-path)
          "raster layers with escaped storage.base_path should fail during normalization")
  (assert (string.find err-base-path "direct child of drawing/raster")
          "normalization should explain raster storage path confinement"))

(fn normalize-state-canonicalizes-and-validates-persisted-defaults []
  (local state
    (DrawingDocument.normalize-state
      {:ui {:defaults_by_kind {:vector {:stroke_color [0.1 0.2 0.3 1.0]
                                        :fill_color [0.4 0.5 0.6 1.0]
                                        :thickness 3.0
                                        :opacity 0.75
                                        :fill_enabled true
                                        :banana 7}
                               :raster {:stroke_color [0.9 0.8 0.7 1.0]
                                        :fill_color [0.3 0.2 0.1 1.0]
                                        :thickness 8.0
                                        :opacity 0.5
                                        :fill_enabled false
                                        :pressure_size false
                                        :pressure_opacity true
                                        :banana 9}}}}))
  (assert (= state.ui.defaults_by_kind.vector.banana nil)
          "persisted vector defaults should drop unknown keys during normalization")
  (assert (= state.ui.defaults_by_kind.raster.banana nil)
          "persisted raster defaults should drop unknown keys during normalization")
  (local (ok err)
    (pcall DrawingDocument.normalize-state
           {:ui {:defaults_by_kind {:vector {:stroke_color [0.1 0.2 0.3 1.0]
                                             :fill_color [0.4 0.5 0.6 1.0]
                                             :thickness "banana"
                                             :opacity 1.0
                                             :fill_enabled true}}}}))
  (assert (not ok)
          "invalid persisted defaults should fail during normalization")
  (assert (string.find err "thickness")
          "persisted defaults failure should identify the invalid field")
  (local (ok-container err-container)
    (pcall DrawingDocument.normalize-state
           {:ui {:defaults_by_kind {:vector "banana"}}}))
  (assert (not ok-container)
          "malformed persisted default containers should fail during normalization")
  (assert (string.find err-container "defaults_by_kind.vector")
          "persisted default container failure should identify the malformed kind payload"))

(fn normalize-state-rejects-malformed-document-containers []
  (local (ok-document err-document)
    (pcall DrawingDocument.normalize-state
           {:document "banana"}))
  (assert (not ok-document)
          "malformed persisted document payloads should fail during normalization")
  (assert (string.find err-document "document must be a table")
          "document normalization should identify malformed document payloads")
  (local (ok-layers err-layers)
    (pcall DrawingDocument.normalize-state
           {:document {:layers "banana"}}))
  (assert (not ok-layers)
          "malformed persisted document.layers payloads should fail during normalization")
  (assert (string.find err-layers "document.layers must be an array table")
          "document normalization should identify malformed layers payloads")
  (local (ok-layer-shape err-layer-shape)
    (pcall DrawingDocument.normalize-state
           {:document {:layers {[2] {:id "layer-2"
                                     :name "Layer 2"
                                     :kind "vector"
                                     :objects []}}}}))
  (assert (not ok-layer-shape)
          "sparse persisted layer tables should fail during normalization")
  (assert (string.find err-layer-shape "document.layers must be an array table")
          "document normalization should reject non-sequence layer tables")
  (local (ok-object-shape err-object-shape)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "vector"
                                 :objects {[2] {:id "object-2"
                                                :kind "line"
                                                :start [0 0 0]
                                                :finish [1 1 0]
                                                :style {:stroke_color [0.1 0.2 0.3 1.0]
                                                        :fill_color [0.4 0.5 0.6 1.0]
                                                        :thickness 1.0
                                                        :opacity 1.0
                                                        :fill_enabled false}}}}]}}))
  (assert (not ok-object-shape)
          "sparse persisted object tables should fail during normalization")
  (assert (string.find err-object-shape "document layer objects must be an array table")
          "document normalization should reject non-sequence object tables"))

(fn normalize-state-rejects-invalid-document-counters []
  (local (ok-layer-counter err-layer-counter)
    (pcall DrawingDocument.normalize-state
           {:document {:next_layer_id "banana"}}))
  (assert (not ok-layer-counter)
          "invalid next_layer_id should fail during normalization")
  (assert (string.find err-layer-counter "document.next_layer_id")
          "counter normalization should identify invalid next_layer_id")
  (local (ok-object-counter err-object-counter)
    (pcall DrawingDocument.normalize-state
           {:document {:next_object_id 0}}))
  (assert (not ok-object-counter)
          "invalid next_object_id should fail during normalization")
  (assert (string.find err-object-counter "document.next_object_id")
          "counter normalization should identify invalid next_object_id"))

(fn normalize-state-canonicalizes-document-counters []
  (local style {:stroke_color [0.1 0.2 0.3 1.0]
                :fill_color [0.4 0.5 0.6 1.0]
                :thickness 1.0
                :opacity 1.0
                :fill_enabled false})
  (local state
    (DrawingDocument.normalize-state
      {:document {:next_layer_id 1
                  :next_object_id 1
                  :layers [{:id "layer-3"
                            :name "Layer 3"
                            :kind "vector"
                            :objects [{:id "object-8"
                                       :kind "line"
                                       :start [0 0 0]
                                       :finish [1 1 0]
                                       :style style}]}]}
       :ui {:active_layer_id "layer-3"}}))
  (assert (= state.document.next_layer_id 4)
          "normalization should bump next_layer_id past existing generated ids")
  (assert (= state.document.next_object_id 9)
          "normalization should bump next_object_id past existing generated ids")
  (assert (= (. (DrawingDocument.alloc-layer! state.document "vector") :id) "layer-4")
          "layer allocation should use the canonicalized next layer id")
  (assert (= (DrawingDocument.alloc-object-id! state.document) "object-9")
          "object allocation should use the canonicalized next object id"))

(fn normalize-state-canonicalizes-layer-counter-against-raster-storage-roots []
  (local state
    (DrawingDocument.normalize-state
      {:document {:next_layer_id 1
                  :layers [{:id "foo"
                            :name "Raster"
                            :kind "raster"
                            :objects []
                            :storage {:scheme "png-tile-v1"
                                      :tile_size 128
                                      :channels 4
                                      :base_path "drawing/raster/layer-4"}}]}
       :ui {:active_layer_id "foo"}}))
  (assert (= state.document.next_layer_id 5)
          "normalization should bump next_layer_id past existing generated raster storage roots")
  (local added (DrawingDocument.alloc-layer! state.document "raster"))
  (assert (= added.id "layer-5")
          "raster layer allocation should avoid ids implied by persisted storage roots")
  (assert (= added.storage.base_path "drawing/raster/layer-5")
          "raster layer allocation should avoid future storage root collisions"))

(fn normalize-state-rejects-impossible-layer-payloads []
  (local (ok-vector err-vector)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "vector"
                                 :objects []
                                 :storage {:scheme "png-tile-v1"
                                           :tile_size 128
                                           :channels 4
                                           :base_path "drawing/raster/layer-1"}}]}}))
  (assert (not ok-vector)
          "vector layers should reject raster storage payloads instead of dropping them")
  (assert (string.find err-vector "vector layers must not define storage")
          "vector layer normalization should identify invalid storage payloads")
  (local (ok-raster err-raster)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "raster"
                                 :objects [{}]
                                 :storage {:scheme "png-tile-v1"
                                           :tile_size 128
                                           :channels 4
                                           :base_path "drawing/raster/layer-1"}}]}}))
  (assert (not ok-raster)
          "raster layers should reject persisted vector objects instead of dropping them")
  (assert (string.find err-raster "raster layers must not persist vector objects")
          "raster layer normalization should identify invalid object payloads"))

(fn normalize-state-rejects-invalid-layer-names []
  (local (ok-name-type err-name-type)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name {}
                                 :kind "vector"
                                 :objects []}]}}))
  (assert (not ok-name-type)
          "layer names should remain typed strings during normalization")
  (assert (string.find err-name-type "document layer.name")
          "layer name normalization should identify malformed layer names")
  (local (ok-name-trim err-name-trim)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "  Layer 1  "
                                 :kind "vector"
                                 :objects []}]}}))
  (assert (not ok-name-trim)
          "layer names should reject non-canonical trimmed values during normalization")
  (assert (string.find err-name-trim "already be trimmed")
          "layer name normalization should explain the canonical trimmed-name contract"))

(fn normalize-state-rejects-duplicate-raster-storage-paths []
  (local (ok-storage err-storage)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "raster"
                                 :objects []
                                 :storage {:scheme "png-tile-v1"
                                           :tile_size 128
                                           :channels 4
                                           :base_path "drawing/raster/shared"}}
                                {:id "layer-2"
                                 :name "Layer 2"
                                 :kind "raster"
                                 :objects []
                                 :storage {:scheme "png-tile-v1"
                                           :tile_size 128
                                           :channels 4
                                           :base_path "drawing/raster/shared"}}]}}))
  (assert (not ok-storage)
          "raster layers should reject shared storage roots instead of aliasing tiles")
  (assert (string.find err-storage "duplicate raster storage.base_path")
          "raster storage normalization should identify duplicate persisted storage roots"))

(fn normalize-state-rejects-malformed-vector-geometry []
  (local style {:stroke_color [0.1 0.2 0.3 1.0]
                :fill_color [0.4 0.5 0.6 1.0]
                :thickness 1.0
                :opacity 1.0
                :fill_enabled false})
  (local (ok-start err-start)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "vector"
                                 :objects [{:id "object-1"
                                            :kind "line"
                                            :start "banana"
                                            :finish [1 1 0]
                                            :style style}]}]}}))
  (assert (not ok-start)
          "malformed vector point payloads should fail during normalization")
  (assert (string.find err-start "document object.start")
          "vector geometry normalization should identify malformed point fields")
  (local (ok-points err-points)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "vector"
                                 :objects [{:id "object-1"
                                            :kind "stroke"
                                            :points {[2] [1 1 0]}
                                            :style style}]}]}}))
  (assert (not ok-points)
          "sparse stroke point arrays should fail during normalization")
  (assert (string.find err-points "document object.points")
          "vector geometry normalization should reject non-sequence stroke point arrays"))

(fn normalize-state-rejects-malformed-object-style []
  (local (ok-style err-style)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "vector"
                                 :objects [{:id "object-1"
                                            :kind "line"
                                            :start [0 0 0]
                                            :finish [1 1 0]
                                            :style "banana"}]}]}}))
  (assert (not ok-style)
          "malformed object.style payloads should fail during normalization")
  (assert (string.find err-style "document object.style")
          "object style normalization should identify malformed style payloads"))

(fn normalize-state-rejects-invalid-document-ids []
  (local style {:stroke_color [0.1 0.2 0.3 1.0]
                :fill_color [0.4 0.5 0.6 1.0]
                :thickness 1.0
                :opacity 1.0
                :fill_enabled false})
  (local (ok-layer-id err-layer-id)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id ""
                                 :name "Layer 1"
                                 :kind "vector"
                                 :objects []}]}}))
  (assert (not ok-layer-id)
          "empty layer ids should fail during normalization")
  (assert (string.find err-layer-id "document layer.id")
          "layer id normalization should identify invalid layer ids")
  (local (ok-object-id err-object-id)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "vector"
                                 :objects [{:id ""
                                            :kind "line"
                                            :start [0 0 0]
                                            :finish [1 1 0]
                                            :style style}]}]}}))
  (assert (not ok-object-id)
          "empty object ids should fail during normalization")
  (assert (string.find err-object-id "document object.id")
          "object id normalization should identify invalid object ids"))

(fn normalize-state-rejects-duplicate-document-ids []
  (local style {:stroke_color [0.1 0.2 0.3 1.0]
                :fill_color [0.4 0.5 0.6 1.0]
                :thickness 1.0
                :opacity 1.0
                :fill_enabled false})
  (local (ok-layer-id err-layer-id)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "vector"
                                 :objects []}
                                {:id "layer-1"
                                 :name "Layer 2"
                                 :kind "vector"
                                 :objects []}]}}))
  (assert (not ok-layer-id)
          "duplicate layer ids should fail during normalization")
  (assert (string.find err-layer-id "duplicate layer id")
          "layer normalization should identify duplicate layer ids")
  (local (ok-object-id err-object-id)
    (pcall DrawingDocument.normalize-state
           {:document {:layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "vector"
                                 :objects [{:id "object-1"
                                            :kind "line"
                                            :start [0 0 0]
                                            :finish [1 1 0]
                                            :style style}]}
                                {:id "layer-2"
                                 :name "Layer 2"
                                 :kind "vector"
                                 :objects [{:id "object-1"
                                            :kind "line"
                                            :start [1 1 0]
                                            :finish [2 2 0]
                                            :style style}]}]}}))
  (assert (not ok-object-id)
          "duplicate object ids should fail during normalization")
  (assert (string.find err-object-id "duplicate object id")
          "object normalization should identify duplicate object ids"))

(fn normalize-state-canonicalizes-object-schema []
  (local style {:stroke_color [0.1 0.2 0.3 1.0]
                :fill_color [0.4 0.5 0.6 1.0]
                :thickness 1.0
                :opacity 1.0
                :fill_enabled false})
  (local state
    (DrawingDocument.normalize-state
      {:document {:layers [{:id "layer-1"
                            :name "Layer 1"
                            :kind "vector"
                            :banana 9
                            :objects [{:id "object-1"
                                       :kind "line"
                                       :start [0 0 0]
                                       :finish [1 1 0]
                                       :style style
                                       :banana 7}]}]}
       :ui {:active_layer_id "layer-1"}}))
  (local layer (. state.document.layers 1))
  (local object (. layer.objects 1))
  (assert (= layer.banana nil)
          "load-time layer normalization should drop unknown layer fields")
  (assert (= object.banana nil)
          "load-time object normalization should drop unknown object fields")
  (local snapshot (DrawingDocument.serialize-state state))
  (local serialized-layer (. snapshot.document.layers 1))
  (local serialized-object (. serialized-layer.objects 1))
  (assert (= serialized-layer.banana nil)
          "serialization should not reintroduce unknown layer fields")
  (assert (= serialized-object.banana nil)
          "serialization should only persist the canonical object schema"))

(fn runtime-insert-apis-canonicalize-and-validate []
  (local style {:stroke_color [0.1 0.2 0.3 1.0]
                :fill_color [0.4 0.5 0.6 1.0]
                :thickness 1.0
                :opacity 1.0
                :fill_enabled false})
  (local document (DrawingDocument.empty-document))
  (DrawingDocument.insert-layer! document
                                {:id "layer-1"
                                 :name "Layer 1"
                                 :kind "vector"
                                 :banana 9
                                 :objects []}
                                nil)
  (local layer (. document.layers 1))
  (assert (= layer.banana nil)
          "runtime layer insertion should drop unknown layer fields")
  (DrawingDocument.insert-object! document
                                  layer
                                  {:id "object-1"
                                   :kind "line"
                                   :start [0 0 0]
                                   :finish [1 1 0]
                                   :style style
                                   :banana 7}
                                  nil)
  (local object (. layer.objects 1))
  (assert (= object.banana nil)
          "runtime object insertion should drop unknown object fields")
  (local snapshot
    (DrawingDocument.serialize-state
      {:document document
       :ui {:active_layer_id "layer-1"}}))
  (local snapshot-layer (. snapshot.document.layers 1))
  (local snapshot-object (. snapshot-layer.objects 1))
  (assert (= snapshot-object.banana nil)
          "runtime-inserted objects should serialize without unknown fields")
  (local (ok-layer-id err-layer-id)
    (pcall DrawingDocument.insert-layer!
           document
           {:id "layer-1"
            :name "Layer 2"
            :kind "vector"
            :objects []}
           nil))
  (assert (not ok-layer-id)
          "runtime layer insertion should reject duplicate layer ids")
  (assert (string.find err-layer-id "duplicate layer id")
          "runtime layer insertion should identify duplicate layer ids")
  (local (ok-object-id err-object-id)
    (pcall DrawingDocument.insert-object!
           document
           layer
           {:id "object-1"
            :kind "line"
            :start [1 1 0]
            :finish [2 2 0]
            :style style}
           nil))
  (assert (not ok-object-id)
          "runtime object insertion should reject duplicate object ids")
  (assert (string.find err-object-id "duplicate object id")
          "runtime object insertion should identify duplicate object ids")
  (DrawingDocument.insert-layer! document
                                {:id "layer-2"
                                 :name "Layer 2"
                                 :kind "raster"
                                 :objects []
                                 :storage {:scheme "png-tile-v1"
                                           :tile_size 128
                                           :channels 4
                                           :base_path "drawing/raster/layer-2"}}
                                nil)
  (local (ok-storage err-storage)
    (pcall DrawingDocument.insert-layer!
           document
           {:id "layer-3"
            :name "Layer 3"
            :kind "raster"
            :objects []
            :storage {:scheme "png-tile-v1"
                      :tile_size 128
                      :channels 4
                      :base_path "drawing/raster/layer-2"}}
           nil))
  (assert (not ok-storage)
          "runtime layer insertion should reject duplicate raster storage roots")
  (assert (string.find err-storage "duplicate raster storage.base_path")
          "runtime layer insertion should identify duplicate raster storage roots"))

(fn runtime-mutation-boundary-rejects-invalid-indices-and-wrong-vec3-userdata []
  (local style {:stroke_color [0.1 0.2 0.3 1.0]
                :fill_color [0.4 0.5 0.6 1.0]
                :thickness 1.0
                :opacity 1.0
                :fill_enabled false})
  (local document (DrawingDocument.empty-document))
  (local (ok-layer-idx err-layer-idx)
    (pcall DrawingDocument.insert-layer!
           document
           {:id "layer-1"
            :name "Layer 1"
            :kind "vector"
            :objects []}
           2))
  (assert (not ok-layer-idx)
          "runtime layer insertion should reject out-of-range indexes instead of clamping them")
  (assert (string.find err-layer-idx "insert%-layer! idx")
          "runtime layer insertion should identify the bad index input")
  (DrawingDocument.insert-layer! document
                                {:id "layer-1"
                                 :name "Layer 1"
                                 :kind "vector"
                                 :objects []}
                                nil)
  (local layer (. document.layers 1))
  (local (ok-object-idx err-object-idx)
    (pcall DrawingDocument.insert-object!
           document
           layer
           {:id "object-1"
            :kind "line"
            :start [0 0 0]
            :finish [1 1 0]
            :style style}
           2))
  (assert (not ok-object-idx)
          "runtime object insertion should reject out-of-range indexes instead of clamping them")
  (assert (string.find err-object-idx "insert%-object! idx")
          "runtime object insertion should identify the bad index input")
  (DrawingDocument.insert-object! document
                                  layer
                                  {:id "object-1"
                                   :kind "line"
                                   :start [0 0 0]
                                   :finish [1 1 0]
                                   :style style}
                                  nil)
  (local (ok-remove-layer err-remove-layer)
    (pcall DrawingDocument.remove-layer-at! document nil))
  (assert (not ok-remove-layer)
          "runtime layer removal should reject missing indexes instead of removing the last layer")
  (assert (string.find err-remove-layer "remove%-layer%-at! idx")
          "runtime layer removal should identify the missing index")
  (local (ok-remove-object err-remove-object)
    (pcall DrawingDocument.remove-object-at! document layer 0))
  (assert (not ok-remove-object)
          "runtime object removal should reject invalid indexes instead of silently no-oping")
  (assert (string.find err-remove-object "remove%-object%-at! idx")
          "runtime object removal should identify the invalid index")
  (local detached-layer (DrawingDocument.clone-table layer))
  (DrawingDocument.remove-object-at! document detached-layer 1)
  (assert (= (length layer.objects) 0)
          "runtime object removal should resolve canonical document layers instead of mutating detached layer tables")
  (assert (= (length detached-layer.objects) 1)
          "runtime object removal should leave detached layer copies untouched")
  (DrawingDocument.insert-layer! document
                                {:id "layer-2"
                                 :name "Layer 2"
                                 :kind "vector"
                                 :objects []}
                                nil)
  (local (ok-move-from err-move-from)
    (pcall DrawingDocument.move-layer! document nil 1))
  (assert (not ok-move-from)
          "layer reordering should reject missing source indexes instead of silently succeeding")
  (assert (string.find err-move-from "move%-layer! from%-idx")
          "layer reordering should identify the missing source index")
  (local (ok-move-to err-move-to)
    (pcall DrawingDocument.move-layer! document 1 3))
  (assert (not ok-move-to)
          "layer reordering should reject out-of-range target indexes instead of silently repairing them")
  (assert (string.find err-move-to "move%-layer! to%-idx")
          "layer reordering should identify the invalid target index")
  (local (ok-vec3 err-vec3)
    (pcall DrawingDocument.insert-object!
           document
           layer
           {:id "object-2"
            :kind "line"
            :start (glm.vec4 0 0 0 1)
            :finish [1 1 0]
            :style style}
           nil))
  (assert (not ok-vec3)
          "runtime object insertion should reject wrong userdata geometry instead of treating it as vec3")
  (assert (string.find err-vec3 "glm.vec3 or a 3%-channel array")
          "runtime object insertion should explain the vec3 contract for geometry fields")
  (local (ok-constructor-finite err-constructor-finite)
    (pcall glm.vec3 math.huge 0 0))
  (assert (not ok-constructor-finite)
          "glm.vec3 construction should reject non-finite components")
  (assert (string.find err-constructor-finite "components must be finite")
          "glm.vec3 constructor rejection should explain the non-finite component contract")
  (local (ok-constructor-magnitude err-constructor-magnitude)
    (pcall glm.vec3 1000001 0 0))
  (assert (not ok-constructor-magnitude)
          "glm.vec3 construction should reject vectors beyond the magnitude limit")
  (assert (string.find err-constructor-magnitude "magnitude exceeds threshold")
          "glm.vec3 constructor rejection should explain the magnitude limit")
  (local vec (glm.vec3 1 2 3))
  (local (ok-setter err-setter)
    (pcall (fn []
             (set vec.x 1000001))))
  (assert (not ok-setter)
          "glm.vec3 property writes should fail before mutating live userdata")
  (assert (string.find err-setter "magnitude exceeds threshold after setting x")
          "glm.vec3 property write rejection should identify the setter magnitude contract")
  (assert (= vec.x 1)
          "failed glm.vec3 property writes should leave the original x component intact")
  (assert (= vec.y 2)
          "failed glm.vec3 property writes should leave untouched components intact")
  (assert (= vec.z 3)
          "failed glm.vec3 property writes should leave untouched components intact")
  (local (ok-indexed-setter err-indexed-setter)
    (pcall (fn []
             (set (. vec 2) 1000001))))
  (assert (not ok-indexed-setter)
          "glm.vec3 indexed writes should fail before mutating live userdata")
  (assert (string.find err-indexed-setter "magnitude exceeds threshold after indexed set")
          "glm.vec3 indexed write rejection should identify the indexed setter magnitude contract")
  (assert (= vec.y 2)
          "failed glm.vec3 indexed writes should leave the original component intact"))

(fn normalize-state-rejects-malformed-selection-ids []
  (local (ok-selection-shape err-selection-shape)
    (pcall DrawingDocument.normalize-state
           {:ui {:selection_ids "banana"}}))
  (assert (not ok-selection-shape)
          "malformed selection_ids payloads should fail during normalization")
  (assert (string.find err-selection-shape "ui.selection_ids")
          "selection normalization should identify malformed selection_ids payloads")
  (local (ok-selection-entry err-selection-entry)
    (pcall DrawingDocument.normalize-state
           {:ui {:selection_ids [7]}}))
  (assert (not ok-selection-entry)
          "selection_ids entries should remain typed ids during normalization")
  (assert (string.find err-selection-entry "ui.selection_ids%[1%]")
          "selection normalization should identify malformed selection_ids entries"))

(fn normalize-state-canonicalizes-persisted-selection-ids []
  (local style {:stroke_color [0.1 0.2 0.3 1.0]
                :fill_color [0.4 0.5 0.6 1.0]
                :thickness 1.0
                :opacity 1.0
                :fill_enabled false})
  (local state
    (DrawingDocument.normalize-state
      {:document {:layers [{:id "layer-1"
                            :name "Layer 1"
                            :kind "vector"
                            :objects [{:id "object-1"
                                       :kind "line"
                                       :start [0 0 0]
                                       :finish [1 1 0]
                                       :style style}]}]}
       :ui {:active_layer_id "layer-1"
            :selection_ids ["object-1" "ghost" "object-1"]}}))
  (assert (= (length state.ui.selection_ids) 1)
          "persisted selection ids should be deduplicated and filtered to real active-layer objects")
  (assert (= (. state.ui.selection_ids 1) "object-1")
          "persisted selection ids should keep valid active-layer ids")
  (local repaired
    (DrawingDocument.normalize-state
      {:document {:layers [{:id "layer-1"
                            :name "Layer 1"
                            :kind "vector"
                            :objects [{:id "object-1"
                                       :kind "line"
                                       :start [0 0 0]
                                       :finish [1 1 0]
                                       :style style}]}]}
       :ui {:active_layer_id "missing-layer"
            :selection_ids ["object-1"]}}))
  (assert (= repaired.ui.active_layer_id "layer-1")
          "normalization should still repair invalid active layer ids")
  (assert (= (length repaired.ui.selection_ids) 0)
          "repairing the active layer should clear persisted selection ids"))

(fn runtime-selection-api-rejects-invalid-requests []
  (local style {:stroke_color [0.1 0.2 0.3 1.0]
                :fill_color [0.4 0.5 0.6 1.0]
                :thickness 1.0
                :opacity 1.0
                :fill_enabled false})
  (local vector-state
    (DrawingDocument.normalize-state
      {:document {:layers [{:id "layer-1"
                            :name "Layer 1"
                            :kind "vector"
                            :objects [{:id "object-1"
                                       :kind "line"
                                       :start [0 0 0]
                                       :finish [1 1 0]
                                       :style style}]}]}
       :ui {:active_layer_id "layer-1"}}))
  (local (ok-ghost err-ghost)
    (pcall DrawingDocument.set-selection! vector-state ["ghost"]))
  (assert (not ok-ghost)
          "runtime selection should reject unknown ids instead of silently dropping them")
  (assert (string.find err-ghost "unknown id")
          "runtime selection failure should identify unknown ids")
  (local (ok-dup err-dup)
    (pcall DrawingDocument.set-selection! vector-state ["object-1" "object-1"]))
  (assert (not ok-dup)
          "runtime selection should reject duplicate ids instead of deduplicating them")
  (assert (string.find err-dup "duplicate id")
          "runtime selection failure should identify duplicate ids")
  (local (ok-toggle err-toggle)
    (pcall DrawingDocument.toggle-selection-id! vector-state "ghost"))
  (assert (not ok-toggle)
          "runtime toggle-selection should reject unknown ids")
  (assert (string.find err-toggle "unknown id")
          "toggle-selection failure should identify unknown ids")
  (local raster-state
    (DrawingDocument.normalize-state
      {:document {:layers [{:id "layer-1"
                            :name "Layer 1"
                            :kind "raster"
                            :objects []
                            :storage {:scheme "png-tile-v1"
                                      :tile_size 128
                                      :channels 4
                                      :base_path "drawing/raster/layer-1"}}]}
       :ui {:active_layer_id "layer-1"}}))
  (local (ok-raster err-raster)
    (pcall DrawingDocument.set-selection! raster-state []))
  (assert (not ok-raster)
          "runtime selection should reject raster layers instead of silently clearing")
  (assert (string.find err-raster "active vector layer")
          "runtime selection failure should identify vector-only selection state"))

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

(fn controller-rejects-uncanonical-runtime-layer-name []
  (local controller (DrawingController {}))
  (local (ok err) (pcall controller.rename-active-layer controller "  Sketch  "))
  (assert (not ok)
          "runtime layer renames should reject non-canonical trimmed names")
  (assert (string.find err "must already be trimmed")
          "runtime layer rename rejection should explain the canonical trimmed-name contract")
  (assert (= (. (controller:active-layer) :name) "Layer 1")
          "rejected runtime renames should leave the layer name unchanged"))

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

(fn controller-object-history-replays-in-layer-context []
  (local controller (DrawingController {}))
  (controller:set-active-tool "rectangle")
  (controller:begin-gesture "rectangle" (glm.vec3 0 0 0))
  (controller:update-gesture (glm.vec3 10 10 0) false)
  (assert (controller:commit-gesture))
  (local layer1-id (. (. controller.state.document.layers 1) :id))
  (controller:add-layer "vector")
  (local layer2-id (. (. controller.state.document.layers 2) :id))
  (controller:set-active-layer layer1-id)
  (controller:set-active-tool "rectangle")
  (controller:begin-gesture "rectangle" (glm.vec3 20 20 0))
  (controller:update-gesture (glm.vec3 30 30 0) false)
  (assert (controller:commit-gesture))
  (local layer1 (. controller.state.document.layers 1))
  (local added-id (. (. layer1.objects 2) :id))
  (controller:set-active-layer layer2-id)
  (assert (controller:on-undo))
  (assert (= controller.state.ui.active_layer_id layer1-id)
          "undo should replay object history on the layer that owns the objects")
  (assert (= (length layer1.objects) 1)
          "undo should remove the replayed object from its original layer")
  (assert (= (length controller.state.ui.selection_ids) 0)
          "undo should restore the pre-command selection on that layer")
  (controller:set-active-layer layer2-id)
  (assert (controller:on-redo))
  (assert (= controller.state.ui.active_layer_id layer1-id)
          "redo should reactivate the object layer before restoring selection")
  (assert (= (length layer1.objects) 2)
          "redo should restore the object on its original layer")
  (assert (= (length controller.state.ui.selection_ids) 1)
          "redo should restore the added object selection")
  (assert (= (. controller.state.ui.selection_ids 1) added-id)
          "redo should select the restored object id on its owning layer")
  (assert (controller:on-delete-selection))
  (assert (= (length layer1.objects) 1)
          "delete should remove the selected object")
  (controller:set-active-layer layer2-id)
  (assert (controller:on-undo))
  (assert (= controller.state.ui.active_layer_id layer1-id)
          "undoing delete should reactivate the layer that owned the deleted objects")
  (assert (= (length layer1.objects) 2)
          "undoing delete should restore the removed object")
  (assert (= (length controller.state.ui.selection_ids) 1)
          "undoing delete should restore the deleted-object selection")
  (assert (= (. controller.state.ui.selection_ids 1) added-id)
          "undoing delete should restore selection for the restored object"))

(fn controller-remembers-tools-by-layer-kind []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:set-active-tool "rectangle")
      (controller:add-layer "raster")
      (assert (= (. (controller:active-layer) :kind) "raster"))
      (assert (= (controller:active-tool) "brush"))
      (controller:set-active-tool "marker")
      (controller:set-active-layer (. (. controller.state.document.layers 1) :id))
      (assert (= (controller:active-tool) "rectangle"))
      (controller:set-active-layer (. (. controller.state.document.layers 2) :id))
      (assert (= (controller:active-tool) "marker")))))

(fn controller-rejects-raster-without-data-dir []
  (local (ok-initial err-initial)
    (pcall DrawingController
           {:document {:version 2
                       :next_layer_id 2
                       :next_object_id 1
                       :layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "raster"
                                 :objects []
                                 :storage {:scheme "png-tile-v1"
                                           :tile_size 128
                                           :channels 4
                                           :base_path "drawing/raster/layer-1"}}]}
            :ui {:active_layer_id "layer-1"}}))
  (assert (not ok-initial)
          "raster controllers should fail during construction without :data_dir")
  (assert (string.find err-initial ":data_dir")
          "raster controller construction should explain the missing data dir")
  (local controller (DrawingController {}))
  (local (ok-add err-add) (pcall controller.add-layer controller "raster"))
  (assert (not ok-add)
          "adding a raster layer should fail without :data_dir")
  (assert (string.find err-add ":data_dir")
          "adding a raster layer without a data dir should explain the failure"))

(fn controller-rejects-invalid-runtime-tool-and-default-keys []
  (local controller (DrawingController {}))
  (local (ok-tool err-tool) (pcall controller.set-active-tool controller "banana"))
  (assert (not ok-tool)
          "runtime tool changes should reject invalid tool names")
  (assert (string.find err-tool "invalid tool")
          "runtime tool rejection should explain the invalid tool")
  (local (ok-default err-default)
    (pcall controller.set-defaults! controller {:banana 1}))
  (assert (not ok-default)
          "runtime default changes should reject unknown keys")
  (assert (string.find err-default "invalid default key")
          "runtime default rejection should explain the bad key")
  (local (ok-thickness err-thickness)
    (pcall controller.set-defaults! controller {:thickness "banana"}))
  (assert (not ok-thickness)
          "runtime defaults should reject invalid value types")
  (assert (string.find err-thickness "thickness")
          "runtime default value rejection should identify the bad field")
  (local (ok-opacity err-opacity)
    (pcall controller.set-defaults! controller {:opacity 2.0}))
  (assert (not ok-opacity)
          "runtime defaults should reject opacity outside the valid range")
  (assert (string.find err-opacity "opacity")
          "runtime default value rejection should explain the invalid opacity"))

(fn controller-rejects-invalid-gesture-tool-entry []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (local (ok err)
        (pcall controller.begin-gesture controller "banana" (glm.vec3 2 2 0) {:pressure 1.0}))
      (assert (not ok)
              "begin-gesture should reject invalid runtime tool names")
      (assert (string.find err "invalid tool")
              "invalid gesture tool rejection should explain the bad tool")
      (assert (not (controller:gesture-active?))
              "rejecting an invalid gesture tool should not leave gesture state behind"))))

(fn controller-rejects-empty-raster-data-dir []
  (local (ok-initial err-initial)
    (pcall DrawingController
           {:document {:version 2
                       :next_layer_id 2
                       :next_object_id 1
                       :layers [{:id "layer-1"
                                 :name "Layer 1"
                                 :kind "raster"
                                 :objects []
                                 :storage {:scheme "png-tile-v1"
                                           :tile_size 128
                                           :channels 4
                                           :base_path "drawing/raster/layer-1"}}]}
            :ui {:active_layer_id "layer-1"}
            :data_dir ""}))
  (assert (not ok-initial)
          "raster controllers should reject empty :data_dir during construction")
  (assert err-initial
          "empty data dir rejection should return an error payload")
  (local controller (DrawingController {:data_dir ""}))
  (assert (= (controller:can-add-raster-layer?) false)
          "empty data dir should not advertise raster support")
  (local (ok-add err-add) (pcall controller.add-layer controller "raster"))
  (assert (not ok-add)
          "adding a raster layer should fail with an empty data dir")
  (assert err-add
          "empty data dir add-layer failure should return an error payload"))

(fn snapshot-with-empty-data-dir-does-not-prune-relative-raster-root []
  (local probe-root "drawing/raster")
  (local probe-path
    (fs.join-path probe-root (.. "empty-data-dir-probe-" (os.time) "-" temp-counter)))
  (when (fs.exists probe-path)
    (fs.remove-all probe-path))
  (fs.create-dirs probe-path)
  (local (ok result)
    (pcall
      (fn []
        (local controller (DrawingController {:data_dir ""}))
        (local snapshot (controller:snapshot))
        (assert (fs.exists probe-path)
                "vector-only snapshot with empty data dir should not prune relative drawing/raster content")
        snapshot)))
  (when (fs.exists probe-path)
    (fs.remove-all probe-path))
  (when (not ok)
    (error result))
  result)

(fn controller-keeps-raster-move-transient []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (assert (not (controller:can-activate-tool? "move"))
              "move should be unavailable without a raster selection")
      (local (ok err) (pcall controller.set-active-tool controller "move"))
      (assert (not ok)
              "move activation should fail loudly without a raster selection")
      (assert (string.find err "cannot activate tool")
              "move activation failure should explain the missing selection state")
      (controller:begin-gesture "brush" (glm.vec3 2 2 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 6 6 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:set-active-tool "marquee")
      (controller:begin-gesture "marquee" (glm.vec3 1 1 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 7 7 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (assert (controller:can-activate-tool? "move")
              "move should become available once a raster selection exists")
      (controller:set-active-tool "move")
      (assert (= (controller:active-tool) "move")
              "move should stay available while a raster selection exists")
      (controller:clear-selection!)
      (assert (= (controller:raster-selection) nil))
      (assert (= (controller:active-tool) "brush")
              "clearing the selection should also clear the transient move tool"))))

(fn snapshot-persists-canonical-ui-state-only []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "fill")
      (controller:set-defaults! {:fill_color [0.9 0.4 0.2 1.0]})
      (local snapshot (controller:snapshot))
      (assert (= snapshot.ui.active_tool nil)
              "snapshot should not persist duplicated derived active tool state")
      (assert (= snapshot.ui.defaults nil)
              "snapshot should not persist duplicated derived defaults state")
      (assert (= snapshot.ui.active_tool_by_kind.raster "fill"))
      (assert (= (. snapshot.ui.defaults_by_kind.raster.fill_color 1) 0.9)))))

(fn raster-layer-persists-tile-sidecars []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "brush")
      (controller:begin-gesture "brush" (glm.vec3 4 4 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 12 8 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (local snapshot (controller:snapshot))
      (local layer (. snapshot.document.layers 2))
      (assert (= layer.kind "raster"))
      (assert layer.storage)
      (local raster-dir (fs.join-path dir layer.storage.base_path))
      (assert (fs.exists raster-dir) "raster snapshot should create the raster sidecar directory")
      (assert (fs.exists (fs.join-path raster-dir "0_0.png"))
              "raster snapshot should persist at least one tile png"))))

(fn reopened-raster-snapshot-preserves-unloaded-tiles []
  (with-temp-dir
    (fn [dir]
      (local writer (DrawingController {:data_dir dir}))
      (writer:add-layer "raster")
      (writer:set-active-tool "brush")
      (writer:begin-gesture "brush" (glm.vec3 4 4 0) {:pressure 1.0})
      (writer:update-gesture (glm.vec3 12 8 0) false {:pressure 1.0})
      (assert (writer:commit-gesture))
      (local first-snapshot (writer:snapshot))
      (local persisted-layer (. first-snapshot.document.layers 2))
      (local raster-dir (fs.join-path dir persisted-layer.storage.base_path))
      (local tile-path (fs.join-path raster-dir "0_0.png"))
      (assert (fs.exists tile-path)
              "setup should persist a raster tile before reopening")
      (local reopened (DrawingController {:data_dir dir
                                          :document first-snapshot.document
                                          :ui first-snapshot.ui}))
      (local reopened-layer (. reopened.state.document.layers 2))
      (local reopened-runtime (reopened:ensure-raster-runtime reopened-layer))
      (assert (= (length reopened-runtime.runtime.tiles) 0)
              "reopened runtime should keep persisted tiles unloaded until needed")
      (local second-snapshot (reopened:snapshot))
      (local second-layer (. second-snapshot.document.layers 2))
      (assert (fs.exists tile-path)
              "snapshot should not delete unloaded persisted raster tiles")
      (assert (= second-layer.storage.base_path
                 persisted-layer.storage.base_path)
              "reopened snapshot should preserve raster storage metadata"))))

(fn snapshot-prunes-deleted-raster-layer-storage []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "brush")
      (controller:begin-gesture "brush" (glm.vec3 4 4 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 12 8 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (local snapshot (controller:snapshot))
      (local layer (. snapshot.document.layers 2))
      (local raster-dir (fs.join-path dir layer.storage.base_path))
      (assert (fs.exists raster-dir)
              "setup should create the raster sidecar directory before delete")
      (assert (controller:delete-active-layer))
      (assert (fs.exists raster-dir)
              "deleting a raster layer should not remove sidecar storage before snapshot persists metadata")
      (controller:snapshot)
      (assert (not (fs.exists raster-dir))
              "snapshot should prune raster sidecar storage for deleted layers"))))

(fn deleting-raster-layer-undo-restores-raster-selection []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "brush")
      (controller:begin-gesture "brush" (glm.vec3 2 2 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 6 6 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:set-active-tool "marquee")
      (controller:begin-gesture "marquee" (glm.vec3 1 1 0))
      (controller:update-gesture (glm.vec3 7 7 0) false)
      (assert (controller:commit-gesture))
      (local selection (controller:raster-selection))
      (assert selection "marquee should create a raster selection before layer deletion")
      (assert (controller:delete-active-layer))
      (assert (= (controller:raster-selection) nil)
              "deleting the raster layer should clear the active raster selection")
      (assert (controller:on-undo))
      (local restored (controller:raster-selection))
      (assert restored "undo should restore the raster selection with the deleted layer")
      (assert (= restored.layer_id selection.layer_id))
      (assert (= restored.bounds.left selection.bounds.left))
      (assert (= restored.bounds.bottom selection.bounds.bottom)))))

(fn reopened-raster-delete-undo-restores-unloaded-tiles []
  (with-temp-dir
    (fn [dir]
      (local writer (DrawingController {:data_dir dir}))
      (writer:add-layer "raster")
      (writer:set-active-tool "brush")
      (writer:begin-gesture "brush" (glm.vec3 4 4 0) {:pressure 1.0})
      (writer:update-gesture (glm.vec3 12 8 0) false {:pressure 1.0})
      (assert (writer:commit-gesture))
      (local first-snapshot (writer:snapshot))
      (local reopened (DrawingController {:data_dir dir
                                          :document first-snapshot.document
                                          :ui first-snapshot.ui}))
      (assert (reopened:delete-active-layer))
      (assert (reopened:on-undo))
      (local restored-layer (. reopened.state.document.layers 2))
      (local runtime (reopened:ensure-raster-runtime restored-layer))
      (local rgba (runtime:get-pixel-rgba 4 4))
      (assert (> (. rgba 4) 0)
              "undo should restore persisted raster pixels even when they were unloaded before deletion"))))

(fn fragment-has-opaque-pixel? [fragment]
  (for [idx 4 (length fragment.bytes) 4]
    (when (> (. fragment.bytes idx) 0)
      (lua "return true")))
  false)

(fn raster-marquee-and-move-updates-selection-and-pixels []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "brush")
      (controller:begin-gesture "brush" (glm.vec3 2 2 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 6 6 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:set-active-tool "marquee")
      (controller:begin-gesture "marquee" (glm.vec3 1 1 0))
      (controller:update-gesture (glm.vec3 7 7 0) false)
      (assert (controller:commit-gesture))
      (local selection (controller:raster-selection))
      (assert selection "marquee should create a raster selection")
      (assert (= selection.bounds.left 1))
      (assert (= selection.bounds.bottom 1))
      (controller:set-active-tool "move")
      (controller:begin-gesture "move" (glm.vec3 1 1 0))
      (controller:update-gesture (glm.vec3 10 9 0) false)
      (assert (controller:commit-gesture))
      (local moved (controller:raster-selection))
      (assert moved "move should preserve a raster selection")
      (assert (= moved.bounds.left 10))
      (assert (= moved.bounds.bottom 9))
      (local runtime (controller:ensure-raster-runtime (controller:active-layer)))
      (local source-fragment (runtime:capture-fragment {:left 1 :right 7 :bottom 1 :top 7 :width 7 :height 7}))
      (local dest-fragment (runtime:capture-fragment moved.bounds))
      (assert (not (fragment-has-opaque-pixel? source-fragment))
              "source bounds should be cleared after raster move")
      (assert (fragment-has-opaque-pixel? dest-fragment)
              "destination bounds should contain moved raster pixels"))))

(fn raster-move-undo-redo-restores-selection-state []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "brush")
      (controller:begin-gesture "brush" (glm.vec3 2 2 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 6 6 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:set-active-tool "marquee")
      (controller:begin-gesture "marquee" (glm.vec3 1 1 0))
      (controller:update-gesture (glm.vec3 7 7 0) false)
      (assert (controller:commit-gesture))
      (controller:set-active-tool "move")
      (controller:begin-gesture "move" (glm.vec3 1 1 0))
      (controller:update-gesture (glm.vec3 10 9 0) false)
      (assert (controller:commit-gesture))
      (local moved (controller:raster-selection))
      (assert (= moved.bounds.left 10))
      (assert (controller:on-undo))
      (local undone (controller:raster-selection))
      (assert undone "undo should restore raster selection state")
      (assert (= undone.bounds.left 1)
              "undo should restore the original raster selection bounds")
      (assert (controller:on-redo))
      (local redone (controller:raster-selection))
      (assert redone "redo should restore moved raster selection state")
      (assert (= redone.bounds.left 10)
              "redo should restore the moved raster selection bounds"))))

(fn raster-move-without-selection-fails-fast []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (local (ok err) (pcall controller.set-active-tool controller "move"))
      (assert (not ok)
              "move should fail loudly without an active raster selection")
      (assert (string.find err "cannot activate tool")
              "move failure should explain the missing raster selection state")
      (assert (not (controller:gesture-active?))
              "failing move activation should leave no active gesture"))))

(fn raster-move-does-not-persist-across-selection-loss []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "brush")
      (controller:begin-gesture "brush" (glm.vec3 2 2 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 6 6 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:set-active-tool "marquee")
      (controller:begin-gesture "marquee" (glm.vec3 1 1 0))
      (controller:update-gesture (glm.vec3 7 7 0) false)
      (assert (controller:commit-gesture))
      (controller:set-active-tool "move")
      (controller:set-active-layer (. (. controller.state.document.layers 1) :id))
      (controller:set-active-layer (. (. controller.state.document.layers 2) :id))
      (assert (= (controller:active-tool) "brush")
              "losing raster selection should drop the transient move tool back to brush")
      (local snapshot (controller:snapshot))
      (assert (= snapshot.ui.active_tool_by_kind.raster "brush")
              "snapshot should not persist move as the raster active tool"))))

(fn snapshot-prunes-cleared-raster-tiles []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "brush")
      (controller:begin-gesture "brush" (glm.vec3 4 4 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 4 4 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (local first-snapshot (controller:snapshot))
      (local layer (. first-snapshot.document.layers 2))
      (local raster-dir (fs.join-path dir layer.storage.base_path))
      (assert (fs.exists (fs.join-path raster-dir "0_0.png"))
              "initial raster snapshot should write a tile png")
      (controller:set-active-tool "marquee")
      (controller:begin-gesture "marquee" (glm.vec3 0 0 0))
      (controller:update-gesture (glm.vec3 12 12 0) false)
      (assert (controller:commit-gesture))
      (assert (controller:on-delete-selection))
      (controller:snapshot)
      (assert (not (fs.exists (fs.join-path raster-dir "0_0.png")))
              "snapshot should prune fully transparent raster tiles"))))

(fn raster-fill-floods-within-bounded-region []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-defaults! {:fill_enabled false})
      (controller:set-active-tool "rectangle")
      (controller:begin-gesture "rectangle" (glm.vec3 2 2 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 10 10 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:set-defaults! {:fill_color [0.9 0.2 0.2 1.0]})
      (controller:set-active-tool "fill")
      (controller:begin-gesture "fill" (glm.vec3 6 6 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 6 6 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (local runtime (controller:ensure-raster-runtime (controller:active-layer)))
      (local inside (runtime:get-pixel-rgba 6 6))
      (local outside (runtime:get-pixel-rgba 0 0))
      (assert (> (. inside 4) 0)
              "fill should color the bounded transparent region")
      (assert (= (. outside 4) 0)
              "fill should not leak outside the bounded region"))))

(fn reopened-raster-edit-undo-restores-previous-pixels []
  (with-temp-dir
    (fn [dir]
      (local writer (DrawingController {:data_dir dir}))
      (writer:add-layer "raster")
      (writer:set-active-tool "brush")
      (writer:begin-gesture "brush" (glm.vec3 4 4 0) {:pressure 1.0})
      (writer:update-gesture (glm.vec3 12 8 0) false {:pressure 1.0})
      (assert (writer:commit-gesture))
      (local first-snapshot (writer:snapshot))
      (local reopened (DrawingController {:data_dir dir
                                          :document first-snapshot.document
                                          :ui first-snapshot.ui}))
      (reopened:set-active-tool "eraser")
      (reopened:begin-gesture "eraser" (glm.vec3 4 4 0) {:pressure 1.0})
      (reopened:update-gesture (glm.vec3 4 4 0) false {:pressure 1.0})
      (assert (reopened:commit-gesture))
      (assert (reopened:on-undo))
      (local runtime (reopened:ensure-raster-runtime (reopened:active-layer)))
      (local rgba (runtime:get-pixel-rgba 4 4))
      (assert (> (. rgba 4) 0)
              "undo should restore pre-edit raster pixels from persisted tiles after reopen"))))

(fn reopened-raster-fill-crosses-persisted-tile-boundary []
  (with-temp-dir
    (fn [dir]
      (local writer (DrawingController {:data_dir dir}))
      (writer:add-layer "raster")
      (writer:set-defaults! {:fill_enabled false
                             :thickness 2.0})
      (writer:set-active-tool "rectangle")
      (writer:begin-gesture "rectangle" (glm.vec3 2 2 0) {:pressure 1.0})
      (writer:update-gesture (glm.vec3 260 12 0) false {:pressure 1.0})
      (assert (writer:commit-gesture))
      (local first-snapshot (writer:snapshot))
      (local reopened (DrawingController {:data_dir dir
                                          :document first-snapshot.document
                                          :ui first-snapshot.ui}))
      (reopened:set-active-tool "fill")
      (reopened:set-defaults! {:fill_color [0.9 0.2 0.2 1.0]})
      (reopened:begin-gesture "fill" (glm.vec3 8 8 0) {:pressure 1.0})
      (reopened:update-gesture (glm.vec3 8 8 0) false {:pressure 1.0})
      (assert (reopened:commit-gesture))
      (local runtime (reopened:ensure-raster-runtime (reopened:active-layer)))
      (local near (runtime:get-pixel-rgba 8 8))
      (local far (runtime:get-pixel-rgba 250 8))
      (local outside (runtime:get-pixel-rgba 0 0))
      (assert (> (. near 1) 200)
              "fill should update the seed tile after reopen")
      (assert (> (. far 1) 200)
              "fill should continue across persisted neighboring tiles after reopen instead of stopping at the loaded tile window")
      (assert (= (. outside 4) 0)
              "fill should still respect the persisted outline boundary after reopening"))))

(fn raster-noop-fill-does-not-add-history []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "fill")
      (controller:begin-gesture "fill" (glm.vec3 6 6 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 6 6 0) false {:pressure 1.0})
      (assert (not (controller:commit-gesture))
              "fill on an empty raster layer should be a no-op")
      (var undo-count 0)
      (while (controller:on-undo)
        (set undo-count (+ undo-count 1)))
      (assert (= undo-count 1)
              "no-op fill should not add an undo entry beyond the raster layer creation"))))

(fn reopened-sparse-raster-fill-does-not-bridge-disconnected-islands []
  (with-temp-dir
    (fn [dir]
      (local writer (DrawingController {:data_dir dir}))
      (writer:add-layer "raster")
      (writer:set-defaults! {:fill_enabled false
                             :thickness 2.0})
      (writer:set-active-tool "rectangle")
      (writer:begin-gesture "rectangle" (glm.vec3 2 2 0) {:pressure 1.0})
      (writer:update-gesture (glm.vec3 40 24 0) false {:pressure 1.0})
      (assert (writer:commit-gesture))
      (writer:begin-gesture "rectangle" (glm.vec3 260 2 0) {:pressure 1.0})
      (writer:update-gesture (glm.vec3 300 24 0) false {:pressure 1.0})
      (assert (writer:commit-gesture))
      (local first-snapshot (writer:snapshot))
      (local reopened (DrawingController {:data_dir dir
                                          :document first-snapshot.document
                                          :ui first-snapshot.ui}))
      (reopened:set-active-tool "fill")
      (reopened:set-defaults! {:fill_color [0.9 0.2 0.2 1.0]})
      (reopened:begin-gesture "fill" (glm.vec3 8 8 0) {:pressure 1.0})
      (reopened:update-gesture (glm.vec3 8 8 0) false {:pressure 1.0})
      (assert (reopened:commit-gesture))
      (local runtime (reopened:ensure-raster-runtime (reopened:active-layer)))
      (local near (runtime:get-pixel-rgba 8 8))
      (local far (runtime:get-pixel-rgba 268 8))
      (assert (> (. near 1) 200)
              "fill should update the seeded disconnected island after reopen")
      (assert (< (. far 1) 100)
              "fill should not bridge across sparse empty space into a disconnected persisted island"))))

(fn raster-eyedropper-unpremultiplies-translucent-color []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "pen")
      (controller:set-defaults! {:stroke_color [0.8 0.25 0.1 0.5]
                                 :opacity 1.0})
      (controller:begin-gesture "pen" (glm.vec3 6 6 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 6 6 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:set-active-tool "eyedropper")
      (controller:begin-gesture "eyedropper" (glm.vec3 6 6 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 6 6 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (local sampled (. (controller:current-defaults) :stroke_color))
      (assert (> (. sampled 1) 0.75)
              "eyedropper should recover the original translucent red instead of returning premultiplied dark red")
      (assert (< (. sampled 2) 0.3)
              "eyedropper should keep the sampled green channel near the authored color")
      (assert (< (. sampled 3) 0.15)
              "eyedropper should keep the sampled blue channel near the authored color")
      (assert (> (. sampled 4) 0.45)
              "eyedropper should preserve the sampled translucency"))))

(fn raster-selection-fragment-refreshes-after-edit []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "brush")
      (controller:begin-gesture "brush" (glm.vec3 6 6 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 10 10 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:set-active-tool "marquee")
      (controller:begin-gesture "marquee" (glm.vec3 4 4 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 12 12 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:set-active-tool "eraser")
      (controller:begin-gesture "eraser" (glm.vec3 6 6 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 6 6 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:set-active-tool "move")
      (controller:begin-gesture "move" (glm.vec3 8 8 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 18 8 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (local runtime (controller:ensure-raster-runtime (controller:active-layer)))
      (local moved-cleared (runtime:get-pixel-rgba 16 6))
      (assert (= (. moved-cleared 4) 0)
              "moving a selection after editing it should use the refreshed fragment instead of replaying stale pixels"))))

(fn raster-eyedropper-samples-composited-document-color []
  (with-temp-dir
    (fn [dir]
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (local raster-id (. (controller:active-layer) :id))
      (controller:set-active-tool "brush")
      (controller:set-defaults! {:stroke_color [0.1 0.2 0.9 1.0]})
      (controller:begin-gesture "brush" (glm.vec3 6 6 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 6 6 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:add-layer "vector")
      (controller:set-defaults! {:fill_enabled true
                                 :fill_color [0.2 0.85 0.3 1.0]
                                 :stroke_color [0.2 0.85 0.3 1.0]})
      (controller:set-active-tool "rectangle")
      (controller:begin-gesture "rectangle" (glm.vec3 3 3 0))
      (controller:update-gesture (glm.vec3 9 9 0) false)
      (assert (controller:commit-gesture))
      (controller:set-active-layer raster-id)
      (controller:set-active-tool "eyedropper")
      (controller:begin-gesture "eyedropper" (glm.vec3 6 6 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 6 6 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (local sampled (. (controller:current-defaults) :stroke_color))
      (assert (> (. sampled 2) 0.8)
              "eyedropper should sample the composited top-layer green")
      (assert (< (. sampled 3) 0.5)
              "eyedropper should not leave the obscured raster blue as the sampled color"))))

(table.insert tests {:name "Drawing document ensures a default layer"
                     :fn normalize-state-creates-default-layer})
(table.insert tests {:name "Drawing document upgrades the legacy default style"
                     :fn normalize-state-upgrades-legacy-default-style})
(table.insert tests {:name "Drawing document keeps legacy shared defaults out of raster defaults"
                     :fn normalize-state-keeps-legacy-defaults-out-of-raster-style})
(table.insert tests {:name "Drawing document migrates legacy active tools by active layer kind"
                     :fn normalize-state-migrates-legacy-active-tool-by-active-kind})
(table.insert tests {:name "Drawing document rejects unknown tools during normalization"
                     :fn normalize-state-rejects-unknown-tools})
(table.insert tests {:name "Drawing document rejects raster layers without storage paths"
                     :fn normalize-state-rejects-raster-layers-without-storage-path})
(table.insert tests {:name "Drawing document canonicalizes and validates persisted defaults"
                     :fn normalize-state-canonicalizes-and-validates-persisted-defaults})
(table.insert tests {:name "Drawing document rejects malformed document containers"
                     :fn normalize-state-rejects-malformed-document-containers})
(table.insert tests {:name "Drawing document rejects invalid document counters"
                     :fn normalize-state-rejects-invalid-document-counters})
(table.insert tests {:name "Drawing document canonicalizes document counters against existing ids"
                     :fn normalize-state-canonicalizes-document-counters})
(table.insert tests {:name "Drawing document canonicalizes layer counters against raster storage roots"
                     :fn normalize-state-canonicalizes-layer-counter-against-raster-storage-roots})
(table.insert tests {:name "Drawing document rejects impossible layer payloads"
                     :fn normalize-state-rejects-impossible-layer-payloads})
(table.insert tests {:name "Drawing document rejects invalid layer names"
                     :fn normalize-state-rejects-invalid-layer-names})
(table.insert tests {:name "Drawing document rejects duplicate raster storage roots"
                     :fn normalize-state-rejects-duplicate-raster-storage-paths})
(table.insert tests {:name "Drawing document rejects malformed vector geometry"
                     :fn normalize-state-rejects-malformed-vector-geometry})
(table.insert tests {:name "Drawing document rejects malformed object styles"
                     :fn normalize-state-rejects-malformed-object-style})
(table.insert tests {:name "Drawing document rejects invalid document ids"
                     :fn normalize-state-rejects-invalid-document-ids})
(table.insert tests {:name "Drawing document rejects duplicate document ids"
                     :fn normalize-state-rejects-duplicate-document-ids})
(table.insert tests {:name "Drawing document canonicalizes object schema"
                     :fn normalize-state-canonicalizes-object-schema})
(table.insert tests {:name "Drawing document runtime insert apis enforce canonical invariants"
                     :fn runtime-insert-apis-canonicalize-and-validate})
(table.insert tests {:name "Drawing document runtime mutation boundary rejects invalid indices and wrong vec3 userdata"
                     :fn runtime-mutation-boundary-rejects-invalid-indices-and-wrong-vec3-userdata})
(table.insert tests {:name "Drawing document rejects malformed selection ids"
                     :fn normalize-state-rejects-malformed-selection-ids})
(table.insert tests {:name "Drawing document canonicalizes persisted selection ids"
                     :fn normalize-state-canonicalizes-persisted-selection-ids})
(table.insert tests {:name "Drawing document runtime selection api rejects invalid requests"
                     :fn runtime-selection-api-rejects-invalid-requests})
(table.insert tests {:name "Drawing controller creates rectangle objects with undo/redo"
                     :fn controller-creates-rectangle-and-supports-undo-redo})
(table.insert tests {:name "Drawing controller snapshots serialize vector data"
                     :fn snapshot-serializes-glm-vectors})
(table.insert tests {:name "Drawing controller renames layers with undo/redo"
                     :fn controller-renames-layers-with-undo-redo})
(table.insert tests {:name "Drawing controller rejects non-canonical runtime layer names"
                     :fn controller-rejects-uncanonical-runtime-layer-name})
(table.insert tests {:name "Drawing controller undoes layer structure edits cleanly"
                     :fn controller-layer-structure-edits-undo-cleanly})
(table.insert tests {:name "Drawing controller replays object history in layer context"
                     :fn controller-object-history-replays-in-layer-context})
(table.insert tests {:name "Drawing controller remembers tools by layer kind"
                     :fn controller-remembers-tools-by-layer-kind})
(table.insert tests {:name "Drawing controller rejects raster use without data dir"
                     :fn controller-rejects-raster-without-data-dir})
(table.insert tests {:name "Drawing controller rejects invalid runtime tools and default keys"
                     :fn controller-rejects-invalid-runtime-tool-and-default-keys})
(table.insert tests {:name "Drawing controller rejects invalid gesture tool entry"
                     :fn controller-rejects-invalid-gesture-tool-entry})
(table.insert tests {:name "Drawing controller rejects empty raster data dir"
                     :fn controller-rejects-empty-raster-data-dir})
(table.insert tests {:name "Drawing snapshot with empty data dir does not prune relative raster roots"
                     :fn snapshot-with-empty-data-dir-does-not-prune-relative-raster-root})
(table.insert tests {:name "Drawing controller keeps raster move transient"
                     :fn controller-keeps-raster-move-transient})
(table.insert tests {:name "Drawing snapshot persists only canonical UI state"
                     :fn snapshot-persists-canonical-ui-state-only})
(table.insert tests {:name "Raster drawing persists tile sidecars on snapshot"
                     :fn raster-layer-persists-tile-sidecars})
(table.insert tests {:name "Reopened raster snapshots preserve unloaded persisted tiles"
                     :fn reopened-raster-snapshot-preserves-unloaded-tiles})
(table.insert tests {:name "Raster snapshot prunes deleted layer sidecar storage"
                     :fn snapshot-prunes-deleted-raster-layer-storage})
(table.insert tests {:name "Deleting a raster layer and undoing restores raster selection"
                     :fn deleting-raster-layer-undo-restores-raster-selection})
(table.insert tests {:name "Reopened raster delete undo restores unloaded persisted tiles"
                     :fn reopened-raster-delete-undo-restores-unloaded-tiles})
(table.insert tests {:name "Raster marquee and move update selection and pixel position"
                     :fn raster-marquee-and-move-updates-selection-and-pixels})
(table.insert tests {:name "Raster move undo and redo restore selection state"
                     :fn raster-move-undo-redo-restores-selection-state})
(table.insert tests {:name "Raster move without selection fails fast"
                     :fn raster-move-without-selection-fails-fast})
(table.insert tests {:name "Raster move does not persist across selection loss"
                     :fn raster-move-does-not-persist-across-selection-loss})
(table.insert tests {:name "Raster snapshot prunes cleared transparent tiles"
                     :fn snapshot-prunes-cleared-raster-tiles})
(table.insert tests {:name "Raster fill floods within the current bounded region"
                     :fn raster-fill-floods-within-bounded-region})
(table.insert tests {:name "Reopened raster edit undo restores previous pixels"
                     :fn reopened-raster-edit-undo-restores-previous-pixels})
(table.insert tests {:name "Reopened raster fill crosses persisted tile boundaries"
                     :fn reopened-raster-fill-crosses-persisted-tile-boundary})
(table.insert tests {:name "Reopened sparse raster fill does not bridge disconnected islands"
                     :fn reopened-sparse-raster-fill-does-not-bridge-disconnected-islands})
(table.insert tests {:name "Raster no-op fill does not add history entries"
                     :fn raster-noop-fill-does-not-add-history})
(table.insert tests {:name "Raster eyedropper samples composited document color"
                     :fn raster-eyedropper-samples-composited-document-color})
(table.insert tests {:name "Raster eyedropper recovers translucent authored color"
                     :fn raster-eyedropper-unpremultiplies-translucent-color})
(table.insert tests {:name "Raster selection fragment refreshes after edit"
                     :fn raster-selection-fragment-refreshes-after-edit})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-document"
                       :tests tests})))

{:name "drawing-document"
 :tests tests
 :main main}
