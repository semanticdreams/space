(local glm (require :glm))
(local Rectangle (require :rectangle))
(local {: Layout} (require :layout))

(fn ensure-glm-vec3 [value fallback]
    (if value
        (if (= (type value) :userdata)
            value
            (glm.vec3 (or (. value 1) 0)
                  (or (. value 2) 0)
                  (or (. value 3) 0)))
        (or fallback (glm.vec3 0 0 0))))

(fn ensure-glm-vec4 [value fallback]
    (if value
        (if (= (type value) :userdata)
            value
            (glm.vec4 (or (. value 1) 0)
                  (or (. value 2) 0)
                  (or (. value 3) 0)
                  (or (. value 4) 1)))
        (or fallback (glm.vec4 0 0 0 1))))

(fn Chart [opts]
    (local options (or opts {}))
    (local default-size (ensure-glm-vec3 options.size (glm.vec3 12 6 0)))
    (local padding (ensure-glm-vec3 options.padding (glm.vec3 0.4 0.4 0)))
    (local background-color (ensure-glm-vec4 options.background (glm.vec4 0.06 0.06 0.08 0.9)))
    (local show-background (if (= options.show-background false) false true))

    (fn build [ctx]
        (local series-builders (or options.series []))
        (local series [])
        (each [_ builder (ipairs series-builders)]
            (when (and builder builder.build)
                (table.insert series (builder:build ctx))))

        (local background (if show-background
                              ((Rectangle {:color background-color}) ctx)
                              nil))

        (local layout-children [])
        (when background
            (table.insert layout-children background.layout))
        (each [_ s (ipairs series)]
            (when s.layout
                (table.insert layout-children s.layout))
            (when s.layouts
                (each [_ child (ipairs s.layouts)]
                    (table.insert layout-children child))))

        (fn combine-extents []
            (var found false)
            (var min-x math.huge)
            (var max-x (- math.huge))
            (var min-y math.huge)
            (var max-y (- math.huge))
            (fn widen [candidate]
                (when candidate
                    (set found true)
                    (when candidate.xmin
                        (set min-x (math.min min-x candidate.xmin)))
                    (when candidate.xmax
                        (set max-x (math.max max-x candidate.xmax)))
                    (when candidate.ymin
                        (set min-y (math.min min-y candidate.ymin)))
                    (when candidate.ymax
                        (set max-y (math.max max-y candidate.ymax)))))
            (each [_ s (ipairs series)]
                (widen (or s.extent (and s.get-extent (s:get-extent)))))
            (if found
                {:xmin min-x :xmax max-x :ymin min-y :ymax max-y}
                {:xmin 0 :xmax 1 :ymin 0 :ymax 1}))

        (fn measurer [self]
            (set self.measure default-size)
            (when background
                (background.layout:measurer)))

        (fn layouter [self]
            (local extent (combine-extents))
            (local inner-size (glm.vec3 (math.max 0 (- self.size.x (* 2 padding.x)))
                                    (math.max 0 (- self.size.y (* 2 padding.y)))
                                    self.size.z))
            (local inner-origin (+ self.position (self.rotation:rotate padding)))
            (local series-depth-offset-index (+ self.depth-offset-index 1))
            (when background
                (set background.layout.position self.position)
                (set background.layout.rotation self.rotation)
                (set background.layout.size self.size)
                (set background.layout.depth-offset-index self.depth-offset-index)
                (set background.layout.clip-region self.clip-region)
                (background.layout:layouter))

            (local frame {:origin inner-origin
                          :size inner-size
                          :rotation self.rotation
                          :extent extent
                          :depth-offset series-depth-offset-index
                          :clip self.clip-region})

            (local x-range (math.max 1e-4 (- extent.xmax extent.xmin)))
            (local y-range (math.max 1e-4 (- extent.ymax extent.ymin)))
            (set frame.x-scale (if (> x-range 0) (/ inner-size.x x-range) 0))
            (set frame.y-scale (if (> y-range 0) (/ inner-size.y y-range) 0))

            (set frame.map-point
                 (fn [chart-frame x y]
                     (local lx (* (- x chart-frame.extent.xmin) chart-frame.x-scale))
                     (local ly (* (- y chart-frame.extent.ymin) chart-frame.y-scale))
                     (+ chart-frame.origin
                        (chart-frame.rotation:rotate (glm.vec3 lx ly 0)))))
            (set frame.map-y
                 (fn [chart-frame y]
                     (chart-frame.map-point chart-frame chart-frame.extent.xmin y)))
            (each [_ s (ipairs series)]
                (when s.update
                    (s:update frame))))

        (local layout (Layout {:name "chart"
                               :children layout-children
                               : measurer
                               : layouter}))

        (fn drop [self]
            (each [_ s (ipairs series)]
                (when s.drop
                    (s:drop)))
            (when background
                (background:drop))
            (self.layout:drop))

        {:layout layout
         :series series
         :drop drop}))
