(local glm (require :glm))
(local default-color (glm.vec4 1 0.7 0.3 1))
(local default-size 11.0)

(fn ensure-glm-vec4 [value fallback]
    (if value
        (if (= (type value) :userdata)
            value
            (glm.vec4 (or (. value 1) 0)
                  (or (. value 2) 0)
                  (or (. value 3) 0)
                  (or (. value 4) 1)))
        (or fallback default-color)))

(fn resolve-point [entry idx size color]
    (local etype (type entry))
    (if (= etype :number)
        {:x idx :y entry :size size :color color}
        (if (= etype :userdata)
            {:x (or entry.x idx)
             :y (or entry.y entry.z entry.x 0)
             :size (or entry.size size)
             :color (or entry.color color)}
            (if (= etype :table)
                (do
                    (local x (or entry.x (. entry 1) idx))
                    (local y (or entry.y (. entry 2) 0))
                    {:x x
                     :y y
                     :size (or entry.size (. entry 3) size)
                     :color (or entry.color color)})
                {:x idx :y 0 :size size :color color}))))

(fn compute-extent [points]
    (var found false)
    (var min-x math.huge)
    (var max-x (- math.huge))
    (var min-y math.huge)
    (var max-y (- math.huge))
    (each [_ point (ipairs points)]
        (when point
            (set found true)
            (set min-x (math.min min-x point.x))
            (set max-x (math.max max-x point.x))
            (set min-y (math.min min-y point.y))
            (set max-y (math.max max-y point.y))))
    (when (not found)
        (set min-x 0)
        (set max-x 1)
        (set min-y 0)
        (set max-y 1))
    {:xmin min-x :xmax max-x :ymin min-y :ymax max-y})

(fn ScatterSeries [opts]
    (local options (or opts {}))
    (local series-color (ensure-glm-vec4 options.color default-color))
    (local series-size (or options.size default-size))
    (local samples (or options.points []))
    (local resolved-points (icollect [i entry (ipairs samples)]
                                      (resolve-point entry i series-size series-color)))
    (local extent (compute-extent resolved-points))

    (fn build [_self ctx]
        (assert (and ctx ctx.points) "ScatterSeries requires ctx.points")
        (local created [])
        (each [_ point (ipairs resolved-points)]
            (table.insert created
                          (ctx.points:create-point {:position (glm.vec3 0 0 0)
                                                    :color (or point.color series-color)
                                                    :size (or point.size series-size)})))

        (fn update [_self frame]
            (for [i 1 (length created)]
                (local point (. created i))
                (local sample (. resolved-points i))
                (point:set-position (frame.map-point frame sample.x sample.y))
                (point:set-color (or sample.color series-color))
                (point:set-size (or sample.size series-size))))

        (fn drop [_self]
            (each [_ point (ipairs created)]
                (point:drop)))

        {:points created
         :extent extent
         :update update
         :drop drop})

    {:build build
     :extent extent
     :points resolved-points})

ScatterSeries
