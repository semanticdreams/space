(local glm (require :glm))

(local ellipse-segments 28)

(fn rectangle-corners [object]
  (local half (* object.size 0.5))
  {:a (glm.vec3 (- object.center.x half.x) (- object.center.y half.y) 0)
   :b (glm.vec3 (+ object.center.x half.x) (- object.center.y half.y) 0)
   :c (glm.vec3 (+ object.center.x half.x) (+ object.center.y half.y) 0)
   :d (glm.vec3 (- object.center.x half.x) (+ object.center.y half.y) 0)})

(fn ellipse-points [object]
  (local points [])
  (local rx (* object.size.x 0.5))
  (local ry (* object.size.y 0.5))
  (for [idx 0 ellipse-segments]
    (local angle (* (/ idx ellipse-segments) (* 2 math.pi)))
    (table.insert points
                  (glm.vec3 (+ object.center.x (* (math.cos angle) rx))
                            (+ object.center.y (* (math.sin angle) ry))
                            0)))
  points)

{:ellipse-segments ellipse-segments
 :rectangle-corners rectangle-corners
 :ellipse-points ellipse-points}
