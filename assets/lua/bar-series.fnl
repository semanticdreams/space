(local glm (require :glm))
(local Rectangle (require :rectangle))

(fn ensure-glm-vec4 [value fallback]
  (if value
    (if (= (type value) :userdata)
      value
      (glm.vec4 (or (. value 1) 0)
            (or (. value 2) 0)
            (or (. value 3) 0)
            (or (. value 4) 1)))
    (or fallback (glm.vec4 0.3 0.7 1.0 0.9))))

(fn resolve-point [entry idx]
  (local etype (type entry))
  (if (= etype :number)
    {:x idx :y entry}
    (if (= etype :userdata)
      {:x (or entry.x idx) :y (or entry.y entry.z entry.x 0) :color nil}
      (if (= etype :table)
        (do
          (local x (or entry.x (. entry 1) idx))
          (local y (or entry.y (. entry 2) 0))
          {:x x :y y :color entry.color})
        {:x idx :y 0}))))

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

(fn BarSeries [opts]
  (local options (or opts {}))
  (local baseline (or options.baseline 0))
  (local width-scale (or options.width-scale 0.7))
  (local default-color (ensure-glm-vec4 options.color))
  (local default-set {:data (or options.data []) :color default-color})
  (local configured-sets (or options.bar-sets []))
  (local raw-sets (if (> (length configured-sets) 0) configured-sets [default-set]))

  (local resolved-sets [])
  (each [_ set-opts (ipairs raw-sets)]
    (local set-color (ensure-glm-vec4 set-opts.color default-color))
    (local samples (or set-opts.data []))
    (local points (icollect [i entry (ipairs samples)]
                            (resolve-point entry i)))
    (table.insert resolved-sets {:points points :color set-color}))

  (var column-count 0)
  (each [_ bar-set (ipairs resolved-sets)]
    (set column-count (math.max column-count (length bar-set.points))))

  (local column-x [])
  (for [i 1 column-count]
    (var x nil)
    (each [_ bar-set (ipairs resolved-sets)]
      (when (and (not x) (. bar-set.points i))
        (set x (. (. bar-set.points i) :x))))
    (table.insert column-x (or x i)))

  (local extent (compute-extent resolved-sets baseline))

  (fn build [_self ctx]
    (local bar-sets [])
    (local bars [])
    (each [_ resolved-set (ipairs resolved-sets)]
      (local set-bars [])
      (each [_ _ (ipairs resolved-set.points)]
        (local bar ((Rectangle {:color resolved-set.color}) ctx))
        (table.insert set-bars bar)
        (table.insert bars bar))
      (table.insert bar-sets {:bars set-bars
                              :points resolved-set.points
                              :color resolved-set.color}))

    (local layouts (icollect [_ bar (ipairs bars)] bar.layout))

    (fn update [self frame]
      (when (> column-count 0)
        (local set-count (length bar-sets))
        (local slot (if (> frame.size.x 0)
                      (/ frame.size.x column-count)
                      0))
        (local group-width (math.max 0 (* slot width-scale)))
        (local bar-width (if (> set-count 0)
                           (/ group-width set-count)
                           group-width))
        (local y0 (* (- baseline extent.ymin) frame.y-scale))
        (for [column 1 column-count]
          (local center-x (* (- (. column-x column) extent.xmin) frame.x-scale))
          (local start-x (- center-x (/ group-width 2)))
          (for [set-idx 1 set-count]
            (local bar-set (. bar-sets set-idx))
            (local point (. bar-set.points column))
            (local bar (. bar-set.bars column))
            (when (and point bar)
              (var height (* (- point.y baseline) frame.y-scale))
              (var start-y y0)
              (when (< height 0)
                (set start-y (+ y0 height))
                (set height (- height)))
              (set bar.color (or point.color bar-set.color default-color))
              (set bar.layout.size (glm.vec3 bar-width height 0))
              (local local-pos (glm.vec3 (+ start-x (* bar-width (- set-idx 1)))
                                     start-y
                                     0))
              (set bar.layout.position
                   (+ frame.origin (frame.rotation:rotate local-pos)))
              (set bar.layout.rotation frame.rotation)
              (set bar.layout.depth-offset-index frame.depth-offset)
              (set bar.layout.clip-region frame.clip)
              (bar.layout:layouter))))))

    (fn drop [_self]
      (each [_ bar (ipairs bars)]
        (bar:drop)))

    {:bars bars
     :bar-sets bar-sets
     :layouts layouts
     :column-count column-count
     :extent extent
     :update update
     :drop drop})

  {:build build
   :extent extent
   :sets resolved-sets
   :baseline baseline})

BarSeries
