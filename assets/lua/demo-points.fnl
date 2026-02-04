(local glm (require :glm))
(local DemoPoints {})

(fn DemoPoints.attach [ctx entity]
  (if (or (not ctx) (not ctx.points) (not entity))
      entity
      (let [points ctx.points
            created []]
        (fn add-point [position color size]
          (local point (points:create-point {:position position
                                             :color color
                                             :size size}))
          (table.insert created point))
        (local segments 14)
        (local radius 11.0)
        (for [i 0 (- segments 1)]
          (local progress (/ i segments))
          (local angle (* progress (* 2 math.pi)))
          (local x (* radius (math.cos angle)))
          (local y (+ 1.5 (* 1.2 (math.sin (* 2 angle)))))
          (local z (+ 5.0 (* 0.6 (math.cos (* 3 angle)))))
          (local gradient progress)
          (local red (+ 0.3 (* 0.6 gradient)))
          (local green (+ 0.2 (* 0.5 (- 1 gradient))))
          (local size (+ 10 (* 3 (math.sin angle))))
          (add-point (glm.vec3 x y z) (glm.vec4 red green 1.0 1.0) size))
        (add-point (glm.vec3 0 4 7)
                   (glm.vec4 1.0 0.95 0.8 1.0)
                   22.0)
        (add-point (glm.vec3 -3 6 4)
                   (glm.vec4 0.6 0.9 1.0 1.0)
                   16.0)
        (when (> (length created) 0)
          (local original-drop entity.drop)
          (set entity.drop
               (fn [self]
                 (each [_ point (ipairs created)]
                   (when point.drop
                     (point:drop)))
                 (when original-drop
                   (original-drop self)))))
        entity)))

DemoPoints
