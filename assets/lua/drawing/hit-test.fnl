(local glm (require :glm))
(local VectorGeometry (require :drawing/vector-geometry))

(fn color->glm-vec4 [value fallback]
  (local source (or value fallback [1 1 1 1]))
  (glm.vec4 (or (. source 1) source.x 1)
            (or (. source 2) source.y 1)
            (or (. source 3) source.z 1)
            (or (. source 4) source.w 1)))

(fn screen-pos->canvas-point [canvas payload]
  (when (and canvas canvas.screen-pos-ray payload)
    (local ray (canvas:screen-pos-ray payload))
    (when (and ray ray.origin ray.direction)
      (local dz (or ray.direction.z 0))
      (when (not (= dz 0))
        (local t (/ (- 0 ray.origin.z) dz))
        (+ ray.origin (* ray.direction t))))))

(fn constrain-line [start finish]
  (local delta (- finish start))
  (local dx delta.x)
  (local dy delta.y)
  (local angle (math.atan dy dx))
  (local snapped-angle (* (/ math.pi 4) (math.floor (+ 0.5 (/ angle (/ math.pi 4))))))
  (local segment-length (glm.length delta))
  (+ start (glm.vec3 (* (math.cos snapped-angle) segment-length)
                     (* (math.sin snapped-angle) segment-length)
                     0)))

(fn distance-to-segment [point start finish]
  (local delta (- finish start))
  (local len2 (+ (* delta.x delta.x)
                 (* delta.y delta.y)
                 (* delta.z delta.z)))
  (if (< len2 1e-6)
      (glm.length (- point start))
      (do
        (local t
          (math.max 0
                    (math.min 1
                              (/ (+ (* (- point.x start.x) delta.x)
                                    (* (- point.y start.y) delta.y)
                                    (* (- point.z start.z) delta.z))
                                 len2))))
        (local projection (+ start (* delta t)))
        (glm.length (- point projection)))))

(fn point-to-object-local [object point]
  (VectorGeometry.rotate-offset (- point object.center) (- (or object.rotation 0))))

(fn point-in-rectangle? [object point]
  (local half (* object.size 0.5))
  (local local-point (point-to-object-local object point))
  (and (>= local-point.x (- half.x))
       (<= local-point.x half.x)
       (>= local-point.y (- half.y))
       (<= local-point.y half.y)))

(fn distance-to-rect-outline [object point]
  (local corners (VectorGeometry.rectangle-corners object))
  (local segments [[corners.a corners.b]
                   [corners.b corners.c]
                   [corners.c corners.d]
                   [corners.d corners.a]])
  (var best math.huge)
  (each [_ pair (ipairs segments)]
    (local candidate (distance-to-segment point (. pair 1) (. pair 2)))
    (when (< candidate best)
      (set best candidate)))
  best)

(fn hit-rectangle? [object point tolerance]
  (local style (or object.style {}))
  (if (and style.fill_enabled (point-in-rectangle? object point))
      true
      (<= (distance-to-rect-outline object point)
          (+ tolerance (* 0.5 (or style.thickness 1.0))))))

(fn hit-line? [object point tolerance]
  (local style (or object.style {}))
  (<= (distance-to-segment point object.start object.finish)
      (+ tolerance (* 0.5 (or style.thickness 1.0)))))

(fn hit-stroke? [object point tolerance]
  (local points (or object.points []))
  (local style (or object.style {}))
  (var best math.huge)
  (for [idx 1 (- (length points) 1)]
    (local start (. points idx))
    (local finish (. points (+ idx 1)))
    (local distance (distance-to-segment point start finish))
    (when (< distance best)
      (set best distance)))
  (if (= (length points) 1)
      (<= (glm.length (- point (. points 1)))
          (+ tolerance (* 0.5 (or style.thickness 1.0))))
      (<= best (+ tolerance (* 0.5 (or style.thickness 1.0))))))

(fn hit-ellipse? [object point tolerance]
  (local radii (* object.size 0.5))
  (if (or (< radii.x 1e-6) (< radii.y 1e-6))
      false
      (do
        (local local-point (point-to-object-local object point))
        (local nx (/ local-point.x radii.x))
        (local ny (/ local-point.y radii.y))
        (local d (+ (* nx nx) (* ny ny)))
        (if (and object.style object.style.fill_enabled (<= d 1.0))
            true
            (<= (math.abs (- 1.0 d))
                (/ tolerance (math.max radii.x radii.y)))))))

(fn hit-object? [object point tolerance]
  (if (= object.kind "rectangle")
      (hit-rectangle? object point tolerance)
      (= object.kind "ellipse")
      (hit-ellipse? object point tolerance)
      (= object.kind "line")
      (hit-line? object point tolerance)
      (= object.kind "stroke")
      (hit-stroke? object point tolerance)
      false))

(fn select-object [layer point tolerance]
  (var resolved nil)
  (for [idx (length (or layer.objects [])) 1 -1]
    (local object (. layer.objects idx))
    (when (and (not resolved)
               (hit-object? object point tolerance))
      (set resolved object)))
  resolved)

(fn collect-hit-object-ids [layer point tolerance]
  (local ids [])
  (for [idx (length (or layer.objects [])) 1 -1]
    (local object (. layer.objects idx))
    (when (hit-object? object point tolerance)
      (table.insert ids object.id)))
  ids)

{:color->glm-vec4 color->glm-vec4
 :screen-pos->canvas-point screen-pos->canvas-point
 :constrain-line constrain-line
 :distance-to-segment distance-to-segment
 :hit-object? hit-object?
 :select-object select-object
 :collect-hit-object-ids collect-hit-object-ids}
