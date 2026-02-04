(local glm (require :glm))
(local DemoLines {})

(fn DemoLines.attach [ctx entity]
  (if (or (not ctx) (not ctx.lines) (not entity))
      entity
      (let [lines ctx.lines
            created []]
        (fn add-line [start end color]
          (local line (lines:create-line {:start start :end end :color color}))
          (table.insert created line))
        (local axis-length 25.0)
        (add-line (glm.vec3 (- axis-length) 0 0) (glm.vec3 axis-length 0 0) (glm.vec3 1 0 0))
        (add-line (glm.vec3 0 (- axis-length) 0) (glm.vec3 0 axis-length 0) (glm.vec3 0 1 0))
        (add-line (glm.vec3 0 0 (- axis-length)) (glm.vec3 0 0 axis-length) (glm.vec3 0 0 1))
        (local grid-half 15.0)
        (local grid-step 5.0)
        (local grey (glm.vec3 0.5 0.5 0.5))
        (for [offset (- grid-half) grid-half grid-step]
          (add-line (glm.vec3 (- grid-half) 0 offset)
                    (glm.vec3 grid-half 0 offset)
                    grey)
          (add-line (glm.vec3 offset 0 (- grid-half))
                    (glm.vec3 offset 0 grid-half)
                    grey))
        (local wave-points [])
        (var x (- grid-half))
        (while (<= x grid-half)
          (local height (+ 2.0 (* 1.5 (math.sin (* 0.3 x)))))
          (table.insert wave-points (glm.vec3 x height 6.0))
          (set x (+ x 1.2)))
        (local strip (lines:create-line-strip {:points wave-points
                                               :color (glm.vec3 1 0.8 0.2)}))
        (table.insert created strip)
        (when (> (length created) 0)
          (local original-drop entity.drop)
          (set entity.drop
               (fn [self]
                 (each [_ line (ipairs created)]
                   (when line.drop
                     (line:drop)))
                 (when original-drop
                   (original-drop self)))))
        entity)))

DemoLines
