(local glm (require :glm))
(local {: Layout} (require :layout))

(fn resolve-spacing [opts key default]
  (local explicit (. opts key))
  (if (not (= explicit nil))
      explicit
      (let [spacing opts.spacing
            stype (type spacing)
            axis (if (= key :xspacing) 1 2)]
        (if (= stype :table)
            (or (. spacing key)
                (. spacing axis)
                (. spacing (if (= axis 1) :x :y))
                default
                0.5)
            (if (= stype :userdata)
                (. spacing axis)
                (if (= stype :number)
                    spacing
                    (or default 0.5)))))))

(fn resolve-positive-int [value fallback]
  (local number (tonumber value))
  (if (and number (> number 0))
      (math.floor number)
      fallback))

(local alignment-options {:start :start :center :center :end :end :stretch :stretch
                          "start" :start "center" :center "end" :end "stretch" :stretch})

(fn resolve-alignment [value fallback]
  (or (. alignment-options value) fallback))

(local axis-mode-options {:even :even :tight :tight
                          "even" :even "tight" :tight})

(fn resolve-axis-mode [value fallback]
  (or (. axis-mode-options value) fallback))

(fn sum-list [items]
  (var total 0)
  (each [_ value (ipairs items)]
    (set total (+ total (or value 0))))
  total)

(fn Grid [opts]
  (fn build [ctx]
    (local options (or opts {}))
    (local metadata-children
      (icollect [_ child (ipairs (or options.children []))]
        (do
          (local element (child.widget ctx))
          (local align-x (resolve-alignment child.align-x nil))
          (local align-y (resolve-alignment child.align-y nil))
          {:element element
           :align-x align-x
           :align-y align-y})))

    (local rows (resolve-positive-int options.rows 1))
    (local min-columns (resolve-positive-int options.columns 1))
    (local row-specs (or options.row-specs options.rows-specs))
    (local column-specs (or options.column-specs options.columns-specs))
    (local align-x (resolve-alignment options.align-x :stretch))
    (local align-y (resolve-alignment options.align-y :stretch))
    (local xmode (resolve-axis-mode options.xmode :even))
    (local ymode (resolve-axis-mode options.ymode :even))
    (local xspacing (resolve-spacing options :xspacing 0.5))
    (local yspacing (resolve-spacing options :yspacing 0.5))

    (fn effective-rows []
      (local spec-count (length (or row-specs [])))
      (math.max rows spec-count))

    (fn effective-columns [child-count]
      (local row-count (effective-rows))
      (local spec-count (length (or column-specs [])))
      (local required (math.ceil (/ child-count row-count)))
      (math.max min-columns spec-count required))

    (fn column-spec [index]
      (and column-specs (. column-specs index)))

    (fn row-spec [index]
      (and row-specs (. row-specs index)))

    (fn resolve-spec-size [spec fallback]
      (if (and spec (not (= spec.size nil)))
          spec.size
          fallback))

    (fn resolve-spec-flex [spec]
      (math.max 0 (or (and spec spec.flex) 0)))

    (fn compute-max-sizes [child-count column-count row-count]
      (local column-sizes [])
      (local row-sizes [])
      (for [i 1 column-count]
        (table.insert column-sizes 0))
      (for [i 1 row-count]
        (table.insert row-sizes 0))
      (each [idx child (ipairs metadata-children)]
        (child.element.layout:measurer)
        (local measure child.element.layout.measure)
        (local zero-based (- idx 1))
        (local row (math.fmod zero-based row-count))
        (local column (math.floor (/ zero-based row-count)))
        (local col-index (+ column 1))
        (local row-index (+ row 1))
        (when measure
          (when (> measure.x (. column-sizes col-index))
            (set (. column-sizes col-index) measure.x))
          (when (> measure.y (. row-sizes row-index))
            (set (. row-sizes row-index) measure.y))))
      (each [i _ (ipairs column-sizes)]
        (local spec (column-spec i))
        (set (. column-sizes i) (resolve-spec-size spec (. column-sizes i))))
      (each [i _ (ipairs row-sizes)]
        (local spec (row-spec i))
        (set (. row-sizes i) (resolve-spec-size spec (. row-sizes i))))
      {:columns column-sizes
       :rows row-sizes})

    (fn compute-even-sizes [sizes]
      (var max-value 0)
      (each [_ value (ipairs sizes)]
        (when (> value max-value)
          (set max-value value)))
      (icollect [_ i (ipairs sizes)] max-value))

    (fn compute-flex-sizes [sizes specs available]
      (local total-base (sum-list sizes))
      (local extra (math.max 0 (- available total-base)))
      (local flex-total
        (do
          (var sum 0)
          (each [i _ (ipairs sizes)]
            (set sum (+ sum (resolve-spec-flex (specs i)))))
          sum))
      (if (> flex-total 0)
          (icollect [i size (ipairs sizes)]
            (do
              (local flex (resolve-spec-flex (specs i)))
              (+ size (* extra (/ flex flex-total)))))
          sizes))

    (fn measurer [self]
      (var max-depth 0)
      (local child-count (length metadata-children))
      (local row-count (effective-rows))
      (local column-count (effective-columns child-count))
      (local sizes (compute-max-sizes child-count column-count row-count))
      (local column-sizes
        (if (= xmode :even)
            (compute-even-sizes sizes.columns)
            sizes.columns))
      (local row-sizes
        (if (= ymode :even)
            (compute-even-sizes sizes.rows)
            sizes.rows))
      (each [_ child (ipairs metadata-children)]
        (local measure child.element.layout.measure)
        (when (and measure (> measure.z max-depth))
          (set max-depth measure.z)))
      (local width (+ (sum-list column-sizes)
                      (* (math.max 0 (- column-count 1)) xspacing)))
      (local height (+ (sum-list row-sizes)
                       (* (math.max 0 (- row-count 1)) yspacing)))
      (set self.measure (glm.vec3 width height max-depth)))

    (fn layouter [self]
      (local child-count (length metadata-children))
      (local row-count (effective-rows))
      (local column-count (effective-columns child-count))
      (local total-x-spacing (* (math.max 0 (- column-count 1)) xspacing))
      (local total-y-spacing (* (math.max 0 (- row-count 1)) yspacing))
      (local available-width (math.max 0 (- self.size.x total-x-spacing)))
      (local available-height (math.max 0 (- self.size.y total-y-spacing)))
      (local sizes (compute-max-sizes child-count column-count row-count))
      (local column-sizes
        (if (= xmode :even)
            (do
              (local even (if (> column-count 0)
                              (/ available-width column-count)
                              0))
              (local entries [])
              (for [i 1 column-count]
                (table.insert entries even))
              entries)
            (compute-flex-sizes sizes.columns column-spec available-width)))
      (local row-sizes
        (if (= ymode :even)
            (do
              (local even (if (> row-count 0)
                              (/ available-height row-count)
                              0))
              (local entries [])
              (for [i 1 row-count]
                (table.insert entries even))
              entries)
            (compute-flex-sizes sizes.rows row-spec available-height)))
      (local column-offsets [])
      (local row-offsets [])
      (var x-offset 0)
      (each [idx size (ipairs column-sizes)]
        (table.insert column-offsets x-offset)
        (set x-offset (+ x-offset size xspacing)))
      (var consumed-height 0)
      (each [idx size (ipairs row-sizes)]
        (set consumed-height (+ consumed-height size))
        (table.insert row-offsets (- self.size.y consumed-height (* (- idx 1) yspacing))))
      (local base-position self.position)
      (each [idx child (ipairs metadata-children)]
        (local zero-based (- idx 1))
        (local row (math.fmod zero-based row-count))
        (local column (math.floor (/ zero-based row-count)))
        (local col-index (+ column 1))
        (local row-index (+ row 1))
        (local cell-width (. column-sizes col-index))
        (local cell-height (. row-sizes row-index))
        (local cell-x (. column-offsets col-index))
        (local cell-y (. row-offsets row-index))
        (local position-offset (glm.vec3 cell-x cell-y 0))
        (local desired-align-x (resolve-alignment child.align-x align-x))
        (local desired-align-y (resolve-alignment child.align-y align-y))
        (local measure child.element.layout.measure)
        (local child-width
          (if (= desired-align-x :stretch)
              cell-width
              (math.min cell-width (or (and measure measure.x) cell-width))))
        (local child-height
          (if (= desired-align-y :stretch)
              cell-height
              (math.min cell-height (or (and measure measure.y) cell-height))))
        (local x-adjust
          (if (= desired-align-x :center)
              (/ (- cell-width child-width) 2)
              (if (= desired-align-x :end)
                  (- cell-width child-width)
                  0)))
        (local y-adjust
          (if (= desired-align-y :center)
              (/ (- cell-height child-height) 2)
              (if (= desired-align-y :end)
                  (- cell-height child-height)
                  0)))
        (local layout child.element.layout)
        (set layout.size (glm.vec3 child-width child-height (or (. layout.measure 3) 0)))
        (set layout.position (+ base-position (self.rotation:rotate position-offset)))
        (set layout.rotation self.rotation)
        (set layout.depth-offset-index self.depth-offset-index)
        (set layout.clip-region self.clip-region)
        (when (or (> x-adjust 0) (> y-adjust 0))
          (set layout.position (+ layout.position (self.rotation:rotate (glm.vec3 x-adjust y-adjust 0)))))
        (layout:layouter)))

    (local layout
      (Layout {:name "grid"
               :children (icollect [_ v (ipairs metadata-children)]
                                   v.element.layout)
               :measurer measurer
               :layouter layouter}))

    (local grid
      {:children metadata-children
       :layout layout})

    (set grid.drop
         (fn [_self]
           (grid.layout:drop)
           (each [_ child (ipairs grid.children)]
             (child.element:drop))))

    grid))

{:Grid Grid}
