(local glm (require :glm))
(local DemoForceLayout {})

(local {:ForceLayout ForceLayout :ForceLayoutSignal ForceLayoutSignal} (require :force-layout))
(fn DemoForceLayout.attach [ctx entity]
  (if (or (not ctx) (not ctx.points) (not ctx.lines) (not entity))
      entity
      (let [layout (ForceLayout (glm.vec3 0 0 0) 55 5200 1.1 0.02 0.00008 0.03 0.02 90 0.05)
            node-count 6
            edges [[0 1] [0 2] [1 3] [1 4] [2 4] [3 5] [5 4]]
            base (glm.vec3 40 6 18)
            point-system ctx.points
            created-points []
            created-lines []
            world-positions []]
        (var update-handler nil)

        (fn rand-range [range]
          (- (* (math.random) (* 2 range)) range))

        (fn random-pos []
          (glm.vec3 (rand-range 90) (rand-range 60) 0))

        (layout:clear)
        (for [_ 1 node-count]
          (layout:add-node (random-pos)))
        (layout:pin-node 0 true)
        (each [_ edge (ipairs edges)]
          (layout:add-edge (. edge 1) (. edge 2) true))

        (for [i 1 node-count]
          (local gradient (/ i (math.max 1 node-count)))
          (local color (glm.vec4 (+ 0.35 (* 0.35 gradient))
                             (+ 0.45 (* 0.25 gradient))
                             1.0
                             1.0))
          (local point (point-system:create-point {:position base
                                                   :color color
                                                   :size (+ 8 (* 2 gradient))}))
          (table.insert created-points point))

        (each [_ _edge (ipairs edges)]
          (local line (ctx.lines:create-line {:start base
                                              :end base
                                              :color (glm.vec3 0.5 0.7 1.0)}))
          (table.insert created-lines line))

        (fn apply-positions []
          (local positions (layout:get-positions))
          (local count (length positions))
          (for [i 1 count]
            (local pos (. positions i))
            (local shifted (glm.vec3 (+ base.x pos.x)
                                 (+ base.y pos.y)
                                 (+ base.z (* 0.2 i))))
            (set (. world-positions i) shifted)
            (local point (. created-points i))
            (when point
              (point:set-position shifted)))
          (each [idx edge (ipairs edges)]
            (local start (. world-positions (+ (. edge 1) 1)))
            (local finish (. world-positions (+ (. edge 2) 1)))
            (local line (. created-lines idx))
            (when (and start finish line)
              (line:set-start start)
              (line:set-end finish))))

        (apply-positions)
        (layout:start)

        (fn on-update [_delta]
          (when layout.active
            (layout:update 40))
          (apply-positions))

        (set update-handler on-update)
        (when (and app.engine app.engine.events app.engine.events.updated)
          (app.engine.events.updated:connect on-update))

        (when (> node-count 0)
          (local original-drop entity.drop)
          (set entity.drop
               (fn [self]
                 (when (and update-handler app.engine app.engine.events app.engine.events.updated)
                   (app.engine.events.updated:disconnect update-handler true))
                 (each [_ line (ipairs created-lines)]
                   (when line.drop
                     (line:drop)))
                 (each [_ point (ipairs created-points)]
                   (when point.drop
                     (point:drop)))
                 (when original-drop
                   (original-drop self)))))

        entity)))

DemoForceLayout
