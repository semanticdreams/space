(local glm (require :glm))
(local RasterLayer (require :drawing/raster-layer))
(local VectorGeometry (require :drawing/vector-geometry))

(fn color->glm-vec4 [style key opacity-multiplier fallback]
  (local source (or (. style key) fallback [1 1 1 1]))
  (local opacity (* (or (. source 4) source.w 1.0) (or style.opacity 1.0) (or opacity-multiplier 1.0)))
  (glm.vec4 (or (. source 1) source.x 1.0)
            (or (. source 2) source.y 1.0)
            (or (. source 3) source.z 1.0)
            opacity))

(fn append-vertex! [vertices position color depth]
  (table.insert vertices {:position position :color color :depth depth}))

(fn append-triangle! [vertices a b c color depth]
  (append-vertex! vertices a color depth)
  (append-vertex! vertices b color depth)
  (append-vertex! vertices c color depth))

(fn append-quad! [vertices a b c d color depth]
  (append-triangle! vertices a b c color depth)
  (append-triangle! vertices a c d color depth))

(fn append-ribbon! [vertices start finish thickness color depth]
  (local delta (- finish start))
  (local len (glm.length delta))
  (when (> len 1e-4)
    (local direction (/ delta len))
    (local normal (* (glm.vec3 (- direction.y) direction.x 0) (* thickness 0.5)))
    (local a (+ start normal))
    (local b (- start normal))
    (local c (- finish normal))
    (local d (+ finish normal))
    (append-quad! vertices a b c d color depth)))

(fn append-rectangle! [vertices object depth]
  (local style (or object.style {}))
  (local corners (VectorGeometry.rectangle-corners object))
  (local a corners.a)
  (local b corners.b)
  (local c corners.c)
  (local d corners.d)
  (when style.fill_enabled
    (append-quad! vertices a b c d (color->glm-vec4 style :fill_color 1.0 [0.33 0.6 0.96 0.25]) depth))
  (local stroke-color (color->glm-vec4 style :stroke_color 1.0 [0.95 0.95 0.97 1.0]))
  (local thickness (or style.thickness 1.0))
  (append-ribbon! vertices a b thickness stroke-color (+ depth 0.01))
  (append-ribbon! vertices b c thickness stroke-color (+ depth 0.01))
  (append-ribbon! vertices c d thickness stroke-color (+ depth 0.01))
  (append-ribbon! vertices d a thickness stroke-color (+ depth 0.01)))

(fn append-ellipse! [vertices object depth]
  (local style (or object.style {}))
  (local fill-color (color->glm-vec4 style :fill_color 1.0 [0.33 0.6 0.96 0.25]))
  (local stroke-color (color->glm-vec4 style :stroke_color 1.0 [0.95 0.95 0.97 1.0]))
  (local thickness (or style.thickness 1.0))
  (var previous nil)
  (each [_ point (ipairs (VectorGeometry.ellipse-points object))]
    (when (and previous style.fill_enabled)
      (append-triangle! vertices object.center previous point fill-color depth))
    (when previous
      (append-ribbon! vertices previous point thickness stroke-color (+ depth 0.01)))
    (set previous point)))

(fn append-line! [vertices object depth]
  (local style (or object.style {}))
  (append-ribbon! vertices object.start object.finish (or style.thickness 1.0)
                  (color->glm-vec4 style :stroke_color 1.0 [0.95 0.95 0.97 1.0])
                  depth))

(fn append-stroke! [vertices object depth]
  (local points (or object.points []))
  (local style (or object.style {}))
  (local color (color->glm-vec4 style :stroke_color 1.0 [0.95 0.95 0.97 1.0]))
  (local thickness (or style.thickness 1.0))
  (for [idx 1 (- (length points) 1)]
    (append-ribbon! vertices (. points idx) (. points (+ idx 1)) thickness color (+ depth (* idx 0.0001)))))

(fn append-object! [vertices object depth]
  (if (= object.kind "rectangle")
      (append-rectangle! vertices object depth)
      (= object.kind "ellipse")
      (append-ellipse! vertices object depth)
      (= object.kind "line")
      (append-line! vertices object depth)
      (= object.kind "stroke")
      (append-stroke! vertices object depth)
      nil))

(fn append-selection-outline! [vertices object depth]
  (local highlighted {:stroke_color [1.0 0.72 0.22 1.0]
                      :fill_color [0 0 0 0]
                      :thickness (+ (or (and object.style object.style.thickness) 1.0) 1.5)
                      :opacity 1.0
                      :fill_enabled false})
  (local copy {})
  (each [k v (pairs object)]
    (set (. copy k) v))
  (set copy.style highlighted)
  (append-object! vertices copy depth))

(fn write-image-quad! [vector handle position size color depth]
  (local verts
    [[0 0 0] [1 0 0] [1 1 0]
     [0 0 0] [1 1 0] [0 1 0]])
  (local uvs
    [[0 0] [1 0] [1 1]
     [0 0] [1 1] [0 1]])
  (for [i 1 6]
    (local base (glm.vec3 (table.unpack (. verts i))))
    (local scaled (glm.vec3 (* size.x base.x)
                            (* size.y base.y)
                            0))
    (vector.set-glm-vec3 vector
                         handle
                         (* (- i 1) 10)
                         (+ position scaled))
    (vector.set-glm-vec2 vector
                         handle
                         (+ (* (- i 1) 10) 3)
                         (glm.vec2 (table.unpack (. uvs i))))
    (vector.set-glm-vec4 vector
                         handle
                         (+ (* (- i 1) 10) 5)
                         color)
    (vector:set-float handle (+ (* (- i 1) 10) 9) depth)))

(fn clone-bytes [bytes]
  (local out {})
  (for [idx 1 (length bytes)]
    (set (. out idx) (. bytes idx)))
  out)

(fn raster-visible-bounds [canvas]
  (if (not canvas)
      nil
      (do
        (local camera (assert canvas.camera "DrawingRender raster culling requires canvas.camera"))
        (local half-width (assert canvas.half-width "DrawingRender raster culling requires canvas.half-width"))
        (local half-height (assert canvas.half-height "DrawingRender raster culling requires canvas.half-height"))
        {:left (math.floor (- camera.position.x half-width))
         :right (math.ceil (+ camera.position.x half-width))
         :bottom (math.floor (- camera.position.y half-height))
         :top (math.ceil (+ camera.position.y half-height))
         :width (+ (math.ceil (* half-width 2)) 1)
         :height (+ (math.ceil (* half-height 2)) 1)})))

(fn visible-bounds-changed? [left right]
  (if (or (= left nil) (= right nil))
      (not (= left right))
      (or (not (= left.left right.left))
          (not (= left.right right.right))
          (not (= left.bottom right.bottom))
          (not (= left.top right.top))
          (not (= left.width right.width))
          (not (= left.height right.height)))))

(fn masked-tile-bytes [tile runtime bounds]
  (local left (math.max bounds.left (* tile.tx runtime.tile-size)))
  (local right (math.min bounds.right (+ (* (+ tile.tx 1) runtime.tile-size) -1)))
  (local bottom (math.max bounds.bottom (* tile.ty runtime.tile-size)))
  (local top (math.min bounds.top (+ (* (+ tile.ty 1) runtime.tile-size) -1)))
  (if (or (> left right) (> bottom top))
      tile.bytes
      (do
        (local bytes (clone-bytes tile.bytes))
        (for [y bottom top]
          (for [x left right]
            (local local-x (- x (* tile.tx runtime.tile-size)))
            (local local-y (- y (* tile.ty runtime.tile-size)))
            (local idx (+ (* (+ (* local-y runtime.tile-size) local-x) 4) 1))
            (set (. bytes idx) 0)
            (set (. bytes (+ idx 1)) 0)
            (set (. bytes (+ idx 2)) 0)
            (set (. bytes (+ idx 3)) 0)))
        bytes)))

(fn tile-intersects-bounds? [tx ty tile-size bounds]
  (and bounds
       (not (< (+ (* (+ tx 1) tile-size) -1) bounds.left))
       (not (> (* tx tile-size) bounds.right))
       (not (< (+ (* (+ ty 1) tile-size) -1) bounds.bottom))
       (not (> (* ty tile-size) bounds.top))))

(fn DynamicTriangleBuffer [ctx]
  (assert (and ctx ctx.triangle-vector) "DynamicTriangleBuffer requires ctx.triangle-vector")
  (var handle nil)
  (var handle-size 0)

  (fn ensure-handle [size]
    (if (or (not handle) (not (= handle-size size)))
        (do
          (when handle
            (when (and ctx ctx.untrack-triangle-handle)
              (ctx:untrack-triangle-handle handle))
            (ctx.triangle-vector:delete handle))
          (set handle (if (> size 0)
                          (ctx.triangle-vector:allocate size)
                          nil))
          (set handle-size size))))

  (fn clear [_self]
    (ensure-handle 0))

  (fn update [_self vertices]
    (local count (length vertices))
    (local size (* count 8))
    (ensure-handle size)
    (when handle
      (each [idx vertex (ipairs vertices)]
        (local offset (* (- idx 1) 8))
        (ctx.triangle-vector:set-glm-vec3 handle offset vertex.position)
        (ctx.triangle-vector:set-glm-vec4 handle (+ offset 3) vertex.color)
        (ctx.triangle-vector:set-float handle (+ offset 7) vertex.depth))
      (when (and ctx ctx.track-triangle-handle)
        (ctx:track-triangle-handle handle nil))))

  (fn drop [_self]
    (when handle
      (when (and ctx ctx.untrack-triangle-handle)
        (ctx:untrack-triangle-handle handle))
      (ctx.triangle-vector:delete handle)
      (set handle nil)
      (set handle-size 0)))

  {:update update
   :clear clear
   :drop drop})

(fn vec3= [left right]
  (if (or (= left nil) (= right nil))
      (= left right)
      (and (= left.x right.x)
           (= left.y right.y)
           (= left.z right.z))))

(fn vec4= [left right]
  (if (or (= left nil) (= right nil))
      (= left right)
      (and (= left.x right.x)
           (= left.y right.y)
           (= left.z right.z)
           (= left.w right.w))))

(fn clone-vec3 [value]
  (and value
       (glm.vec3 value.x value.y value.z)))

(fn clone-vec4 [value]
  (and value
       (glm.vec4 value.x value.y value.z value.w)))

(fn bounds= [left right]
  (if (or (= left nil) (= right nil))
      (= left right)
      (and (= left.left right.left)
           (= left.right right.right)
           (= left.bottom right.bottom)
           (= left.top right.top)
           (= left.width right.width)
           (= left.height right.height))))

(fn overlay-source-state [overlay]
  (if (and overlay
           overlay.layer_id
           overlay.fragment
           overlay.selection
           overlay.selection.bounds)
      {:layer_id overlay.layer_id
       :bounds {:left overlay.selection.bounds.left
                :right overlay.selection.bounds.right
                :bottom overlay.selection.bounds.bottom
                :top overlay.selection.bounds.top
                :width overlay.selection.bounds.width
                :height overlay.selection.bounds.height}
       :width overlay.fragment.width
       :height overlay.fragment.height
       :fragment-token overlay.fragment.bytes}
      nil))

(fn overlay-source-state= [left right]
  (if (or (= left nil) (= right nil))
      (= left right)
      (and (= left.layer_id right.layer_id)
           (bounds= left.bounds right.bounds)
           (= left.width right.width)
           (= left.height right.height)
           (= left.fragment-token right.fragment-token))))

(fn overlay-position-state [overlay]
  (if (and overlay
           overlay.fragment
           overlay.position)
      {:x overlay.position.x
       :y overlay.position.y
       :width overlay.fragment.width
       :height overlay.fragment.height}
      nil))

(fn overlay-position-state= [left right]
  (if (or (= left nil) (= right nil))
      (= left right)
      (and (= left.x right.x)
           (= left.y right.y)
           (= left.width right.width)
           (= left.height right.height))))

(fn DrawingRender [opts]
  (local options (or opts {}))
  (local ctx (assert options.ctx "DrawingRender requires :ctx"))
  (local controller (assert options.controller "DrawingRender requires :controller"))
  (local textures (require :textures))
  (local allocate-texture (assert (. textures "allocate-texture")
                                  "DrawingRender requires textures.allocate-texture"))
  (local drop-texture (assert (. textures "drop-texture")
                              "DrawingRender requires textures.drop-texture"))
  (local canvas options.canvas)
  (local buffer (DynamicTriangleBuffer ctx))
  (var tile-image-handles {})
  (var tile-texture-cache {})
  (var overlay-image-handle nil)
  (var overlay-texture-entry nil)
  (var triangles-dirty? true)
  (var tile-images-dirty? true)
  (var overlay-image-dirty? true)
  (var last-preview-active? false)
  (var last-visible-bounds nil)
  (var last-overlay-source nil)
  (var last-overlay-position nil)
  (var changed-handler nil)

  (fn mark-triangles-dirty []
    (set triangles-dirty? true))

  (fn mark-tile-images-dirty []
    (set tile-images-dirty? true))

  (fn mark-overlay-image-dirty []
    (set overlay-image-dirty? true))

  (fn mark-dirty []
    (mark-triangles-dirty)
    (mark-tile-images-dirty)
    (mark-overlay-image-dirty))

  (fn drop-tile-image-handle! [handle-key]
    (local entry (. tile-image-handles handle-key))
    (when entry
      (when (and ctx ctx.untrack-image-handle)
        (ctx:untrack-image-handle entry.batch entry.handle))
      (entry.batch.vector:delete entry.handle)
      (set (. tile-image-handles handle-key) nil)))

  (fn image-handle-write-needed? [entry batch position size color depth]
    (or (not entry)
        (not (= entry.batch batch))
        (not (vec3= entry.position position))
        (not (vec3= entry.size size))
        (not (vec4= entry.color color))
        (not (= entry.depth depth))))

  (fn ensure-tile-image-handle! [handle-key batch position size color depth]
    (var entry (. tile-image-handles handle-key))
    (local needs-write?
      (image-handle-write-needed? entry
                                  batch
                                  position
                                  size
                                  color
                                  depth))
    (when (or (not entry)
              (not (= entry.batch batch)))
      (when entry
        (drop-tile-image-handle! handle-key))
      (set entry {:batch batch
                  :handle (batch.vector:allocate (* 10 6))})
      (when (and ctx ctx.track-image-handle)
        (ctx:track-image-handle batch entry.handle nil))
      (set (. tile-image-handles handle-key) entry))
    (when needs-write?
      (write-image-quad! batch.vector
                         entry.handle
                         position
                         size
                         color
                         depth)
      (set entry.position (clone-vec3 position))
      (set entry.size (clone-vec3 size))
      (set entry.color (clone-vec4 color))
      (set entry.depth depth))
    entry)

  (fn prune-tile-image-handles! [active-handle-keys]
    (each [handle-key _entry (pairs tile-image-handles)]
      (when (not (. active-handle-keys handle-key))
        (drop-tile-image-handle! handle-key))))

  (fn drop-overlay-image-handle! []
    (when overlay-image-handle
      (when (and ctx ctx.untrack-image-handle)
        (ctx:untrack-image-handle overlay-image-handle.batch
                                  overlay-image-handle.handle))
      (overlay-image-handle.batch.vector:delete overlay-image-handle.handle)
      (set overlay-image-handle nil)))

  (fn ensure-overlay-image-handle! [batch position size color depth]
    (local needs-write?
      (image-handle-write-needed? overlay-image-handle
                                  batch
                                  position
                                  size
                                  color
                                  depth))
    (when (or (not overlay-image-handle)
              (not (= overlay-image-handle.batch batch)))
      (drop-overlay-image-handle!)
      (set overlay-image-handle {:batch batch
                                 :handle (batch.vector:allocate (* 10 6))})
      (when (and ctx ctx.track-image-handle)
        (ctx:track-image-handle batch overlay-image-handle.handle nil)))
    (when needs-write?
      (write-image-quad! batch.vector
                         overlay-image-handle.handle
                         position
                         size
                         color
                         depth)
      (set overlay-image-handle.position (clone-vec3 position))
      (set overlay-image-handle.size (clone-vec3 size))
      (set overlay-image-handle.color (clone-vec4 color))
      (set overlay-image-handle.depth depth))
    overlay-image-handle)

  (fn drop-tile-cache-entry! [cache-key]
    (local entry (. tile-texture-cache cache-key))
    (when entry
      (local texture-id (and entry.texture entry.texture.id))
      (drop-texture entry.name)
      (when (and ctx ctx.unregister-image-batch texture-id)
        (ctx:unregister-image-batch texture-id))
      (set (. tile-texture-cache cache-key) nil)))

  (fn ensure-tile-cache-entry! [cache-key name width height]
    (when (= (. tile-texture-cache cache-key) nil)
      (set (. tile-texture-cache cache-key)
           {:name name
            :texture (allocate-texture name width height 4)
            :uploaded? false
            :preview-token nil}))
    (local entry (. tile-texture-cache cache-key))
    (when (or (not (= entry.texture.width width))
              (not (= entry.texture.height height)))
      (entry.texture:allocate width height 4)
      (set entry.uploaded? false)
      (set entry.preview-token nil))
    entry)

  (fn ensure-tile-texture! [cache-key tile runtime bytes opts]
    (local options (or opts {}))
    (local entry
      (ensure-tile-cache-entry! cache-key
                                (or options.name (.. "__drawing_raster_" cache-key))
                                runtime.tile-size
                                runtime.tile-size))
    (local preview-token options.preview-token)
    (local upload-needed?
      (if preview-token
          (or (not entry.uploaded?)
              tile.dirty?
              (not (= entry.preview-token preview-token)))
          (or (not entry.uploaded?)
              tile.dirty?)))
    (when upload-needed?
      (local update-full (assert (. entry.texture "update-full")
                                 "DrawingRender requires texture:update-full"))
      (update-full entry.texture (RasterLayer.bytes-string-from-table bytes))
      (set entry.uploaded? true)
      (set entry.preview-token preview-token)
      (when (not preview-token)
        (set tile.dirty? false)))
    entry.texture)

  (fn prune-tile-texture-cache! [active-cache-keys]
    (each [cache-key _entry (pairs tile-texture-cache)]
      (when (not (. active-cache-keys cache-key))
        (drop-tile-cache-entry! cache-key))))

  (fn drop-overlay-texture! []
    (when overlay-texture-entry
      (local texture-id (and overlay-texture-entry.texture
                             overlay-texture-entry.texture.id))
      (drop-texture overlay-texture-entry.name)
      (when (and ctx ctx.unregister-image-batch texture-id)
        (ctx:unregister-image-batch texture-id))
      (set overlay-texture-entry nil)))

  (fn ensure-overlay-texture! [cache-key fragment]
    (when (or (not overlay-texture-entry)
              (not (= overlay-texture-entry.cache-key cache-key)))
      (drop-overlay-texture!)
      (set overlay-texture-entry
           {:cache-key cache-key
            :name (.. "__drawing_overlay_" cache-key)
            :texture (allocate-texture (.. "__drawing_overlay_" cache-key)
                                       fragment.width
                                       fragment.height
                                       4)
            :uploaded? false
            :fragment-token nil}))
    (local entry overlay-texture-entry)
    (when (or (not (= entry.texture.width fragment.width))
              (not (= entry.texture.height fragment.height)))
      (entry.texture:allocate fragment.width fragment.height 4)
      (set entry.uploaded? false)
      (set entry.fragment-token nil))
    (when (or (not entry.uploaded?)
              (not (= entry.fragment-token fragment.bytes)))
      (local update-full (assert (. entry.texture "update-full")
                                 "DrawingRender requires texture:update-full"))
      (update-full entry.texture (RasterLayer.bytes-string-from-table fragment.bytes))
      (set entry.uploaded? true)
      (set entry.fragment-token fragment.bytes))
    entry.texture)

  (fn rebuild-triangles! [overlay preview]
    (local vertices [])
    (local selected-set {})
    (each [_ object-id (ipairs (or controller.state.ui.selection_ids []))]
      (set (. selected-set object-id) true))
    (each [layer-index layer (ipairs (or controller.state.document.layers []))]
      (when (= layer.kind "vector")
        (each [object-index object (ipairs (or layer.objects []))]
            (local depth (+ (* layer-index 10.0) (* object-index 0.1)))
            (append-object! vertices object depth)
            (when (. selected-set object.id)
              (append-selection-outline! vertices object (+ depth 0.05))))))
    (when (and overlay overlay.selection)
      (local bounds overlay.selection.bounds)
      (append-object! vertices
                      {:kind "rectangle"
                       :center (glm.vec3 (* (+ bounds.left bounds.right) 0.5)
                                         (* (+ bounds.bottom bounds.top) 0.5)
                                         0)
                       :size (glm.vec3 bounds.width bounds.height 0)
                       :style {:stroke_color [1.0 0.72 0.22 1.0]
                               :fill_color [0 0 0 0]
                               :thickness 1.5
                                :opacity 1.0
                               :fill_enabled false}}
                      800.0))
    (when preview
      (append-object! vertices preview 500.0))
    (buffer:update vertices)
    (set triangles-dirty? false))

  (fn sync-tile-images! [overlay visible-bounds]
    (local active-cache-keys {})
    (local active-handle-keys {})
    (each [layer-index layer (ipairs (or controller.state.document.layers []))]
      (when (= layer.kind "raster")
        (local raster-runtime (controller:ensure-raster-runtime layer))
        (local runtime raster-runtime.runtime)
        (each [_ entry (ipairs (raster-runtime:visible-tile-entries visible-bounds))]
          (local key (.. (tostring entry.tx) ":" (tostring entry.ty)))
          (local preview-source-tile?
            (and overlay
                 overlay.fragment
                 overlay.selection
                 (= overlay.layer_id layer.id)
                 (tile-intersects-bounds? entry.tx
                                         entry.ty
                                         runtime.tile-size
                                         overlay.selection.bounds)))
          (local cache-key
            (if preview-source-tile?
                (.. layer.id ":" key ":preview")
                (.. layer.id ":" key)))
          (local cache-entry (. tile-texture-cache cache-key))
          (local loaded-tile (. runtime.tiles key))
          (local needs-bytes? (or preview-source-tile?
                                 (not cache-entry)
                                 (and loaded-tile loaded-tile.dirty?)))
          (local tile
            (and needs-bytes?
                 (or loaded-tile
                     (raster-runtime:render-tile entry.tx entry.ty))))
          (assert (or (not needs-bytes?) tile)
                  (.. "DrawingRender missing raster tile " layer.id ":" key))
          (local bytes
            (and tile
                 (if preview-source-tile?
                     (masked-tile-bytes tile runtime overlay.selection.bounds)
                     tile.bytes)))
          (local texture
            (ensure-tile-texture! cache-key
                                  (or tile {:dirty? false})
                                  runtime
                                  bytes
                                  {:preview-token (and preview-source-tile?
                                                       overlay.fragment.bytes)
                                   :name (if preview-source-tile?
                                             (.. "__drawing_raster_preview_" layer.id ":" key)
                                             (.. "__drawing_raster_" layer.id ":" key))}))
          (set (. active-cache-keys cache-key) true)
          (local batch (ctx:get-image-batch texture))
          (local position (glm.vec3 (* entry.tx runtime.tile-size)
                                    (* entry.ty runtime.tile-size)
                                    0))
          (local size (glm.vec3 runtime.tile-size runtime.tile-size 0))
          (local depth (* layer-index 10.0))
          (ensure-tile-image-handle! cache-key
                                     batch
                                     position
                                     size
                                     (glm.vec4 1 1 1 1)
                                     depth)
          (set (. active-handle-keys cache-key) true))))
    (prune-tile-image-handles! active-handle-keys)
    (prune-tile-texture-cache! active-cache-keys)
    (set tile-images-dirty? false))

  (fn sync-overlay-image! [overlay]
    (if (and overlay overlay.fragment overlay.position)
        (do
          (local overlay-key (or (and overlay.selection overlay.selection.layer_id)
                                 "overlay"))
          (local texture (ensure-overlay-texture! overlay-key
                                                  overlay.fragment))
          (local batch (ctx:get-image-batch texture))
          (ensure-overlay-image-handle! batch
                                        (glm.vec3 overlay.position.x overlay.position.y 0)
                                        (glm.vec3 overlay.fragment.width overlay.fragment.height 0)
                                        (glm.vec4 1 1 1 0.85)
                                        850.0))
        (drop-overlay-image-handle!))
    (set overlay-image-dirty? false))

  (fn preview-active? []
    (and controller.preview-active?
         (controller:preview-active?)))

  (fn mark-preview-triangles-dirty! []
    (when (or last-preview-active?
              (preview-active?))
      (mark-triangles-dirty)))

  (local known-reasons {:vector-selection true
                        :raster-selection true
                        :vector-content true
                        :raster-content true
                        :raster-selection-content true
                        :active-layer true
                        :layer-meta true
                        :layer-structure true
                        :tool true
                        :defaults true
                        :history true})

  (set changed-handler
       (controller.changed:connect
         (fn [payload]
           (local reason (or (and payload payload.reason)
                             "drawing-render"))
           (if (= reason "layer-structure")
               (do
                 (mark-triangles-dirty)
                 (mark-tile-images-dirty)
                 (mark-overlay-image-dirty))
               (= reason "active-layer")
               (do
                 (mark-triangles-dirty)
                 (mark-overlay-image-dirty))
               (= reason "vector-selection")
               (mark-triangles-dirty)
               (= reason "raster-selection")
               (mark-triangles-dirty)
               (= reason "layer-meta")
               nil
               (= reason "vector-content")
               (mark-triangles-dirty)
               (= reason "raster-content")
               (mark-tile-images-dirty)
               (= reason "raster-selection-content")
               (do
                 (mark-triangles-dirty)
                 (mark-tile-images-dirty)
                 (mark-overlay-image-dirty))
               (= reason "gesture")
               (do
                 (mark-preview-triangles-dirty!)
                 (mark-overlay-image-dirty))
               (= reason "defaults")
               (mark-preview-triangles-dirty!)
               (not (. known-reasons reason))
               (do
                 (mark-triangles-dirty)
                 (mark-tile-images-dirty)
                 (mark-overlay-image-dirty))
               nil))))

  (fn update [_self]
    (local visible-bounds (raster-visible-bounds canvas))
    (when (visible-bounds-changed? last-visible-bounds visible-bounds)
      (mark-tile-images-dirty))
    (local overlay
      (and controller.raster-overlay
           (controller:raster-overlay)))
    (local preview
      (and controller.preview-object
           (controller:preview-object)))
    (local preview-active? (not (= preview nil)))
    (local overlay-source (overlay-source-state overlay))
    (local overlay-position (overlay-position-state overlay))
    (when (not (= last-preview-active? preview-active?))
      (mark-triangles-dirty))
    (when (not (overlay-source-state= last-overlay-source overlay-source))
      (mark-tile-images-dirty)
      (mark-overlay-image-dirty))
    (when (not (overlay-position-state= last-overlay-position overlay-position))
      (mark-overlay-image-dirty))
    (when triangles-dirty?
      (rebuild-triangles! overlay preview))
    (when tile-images-dirty?
      (sync-tile-images! overlay visible-bounds))
    (when overlay-image-dirty?
      (sync-overlay-image! overlay))
    (set last-visible-bounds visible-bounds)
    (set last-preview-active? preview-active?)
    (set last-overlay-source overlay-source)
    (set last-overlay-position overlay-position))

  (fn drop [_self]
    (when changed-handler
      (controller.changed:disconnect changed-handler true)
      (set changed-handler nil))
    (each [handle-key _entry (pairs tile-image-handles)]
      (drop-tile-image-handle! handle-key))
    (drop-overlay-image-handle!)
    (each [cache-key _entry (pairs tile-texture-cache)]
      (drop-tile-cache-entry! cache-key))
    (drop-overlay-texture!)
    (buffer:drop))

  {:update update
   :drop drop
   :mark-dirty mark-dirty})

{:DrawingRender DrawingRender}
