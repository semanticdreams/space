(local glm (require :glm))
(local fs (require :fs))
(local textures (require :textures))
(local DrawingController (require :drawing/controller))
(local {:DrawingRender DrawingRender} (require :drawing/render))

(local tests [])

(local temp-root (fs.join-path "/tmp/space/tests" "drawing-render"))
(var temp-counter 0)

(fn with-temp-dir [f]
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "drawing-render-" (os.time) "-" temp-counter)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (when (not ok)
    (error result))
  result)

(fn table-entry-count [items]
  (var count 0)
  (each [_ _value (pairs items)]
    (set count (+ count 1)))
  count)

(fn make-vector-buffer []
  (local state {:allocations 0
                :deletes 0
                :vec3-writes 0
                :vec4-writes 0
                :float-writes 0
                :last-size nil
                :last-handle nil})
  (local buffer {})
  (set buffer.allocate
       (fn [_self count]
         (set state.allocations (+ state.allocations 1))
         (set state.last-size count)
         (set state.last-handle (+ state.allocations 100))
         state.last-handle))
  (set buffer.delete
       (fn [_self handle]
         (assert (= handle state.last-handle)
                 "drawing render should delete the tracked triangle handle")
         (set state.deletes (+ state.deletes 1))))
  (set buffer.set-glm-vec3
       (fn [_self handle _offset value]
         (assert (= handle state.last-handle)
                 "drawing render should write positions to the current triangle handle")
         (assert (= (type value.x) :number))
         (set state.vec3-writes (+ state.vec3-writes 1))))
  (set buffer.set-glm-vec4
       (fn [_self handle _offset value]
         (assert (= handle state.last-handle)
                 "drawing render should write colors to the current triangle handle")
         (assert (= (type value.x) :number))
         (set state.vec4-writes (+ state.vec4-writes 1))))
  (set buffer.set-float
       (fn [_self handle _offset value]
         (assert (= handle state.last-handle)
                 "drawing render should write depths to the current triangle handle")
         (assert (= (type value) :number))
         (set state.float-writes (+ state.float-writes 1))))
  (set buffer.state state)
  buffer)

(fn make-image-buffer []
  (local state {:allocations 0
                :deletes 0
                :vec3-writes 0
                :vec2-writes 0
                :vec4-writes 0
                :float-writes 0})
  (local buffer {})
  (set buffer.allocate
       (fn [_self count]
         (set state.allocations (+ state.allocations 1))
         (+ 500 state.allocations)))
  (set buffer.delete
       (fn [_self _handle]
         (set state.deletes (+ state.deletes 1))))
  (set buffer.set-glm-vec3
       (fn [_self _handle _offset _value]
         (set state.vec3-writes (+ state.vec3-writes 1))))
  (set buffer.set-glm-vec2
       (fn [_self _handle _offset _value]
         (set state.vec2-writes (+ state.vec2-writes 1))))
  (set buffer.set-glm-vec4
       (fn [_self _handle _offset _value]
         (set state.vec4-writes (+ state.vec4-writes 1))))
  (set buffer.set-float
       (fn [_self _handle _offset _value]
         (set state.float-writes (+ state.float-writes 1))))
  (set buffer.state state)
  buffer)

(fn with-texture-update-counts [f]
  (local original-allocate-hyphen (. textures "allocate-texture"))
  (local original-allocate
    (assert original-allocate-hyphen
            "drawing render texture counting requires textures.allocate-texture"))
  (local counts {})
  (local counted-allocate
    (fn [name width height channels]
      (set counts.__allocations (+ (or counts.__allocations 0) 1))
      (local raw (original-allocate name width height channels))
      (local proxy {:id raw.id
                    :name name
                    :ready raw.ready
                    :width raw.width
                    :height raw.height})
      (local allocate!
        (fn [self next-width next-height next-channels]
          (raw:allocate next-width next-height next-channels)
          (set self.width raw.width)
          (set self.height raw.height)
          (set self.ready raw.ready)))
      (local update-full!
        (fn [_self bytes]
          (set (. counts name) (+ (or (. counts name) 0) 1))
          (raw:update-full bytes)
          (set proxy.ready raw.ready)))
      (local update-sub-rect!
        (fn [_self x y next-width next-height bytes]
          (raw:update-sub-rect x y next-width next-height bytes)
          (set proxy.ready raw.ready)))
      (set proxy.allocate allocate!)
      (set proxy.update-full update-full!)
      (set proxy.update-sub-rect update-sub-rect!)
      (tset proxy "update-full" update-full!)
      (tset proxy "update-sub-rect" update-sub-rect!)
      proxy))
  (set textures.allocate-texture counted-allocate)
  (tset textures "allocate-texture" counted-allocate)
  (local (ok result) (pcall f counts))
  (set textures.allocate-texture original-allocate-hyphen)
  (tset textures "allocate-texture" original-allocate-hyphen)
  (when (not ok)
    (error result))
  result)

(fn total-texture-updates [counts]
  (var total 0)
  (each [key count (pairs counts)]
    (when (not (= key "__allocations"))
      (set total (+ total count))))
  total)

(fn drawing-render-populates-triangle-buffer []
  (local track-log [])
  (local vector (make-vector-buffer))
  (local ctx {:triangle-vector vector
              :track-triangle-handle (fn [_self handle clip]
                                       (table.insert track-log {:handle handle
                                                                :clip clip}))
              :untrack-triangle-handle (fn [_self handle]
                                         (table.insert track-log {:untracked handle}))})
  (local controller (DrawingController {}))
  (controller:begin-gesture "rectangle" (glm.vec3 0 0 0))
  (controller:update-gesture (glm.vec3 24 12 0) false)
  (assert (controller:commit-gesture)
          "drawing render regression test expected rectangle commit to succeed")
  (local render (DrawingRender {:ctx ctx
                                :controller controller}))

  (render:update)

  (assert (> vector.state.last-size 0)
          "drawing render should allocate triangle storage for committed objects")
  (assert (> vector.state.vec3-writes 0)
          "drawing render should write vertex positions into the triangle buffer")
  (assert (= vector.state.vec3-writes vector.state.vec4-writes)
          "drawing render should write one color per vertex")
  (assert (= vector.state.vec3-writes vector.state.float-writes)
          "drawing render should write one depth per vertex")
  (assert (= (length track-log) 1)
          "drawing render should register the uploaded triangle handle once")
  (assert (= (. (. track-log 1) :handle) vector.state.last-handle)
          "drawing render should track the same handle it uploads")

  (render:drop)
  (assert (= vector.state.deletes 1)
          "drawing render should release the triangle handle on drop")
  (assert (= (length track-log) 2)
          "drawing render should untrack the triangle handle on drop")
  (assert (= (. (. track-log 2) :untracked) vector.state.last-handle)
          "drawing render should untrack the uploaded handle"))

(fn drawing-render-tracks-raster-image-quads []
  (with-temp-dir
    (fn [dir]
      (local triangle-vector (make-vector-buffer))
      (local image-vector (make-image-buffer))
      (local tracked-images [])
      (local image-batches {})
      (local ctx {:triangle-vector triangle-vector
                  :track-triangle-handle (fn [_self _handle _clip] nil)
                  :untrack-triangle-handle (fn [_self _handle] nil)
                  :get-image-batch (fn [_self texture]
                                     (when (= (. image-batches texture.id) nil)
                                       (set (. image-batches texture.id)
                                            {:texture texture
                                             :vector image-vector}))
                                     (. image-batches texture.id))
                  :track-image-handle (fn [_self batch handle clip]
                                        (table.insert tracked-images {:batch batch
                                                                      :handle handle
                                                                      :clip clip}))
                  :untrack-image-handle (fn [_self _batch _handle] nil)})
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "brush")
      (controller:begin-gesture "brush" (glm.vec3 4 4 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 14 10 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (local first-runtime (controller:ensure-raster-runtime (controller:active-layer)))
      (assert (> (table-entry-count first-runtime.runtime.tiles) 0)
              "drawing render refresh test should start from a raster tile")
      (local render (DrawingRender {:ctx ctx
                                    :controller controller}))
      (render:update)
      (assert (> image-vector.state.allocations 0)
              "drawing render should allocate image quad storage for raster tiles")
      (assert (> image-vector.state.vec3-writes 0)
              "drawing render should write raster quad positions")
      (assert (> (length tracked-images) 0)
              "drawing render should track raster image handles")
      (render:drop))))

(fn drawing-render-culls-offscreen-raster-tiles []
  (with-temp-dir
    (fn [dir]
      (local triangle-vector (make-vector-buffer))
      (local image-vector (make-image-buffer))
      (local image-batches {})
      (local ctx {:triangle-vector triangle-vector
                  :track-triangle-handle (fn [_self _handle _clip] nil)
                  :untrack-triangle-handle (fn [_self _handle] nil)
                  :get-image-batch (fn [_self texture]
                                     (when (= (. image-batches texture.id) nil)
                                       (set (. image-batches texture.id)
                                            {:texture texture
                                             :vector image-vector}))
                                     (. image-batches texture.id))
                  :track-image-handle (fn [_self _batch _handle _clip] nil)
                  :untrack-image-handle (fn [_self _batch _handle] nil)})
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "brush")
      (controller:begin-gesture "brush" (glm.vec3 1000 1000 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 1012 1008 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:snapshot)
      (local canvas {:camera {:position (glm.vec3 0 0 100)}
                     :half-width 64
                     :half-height 64})
      (local render (DrawingRender {:ctx ctx
                                    :controller controller
                                    :canvas canvas}))
      (render:update)
      (assert (= image-vector.state.allocations 0)
              "drawing render should not allocate image quads for offscreen raster tiles")
      (render:drop))))

(fn drawing-render-rebuilds-when-camera-bounds-change []
  (with-temp-dir
    (fn [dir]
      (local triangle-vector (make-vector-buffer))
      (local image-vector (make-image-buffer))
      (local image-batches {})
      (local ctx {:triangle-vector triangle-vector
                  :track-triangle-handle (fn [_self _handle _clip] nil)
                  :untrack-triangle-handle (fn [_self _handle] nil)
                  :get-image-batch (fn [_self texture]
                                     (when (= (. image-batches texture.id) nil)
                                       (set (. image-batches texture.id)
                                            {:texture texture
                                             :vector image-vector}))
                                     (. image-batches texture.id))
                  :track-image-handle (fn [_self _batch _handle _clip] nil)
                  :untrack-image-handle (fn [_self _batch _handle] nil)})
      (local controller (DrawingController {:data_dir dir}))
      (controller:add-layer "raster")
      (controller:set-active-tool "brush")
      (controller:begin-gesture "brush" (glm.vec3 1000 1000 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 1012 1008 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (controller:snapshot)
      (local canvas {:camera {:position (glm.vec3 0 0 100)}
                     :half-width 32
                     :half-height 32})
      (local render (DrawingRender {:ctx ctx
                                    :controller controller
                                    :canvas canvas}))
      (render:update)
      (assert (= image-vector.state.allocations 0)
              "drawing render should not allocate image quads for offscreen raster tiles before the camera moves")
      (set canvas.camera.position (glm.vec3 1000 1000 100))
      (render:update)
      (assert (> image-vector.state.allocations 0)
              "drawing render should rebuild when the visible raster bounds change")
      (render:drop))))

(fn drawing-render-does-not-materialize-persisted-tiles-into-runtime []
  (with-temp-dir
    (fn [dir]
      (local triangle-vector (make-vector-buffer))
      (local image-vector (make-image-buffer))
      (local image-batches {})
      (local ctx {:triangle-vector triangle-vector
                  :track-triangle-handle (fn [_self _handle _clip] nil)
                  :untrack-triangle-handle (fn [_self _handle] nil)
                  :get-image-batch (fn [_self texture]
                                     (when (= (. image-batches texture.id) nil)
                                       (set (. image-batches texture.id)
                                            {:texture texture
                                             :vector image-vector}))
                                     (. image-batches texture.id))
                  :track-image-handle (fn [_self _batch _handle _clip] nil)
                  :untrack-image-handle (fn [_self _batch _handle] nil)})
      (local writer (DrawingController {:data_dir dir}))
      (writer:add-layer "raster")
      (writer:set-active-tool "brush")
      (writer:begin-gesture "brush" (glm.vec3 4 4 0) {:pressure 1.0})
      (writer:update-gesture (glm.vec3 14 10 0) false {:pressure 1.0})
      (assert (writer:commit-gesture))
      (local snapshot (writer:snapshot))
      (local reopened (DrawingController {:data_dir dir
                                          :document snapshot.document
                                          :ui snapshot.ui}))
      (local layer (reopened:active-layer))
      (local runtime (reopened:ensure-raster-runtime layer))
      (assert (= (length runtime.runtime.tiles) 0)
              "reopened raster runtime should start with no loaded tiles")
      (local canvas {:camera {:position (glm.vec3 0 0 100)}
                     :half-width 64
                     :half-height 64})
      (local render (DrawingRender {:ctx ctx
                                    :controller reopened
                                    :canvas canvas}))
      (render:update)
      (assert (= (length runtime.runtime.tiles) 0)
              "drawing render should not materialize persisted tiles into the runtime tile set")
      (render:drop))))

(fn drawing-render-refreshes-cached-raster-textures-after-edit []
  (with-texture-update-counts
    (fn [texture-updates]
      (with-temp-dir
        (fn [dir]
          (local triangle-vector (make-vector-buffer))
          (local image-vector (make-image-buffer))
          (local image-batches {})
          (local ctx {:triangle-vector triangle-vector
                      :track-triangle-handle (fn [_self _handle _clip] nil)
                      :untrack-triangle-handle (fn [_self _handle] nil)
                      :get-image-batch (fn [_self texture]
                                         (when (= (. image-batches texture.id) nil)
                                           (set (. image-batches texture.id)
                                                {:texture texture
                                                 :vector image-vector}))
                                         (. image-batches texture.id))
                      :track-image-handle (fn [_self _batch _handle _clip] nil)
                      :untrack-image-handle (fn [_self _batch _handle] nil)})
          (local controller (DrawingController {:data_dir dir}))
          (controller:add-layer "raster")
          (controller:set-active-tool "brush")
          (controller:begin-gesture "brush" (glm.vec3 4 4 0) {:pressure 1.0})
          (controller:update-gesture (glm.vec3 14 10 0) false {:pressure 1.0})
          (assert (controller:commit-gesture))
          (local render (DrawingRender {:ctx ctx
                                        :controller controller}))
          (render:update)
          (local first-allocations image-vector.state.allocations)
          (local first-writes image-vector.state.vec3-writes)
          (local first-updates (total-texture-updates texture-updates))
          (assert (> first-allocations 0)
                  "drawing render refresh test should allocate the initial raster image handle")
          (assert (> first-updates 0)
                  (string.format "drawing render refresh test should upload the initial raster texture (%d allocations, %d texture allocations, %d writes)"
                                 first-allocations
                                 (or texture-updates.__allocations 0)
                                 first-writes))
          (controller:begin-gesture "brush" (glm.vec3 18 12 0) {:pressure 1.0})
          (controller:update-gesture (glm.vec3 28 18 0) false {:pressure 1.0})
          (assert (controller:commit-gesture))
          (render:update)
          (assert (= image-vector.state.allocations first-allocations)
                  "drawing render should reuse raster image handles across redraws instead of reallocating them")
          (assert (= image-vector.state.vec3-writes first-writes)
                  "drawing render should not rewrite stable raster quads when only tile texture bytes changed")
          (local second-updates (total-texture-updates texture-updates))
          (assert (> second-updates first-updates)
                  (string.format "drawing render should still refresh dirty raster textures after an edit (%d -> %d)"
                                 first-updates
                                 second-updates))
          (render:drop))))))

(fn drawing-render-ignores-vector-only-changes-for-raster-sync []
  (with-texture-update-counts
    (fn [texture-updates]
      (with-temp-dir
        (fn [dir]
          (local triangle-vector (make-vector-buffer))
          (local image-vector (make-image-buffer))
          (local image-batches {})
          (local ctx {:triangle-vector triangle-vector
                      :track-triangle-handle (fn [_self _handle _clip] nil)
                      :untrack-triangle-handle (fn [_self _handle] nil)
                      :get-image-batch (fn [_self texture]
                                         (when (= (. image-batches texture.id) nil)
                                           (set (. image-batches texture.id)
                                                {:texture texture
                                                 :vector image-vector}))
                                         (. image-batches texture.id))
                      :track-image-handle (fn [_self _batch _handle _clip] nil)
                      :untrack-image-handle (fn [_self _batch _handle] nil)})
          (local controller (DrawingController {:data_dir dir}))
          (local vector-layer (. controller.state.document.layers 1))
          (local vector-layer-id vector-layer.id)
          (controller:add-layer "raster")
          (controller:set-active-tool "brush")
          (controller:begin-gesture "brush" (glm.vec3 4 4 0) {:pressure 1.0})
          (controller:update-gesture (glm.vec3 14 10 0) false {:pressure 1.0})
          (assert (controller:commit-gesture))
          (local render (DrawingRender {:ctx ctx
                                        :controller controller}))
          (render:update)
          (local first-writes image-vector.state.vec3-writes)
          (local first-updates (total-texture-updates texture-updates))
          (controller:set-active-layer vector-layer-id)
          (controller:set-active-tool "rectangle")
          (controller:begin-gesture "rectangle" (glm.vec3 20 20 0) {:pressure 1.0})
          (controller:update-gesture (glm.vec3 34 30 0) false {:pressure 1.0})
          (assert (controller:commit-gesture))
          (render:update)
          (assert (= image-vector.state.vec3-writes first-writes)
                  "drawing render should not rewrite raster image quads for vector-only document changes")
          (assert (= (total-texture-updates texture-updates) first-updates)
                  "drawing render should not resync raster textures for vector-only document changes")
          (render:drop))))))

(fn drawing-render-ignores-vector-only-history-for-raster-sync []
  (with-texture-update-counts
    (fn [texture-updates]
      (with-temp-dir
        (fn [dir]
          (local triangle-vector (make-vector-buffer))
          (local image-vector (make-image-buffer))
          (local image-batches {})
          (local ctx {:triangle-vector triangle-vector
                      :track-triangle-handle (fn [_self _handle _clip] nil)
                      :untrack-triangle-handle (fn [_self _handle] nil)
                      :get-image-batch (fn [_self texture]
                                         (when (= (. image-batches texture.id) nil)
                                           (set (. image-batches texture.id)
                                                {:texture texture
                                                 :vector image-vector}))
                                         (. image-batches texture.id))
                      :track-image-handle (fn [_self _batch _handle _clip] nil)
                      :untrack-image-handle (fn [_self _batch _handle] nil)})
          (local controller (DrawingController {:data_dir dir}))
          (local vector-layer (. controller.state.document.layers 1))
          (local vector-layer-id vector-layer.id)
          (controller:add-layer "raster")
          (controller:set-active-tool "brush")
          (controller:begin-gesture "brush" (glm.vec3 4 4 0) {:pressure 1.0})
          (controller:update-gesture (glm.vec3 14 10 0) false {:pressure 1.0})
          (assert (controller:commit-gesture))
          (local render (DrawingRender {:ctx ctx
                                        :controller controller}))
          (render:update)
          (local first-writes image-vector.state.vec3-writes)
          (local first-updates (total-texture-updates texture-updates))
          (controller:set-active-layer vector-layer-id)
          (controller:set-active-tool "rectangle")
          (controller:begin-gesture "rectangle" (glm.vec3 20 20 0) {:pressure 1.0})
          (controller:update-gesture (glm.vec3 34 30 0) false {:pressure 1.0})
          (assert (controller:commit-gesture))
          (render:update)
          (assert (= image-vector.state.vec3-writes first-writes)
                  "drawing render should not rewrite raster image quads after vector-only history entries are created")
          (assert (= (total-texture-updates texture-updates) first-updates)
                  "drawing render should not resync raster textures after vector-only history entries are created")
          (assert (controller:on-undo))
          (render:update)
          (assert (= image-vector.state.vec3-writes first-writes)
                  "drawing render should not rewrite raster image quads for vector-only undo")
          (assert (= (total-texture-updates texture-updates) first-updates)
                  "drawing render should not resync raster textures for vector-only undo")
          (assert (controller:on-redo))
          (render:update)
          (assert (= image-vector.state.vec3-writes first-writes)
                  "drawing render should not rewrite raster image quads for vector-only redo")
          (assert (= (total-texture-updates texture-updates) first-updates)
                  "drawing render should not resync raster textures for vector-only redo")
          (render:drop))))))

(fn drawing-render-ignores-layer-ui-only-changes-for-raster-sync []
  (with-temp-dir
    (fn [dir]
      (local triangle-vector (make-vector-buffer))
      (local image-vector (make-image-buffer))
      (local image-batches {})
      (var batch-requests 0)
      (local ctx {:triangle-vector triangle-vector
                  :track-triangle-handle (fn [_self _handle _clip] nil)
                  :untrack-triangle-handle (fn [_self _handle] nil)
                  :get-image-batch (fn [_self texture]
                                     (set batch-requests (+ batch-requests 1))
                                     (when (= (. image-batches texture.id) nil)
                                       (set (. image-batches texture.id)
                                            {:texture texture
                                             :vector image-vector}))
                                     (. image-batches texture.id))
                  :track-image-handle (fn [_self _batch _handle _clip] nil)
                  :untrack-image-handle (fn [_self _batch _handle] nil)})
      (local controller (DrawingController {:data_dir dir}))
      (local vector-layer (. controller.state.document.layers 1))
      (local vector-layer-id vector-layer.id)
      (controller:add-layer "raster")
      (controller:set-active-tool "brush")
      (controller:begin-gesture "brush" (glm.vec3 4 4 0) {:pressure 1.0})
      (controller:update-gesture (glm.vec3 14 10 0) false {:pressure 1.0})
      (assert (controller:commit-gesture))
      (local render (DrawingRender {:ctx ctx
                                    :controller controller}))
      (render:update)
      (local initial-batch-requests batch-requests)
      (controller:set-active-layer vector-layer-id)
      (render:update)
      (assert (= batch-requests initial-batch-requests)
              "drawing render should not walk visible raster batches when only the active layer changes")
      (assert (controller:rename-active-layer "Foreground"))
      (render:update)
      (assert (= batch-requests initial-batch-requests)
              "drawing render should not walk visible raster batches when only layer metadata changes")
      (render:drop))))

(fn drawing-render-masks-only-source-tiles-during-raster-move-preview []
  (with-texture-update-counts
    (fn [texture-updates]
      (with-temp-dir
        (fn [dir]
          (local triangle-vector (make-vector-buffer))
          (local image-vector (make-image-buffer))
          (local image-batches {})
          (local seen-texture-names [])
          (local ctx {:triangle-vector triangle-vector
                      :track-triangle-handle (fn [_self _handle _clip] nil)
                      :untrack-triangle-handle (fn [_self _handle] nil)
                      :get-image-batch (fn [_self texture]
                                         (table.insert seen-texture-names texture.name)
                                         (when (= (. image-batches texture.id) nil)
                                           (set (. image-batches texture.id)
                                                {:texture texture
                                                 :vector image-vector}))
                                         (. image-batches texture.id))
                      :track-image-handle (fn [_self _batch _handle _clip] nil)
                      :untrack-image-handle (fn [_self _batch _handle] nil)
                      :unregister-image-batch (fn [_self texture-id]
                                                (set (. image-batches texture-id) nil))})
          (local controller (DrawingController {:data_dir dir}))
          (controller:add-layer "raster")
          (controller:set-active-tool "brush")
          (controller:begin-gesture "brush" (glm.vec3 8 8 0) {:pressure 1.0})
          (controller:update-gesture (glm.vec3 24 24 0) false {:pressure 1.0})
          (assert (controller:commit-gesture))
          (controller:begin-gesture "brush" (glm.vec3 180 8 0) {:pressure 1.0})
          (controller:update-gesture (glm.vec3 196 24 0) false {:pressure 1.0})
          (assert (controller:commit-gesture))
          (controller:set-active-tool "marquee")
          (controller:begin-gesture "marquee" (glm.vec3 0 0 0) {:pressure 1.0})
          (controller:update-gesture (glm.vec3 32 32 0) false {:pressure 1.0})
          (assert (controller:commit-gesture))
          (controller:set-active-tool "move")
          (controller:begin-gesture "move" (glm.vec3 8 8 0) {:pressure 1.0})
          (controller:update-gesture (glm.vec3 40 8 0) false {:pressure 1.0})
          (local canvas {:camera {:position (glm.vec3 96 16 100)}
                         :half-width 128
                         :half-height 32})
          (local render (DrawingRender {:ctx ctx
                                        :controller controller
                                        :canvas canvas}))
          (render:update)
          (local first-allocations image-vector.state.allocations)
          (local first-triangle-writes triangle-vector.state.vec3-writes)
          (local first-updates (total-texture-updates texture-updates))
          (var preview-count 0)
          (var normal-count 0)
          (each [_ name (ipairs seen-texture-names)]
            (when (and (= (type name) :string)
                       (string.find name "__drawing_raster_preview_" 1 true))
              (set preview-count (+ preview-count 1)))
            (when (and (= (type name) :string)
                       (string.find name "__drawing_raster_" 1 true)
                       (not (string.find name "__drawing_raster_preview_" 1 true)))
              (set normal-count (+ normal-count 1))))
          (assert (> preview-count 0)
                  "drawing render should allocate at least one preview texture while moving a raster selection")
          (assert (> normal-count 0)
                  "drawing render should keep unaffected visible tiles on their normal raster textures during move preview")
          (controller:update-gesture (glm.vec3 56 8 0) false {:pressure 1.0})
          (render:update)
          (assert (= image-vector.state.allocations first-allocations)
                  "drawing render should reuse tile and overlay image handles while move preview position changes")
          (assert (= triangle-vector.state.vec3-writes first-triangle-writes)
                  "drawing render should leave triangle geometry untouched when a raster move only changes overlay position")
          (assert (= (total-texture-updates texture-updates) first-updates)
                  "drawing render should not reupload preview textures when a move gesture only changes overlay position")
          (render:drop))))))

(table.insert tests {:name "Drawing render uploads triangle data for committed objects"
                     :fn drawing-render-populates-triangle-buffer})
(table.insert tests {:name "Drawing render uploads image quads for raster tiles"
                     :fn drawing-render-tracks-raster-image-quads})
(table.insert tests {:name "Drawing render culls offscreen raster tiles"
                     :fn drawing-render-culls-offscreen-raster-tiles})
(table.insert tests {:name "Drawing render rebuilds when camera bounds change"
                     :fn drawing-render-rebuilds-when-camera-bounds-change})
(table.insert tests {:name "Drawing render does not materialize persisted tiles into runtime state"
                     :fn drawing-render-does-not-materialize-persisted-tiles-into-runtime})
(table.insert tests {:name "Drawing render refreshes cached raster textures after edit"
                     :fn drawing-render-refreshes-cached-raster-textures-after-edit})
(table.insert tests {:name "Drawing render ignores vector-only changes for raster sync"
                     :fn drawing-render-ignores-vector-only-changes-for-raster-sync})
(table.insert tests {:name "Drawing render ignores vector-only history for raster sync"
                     :fn drawing-render-ignores-vector-only-history-for-raster-sync})
(table.insert tests {:name "Drawing render ignores layer ui-only changes for raster sync"
                     :fn drawing-render-ignores-layer-ui-only-changes-for-raster-sync})
(table.insert tests {:name "Drawing render masks only source tiles during raster move preview"
                     :fn drawing-render-masks-only-source-tiles-during-raster-move-preview})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-render"
                       :tests tests})))

{:name "drawing-render"
 :tests tests
 :main main}
