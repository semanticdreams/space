(local glm (require :glm))

(local ellipse-segments 28)

(fn rotate-offset [offset angle]
  (if (= angle 0)
      offset
      (do
        (local c (math.cos angle))
        (local s (math.sin angle))
        (glm.vec3 (- (* offset.x c) (* offset.y s))
                  (+ (* offset.x s) (* offset.y c))
                  offset.z))))

(fn object-point [object offset]
  (+ object.center (rotate-offset offset (or object.rotation 0))))

(fn rectangle-corners [object]
  (local half (* object.size 0.5))
  {:a (object-point object (glm.vec3 (- half.x) (- half.y) 0))
   :b (object-point object (glm.vec3 half.x (- half.y) 0))
   :c (object-point object (glm.vec3 half.x half.y 0))
   :d (object-point object (glm.vec3 (- half.x) half.y 0))})

(fn ellipse-points [object]
  (local points [])
  (local rx (* object.size.x 0.5))
  (local ry (* object.size.y 0.5))
  (for [idx 0 ellipse-segments]
    (local angle (* (/ idx ellipse-segments) (* 2 math.pi)))
    (table.insert points
                  (object-point object
                                (glm.vec3 (* (math.cos angle) rx)
                                          (* (math.sin angle) ry)
                                          0))))
  points)

{:ellipse-segments ellipse-segments
 :rotate-offset rotate-offset
 :rectangle-corners rectangle-corners
 :ellipse-points ellipse-points}
