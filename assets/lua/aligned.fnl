(local glm (require :glm))
(local {: Layout} (require :layout))

(local axis-name-map {:x 1 :y 2 :z 3 "x" 1 "y" 2 "z" 3})
(local alignment-options {:start :start :center :center :end :end :stretch :stretch
                          "start" :start "center" :center "end" :end "stretch" :stretch})

(fn normalize-axis [axis]
  (var resolved axis)
  (when (= resolved nil)
    (set resolved 1))
  (when (= (type resolved) :string)
    (set resolved (or (. axis-name-map resolved)
                      (tonumber resolved)
                      resolved)))
  (if (and (= (type resolved) :number)
           (>= resolved 1)
           (<= resolved 3))
      resolved
      1))

(fn resolve-alignment [value]
  (or (. alignment-options value) :start))

(fn copy-glm-vec3 [v]
  (glm.vec3 v.x v.y v.z))

(fn Aligned [opts]
  (local multi-axis?
    (and (= opts.axis nil)
         (or (not (= opts.xalign nil))
             (not (= opts.yalign nil))
             (not (= opts.zalign nil))
             (not (= opts.align nil)))))
  (local axis (normalize-axis opts.axis))
  (local alignment (resolve-alignment opts.alignment))
  (local alignments
    (if multi-axis?
        {1 (resolve-alignment (or opts.xalign opts.align))
         2 (resolve-alignment (or opts.yalign opts.align))
         3 (resolve-alignment (or opts.zalign opts.align))}
        nil))
  (fn build [ctx]
    (local child (opts.child ctx))

    (fn measurer [self]
      (local child-layout child.layout)
      (child-layout:measurer)
      (set self.measure child-layout.measure))

    (fn layouter [self]
      (local child-layout child.layout)
      (set child-layout.rotation self.rotation)
      (if multi-axis?
          (do
            (local child-size
              (glm.vec3
                (if (= (. alignments 1) :stretch)
                    self.size.x
                    child-layout.measure.x)
                (if (= (. alignments 2) :stretch)
                    self.size.y
                    child-layout.measure.y)
                (if (= (. alignments 3) :stretch)
                    self.size.z
                    child-layout.measure.z)))
            (set child-layout.size child-size)
            (local offset (glm.vec3 0))
            (each [_ idx (ipairs [1 2 3])]
              (local align (. alignments idx))
              (local delta (- (. self.size idx) (. child-size idx)))
              (match align
                :center (set (. offset idx) (/ delta 2))
                :end (set (. offset idx) delta)
                _ nil))
            (set child-layout.position (+ self.position (self.rotation:rotate offset)))
            (set child-layout.depth-offset-index self.depth-offset-index)
            (set child-layout.clip-region self.clip-region)
            (child-layout:layouter))
          (do
            (local child-size (copy-glm-vec3 self.size))
            (when (not (= alignment :stretch))
              (set (. child-size axis) (. child-layout.measure axis)))
            (set child-layout.size child-size)
            (local delta (- (. self.size axis) (. child-size axis)))
            (local offset (glm.vec3 0))
            (match alignment
              :center (set (. offset axis) (/ delta 2))
              :end (set (. offset axis) delta)
              _ nil)
            (set child-layout.position (+ self.position (self.rotation:rotate offset)))
            (set child-layout.depth-offset-index self.depth-offset-index)
            (set child-layout.clip-region self.clip-region)
            (child-layout:layouter))))

    (local layout
      (Layout {:name "aligned"
               : measurer : layouter
               :children [child.layout]}))

    (fn drop [self]
      (self.layout:drop)
      (child:drop))

    {: child : layout : drop}))

Aligned
