(local glm (require :glm))
(local ClipUtils (require :clip-utils))
(local {: fallback-glyph
        : line-height} (require :text-utils))
(local underline (require :terminal-underline))
(local QuadBatcher (require :next-app/quad-batcher))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))

(local default-blink-period 0.6)
(local glyph-stride 12)
(local zero-clip-matrix (glm.mat4 0))
(local blank-cell {:codepoint 32
                   :fg-r 255 :fg-g 255 :fg-b 255
                   :bg-r 0 :bg-g 0 :bg-b 0
                   :bold false :underline false :italic false :reverse false})

(fn to-color [r g b]
  (glm.vec4 (/ r 255.0) (/ g 255.0) (/ b 255.0) 1.0))

(fn clamp-color [value]
  (math.min 1.0 (math.max 0.0 value)))

(fn palette-key [r g b]
  (.. r ":" g ":" b))

(fn apply-bold [color]
  (glm.vec4 (clamp-color (+ color.x 0.1))
            (clamp-color (+ color.y 0.1))
            (clamp-color (+ color.z 0.1))
            color.w))

(fn cell-index [row col cols]
  (+ col (* row cols)))

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

(fn model-matrix [position rotation]
  (local translate (glm.translate (glm.mat4 1) (or position (glm.vec3 0 0 0))))
  (local safe-rotation (or rotation (glm.quat 1 0 0 0)))
  (local (angle axis) (axis-angle-from-glm-quat safe-rotation))
  (* translate (glm.rotate (glm.mat4 1) angle axis)))

(fn vec3-equal? [a b]
  (and (= a.x b.x)
       (= a.y b.y)
       (= a.z b.z)))

(fn quat-equal? [a b]
  (and (= a.w b.w)
       (= a.x b.x)
       (= a.y b.y)
       (= a.z b.z)))

(fn resolve-font-state [fonts font-states cell]
  (local regular (. font-states fonts.regular))
  (local italic-state (and cell.italic (. font-states fonts.italic)))
  (local bold-state (and cell.bold (. font-states fonts.bold)))
  (local bold-italic-state
    (and cell.bold cell.italic (. font-states fonts.bold_italic)))
  (if (and cell.bold cell.italic)
      (or bold-italic-state bold-state italic-state regular)
      (if cell.bold
          (or bold-state regular)
          (if cell.italic
              (or italic-state regular)
              regular))))

(fn ensure-ascender-height [style state]
  (when (and state (not state.ascender-height))
    (local metrics (and state.font state.font.metadata state.font.metadata.metrics))
    (set state.ascender-height
         (if (and metrics metrics.ascender)
             (* style.scale metrics.ascender)
             (line-height style))))
  state.ascender-height)

(fn glyph-uvs [glyph]
  (local atlas glyph.font.metadata.atlas)
  (values (/ glyph.atlasBounds.left atlas.width)
          (/ glyph.atlasBounds.bottom atlas.height)
          (/ glyph.atlasBounds.right atlas.width)
          (/ glyph.atlasBounds.top atlas.height)))

(fn TerminalRenderer [opts]
  (local ctx opts.ctx)
  (local style opts.style)
  (assert ctx "TerminalRenderer requires a build context")
  (assert style "TerminalRenderer requires a text style")
  (var cell-size (or opts.cell-size (glm.vec2 1 1)))
  (local palette (or opts.palette {}))

  (var rows 0)
  (var cols 0)
  (var term nil)
  (var layout-state nil)
  (var dirty? true)
  (var layout-dirty? true)
  (var full-redraw? true)
  (var cursor-dirty? true)
  (var draw-model (glm.mat4 1))
  (var tracking-dirty? true)

  (local background-quad-batcher (QuadBatcher {}))
  (local underline-quad-batcher (QuadBatcher {}))
  (local cursor-quad-batcher (QuadBatcher {}))
  (var background-quad-source nil)
  (var underline-quad-source nil)
  (var cursor-quad-source nil)
  (var text-ssbo-source nil)

  (var blink-on? true)
  (var last-update-time nil)
  (var blink-accumulator 0.0)
  (local blink-period (or opts.blink-period default-blink-period))
  (var scroll-offset 0)
  (var alt-screen? false)

  (local fonts {:regular style.font
                :italic (or style.italic-font style.font)
                :bold (or style.bold-font style.font)
                :bold_italic (or style.bold-italic-font style.bold-font style.italic-font style.font)})

  (local font-states {})
  (local seen-fonts {})
  (local font-state-list [])

  (fn push-font-state [font]
    (when (and font (not (. seen-fonts font)))
      (set (. seen-fonts font) true)
      (local state {:font font
                    :ascender-height nil
                    :variant-index (+ (length font-state-list) 1)
                    :bucket nil})
      (set (. font-states font) state)
      (table.insert font-state-list state)))

  (push-font-state fonts.regular)
  (push-font-state fonts.italic)
  (push-font-state fonts.bold)
  (push-font-state fonts.bold_italic)

  (local font-state-count (length font-state-list))

  (fn resolve-color [r g b]
    (local key (palette-key r g b))
    (or (. palette key)
        (do
          (local color (to-color r g b))
          (set (. palette key) color)
          color)))

  (fn with-model-batches [batches]
    (if (not batches)
        []
        (icollect [_ bucket (ipairs batches)]
          {:firsts bucket.firsts
           :counts bucket.counts
           :model draw-model})))

  (fn resolve-clip-matrix []
    (if (and layout-state layout-state.clip)
        (ClipUtils.resolve-matrix layout-state.clip)
        zero-clip-matrix))

  (fn write-bucket-transform [state depth]
    (local bucket state.bucket)
    (when bucket
      (local clip-matrix (resolve-clip-matrix))
      (local group-matrix draw-model)
      (bucket.group-vector:set-glm-mat4-diff bucket.group-handle 0 group-matrix)
      (bucket.clip-vector:set-glm-mat4-diff bucket.clip-handle 0 clip-matrix)
      (bucket.group-clip-index-vector:set-float-fill-diff bucket.group-clip-index-handle 0 1 0)
      (bucket.group-depth-index-vector:set-float-fill-diff bucket.group-depth-index-handle 0 1 depth)))

  (fn drop-font-bucket [state]
    (when state.bucket
      (local bucket state.bucket)
      (bucket.glyph-vector:delete bucket.glyph-handle)
      (bucket.glyph-group-vector:delete bucket.glyph-group-handle)
      (bucket.group-vector:delete bucket.group-handle)
      (bucket.group-clip-index-vector:delete bucket.group-clip-index-handle)
      (bucket.group-depth-index-vector:delete bucket.group-depth-index-handle)
      (bucket.clip-vector:delete bucket.clip-handle)
      (set state.bucket nil)))

  (fn clear-font-buckets []
    (each [_ state (ipairs font-state-list)]
      (drop-font-bucket state)))

  (fn ensure-font-bucket [state cell-count]
    (when (<= cell-count 0)
      (drop-font-bucket state))
    (when (> cell-count 0)
      (var bucket state.bucket)
      (if (and bucket (= bucket.cell-count cell-count))
          bucket
          (do
            (drop-font-bucket state)
            (set bucket {:glyph-vector (VectorBuffer)
                         :glyph-group-vector (VectorBuffer)
                         :group-vector (VectorBuffer)
                         :group-clip-index-vector (VectorBuffer)
                         :group-depth-index-vector (VectorBuffer)
                         :clip-vector (VectorBuffer)
                         :glyph-handle nil
                         :glyph-group-handle nil
                         :group-handle nil
                         :group-clip-index-handle nil
                         :group-depth-index-handle nil
                         :clip-handle nil
                         :cell-visible {}
                         :visible-count 0
                         :cell-count cell-count})
            (set bucket.glyph-handle (bucket.glyph-vector:allocate (* cell-count glyph-stride)))
            (set bucket.glyph-group-handle (bucket.glyph-group-vector:allocate cell-count))
            (set bucket.group-handle (bucket.group-vector:allocate 16))
            (set bucket.group-clip-index-handle (bucket.group-clip-index-vector:allocate 1))
            (set bucket.group-depth-index-handle (bucket.group-depth-index-vector:allocate 1))
            (set bucket.clip-handle (bucket.clip-vector:allocate 16))
            (bucket.glyph-group-vector:set-float-fill-diff bucket.glyph-group-handle 0 cell-count 0)
            (set state.bucket bucket)
            bucket))))

  (fn set-cell-visible [bucket index visible?]
    (local key (+ index 1))
    (local old? (not (not (. bucket.cell-visible key))))
    (if visible?
        (when (not old?)
          (set (. bucket.cell-visible key) true)
          (set bucket.visible-count (+ bucket.visible-count 1)))
        (when old?
          (set (. bucket.cell-visible key) nil)
          (set bucket.visible-count (- bucket.visible-count 1)))))

  (fn write-empty-glyph [bucket index]
    (local base (* index glyph-stride))
    (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 0) 0.0)
    (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 1) 0.0)
    (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 2) 0.0)
    (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 3) 0.0)
    (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 4) 0.0)
    (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 5) 0.0)
    (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 6) 0.0)
    (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 7) 0.0)
    (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 8) 0.0)
    (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 9) 0.0)
    (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 10) 0.0)
    (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 11) 0.0))

  (fn cell-origin [row col]
    (local total-height (* rows cell-size.y))
    (glm.vec3 (* col cell-size.x)
              (- total-height (* (+ row 1) cell-size.y))
              0.0))

  (fn write-glyph [state row col cell]
    (local bucket state.bucket)
    (when bucket
      (local index (cell-index row col cols))
      (local codepoint (or cell.codepoint 32))
      (local blank-unstyled?
        (and (or (= codepoint 0) (= codepoint 32))
             (not cell.bold)
             (not cell.italic)
             (not cell.underline)
             (not cell.reverse)))
      (local glyph (and state.font (fallback-glyph state.font codepoint)))
      (when (and glyph state.font (not glyph.font))
        (set glyph.font state.font))
      (local valid-glyph?
        (and (not blank-unstyled?)
             glyph
             glyph.planeBounds
             glyph.atlasBounds
             glyph.font
             glyph.font.metadata
             glyph.font.metadata.atlas))
      (if (not valid-glyph?)
          (do
            (write-empty-glyph bucket index)
            (set-cell-visible bucket index false))
          (do
            (local asc (or (ensure-ascender-height style state) cell-size.y))
            (local baseline-start (math.max 0.0 (- cell-size.y asc)))
            (local offset (cell-origin row col))
            (local left (* glyph.planeBounds.left style.scale))
            (local right (* glyph.planeBounds.right style.scale))
            (local bottom (* glyph.planeBounds.bottom style.scale))
            (local top (* glyph.planeBounds.top style.scale))
            (local x0 (+ offset.x left))
            (local y0 (+ offset.y baseline-start bottom))
            (local width (- right left))
            (local height (- top bottom))
            (local (s0 t0 s1 t1) (glyph-uvs glyph))
            (var fg (resolve-color cell.fg-r cell.fg-g cell.fg-b))
            (when cell.bold
              (set fg (apply-bold fg)))
            (when cell.reverse
              (set fg (resolve-color cell.bg-r cell.bg-g cell.bg-b)))
            (local base (* index glyph-stride))
            (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 0) x0)
            (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 1) y0)
            (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 2) width)
            (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 3) height)
            (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 4) s0)
            (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 5) t0)
            (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 6) s1)
            (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 7) t1)
            (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 8) fg.x)
            (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 9) fg.y)
            (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 10) fg.z)
            (bucket.glyph-vector:set-float bucket.glyph-handle (+ base 11) fg.w)
            (set-cell-visible bucket index true)))))

  (fn clear-glyph-at [state row col]
    (local bucket state.bucket)
    (when bucket
      (local index (cell-index row col cols))
      (write-empty-glyph bucket index)
      (set-cell-visible bucket index false)))

  (fn cell-matrix [row col y0 y1]
    (local offset (cell-origin row col))
    (local x0 offset.x)
    (local bottom (+ offset.y (or y0 0.0)))
    (local top (+ offset.y (or y1 cell-size.y)))
    (local height (math.max 0.0001 (- top bottom)))
    (* (glm.translate (glm.mat4 1) (glm.vec3 x0 bottom offset.z))
       (glm.scale (glm.mat4 1) (glm.vec3 cell-size.x height 1))))

  (fn write-background [row col color depth]
    (local index (cell-index row col cols))
    (background-quad-batcher:upsert-quad index
                                         {:matrix (cell-matrix row col 0 cell-size.y)
                                          :color color
                                          :depth-offset depth
                                          :clip (and layout-state layout-state.clip)}))

  (fn underline-geometry [state]
    (underline.underline-geometry state cell-size style line-height
                                  (fn [st]
                                    (ensure-ascender-height style st))))

  (fn write-underline [row col color depth y0 y1]
    (local index (cell-index row col cols))
    (underline-quad-batcher:upsert-quad index
                                        {:matrix (cell-matrix row col y0 y1)
                                         :color color
                                         :depth-offset depth
                                         :clip (and layout-state layout-state.clip)}))

  (fn write-empty-underline [row col depth]
    (write-underline row col (glm.vec4 0 0 0 0) depth 0.0 0.0001))

  (set background-quad-source
       {:get-draw-list
        (fn [_self]
          (if (or (not layout-state) layout-state.culled?)
              []
              (do
                (local vector (background-quad-batcher:get-vector))
                (local batches (background-quad-batcher:get-batches))
                (if (or (not vector)
                        (<= (vector:length) 0)
                        (not batches)
                        (<= (# batches) 0))
                    []
                    [{:vector vector
                      :clip-vector (background-quad-batcher:get-clip-vector)
                      :clip-group-vector (background-quad-batcher:get-clip-group-vector)
                      :batches (with-model-batches batches)}]))))})

  (set underline-quad-source
       {:get-draw-list
        (fn [_self]
          (if (or (not layout-state) layout-state.culled?)
              []
              (do
                (local vector (underline-quad-batcher:get-vector))
                (local batches (underline-quad-batcher:get-batches))
                (if (or (not vector)
                        (<= (vector:length) 0)
                        (not batches)
                        (<= (# batches) 0))
                    []
                    [{:vector vector
                      :clip-vector (underline-quad-batcher:get-clip-vector)
                      :clip-group-vector (underline-quad-batcher:get-clip-group-vector)
                      :batches (with-model-batches batches)}]))))})

  (set cursor-quad-source
       {:get-draw-list
        (fn [_self]
          (if (or (not layout-state) layout-state.culled?)
              []
              (do
                (local vector (cursor-quad-batcher:get-vector))
                (local batches (cursor-quad-batcher:get-batches))
                (if (or (not vector)
                        (<= (vector:length) 0)
                        (not batches)
                        (<= (# batches) 0))
                    []
                    [{:vector vector
                      :clip-vector (cursor-quad-batcher:get-clip-vector)
                      :clip-group-vector (cursor-quad-batcher:get-clip-group-vector)
                      :batches (with-model-batches batches)}]))))})

  (set text-ssbo-source
       {:get-draw-list
        (fn [_self]
          (if (or (not layout-state) layout-state.culled?)
              []
              (do
                (local out [])
                (each [_ state (ipairs font-state-list)]
                  (local bucket state.bucket)
                  (when (and bucket (> bucket.visible-count 0))
                    (table.insert out {:font state.font
                                       :glyph-vector bucket.glyph-vector
                                       :glyph-group-vector bucket.glyph-group-vector
                                       :group-vector bucket.group-vector
                                       :group-clip-index-vector bucket.group-clip-index-vector
                                       :group-depth-index-vector bucket.group-depth-index-vector
                                       :clip-vector bucket.clip-vector
                                       :batches [{:firsts [0]
                                                  :counts [bucket.cell-count]}]})))
                out)))})

  (when ctx.register-quad-source
    (ctx:register-quad-source background-quad-source)
    (ctx:register-quad-source underline-quad-source)
    (ctx:register-quad-source cursor-quad-source))
  (when ctx.register-text-ssbo-source
    (ctx:register-text-ssbo-source text-ssbo-source))

  (fn drop [_self]
    (when (and ctx ctx.unregister-quad-source)
      (ctx:unregister-quad-source background-quad-source)
      (ctx:unregister-quad-source underline-quad-source)
      (ctx:unregister-quad-source cursor-quad-source))
    (when (and ctx ctx.unregister-text-ssbo-source)
      (ctx:unregister-text-ssbo-source text-ssbo-source))
    (background-quad-batcher:drop)
    (underline-quad-batcher:drop)
    (cursor-quad-batcher:drop)
    (clear-font-buckets)
    (set term nil)
    (set layout-state nil))

  (fn set-term [self new-term]
    (set term new-term)
    (set dirty? true)
    (set full-redraw? true)
    self)

  (fn set-cell-size [self size]
    (when (and size (or (not (= size.x cell-size.x))
                        (not (= size.y cell-size.y))))
      (set cell-size size)
      (background-quad-batcher:clear)
      (underline-quad-batcher:clear)
      (clear-font-buckets)
      (set full-redraw? true)
      (set layout-dirty? true))
    self)

  (fn set-grid-size [self new-rows new-cols]
    (when (or (not (= new-rows rows))
              (not (= new-cols cols)))
      (set rows new-rows)
      (set cols new-cols)
      (background-quad-batcher:clear)
      (underline-quad-batcher:clear)
      (clear-font-buckets)
      (set full-redraw? true)
      (set dirty? true))
    self)

  (fn set-scroll-state [self state]
    (local next-offset (math.max 0 (or (and state state.offset) 0)))
    (local next-alt (not (not (and state state.alt-screen?))))
    (when (or (not (= next-offset scroll-offset))
              (not (= next-alt alt-screen?)))
      (set scroll-offset next-offset)
      (set alt-screen? next-alt)
      (set full-redraw? true)
      (set dirty? true)
      (set cursor-dirty? true))
    self)

  (fn set-layout [self layout]
    (when layout
      (local next-state {:position layout.position
                         :rotation layout.rotation
                         :clip layout.clip-region
                         :depth layout.depth-offset-index
                         :culled? (layout:effective-culled?)})
      (if (not layout-state)
          (do
            (set layout-state next-state)
            (set draw-model (model-matrix next-state.position next-state.rotation))
            (set tracking-dirty? true)
            (set layout-dirty? true)
            (set full-redraw? true))
          (do
            (local transform-changed?
              (or (not (vec3-equal? layout-state.position next-state.position))
                  (not (quat-equal? layout-state.rotation next-state.rotation))))
            (local clip-changed? (not (= layout-state.clip next-state.clip)))
            (local depth-changed? (not (= layout-state.depth next-state.depth)))
            (local cull-changed? (not (= layout-state.culled? next-state.culled?)))
            (set layout-state next-state)
            (when transform-changed?
              (set draw-model (model-matrix next-state.position next-state.rotation))
              (set layout-dirty? true)
              (set tracking-dirty? true)
              (set cursor-dirty? true))
            (when clip-changed?
              (set layout-dirty? true)
              (set tracking-dirty? true)
              (set cursor-dirty? true))
            (when depth-changed?
              (set layout-dirty? true)
              (set tracking-dirty? true)
              (set full-redraw? true)
              (set dirty? true)
              (set cursor-dirty? true))
            (when cull-changed?
              (set layout-dirty? true)
              (set tracking-dirty? true)
              (set full-redraw? true)
              (set dirty? true)
              (set cursor-dirty? true)))))
    self)

  (fn mark-dirty [self opts]
    (set dirty? true)
    (when (and opts opts.full?)
      (set full-redraw? true))
    self)

  (fn ensure-ready []
    (if (or (not term)
            (not layout-state)
            layout-state.culled?
            (<= rows 0)
            (<= cols 0)
            (not ctx))
        (do
          (cursor-quad-batcher:clear)
          false)
        true))

  (fn ensure-buckets [depth]
    (local cell-count (* rows cols))
    (each [_ state (ipairs font-state-list)]
      (when (ensure-font-bucket state cell-count)
        (write-bucket-transform state (+ depth 2.0)))))

  (fn update-bucket-transforms [depth]
    (each [_ state (ipairs font-state-list)]
      (when state.bucket
        (write-bucket-transform state (+ depth 2.0)))))

  (fn write-cursor [cursor]
    (if (and cursor cursor.visible layout-state (not layout-state.culled?))
        (do
          (local color (glm.vec4 1 1 1 0.8))
          (local depth (+ (or layout-state.depth 0) 3.0))
          (when (and cursor.blinking (not blink-on?))
            (cursor-quad-batcher:clear)
            (set cursor-dirty? false)
            (lua "return"))
          (cursor-quad-batcher:upsert-quad 0
                                           {:matrix (cell-matrix cursor.row cursor.col 0 cell-size.y)
                                            :color color
                                            :depth-offset depth
                                            :clip layout-state.clip})
          (set cursor-dirty? false))
        (do
          (cursor-quad-batcher:clear)
          (set cursor-dirty? false))))

  (fn paint [_self]
    (when (ensure-ready)
      (local depth (or layout-state.depth 0))
      (when full-redraw?
        (background-quad-batcher:clear)
        (underline-quad-batcher:clear))
      (ensure-buckets depth)
      (when (and layout-dirty? tracking-dirty? (not full-redraw?))
        (update-bucket-transforms depth))

      (local use-scrollback? (and term (> scroll-offset 0) (not alt-screen?)))
      (local scrollback-size (if (and use-scrollback? term term.get-scrollback-size)
                                 (math.max 0 (term:get-scrollback-size))
                                 0))
      (local viewport-start
        (if use-scrollback?
            (math.max 0 (- scrollback-size scroll-offset))
            0))
      (local screen-row-offset (math.max 0 (- scrollback-size viewport-start)))
      (local regions
        (if (or full-redraw? use-scrollback?)
            [{:top 0 :left 0 :bottom (- rows 1) :right (- cols 1)}]
            (term:get-dirty-regions)))

      (when (and regions (> (# regions) 0))
        (local line-cache {})
        (local line-for-viewport
          (fn [viewport-row]
            (local combined-index (+ viewport-start viewport-row))
            (if (< combined-index scrollback-size)
                (or (. line-cache combined-index)
                    (do
                      (local line (term:get-scrollback-line combined-index))
                      (set (. line-cache combined-index) line)
                      line))
                (or (. line-cache combined-index)
                    (do
                      (local line (term:get-row (- combined-index scrollback-size)))
                      (set (. line-cache combined-index) line)
                      line)))))

        (each [_ region (ipairs regions)]
          (for [row region.top region.bottom]
            (var source-row row)
            (when use-scrollback?
              (set source-row (+ viewport-start row)))
            (local line (if use-scrollback?
                            (line-for-viewport row)
                            nil))
            (for [col region.left region.right]
              (local cell
                (if use-scrollback?
                    (or (and line (. line (+ col 1))) blank-cell)
                    (term:get-cell source-row col)))
              (var fg (resolve-color cell.fg-r cell.fg-g cell.fg-b))
              (var bg (resolve-color cell.bg-r cell.bg-g cell.bg-b))
              (when cell.reverse
                (local tmp fg)
                (set fg bg)
                (set bg tmp))
              (var underline-color (resolve-color cell.fg-r cell.fg-g cell.fg-b))
              (when cell.bold
                (set underline-color (apply-bold underline-color)))
              (when cell.reverse
                (set underline-color (resolve-color cell.bg-r cell.bg-g cell.bg-b)))
              (local target-state (resolve-font-state fonts font-states cell))
              (local underline-geo (underline-geometry target-state))
              (write-background row col bg depth)
              (if cell.underline
                  (write-underline row col underline-color (+ depth 1.0) underline-geo.y0 underline-geo.y1)
                  (write-empty-underline row col (+ depth 1.0)))
              (each [_ state (ipairs font-state-list)]
                (if (= state target-state)
                    (write-glyph state row col cell)
                    (clear-glyph-at state row col))))))
        (term:clear-dirty-regions))

      (local cursor (term:get-cursor))
      (local cursor-to-draw
        (if (and use-scrollback? cursor)
            (do
              (local row (+ cursor.row screen-row-offset))
              (and (>= row 0)
                   (< row rows)
                   {:row row
                    :col cursor.col
                    :visible cursor.visible
                    :blinking cursor.blinking}))
            cursor))
      (write-cursor cursor-to-draw)
      (set dirty? false)
      (set layout-dirty? false)
      (set full-redraw? false)
      (set tracking-dirty? false)))

  (fn update-blink [_self delta cursor]
    (when cursor
      (if cursor.blinking
          (do
            (set blink-accumulator (+ blink-accumulator delta))
            (when (>= blink-accumulator blink-period)
              (set blink-accumulator (- blink-accumulator blink-period))
              (set blink-on? (not blink-on?))
              (set cursor-dirty? true)))
          (do
            (when (not blink-on?)
              (set blink-on? true)
              (set cursor-dirty? true))
            (set blink-accumulator 0)))))

  (fn cursor-state-changed? [a b]
    (or (not a)
        (not b)
        (not (= a.row b.row))
        (not (= a.col b.col))
        (not (= a.visible b.visible))
        (not (= a.blinking b.blinking))))

  (var last-cursor nil)

  (fn copy-cursor [cursor]
    (and cursor {:row cursor.row
                 :col cursor.col
                 :visible cursor.visible
                 :blinking cursor.blinking}))

  (fn update [self delta]
    (when term
      (local now (os.clock))
      (local elapsed (or delta (and last-update-time (- now last-update-time)) 0))
      (set last-update-time now)
      (local cursor (term:get-cursor))
      (when (cursor-state-changed? cursor last-cursor)
        (set cursor-dirty? true))
      (set last-cursor (copy-cursor cursor))
      (update-blink self elapsed cursor)
      (when (or dirty? layout-dirty? full-redraw? cursor-dirty?)
        (paint self))))

  (fn get-handles [_self]
    (var active-count 0)
    (each [_ state (ipairs font-state-list)]
      (when state.bucket
        (set active-count (+ active-count state.bucket.visible-count))))
    {:glyph {}
     :glyph-count active-count
     :cursor nil})

  {:set-term set-term
   :set-cell-size set-cell-size
   :set-grid-size set-grid-size
   :set-scroll-state set-scroll-state
   :set-layout set-layout
   :mark-dirty mark-dirty
   :update update
   :drop drop
   :get-handles get-handles})

TerminalRenderer
