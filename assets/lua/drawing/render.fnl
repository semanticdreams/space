(local glm (require :glm))

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
  (local half (* object.size 0.5))
  (local left (- object.center.x half.x))
  (local right (+ object.center.x half.x))
  (local bottom (- object.center.y half.y))
  (local top (+ object.center.y half.y))
  (local a (glm.vec3 left bottom 0))
  (local b (glm.vec3 right bottom 0))
  (local c (glm.vec3 right top 0))
  (local d (glm.vec3 left top 0))
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
  (local rx (* object.size.x 0.5))
  (local ry (* object.size.y 0.5))
  (local segments 28)
  (local fill-color (color->glm-vec4 style :fill_color 1.0 [0.33 0.6 0.96 0.25]))
  (local stroke-color (color->glm-vec4 style :stroke_color 1.0 [0.95 0.95 0.97 1.0]))
  (local thickness (or style.thickness 1.0))
  (var previous nil)
  (for [idx 0 segments]
    (local angle (* (/ idx segments) (* 2 math.pi)))
    (local point (glm.vec3 (+ object.center.x (* (math.cos angle) rx))
                           (+ object.center.y (* (math.sin angle) ry))
                           0))
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

  (fn clear []
    (ensure-handle 0))

  (fn update [vertices]
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

  (fn drop []
    (when handle
      (when (and ctx ctx.untrack-triangle-handle)
        (ctx:untrack-triangle-handle handle))
      (ctx.triangle-vector:delete handle)
      (set handle nil)
      (set handle-size 0)))

  {:update update
   :clear clear
   :drop drop})

(fn DrawingRender [opts]
  (local options (or opts {}))
  (local ctx (assert options.ctx "DrawingRender requires :ctx"))
  (local controller (assert options.controller "DrawingRender requires :controller"))
  (local buffer (DynamicTriangleBuffer ctx))
  (var dirty? true)
  (var changed-handler nil)

  (fn mark-dirty []
    (set dirty? true))

  (set changed-handler
       (controller.changed:connect
         (fn [_payload]
           (mark-dirty))))

  (fn rebuild! []
    (local vertices [])
    (local selected-set {})
    (each [_ object-id (ipairs (or controller.state.ui.selection_ids []))]
      (set (. selected-set object-id) true))
    (each [layer-index layer (ipairs (or controller.state.document.layers []))]
      (each [object-index object (ipairs (or layer.objects []))]
        (local depth (+ (* layer-index 10.0) (* object-index 0.1)))
        (append-object! vertices object depth)
        (when (. selected-set object.id)
          (append-selection-outline! vertices object (+ depth 0.05)))))
    (local preview (controller:preview-object))
    (when preview
      (append-object! vertices preview 500.0))
    (buffer:update vertices)
    (set dirty? false))

  (fn update [_self]
    (when dirty?
      (rebuild!)))

  (fn drop [_self]
    (when changed-handler
      (controller.changed:disconnect changed-handler true)
      (set changed-handler nil))
    (buffer:drop))

  {:update update
   :drop drop
   :mark-dirty mark-dirty})

{:DrawingRender DrawingRender}
