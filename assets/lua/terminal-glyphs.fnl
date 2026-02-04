(local glm (require :glm))
(local glyph-stride (* 10 6))

(fn ensure-font-state [font-states font]
  (when (and font (not (. font-states font)))
    (set (. font-states font)
         {:font font
          :vector nil
          :handle nil
          :ascender-height nil})))

(fn each-font-state [font-states iter]
  (each [_ state (pairs font-states)]
    (iter state)))

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

(fn resolve-text-vector [ctx state]
  (when (and state (not state.vector) ctx ctx.get-text-vector)
    (set state.vector (ctx:get-text-vector state.font)))
  (and state state.vector))

(fn resolve-ascender-height [style state line-height]
  (when (and state (not state.ascender-height))
    (local metrics (and state.font state.font.metadata state.font.metadata.metrics))
    (set state.ascender-height
         (if (and metrics metrics.ascender)
             (* style.scale metrics.ascender)
             (line-height style))))
  state.ascender-height)

(fn glyph-positions [glyph ascender-height cell-size style]
  (local baseline-start (math.max 0.0 (- cell-size.y ascender-height)))
  (local x0 (* glyph.planeBounds.left style.scale))
  (local y0 (+ baseline-start (* glyph.planeBounds.bottom style.scale)))
  (local x1 (* glyph.planeBounds.right style.scale))
  (local y1 (+ baseline-start (* glyph.planeBounds.top style.scale)))
  [[x0 y0 0.0] [x1 y0 0.0] [x1 y1 0.0]
   [x0 y0 0.0] [x1 y1 0.0] [x0 y1 0.0]])

(fn glyph-uvs [glyph]
  (local atlas glyph.font.metadata.atlas)
  (local s0 (/ glyph.atlasBounds.left atlas.width))
  (local s1 (/ glyph.atlasBounds.right atlas.width))
  (local t1 (/ glyph.atlasBounds.top atlas.height))
  (local t0 (/ glyph.atlasBounds.bottom atlas.height))
  [[s0 t0] [s1 t0] [s1 t1]
   [s0 t0] [s1 t1] [s0 t1]])

(fn write-empty-glyph [vector handle base depth]
  (when (and vector handle)
    (for [i 0 5]
      (local offset (+ base (* i 10)))
      (vector:set-glm-vec3 handle offset (glm.vec3 0 0 0))
      (vector:set-glm-vec2 handle (+ offset 3) (glm.vec2 0 0))
      (vector:set-glm-vec4 handle (+ offset 5) (glm.vec4 0 0 0 0))
      (vector:set-float handle (+ offset 9) depth))))

(fn write-glyph [opts]
  (local state opts.state)
  (local cell opts.cell)
  (local row opts.row)
  (local col opts.col)
  (local base opts.base)
  (local cell-origin opts.cell-origin)
  (local cell-size opts.cell-size)
  (local style opts.style)
  (local line-height opts.line-height)
  (local fallback-glyph opts.fallback-glyph)
  (local resolve-color opts.resolve-color)
  (local apply-bold opts.apply-bold)
  (local rotation opts.rotation)
  (local position opts.position)
  (local depth opts.depth)
  (local font (and state state.font))
  (local glyph (and font (fallback-glyph font cell.codepoint)))
  (when (and glyph font (not glyph.font))
    (set glyph.font font))
  (local handle (and state state.handle))
  (local vector (and state state.vector))
  (local ascender-height
    (or state.ascender-height
        (resolve-ascender-height style state line-height)))
  (local blank-unstyled?
    (and (or (= cell.codepoint 0) (= cell.codepoint 32))
         (not cell.bold)
         (not cell.italic)
         (not cell.underline)
         (not cell.reverse)))
  (local draw-glyph (and (not blank-unstyled?) glyph))
  (local has-glyph
    (and draw-glyph draw-glyph.font draw-glyph.planeBounds draw-glyph.atlasBounds
         draw-glyph.font.metadata draw-glyph.font.metadata.atlas))
  (if (or (not has-glyph) blank-unstyled?)
      (write-empty-glyph vector handle base depth)
      (do
        (local positions (glyph-positions draw-glyph ascender-height cell-size style))
        (local uvs (glyph-uvs draw-glyph))
        (var fg (resolve-color cell.fg-r cell.fg-g cell.fg-b))
        (when cell.bold
          (set fg (apply-bold fg)))
        (when cell.reverse
          (set fg (resolve-color cell.bg-r cell.bg-g cell.bg-b)))
        (for [i 1 6]
          (local local-pos (glm.vec3 (table.unpack (. positions i))))
          (local uv (. uvs i))
          (local offset (+ base (* (- i 1) 10)))
          (vector.set-glm-vec3
           vector
           handle
           offset
           (+ (rotation:rotate (+ (cell-origin row col) local-pos))
              position))
          (vector:set-glm-vec2 handle (+ offset 3) (glm.vec2 (table.unpack uv)))
          (vector:set-glm-vec4 handle (+ offset 5) fg)
          (vector:set-float handle (+ offset 9) depth)))))

{:glyph-stride glyph-stride
 :ensure-font-state ensure-font-state
 :each-font-state each-font-state
 :resolve-font-state resolve-font-state
 :resolve-text-vector resolve-text-vector
 :resolve-ascender-height resolve-ascender-height
 :write-empty-glyph write-empty-glyph
 :write-glyph write-glyph}
