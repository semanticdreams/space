(import-macros {: incf : maxf} :macros)

(local Widget (require :widget))
(local {: Layout} (require :layout))

(fn FlexChild [widget flex]
  {: widget :flex (or flex 0)})

(fn Flex [opts]
  (fn build [ctx]
    (local e {:children
              (icollect [_ x (ipairs (or opts.children []))]
                        {:flex (or x.flex 0)
                         :element (x.widget ctx)})
              })

    (local axis (or opts.axis 1))
    (local spacing (or opts.spacing 0.5))
    (local cross-axes (icollect [_ x (ipairs [1 2 3])] (if (not (= x axis)) x)))
    (local reverse (if
                     (not (= opts.reverse nil)) opts.reverse
                     (= axis 2) true
                     false))

    (fn measurer [self]
      (set self.measure (vec3 0))
      (each [i child (ipairs self.children)]
        (child:measurer)
        (incf (. self.measure axis) (. child.measure axis))
        (each [_ a (ipairs cross-axes)]
          (maxf (. self.measure a) (. child.measure a))
          )
        )
      (incf (. self.measure axis) (* spacing (- (length self.children) 1)))
      )

    (fn layouter [self]
      (local flex-sum (accumulate [sum 0 _ x (ipairs e.children)] (+ sum x.flex)))
      (local offset (vec3 0))
      (each [i child (ipairs self.children)]
        (set child.size child.measure)
        (set child.position (+ self.position offset))
        (child:layouter)
        (incf (. offset axis) (. child.size axis) spacing)
        )
      )

    (set e.layout
         (Layout
           {:name "flex"
            :children (icollect [_ v (ipairs e.children)]
                                v.element.layout)
            : measurer
            : layouter}))

    (set e.drop (fn [self]
                  (e.layout:drop)
                  (each [_ child (ipairs e.children)]
                    (child.element:drop))))

    e)
  )
  ;(Widget {}))

{: Flex : FlexChild}
