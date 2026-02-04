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

(fn Text [opts]
  (fn build [ctx]
    (local style (resolve-style ctx opts))
    (local style-line-height (line-height style))
    (local font-metrics (and style style.font style.font.metadata style.font.metadata.metrics))
    (local ascender-height
      (if (and font-metrics font-metrics.ascender)
          (* style.scale font-metrics.ascender)
          style-line-height))
    (local vector (ctx:get-text-vector style.font))

    (var handle nil)
    (var codepoints [])
    (var tracked? false)
    (var glyph-cache [])
    (var renderable-count 0)

    (fn untrack-handle []
      (when (and tracked? ctx ctx.untrack-text-handle handle)
        (ctx:untrack-text-handle style.font handle)
        (set tracked? false)))

    (fn track-handle [self]
      (when (and ctx ctx.track-text-handle handle)
        (ctx:track-text-handle style.font handle self.clip-region)
        (set tracked? true)))

    (fn measurer [self]
      (measure-text self codepoints style))

    (fn rebuild-glyph-cache []
      (set renderable-count 0)
      (set glyph-cache [])
      (each [_ codepoint (ipairs codepoints)]
        (if (line-break? codepoint)
            (table.insert glyph-cache {:line-break? true :codepoint codepoint})
            (do
              (local glyph (fallback-glyph style.font codepoint))
              (set renderable-count (+ renderable-count 1))
              (table.insert glyph-cache {:line-break? false
                                         :codepoint codepoint
                                         :glyph glyph})))))

    (fn maybe-skip-line-feed [i total codepoint]
      (if (and (= codepoint carriage-return-codepoint)
               (< i total)
               (= (. codepoints (+ i 1)) newline-codepoint))
          (+ i 1)
          i))

    (fn layouter [self]
      (if (self:effective-culled?)
          (untrack-handle)
          (do
            (var x-cursor 0.0)
            (var line-index 0)
            (var glyph-index 0)
            (local total (# codepoints))
            (var i 1)
            (local measured-height (or (and self self.measure self.measure.y) style-line-height))
            (local baseline-start (math.max 0.0 (- measured-height ascender-height)))
            (while (<= i total)
              (local cache-entry (. glyph-cache i))
              (local codepoint (. codepoints i))
              (if (and cache-entry cache-entry.line-break?)
                  (do
                    (set line-index (+ line-index 1))
                    (set x-cursor 0.0)
                    (set i (maybe-skip-line-feed i total codepoint)))
                  (do
                    (local glyph (and cache-entry cache-entry.glyph))
                    (local advance (if (and glyph glyph.advance)
                                       (* glyph.advance style.scale)
                                       0))
                    (set glyph-index (+ glyph-index 1))
                    (when (and glyph.planeBounds glyph.atlasBounds)
                      (local line-offset (- baseline-start (* line-index style-line-height)))
                      (local x0 (+ x-cursor (* glyph.planeBounds.left style.scale)))
                      (local y0 (+ line-offset (* glyph.planeBounds.bottom style.scale)))
                      (local x1 (+ x-cursor (* glyph.planeBounds.right style.scale)))
                      (local y1 (+ line-offset (* glyph.planeBounds.top style.scale)))
                      (local s0 (/ glyph.atlasBounds.left style.font.metadata.atlas.width))
                      (local s1 (/ glyph.atlasBounds.right style.font.metadata.atlas.width))
                      (local t1 (/ glyph.atlasBounds.top style.font.metadata.atlas.height))
                      (local t0 (/ glyph.atlasBounds.bottom style.font.metadata.atlas.height))
                      (local base-offset (* 60 (- glyph-index 1)))
                      (fn set-vertex [index px py s t]
                        (vector.set-glm-vec3
                         vector
                         handle
                         (+ (* index 10) base-offset)
                         (+ (self.rotation:rotate (glm.vec3 px py 0.0))
                            self.position))
                        (vector.set-glm-vec2
                         vector
                         handle
                         (+ (* index 10) 3 base-offset)
                         (glm.vec2 s t))
                        (vector:set-glm-vec4 handle (+ (* index 10) 5 base-offset) style.color)
                        (vector:set-float handle (+ (* index 10) 9 base-offset) self.depth-offset-index))
                      (set-vertex 0 x0 y0 s0 t0)
                      (set-vertex 1 x1 y0 s1 t0)
                      (set-vertex 2 x1 y1 s1 t1)
                      (set-vertex 3 x0 y0 s0 t0)
                      (set-vertex 4 x1 y1 s1 t1)
                      (set-vertex 5 x0 y1 s0 t1))
                    (set x-cursor (+ x-cursor advance))))
              (set i (+ i 1)))
            (track-handle self)))
      )

    (local layout
      (Layout {:name "text"
               : measurer
               : layouter}))

    (fn refresh-handle [mark-measure-dirty?]
      (when handle
        (untrack-handle)
        (vector:delete handle))
      (set handle
           (vector:allocate (* 10 6 renderable-count)))
      (when mark-measure-dirty?
        (layout:mark-measure-dirty))
      )

    (fn set-codepoints [_self codepoint-list opts]
      (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
      (set codepoints (copy-codepoints codepoint-list))
      (rebuild-glyph-cache)
      (refresh-handle mark-measure-dirty?))

    (fn set-text [_self text opts]
      (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
      (set codepoints (codepoints-from-text text))
      (rebuild-glyph-cache)
      (refresh-handle mark-measure-dirty?))

    (fn get-codepoints [_self]
      codepoints)

    (fn drop [self]
      (self.layout:drop)
      (when handle
        (untrack-handle)
        (vector:delete handle))
      )

    (if opts.codepoints
        (set-codepoints nil opts.codepoints
                        {:mark-measure-dirty? false})
        (if opts.text
            (set-text nil opts.text {:mark-measure-dirty? false})
            (do
              (set codepoints [])
              (rebuild-glyph-cache))))

  {: layout
   : drop
   :style style
   :set-text set-text
   :set-codepoints set-codepoints
   :get-codepoints get-codepoints}))
