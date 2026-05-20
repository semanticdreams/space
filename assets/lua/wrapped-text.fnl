(local glm (require :glm))
(local Text (require :text))
(local {: Layout : finite-constraint? : resolve-mark-flag} (require :layout))
(local {: resolve-style
        : codepoints-from-text
        : copy-codepoints
        : wrap-codepoints-for-width} (require :text-utils))

(fn constraint-width [constraints]
  (when (finite-constraint? constraints 1)
    constraints.max.x))

(fn WrappedText [opts]
  (local options (or opts {}))
  (fn build [ctx]
    (local style (resolve-style ctx options))
    (local text-widget ((Text {:style style :codepoints []}) ctx))
    (var source-codepoints [])
    (var wrapped-codepoints [])
    (var source-version 0)
    (var cached-source-version -1)
    (var cached-width false)

    (fn update-wrapped-codepoints [max-width]
      (when (or (not (= cached-source-version source-version))
                (not (= cached-width max-width)))
        (set wrapped-codepoints
             (wrap-codepoints-for-width source-codepoints style max-width))
        (text-widget:set-codepoints wrapped-codepoints
                                    {:mark-measure-dirty? false})
        (set cached-source-version source-version)
        (set cached-width max-width)))

    (fn measure-with-width [self max-width]
      (update-wrapped-codepoints max-width)
      (text-widget.layout:measurer)
      (set self.measure text-widget.layout.measure)
      (when max-width
        (set self.measure (glm.vec3 (math.min max-width self.measure.x)
                                    self.measure.y
                                    self.measure.z)))
      self.measure)

    (fn measurer [self]
      (measure-with-width self nil))

    (fn constrained-measurer [self constraints]
      (measure-with-width self (constraint-width constraints)))

    (fn layouter [self]
      (set text-widget.layout.size self.size)
      (set text-widget.layout.position self.position)
      (set text-widget.layout.rotation self.rotation)
      (set text-widget.layout.depth-offset-index self.depth-offset-index)
      (set text-widget.layout.clip-region self.clip-region)
      (text-widget.layout:layouter))

    (local layout
      (Layout {:name (or options.name "wrapped-text")
               :children [text-widget.layout]
               :measurer measurer
               :constrained-measurer constrained-measurer
               :layouter layouter}))

    (fn set-codepoints [_self codepoint-list opts]
      (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
      (set source-codepoints (copy-codepoints codepoint-list))
      (set source-version (+ source-version 1))
      (set cached-source-version -1)
      (when mark-measure-dirty?
        (layout:mark-measure-dirty)))

    (fn set-text [_self text opts]
      (set-codepoints nil (codepoints-from-text text) opts))

    (fn get-codepoints [_self]
      source-codepoints)

    (fn get-wrapped-codepoints [_self]
      wrapped-codepoints)

    (fn drop [self]
      (self.layout:drop)
      (text-widget:drop))

    (if options.codepoints
        (set-codepoints nil options.codepoints {:mark-measure-dirty? false})
        (set-text nil (or options.text "") {:mark-measure-dirty? false}))

    {:layout layout
     :drop drop
     :style style
     :set-text set-text
     :set-codepoints set-codepoints
     :get-codepoints get-codepoints
     :get-wrapped-codepoints get-wrapped-codepoints}))

WrappedText
