(local glm (require :glm))
(local VectorGeometry (require :drawing/vector-geometry))

(fn premultiply-rgba [rgba]
  (local alpha (/ (or (. rgba 4) 0) 255.0))
  [(math.floor (+ 0.5 (* (or (. rgba 1) 0) alpha)))
   (math.floor (+ 0.5 (* (or (. rgba 2) 0) alpha)))
   (math.floor (+ 0.5 (* (or (. rgba 3) 0) alpha)))
   (or (. rgba 4) 0)])

(fn blend-rgba [dst src]
  (local src-a (/ (or (. src 4) 0) 255.0))
  (local out-a (+ src-a (* (or (. dst 4) 0) (/ (- 1 src-a) 255.0))))
  (if (<= out-a 0)
      [0 0 0 0]
      [(math.floor (+ 0.5 (+ (or (. src 1) 0)
                              (* (or (. dst 1) 0) (- 1 src-a)))))
       (math.floor (+ 0.5 (+ (or (. src 2) 0)
                              (* (or (. dst 2) 0) (- 1 src-a)))))
       (math.floor (+ 0.5 (+ (or (. src 3) 0)
                              (* (or (. dst 3) 0) (- 1 src-a)))))
       (math.floor (+ 0.5 (* out-a 255)))]))

(fn color->rgba [color opacity]
  (premultiply-rgba
    [(* (or (. color 1) color.x 0.0) 255)
     (* (or (. color 2) color.y 0.0) 255)
     (* (or (. color 3) color.z 0.0) 255)
     (* (or (. color 4) color.w 1.0) (or opacity 1.0) 255)]))

(fn rect-bounds [center size]
  (local half (* size 0.5))
  {:min (glm.vec3 (- center.x half.x) (- center.y half.y) center.z)
   :max (glm.vec3 (+ center.x half.x) (+ center.y half.y) center.z)})

(fn point-in-polygon? [point polygon]
  (local count (length polygon))
  (var inside? false)
  (var previous (. polygon count))
  (each [_ current (ipairs polygon)]
    (when (and previous
               (not (= current.y previous.y)))
      (local intersects?
        (not (= (> current.y point.y)
                (> previous.y point.y))))
      (when intersects?
        (local edge-x (+ current.x (* (- point.y current.y)
                                      (/ (- previous.x current.x)
                                         (- previous.y current.y)))))
        (when (< point.x edge-x)
          (set inside? (not inside?)))))
    (set previous current))
  inside?)

(fn point-in-bounds? [point bounds]
  (and bounds
       (>= point.x bounds.min.x)
       (<= point.x bounds.max.x)
       (>= point.y bounds.min.y)
       (<= point.y bounds.max.y)))

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

(fn sample-rectangle [object point]
  (local style (or object.style {}))
  (var rgba [0 0 0 0])
  (local corners (VectorGeometry.rectangle-corners object))
  (local bounds (rect-bounds object.center object.size))
  (when (and style.fill_enabled (point-in-bounds? point bounds))
    (set rgba (blend-rgba rgba (color->rgba style.fill_color style.opacity))))
  (when (<= (distance-to-segment point corners.a corners.b)
            (* 0.5 (or style.thickness 1.0)))
    (set rgba (blend-rgba rgba (color->rgba style.stroke_color style.opacity))))
  (when (<= (distance-to-segment point corners.b corners.c)
            (* 0.5 (or style.thickness 1.0)))
    (set rgba (blend-rgba rgba (color->rgba style.stroke_color style.opacity))))
  (when (<= (distance-to-segment point corners.c corners.d)
            (* 0.5 (or style.thickness 1.0)))
    (set rgba (blend-rgba rgba (color->rgba style.stroke_color style.opacity))))
  (when (<= (distance-to-segment point corners.d corners.a)
            (* 0.5 (or style.thickness 1.0)))
    (set rgba (blend-rgba rgba (color->rgba style.stroke_color style.opacity))))
  rgba)

(fn sample-line [object point]
  (if (<= (distance-to-segment point object.start object.finish)
          (* 0.5 (or (and object.style object.style.thickness) 1.0)))
      (color->rgba object.style.stroke_color object.style.opacity)
      [0 0 0 0]))

(fn sample-stroke [object point]
  (local points (or object.points []))
  (var best math.huge)
  (for [idx 1 (- (length points) 1)]
    (local start (. points idx))
    (local finish (. points (+ idx 1)))
    (set best (math.min best (distance-to-segment point start finish))))
  (if (and (= (length points) 1)
           (<= (glm.length (- point (. points 1)))
               (* 0.5 (or (and object.style object.style.thickness) 1.0))))
      (color->rgba object.style.stroke_color object.style.opacity)
      (if (<= best (* 0.5 (or (and object.style object.style.thickness) 1.0)))
          (color->rgba object.style.stroke_color object.style.opacity)
          [0 0 0 0])))

(fn sample-ellipse [object point]
  (local style (or object.style {}))
  (local points (VectorGeometry.ellipse-points object))
  (if (< (length points) 2)
      [0 0 0 0]
      (do
        (var rgba [0 0 0 0])
        (when (and style.fill_enabled (point-in-polygon? point points))
          (set rgba (blend-rgba rgba (color->rgba style.fill_color style.opacity))))
        (for [idx 2 (length points)]
          (when (<= (distance-to-segment point (. points (- idx 1)) (. points idx))
                    (* 0.5 (or style.thickness 1.0)))
            (set rgba (blend-rgba rgba (color->rgba style.stroke_color style.opacity)))))
        rgba)))

(fn sample-vector-object [object point]
  (if (= object.kind "rectangle")
      (sample-rectangle object point)
      (= object.kind "ellipse")
      (sample-ellipse object point)
      (= object.kind "line")
      (sample-line object point)
      (= object.kind "stroke")
      (sample-stroke object point)
      [0 0 0 0]))

(fn sample-vector-layer [layer point]
  (var rgba [0 0 0 0])
  (each [_ object (ipairs (or layer.objects []))]
    (set rgba (blend-rgba rgba (sample-vector-object object point))))
  rgba)

{:blend-rgba blend-rgba
 :sample-vector-layer sample-vector-layer}
