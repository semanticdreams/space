(local glm (require :glm))
(local default-color (glm.vec3 0.5 0.9 1.0))

(fn ensure-color [value fallback]
    (if value
        (if (= (type value) :userdata)
            value
            (glm.vec3 (or (. value 1) 0)
                  (or (. value 2) 0)
                  (or (. value 3) 0)))
        (or fallback default-color)))

(fn resolve-point [entry idx]
    (local etype (type entry))
    (if (= etype :number)
        {:x idx :y entry}
        (if (= etype :userdata)
            {:x (or entry.x idx) :y (or entry.y entry.z entry.x 0)}
            (if (= etype :table)
                (do
                    (local x (or entry.x (. entry 1) idx))
                    (local y (or entry.y (. entry 2) 0))
                    {:x x :y y})
                {:x idx :y 0}))))

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

(fn LineSeries [opts]
    (local options (or opts {}))
    (local points (or options.points []))
    (local color (ensure-color options.color default-color))
    (local resolved-points (icollect [i entry (ipairs points)]
                                      (resolve-point entry i)))
    (local extent (compute-extent resolved-points))

    (fn build [_self ctx]
        (assert (and ctx ctx.lines) "LineSeries requires ctx.lines")
        (local strip (ctx.lines:create-line-strip {:points [(glm.vec3 0 0 0)
                                                            (glm.vec3 0 0 0)]
                                                   :color color}))
        (local self {:strip strip
                     :points resolved-points
                     :color color
                     :extent extent})

        (fn update [series frame]
            (local mapped [])
            (each [_ point (ipairs series.points)]
                (table.insert mapped (frame.map-point frame point.x point.y)))
            (when (< (length mapped) 2)
                (table.insert mapped (frame.map-point frame extent.xmax extent.ymax)))
            (series.strip:set-points mapped)
            (series.strip:set-color series.color))

        (fn drop [series]
            (when series.strip
                (series.strip:drop)))

        (set self.update update)
        (set self.drop drop)
        self)

    {:build build
     :points resolved-points
     :color color
     :extent extent})

LineSeries
