(local glm (require :glm))
(import-macros {: incf : maxf} :macros)

(local {: Layout : finite-constraint?} (require :layout))

(local axis-labels {1 "x" 2 "y" 3 "z"})
(local axis-name-map {:x 1 :y 2 :z 3 "x" 1 "y" 2 "z" 3})

(fn normalize-axis [axis]
  (var resolved axis)
  (when (= (type resolved) :string)
    (set resolved (or (. axis-name-map resolved)
                      (tonumber resolved)
                      resolved)))
  (when (= axis nil)
    (set resolved 1))
  (when (and (= (type resolved) :number)
             (< resolved 1))
    (set resolved (+ resolved 1)))
  (if (and (= (type resolved) :number)
           (>= resolved 1)
           (<= resolved 3))
      resolved
      1))

(fn spacing-component [opts idx]
  (local label (. axis-labels idx))
  (local key (.. label "spacing"))
  (local override (. opts key))
  (if (not (= override nil))
      override
      (let [s opts.spacing
            stype (type s)]
        (if (= stype "table")
            (or (. s label) (. s idx) 0.5)
            (if (= stype "userdata")
                (. s idx)
                (if (= stype "number")
                    s
                    0.5))))))

(local alignment-options {:start :start :center :center :end :end :largest :largest :stretch :stretch
                          "start" :start "center" :center "end" :end "largest" :largest "stretch" :stretch})

(fn resolve-alignment [value fallback]
  (or (. alignment-options value)
      (. alignment-options fallback)
      :start))

(fn FlexChild [widget flex]
  {: widget :flex (or flex 0)})

(fn Flex [opts]
  (fn build [ctx]
    (local e {:children
              (icollect [_ x (ipairs (or opts.children []))]
                        {:flex (or x.flex 0)
                         :element (x.widget ctx)})
              })

    (local axis (normalize-axis opts.axis))
    (local spacing (glm.vec3
                     (spacing-component opts 1)
                     (spacing-component opts 2)
                     (spacing-component opts 3)))
    (local cross-axes (icollect [_ x (ipairs [1 2 3])] (if (not (= x axis)) x)))
    (local reverse (if
                     (not (= opts.reverse nil)) opts.reverse
                     (= axis 2) true
                     false))
    (local alignments
      {1 (resolve-alignment opts.xalign opts.align)
       2 (resolve-alignment opts.yalign opts.align)
       3 (resolve-alignment opts.zalign opts.align)})

    (fn measure-children [self constraints]
      (set self.measure (glm.vec3 0))
      (each [i child (ipairs self.children)]
        (if constraints
            (child:measure-constrained constraints)
            (child:measurer))
        (incf (. self.measure axis) (. child.measure axis))
        (each [_ a (ipairs cross-axes)]
          (maxf (. self.measure a) (. child.measure a))
          )
        )
      (incf (. self.measure axis)
            (* (. spacing axis)
               (math.max 0 (- (length self.children) 1))))
      )

    (fn measurer [self]
      (measure-children self nil))

    (fn constrained-measurer [self constraints]
      (if (and constraints (finite-constraint? constraints axis))
          ;; Flex-aware measurement: fixed children are measured first to
          ;; determine the remaining axis space for flex children.
          (let [axis-spacing (. spacing axis)
                total-spacing (* axis-spacing (math.max 0 (- (length self.children) 1)))
                constraint-max-axis (. constraints.max axis)]
            ;; Measure fixed children at full constraint
            (each [i child (ipairs self.children)]
              (let [metadata (. e.children i)]
                (when (= metadata.flex 0)
                  (child:measure-constrained constraints))))
            ;; Sum axis space consumed by fixed children
            (var fixed-sum 0.0)
            (each [i child (ipairs self.children)]
              (let [metadata (. e.children i)]
                (when (= metadata.flex 0)
                  (set fixed-sum (+ fixed-sum (. child.measure axis))))))
            ;; Remaining axis space shared proportionally by flex children
            (local remaining (math.max 0 (- constraint-max-axis fixed-sum total-spacing)))
            (local flex-sum (accumulate [sum 0 _ x (ipairs e.children)] (+ sum x.flex)))
            (each [i child (ipairs self.children)]
              (let [metadata (. e.children i)]
                (when (> metadata.flex 0)
                  (local share (if (> flex-sum 0)
                                   (/ (* remaining metadata.flex) flex-sum)
                                   0))
                  (local child-constraints
                    (let [m (glm.vec3 (or (. constraints.max 1) 0)
                                      (or (. constraints.max 2) 0)
                                      (or (. constraints.max 3) 0))]
                      (set (. m axis) share)
                      {:max m}))
                  (child:measure-constrained child-constraints))))
            ;; Sum all axis measures
            (set self.measure (glm.vec3 0))
            (each [i child (ipairs self.children)]
              (incf (. self.measure axis) (. child.measure axis))
              (each [_ a (ipairs cross-axes)]
                (maxf (. self.measure a) (. child.measure a))))
            (incf (. self.measure axis) total-spacing))
          (measure-children self constraints)))

    (fn layouter [self]
      (local flex-sum (accumulate [sum 0 _ x (ipairs e.children)] (+ sum x.flex)))
      (local child-count (length self.children))
      (local axis-spacing (. spacing axis))
      (local total-axis-spacing (* axis-spacing (math.max 0 (- child-count 1))))
      (var remaining (- (. self.size axis) total-axis-spacing))
      (each [i child (ipairs self.children)]
        (local metadata (. e.children i))
        (if (= metadata.flex 0)
            (set (. child.size axis) (. child.measure axis))
            (set (. child.size axis) 0))
        (set remaining (- remaining (. child.size axis))))
      (when (> flex-sum 0)
        (var flex-base (/ remaining flex-sum))
        (each [i child (ipairs self.children)]
          (local metadata (. e.children i))
          (when (> metadata.flex 0)
            (set flex-base (math.max
                             flex-base
                             (/ (. child.measure axis) metadata.flex)))))
        (each [i child (ipairs self.children)]
          (local metadata (. e.children i))
          (when (> metadata.flex 0)
            (local candidate-size (* metadata.flex flex-base))
            (set (. child.size axis) candidate-size)
            (set remaining (- remaining candidate-size)))))

      (var content-size 0)
      (each [_ child (ipairs self.children)]
        (incf content-size (. child.size axis)))
      (local available-size (math.max 0 (- (. self.size axis) total-axis-spacing)))
      (when (> content-size available-size)
        (local overfull (- content-size available-size))
        (var shrinkable-size 0)
        (each [i child (ipairs self.children)]
          (local metadata (. e.children i))
          (when (> metadata.flex 0)
            (incf shrinkable-size (. child.size axis))))
        (when (> shrinkable-size 0)
          (local shrink-factor
            (math.max 0 (/ (- shrinkable-size overfull) shrinkable-size)))
          (each [i child (ipairs self.children)]
            (local metadata (. e.children i))
            (when (> metadata.flex 0)
              (set (. child.size axis) (* (. child.size axis) shrink-factor)))))
        )

      (var offset 0)
      (each [i child (ipairs self.children)]
        (each [_ a (ipairs cross-axes)]
          (local align (. alignments a))
          (if (= align :stretch)
              (set (. child.size a) (. self.size a))
              (if (= align :largest)
                  (set (. child.size a) (math.min (. self.measure a) (. self.size a)))
                  (set (. child.size a) (. child.measure a)))))
        (set child.rotation self.rotation)
        (local child-position (glm.vec3 0))
        (if reverse
            (set (. child-position axis)
                 (- (. self.size axis) offset (. child.size axis)))
            (set (. child-position axis) offset))
        (each [_ a (ipairs cross-axes)]
          (local align (. alignments a))
          (if (= align :center)
              (incf (. child-position a)
                    (/ (- (. self.size a) (. child.size a)) 2))
              (when (= align :end)
                (incf (. child-position a)
                      (- (. self.size a) (. child.size a))))))
        (set child.position (+ self.position (self.rotation:rotate child-position)))
        (set child.depth-offset-index self.depth-offset-index)
        (set child.clip-region self.clip-region)
        (child:layouter)
        (incf offset (. child.size axis) axis-spacing))
      )

    (set e.layout
         (Layout
           {:name "flex"
            :children (icollect [_ v (ipairs e.children)]
                                v.element.layout)
            : measurer :constrained-measurer constrained-measurer
            : layouter}))

    (set e.drop (fn [self]
                  (e.layout:drop)
                  (each [_ child (ipairs e.children)]
                    (child.element:drop))))

    e)
  )
  ;(Widget {}))

{: Flex : FlexChild}
