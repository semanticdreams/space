(local glm (require :glm))
(local {: Layout : resolve-mark-flag} (require :layout))
(local {: resolve-style
        : fallback-glyph
        : measure-text
        : codepoints-from-text
        : copy-codepoints
        : line-height
        : line-break?
        : newline-codepoint
        : carriage-return-codepoint} (require :text-utils))

(fn clamp [value min-value max-value]
  (math.max min-value (math.min max-value value)))

(fn axis-angle-from-glm-quat [rotation]
  (local normalized (rotation:normalize))
  (local w (clamp normalized.w -1 1))
  (local angle (* 2 (math.acos w)))
  (local s (math.sqrt (math.max 0 (- 1 (* w w)))))
  (if (< s 1e-6)
      (values angle (glm.vec3 1 0 0))
      (values angle (glm.vec3 (/ normalized.x s)
                              (/ normalized.y s)
                              (/ normalized.z s)))))

(fn text-model-matrix [position rotation baseline-shift]
  (local translate (glm.translate (glm.mat4 1) (or position (glm.vec3 0 0 0))))
  (local safe-rotation (or rotation (glm.quat 1 0 0 0)))
  (local (angle axis) (axis-angle-from-glm-quat safe-rotation))
  (local rotate (glm.rotate (glm.mat4 1) angle axis))
  (local baseline (glm.translate (glm.mat4 1) (glm.vec3 0 (or baseline-shift 0) 0)))
  (* translate (* rotate baseline)))

(fn Text [opts]
  (fn build [ctx]
    (local style (resolve-style ctx opts))
    (local style-line-height (line-height style))
    (local font-metrics (and style style.font style.font.metadata style.font.metadata.metrics))
    (local ascender-height
      (if (and font-metrics font-metrics.ascender)
          (* style.scale font-metrics.ascender)
          style-line-height))

    (assert (and ctx ctx.get-text-ssbo-batcher)
            "Text requires ctx.get-text-ssbo-batcher")
    (local ssbo-batcher (ctx:get-text-ssbo-batcher))
    (assert ssbo-batcher "Text requires a text ssbo batcher")

    (local ssbo-key {})
    (var codepoints [])
    (var content-dirty? true)
    (var renderable-count 0)
    (var text-present? false)

    (fn remove-text []
      (set text-present? false)
      (ssbo-batcher:remove-text ssbo-key))

    (fn measurer [self]
      (measure-text self codepoints style))

    (fn rebuild-glyph-cache []
      (set renderable-count 0)
      (each [_ codepoint (ipairs codepoints)]
        (when (not (line-break? codepoint))
          (local glyph (fallback-glyph style.font codepoint))
          (when glyph
            (set renderable-count (+ renderable-count 1))))))

    (fn layouter [self]
      (if (self:effective-culled?)
          (remove-text)
          (if (= renderable-count 0)
              (remove-text)
              (do
                (local measured-height (or (and self self.measure self.measure.y) style-line-height))
                (local model
                  (text-model-matrix self.position
                                     self.rotation
                                     measured-height))
                (local text-depth-index (+ (or self.depth-offset-index 0) 1))
                (local transform-opts {:group-matrix model
                                       :clip self.clip-region
                                       :depth-offset-index text-depth-index})
                (if (or content-dirty? (not text-present?))
                    (do
                      (ssbo-batcher:upsert-text ssbo-key
                                                {:font style.font
                                                 :scale style.scale
                                                 :line-height style.line-height
                                                 :color style.color
                                                 :codepoints codepoints
                                                 :group-matrix model
                                                 :clip self.clip-region
                                                 :depth-offset-index text-depth-index})
                      (set text-present? true)
                      (set content-dirty? false))
                    (ssbo-batcher:update-text-transform ssbo-key transform-opts))))))

    (local layout
      (Layout {:name "text"
               :measurer measurer
               :layouter layouter}))

    (fn set-codepoints [_self codepoint-list opts]
      (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
      (set codepoints (copy-codepoints codepoint-list))
      (set content-dirty? true)
      (rebuild-glyph-cache)
      (when mark-measure-dirty?
        (layout:mark-measure-dirty)))

    (fn set-text [_self text opts]
      (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
      (set codepoints (codepoints-from-text text))
      (set content-dirty? true)
      (rebuild-glyph-cache)
      (when mark-measure-dirty?
        (layout:mark-measure-dirty)))

    (fn get-codepoints [_self]
      codepoints)

    (fn drop [self]
      (self.layout:drop)
      (remove-text))

    (if opts.codepoints
        (set-codepoints nil opts.codepoints
                        {:mark-measure-dirty? false})
        (if opts.text
            (set-text nil opts.text {:mark-measure-dirty? false})
            (do
              (set codepoints [])
              (set content-dirty? true)
              (rebuild-glyph-cache))))

    {:layout layout
     :drop drop
     :style style
     :set-text set-text
     :set-codepoints set-codepoints
     :get-codepoints get-codepoints}))

Text
