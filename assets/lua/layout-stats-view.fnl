(local glm (require :glm))
(local Chart (require :chart))
(local BarSeries (require :bar-series))

(local default-max-frames 10)

(fn fill-zeroes [count]
    (local entries [])
    (for [i 1 count]
        (table.insert entries 0))
    entries)

(fn compute-extent [bar-sets baseline]
    (var found false)
    (var min-x math.huge)
    (var max-x (- math.huge))
    (var min-y math.huge)
    (var max-y (- math.huge))
    (each [_ bar-set (ipairs bar-sets)]
        (each [_ point (ipairs bar-set.points)]
            (when point
                (set found true)
                (set min-x (math.min min-x point.x))
                (set max-x (math.max max-x point.x))
                (set min-y (math.min min-y point.y))
                (set max-y (math.max max-y point.y)))))
    (when (not found)
        (set min-x 0)
        (set max-x 1)
        (set min-y (math.min 0 baseline))
        (set max-y (math.max 1 baseline)))
    (local pad 0.5)
    {:xmin (- min-x pad)
     :xmax (+ max-x pad)
     :ymin (math.min min-y baseline)
     :ymax (math.max max-y baseline)})

(fn LayoutStatsView [opts]
    (local options (or opts {}))
    (local baseline (or options.baseline 0))
    (local max-frames (or options.max-frames default-max-frames))
    (local chart-size (or options.size (glm.vec3 11 6.5 0)))
    (local chart-padding (or options.padding (glm.vec3 0.6 0.5 0)))
    (var layout-root options.layout-root)
    (local measure-color (or options.measure-color (glm.vec4 0.32 0.78 1.0 0.92)))
    (local layout-color (or options.layout-color (glm.vec4 1.0 0.68 0.36 0.9)))
    (local background (or options.background (glm.vec4 0.07 0.07 0.1 0.94)))

    (fn build [ctx]
        (when (and (not layout-root) ctx)
            (set layout-root ctx.layout-root))
        (local measure-data (fill-zeroes max-frames))
        (local layout-data (fill-zeroes max-frames))
        (local bar-series-builder
               (BarSeries {:baseline baseline
                           :bar-sets [{:data measure-data :color measure-color}
                                      {:data layout-data :color layout-color}]}))
        (local chart-builder
               (Chart {:size chart-size
                       :padding chart-padding
                       :background background
                       :series [bar-series-builder]}))
        (local chart (chart-builder ctx))
        (local bar-series (. chart.series 1))
        (local bar-sets (and bar-series bar-series.bar-sets))
        (local measure-set (and bar-sets (. bar-sets 1)))
        (local layout-set (and bar-sets (. bar-sets 2)))
        (local measure-points (and measure-set measure-set.points))
        (local layout-points (and layout-set layout-set.points))
        (var update-handler nil)

        (fn mutate-extent []
            (when (and bar-series bar-sets)
                (local current (or bar-series.extent {}))
                (local next (compute-extent bar-sets baseline))
                (set current.xmin next.xmin)
                (set current.xmax next.xmax)
                (set current.ymin next.ymin)
                (set current.ymax next.ymax)
                (set bar-series.extent current)))

        (fn apply-records [_delta]
            (var changed false)
            (local records (or (and layout-root layout-root.stats layout-root.stats.records) []))
            (for [i 1 max-frames]
                (local record (. records i))
                (local measure (or (and record record.measure-dirt) 0))
                (local layout-count (or (and record record.layout-dirt) 0))
                (local measure-point (and measure-points (. measure-points i)))
                (local layout-point (and layout-points (. layout-points i)))
                (when (and measure-point (not (= measure-point.y measure)))
                    (set measure-point.y measure)
                    (set changed true))
                (when (and layout-point (not (= layout-point.y layout-count)))
                    (set layout-point.y layout-count)
                    (set changed true)))
            (when changed
                (mutate-extent)
                (when (and chart chart.layout chart.layout.layouter)
                    (chart.layout:layouter)))
            changed)

        (fn connect-updates []
            (when (and app.engine app.engine.events app.engine.events.updated (not update-handler))
                (set update-handler (app.engine.events.updated:connect apply-records))))

        (fn disconnect-updates []
            (when (and app.engine app.engine.events app.engine.events.updated update-handler)
                (app.engine.events.updated:disconnect update-handler true)
                (set update-handler nil)))

        (apply-records nil)
        (connect-updates)

        (local base-drop chart.drop)
        (set chart.refresh apply-records)
        (set chart.drop (fn [self]
                          (disconnect-updates)
                          (when base-drop
                              (base-drop self))
                          (set chart.series nil)
                          (set chart.layout nil)))
        chart)
    )

LayoutStatsView
