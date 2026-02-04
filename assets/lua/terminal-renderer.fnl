(local glm (require :glm))
(local {: fallback-glyph
        : line-height} (require :text-utils))
(local glyphs (require :terminal-glyphs))
(local underline (require :terminal-underline))

(local default-blink-period 0.6)
(local background-stride (* 8 6)) ; floats per cell background (6 verts * 8 floats)
(local glyph-stride glyphs.glyph-stride)
(local underline-stride underline.underline-stride)
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

(fn ensure-handle [vector handle needed-size]
  (if handle
      (do
        (when (< handle.size needed-size)
          (vector:reallocate handle needed-size))
        handle)
      (vector:allocate needed-size)))

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

  (var background-handle nil)
  (var underline-handle nil)
  (var cursor-handle nil)

  (var blink-on? true)
  (var last-update-time nil)
  (var blink-accumulator 0.0)
  (var cursor-dirty? true)
  (local blink-period (or opts.blink-period default-blink-period))
  (var scroll-offset 0)
  (var alt-screen? false)

  (local fonts {:regular style.font
                :italic (or style.italic-font style.font)
                :bold (or style.bold-font style.font)
                :bold_italic (or style.bold-italic-font style.bold-font style.italic-font style.font)})

  (var font-states {})

  (each [_ font (ipairs [fonts.regular fonts.italic fonts.bold fonts.bold_italic])]
    (glyphs.ensure-font-state font-states font))

  (fn each-font-state [iter]
    (glyphs.each-font-state font-states iter))

  (fn resolve-font-state [cell]
    (glyphs.resolve-font-state fonts font-states cell))

  (fn resolve-text-vector [state]
    (glyphs.resolve-text-vector ctx state))

  (fn resolve-ascender-height [state]
    (glyphs.resolve-ascender-height style state line-height))

  (fn resolve-color [r g b]
    (local key (palette-key r g b))
    (or (. palette key)
        (let [color (to-color r g b)]
          (set (. palette key) color)
          color)))

  (fn release-handle [vector handle tracker]
    (when (and vector handle)
      (when tracker
        (tracker handle))
      (vector:delete handle))
    nil)

  (fn drop [_self]
    (when ctx
      (set background-handle
           (release-handle ctx.triangle-vector
                           background-handle
                           (and ctx.untrack-triangle-handle
                                (fn [handle] (ctx:untrack-triangle-handle handle)))))
      (set underline-handle
           (release-handle ctx.triangle-vector
                           underline-handle
                           (and ctx.untrack-triangle-handle
                                (fn [handle] (ctx:untrack-triangle-handle handle)))))
      (set cursor-handle
           (release-handle ctx.triangle-vector
                           cursor-handle
                           (and ctx.untrack-triangle-handle
                                (fn [handle] (ctx:untrack-triangle-handle handle)))))
      (each-font-state
        (fn [state]
          (when (and ctx state.vector)
            (set state.handle
                 (release-handle state.vector
                                 state.handle
                                 (and ctx.untrack-text-handle
                                      (fn [handle] (ctx:untrack-text-handle state.font handle)))))
            (set state.vector nil)
            (set state.ascender-height nil)))))
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
      (set full-redraw? true)
      (set layout-dirty? true))
    self)

  (fn set-grid-size [self new-rows new-cols]
    (when (or (not (= new-rows rows))
              (not (= new-cols cols)))
      (set rows new-rows)
      (set cols new-cols)
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
      (set layout-state {:position layout.position
                         :rotation layout.rotation
                         :clip layout.clip-region
                         :depth layout.depth-offset-index
                         :culled? (layout:effective-culled?)})
      (set layout-dirty? true)
      (set full-redraw? true))
    self)

  (fn mark-dirty [self opts]
    (set dirty? true)
    (when (and opts opts.full?)
      (set full-redraw? true))
    self)

  (fn cell-origin [row col]
    (local total-height (* rows cell-size.y))
    ; Rows in vterm grow downward; our coordinate system grows upward, so flip Y.
    (glm.vec3 (* col cell-size.x)
          (- total-height (* (+ row 1) cell-size.y))
          0.0))

  (fn write-background [self row col color depth rotation position]
    (local handle background-handle)
    (local vector ctx.triangle-vector)
    (local index (cell-index row col cols))
    (local base (* index background-stride))
    (local offset (cell-origin row col))
    (local verts [[0.0 0.0 0.0]
                  [0.0 cell-size.y 0.0]
                  [cell-size.x cell-size.y 0.0]
                  [cell-size.x cell-size.y 0.0]
                  [cell-size.x 0.0 0.0]
                  [0.0 0.0 0.0]])
    (for [i 1 6]
      (local local-pos (glm.vec3 (table.unpack (. verts i))))
      (vector.set-glm-vec3
       vector
       handle
       (+ base (* (- i 1) 8))
       (+ (rotation:rotate (+ offset local-pos)) position))
      (vector:set-glm-vec4 handle (+ base (* (- i 1) 8) 3) color)
      (vector:set-float handle (+ base (* (- i 1) 8) 7) depth)))

  (fn underline-geometry [state]
    (underline.underline-geometry state cell-size style line-height resolve-ascender-height))

  (fn write-underline [self row col color depth rotation position y0 y1]
    (local base (* (cell-index row col cols) underline-stride))
    (underline.write-underline
      {:vector ctx.triangle-vector
       :handle underline-handle
       :cell-origin cell-origin
       :cell-size cell-size
       :row row
       :col col
       :color color
       :depth depth
       :rotation rotation
       :position position
       :base base
       :y0 y0
       :y1 y1}))

  (fn write-glyph [self state row col cell rotation position depth]
    (glyphs.write-glyph
      {:state state
       :cell cell
       :row row
       :col col
       :base (* (cell-index row col cols) glyph-stride)
       :cell-origin cell-origin
       :cell-size cell-size
       :style style
       :line-height line-height
       :fallback-glyph fallback-glyph
       :resolve-color resolve-color
       :apply-bold apply-bold
       :rotation rotation
       :position position
       :depth depth}))

  (local write-empty-underline underline.write-empty-underline)
  (local write-empty-glyph glyphs.write-empty-glyph)

  (fn ensure-buffers [self]
    (local cell-count (* (math.max 0 rows) (math.max 0 cols)))
    (if (or (<= cell-count 0)
            (not ctx)
            (not ctx.triangle-vector)
            (and layout-state layout-state.culled?))
        (do
          (when ctx
            (when background-handle
              (when ctx.untrack-triangle-handle
                (ctx:untrack-triangle-handle background-handle)))
            (when underline-handle
              (when ctx.untrack-triangle-handle
                (ctx:untrack-triangle-handle underline-handle)))
            (when cursor-handle
              (when ctx.untrack-triangle-handle
                (ctx:untrack-triangle-handle cursor-handle)))
            (each-font-state
              (fn [state]
                (when (and state.handle ctx.untrack-text-handle)
                  (ctx:untrack-text-handle state.font state.handle)))))
          (set background-handle nil)
          (set underline-handle nil)
          (set cursor-handle nil)
          (each-font-state
            (fn [state]
              (set state.handle nil)))
          false)
        (do
          (each-font-state
            (fn [state]
              (when (resolve-text-vector state)
                (resolve-ascender-height state))))
          (set background-handle
               (ensure-handle ctx.triangle-vector background-handle (* cell-count background-stride)))
          (set underline-handle
               (ensure-handle ctx.triangle-vector underline-handle (* cell-count underline-stride)))
          (each-font-state
            (fn [state]
              (if state.vector
                  (set state.handle
                       (ensure-handle state.vector state.handle (* cell-count glyph-stride)))
                  (do
                    (when (and state.handle ctx.untrack-text-handle)
                      (ctx:untrack-text-handle state.font state.handle))
                    (set state.handle nil)))))
          (when (and ctx.track-triangle-handle background-handle)
            (ctx:track-triangle-handle background-handle (and layout-state layout-state.clip)))
          (when (and ctx.track-triangle-handle underline-handle)
            (ctx:track-triangle-handle underline-handle (and layout-state layout-state.clip)))
          (when (and cursor-handle ctx.track-triangle-handle)
            (ctx:track-triangle-handle cursor-handle (and layout-state layout-state.clip)))
          (each-font-state
            (fn [state]
              (when (and state.handle state.vector ctx.track-text-handle)
                (ctx:track-text-handle state.font state.handle (and layout-state layout-state.clip)))))
          true)))

  (fn write-cursor [self cursor rotation position]
    (if (and cursor cursor.visible layout-state (not layout-state.culled?))
        (do
          (when (not cursor-handle)
            (set cursor-handle (ctx.triangle-vector:allocate background-stride)))
          (ctx:track-triangle-handle cursor-handle layout-state.clip)
          (local color (glm.vec4 1 1 1 0.8))
          (when (and cursor.blinking (not blink-on?))
            (ctx:untrack-triangle-handle cursor-handle)
            (set cursor-dirty? false)
            (lua "return"))
          (local depth (+ (or layout-state.depth 0) 2.0))
          (local row cursor.row)
          (local col cursor.col)
          (local verts [[0.0 0.0 0.0]
                        [0.0 cell-size.y 0.0]
                        [cell-size.x cell-size.y 0.0]
                        [cell-size.x cell-size.y 0.0]
                        [cell-size.x 0.0 0.0]
                        [0.0 0.0 0.0]])
          (local offset (cell-origin row col))
          (for [i 1 6]
            (local local-pos (glm.vec3 (table.unpack (. verts i))))
            (ctx.triangle-vector.set-glm-vec3
             ctx.triangle-vector
             cursor-handle
             (* (- i 1) 8)
             (+ (rotation:rotate (+ offset local-pos))
                position))
            (ctx.triangle-vector:set-glm-vec4 cursor-handle (+ (* (- i 1) 8) 3) color)
            (ctx.triangle-vector:set-float cursor-handle (+ (* (- i 1) 8) 7) depth))
          (set cursor-dirty? false))
        (when cursor-handle
          (ctx:untrack-triangle-handle cursor-handle)
          (set cursor-dirty? false))))

  (fn paint [self]
    (when (and term layout-state (not layout-state.culled?) (ensure-buffers self))
      (local rotation layout-state.rotation)
      (local position layout-state.position)
      (local depth (or layout-state.depth 0))
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
                    (let [line (term:get-scrollback-line combined-index)]
                      (set (. line-cache combined-index) line)
                      line))
                (or (. line-cache combined-index)
                    (let [line (term:get-row (- combined-index scrollback-size))]
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
              (local target-state (resolve-font-state cell))
              (local underline-geo (underline-geometry target-state))
              (write-background self row col bg depth rotation position)
              (when underline-handle
                (local underline-base (* (cell-index row col cols) underline-stride))
                (if cell.underline
                    (write-underline self row col underline-color (+ depth 1.0) rotation position underline-geo.y0 underline-geo.y1)
                    (write-empty-underline ctx.triangle-vector underline-handle underline-base (+ depth 1.0))))
              (local glyph-base (* (cell-index row col cols) glyph-stride))
              (each-font-state
                (fn [state]
                  (if (= state target-state)
                      (when (and state state.handle state.vector)
                        (write-glyph self state row col cell rotation position (+ depth 1.0)))
                      (write-empty-glyph state.vector state.handle glyph-base (+ depth 1.0))))))))
        (term:clear-dirty-regions))
      (local cursor (term:get-cursor))
      (local cursor-to-draw
        (if (and use-scrollback? cursor)
            (let [row (+ cursor.row screen-row-offset)]
              (and (>= row 0)
                   (< row rows)
                   {:row row
                    :col cursor.col
                    :visible cursor.visible
                    :blinking cursor.blinking}))
            cursor))
      (write-cursor self cursor-to-draw rotation position)
      (set dirty? false)
      (set layout-dirty? false)
      (set full-redraw? false)))

  (fn update-blink [self delta cursor]
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
    (local glyph-handles {})
    (each-font-state
      (fn [state]
        (set (. glyph-handles state.font) state.handle)))
    {:background background-handle
     :underline underline-handle
     :glyph glyph-handles
     :cursor cursor-handle})

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
