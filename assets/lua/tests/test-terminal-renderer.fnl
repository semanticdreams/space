(local glm (require :glm))
(local _ (require :main))
(local BuildContext (require :build-context))
(local TerminalRenderer (require :terminal-renderer))
(local TerminalWidget (require :terminal-widget))
(local TextUtils (require :text-utils))
(local resolve-style TextUtils.resolve-style)
(local MockOpenGL (require :mock-opengl))
(local terminal-native (require :terminal))
(local MathUtils (require :math-utils))
(local package package)
(local table table)
(local ipairs ipairs)

(local blank-cell {:codepoint 32
                   :fg-r 255 :fg-g 255 :fg-b 255
                   :bg-r 0 :bg-g 0 :bg-b 0
                   :bold false :underline false :italic false :reverse false})

(local tests [])

(fn reload [module-name]
  (set (. package.loaded module-name) nil)
  (require module-name))

(fn with-mock [cb]
  (local mock (MockOpenGL))
  (mock:install)
  (let [(ok result) (pcall cb mock)]
    (mock:restore)
    (if ok
        result
        (error result))))

(fn make-layout []
  (local layout {:position (glm.vec3 1 2 0)
                 :rotation (glm.quat 1 0 0 0)
                 :clip-region nil
                 :depth-offset-index 3})
  (set layout.effective-culled? (fn [_self] false))
  layout)

(fn make-term [cells dirty-ref cursor scrollback]
  (var cleared false)
  (local history (or (and scrollback scrollback.lines) []))
  (local history-size (or (and scrollback scrollback.size) (length history)))
  (local term {})
  (set term.get-dirty-regions (fn [] dirty-ref.regions))
  (set term.clear-dirty-regions (fn [] (set cleared true)))
  (set term.get-row
       (fn [_self row]
         (or (and cells (. cells (+ row 1)))
             [])))
  (set term.get-cell
       (fn [_self row col]
         (or (and cells (. cells (+ row 1)) (. (. cells (+ row 1)) (+ col 1)))
             blank-cell)))
  (set term.get-cursor (fn [] cursor))
  (set term.get-size (fn []
                       {:rows (length cells)
                        :cols (length (or (. cells 1) []))}))
  (set term.get-scrollback-size (fn [_] history-size))
  (set term.get-scrollback-line
       (fn [_ idx]
         (or (. history (+ idx 1)) [])))
  (set term.update (fn [_self] nil))
  [term (fn [] cleared)])

(fn add-basic-glyphs [font]
  (when font
    (local glyph {:planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                  :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}
                  :advance 1
                  :font font})
    (set (. font.glyph-map (string.byte "A")) glyph)
    (set (. font.glyph-map (string.byte "B")) glyph)
    (set (. font.glyph-map 32) glyph)
    (set (. font.glyph-map 65533) glyph))
  font)

(fn make-font [id atlas-size metrics]
  (add-basic-glyphs
    {:metadata {:atlas {:distanceRange 3.5
                        :width atlas-size
                        :height atlas-size}
                :metrics (or metrics {:ascender 6
                                      :descender -2
                                      :lineHeight 8})}
     :texture {:id id}
     :glyph-map {}}))

(fn make-style [opts]
  (local options (or opts {}))
  (local font (or options.font (make-font 77 4)))
  (local italic-font (or options.italic-font font))
  (local bold-font (or options.bold-font font))
  (local bold-italic-font (or options.bold-italic-font bold-font italic-font font))
  (add-basic-glyphs font)
  (add-basic-glyphs italic-font)
  (add-basic-glyphs bold-font)
  (add-basic-glyphs bold-italic-font)
  {:color (glm.vec4 1 1 1 1)
   :scale 1
   :font font
   :italic-font italic-font
   :bold-font bold-font
   :bold-italic-font bold-italic-font})

(local approx (. MathUtils :approx))

(fn uses-font-variants-for-bold-and-italic []
  (with-mock
    (fn [_mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local fonts {:regular (make-font 1 4)
                    :italic (make-font 2 8)
                    :bold (make-font 3 12)
                    :bold_italic (make-font 4 16)})
      (local style (make-style {:font fonts.regular
                                :italic-font fonts.italic
                                :bold-font fonts.bold
                                :bold-italic-font fonts.bold_italic}))
	      (local row [{:codepoint (string.byte "A")
	                   :fg-r 10 :fg-g 0 :fg-b 0
	                   :bg-r 0 :bg-g 0 :bg-b 0
	                   :bold false :underline false :italic false :reverse false}
	                  {:codepoint (string.byte "A")
	                   :fg-r 60 :fg-g 0 :fg-b 0
	                   :bg-r 0 :bg-g 0 :bg-b 0
	                   :bold false :underline false :italic true :reverse false}
	                  {:codepoint (string.byte "A")
	                   :fg-r 110 :fg-g 0 :fg-b 0
	                   :bg-r 0 :bg-g 0 :bg-b 0
	                   :bold true :underline false :italic false :reverse false}
	                  {:codepoint (string.byte "A")
	                   :fg-r 200 :fg-g 0 :fg-b 0
	                   :bg-r 0 :bg-g 0 :bg-b 0
	                   :bold true :underline false :italic true :reverse false}])
      (local dirty {:regions [{:top 0 :left 0 :bottom 0 :right 3}]})
      (local [term _cleared?] (make-term [row] dirty {:row 0 :col 0 :visible false :blinking false}))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 1 1)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 4)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (local handles (renderer:get-handles))
      (local stride (* 10 6))
      (fn normalize [value bold?]
        (local base (/ value 255))
        (if bold?
            (math.min 1.0 (+ base 0.1))
            base))
      (fn assert-font-colors [font active-index expected-r]
        (local handle (. handles.glyph font))
        (assert handle)
        (local vector (ctx:get-text-vector font))
        (local view (vector:view handle))
        (for [i 0 3]
          (local base (* i stride))
          (local r (. view (+ base 6)))
          (if (= i active-index)
              (assert (approx r expected-r)
                      (.. "active color mismatch at cell " i ": " r))
              (assert (approx r 0.0)
                      (.. "inactive color mismatch at cell " i ": " r)))))
      (assert-font-colors fonts.regular 0 (/ 10 255))
      (assert-font-colors fonts.italic 1 (/ 60 255))
      (assert-font-colors fonts.bold 2 (normalize 110 true))
      (assert-font-colors fonts.bold_italic 3 (normalize 200 true)))))

(fn renders-dirty-cells-into-buffers []
  (with-mock
    (fn [_mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local style (make-style))
      (local cell {:codepoint (string.byte "A")
                   :fg-r 10 :fg-g 20 :fg-b 30
                   :bg-r 40 :bg-g 50 :bg-b 60
                   :bold false :underline true :italic false :reverse false})
      (local dirty {:regions [{:top 0 :left 0 :bottom 0 :right 0}]})
      (local [term cleared?] (make-term [[cell]] dirty {:row 0 :col 0 :visible false :blinking false}))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 2 3)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 1)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (assert (cleared?))
      (local handles (renderer:get-handles))
      (assert handles.background)
      (assert handles.underline)
      (assert (. handles.glyph style.font))
      (local TriangleRenderer (reload "triangle-renderer"))
      (local TextRenderer (reload "text-renderer"))
      (local tri (TriangleRenderer))
      (local tex (TextRenderer))
      (tri:render ctx.triangle-vector {:projection true} {:view true} (ctx:get-triangle-batches))
      (local text-batches (ctx:get-text-batches))
      (local text-vector (ctx:get-text-vector style.font))
      (tex:render text-vector style.font {:projection true} {:view true} (. text-batches style.font))
      (local bg-view (ctx.triangle-vector:view handles.background))
      (local underline-view (ctx.triangle-vector:view handles.underline))
      (local glyph-view (text-vector:view (. handles.glyph style.font)))
      (assert (approx (. bg-view 4) (/ 40 255)))
      (assert (approx (. bg-view 8) layout.depth-offset-index))
      (assert (approx (. underline-view 4) (/ 10 255)))
      (assert (approx (. underline-view 8) (+ layout.depth-offset-index 1)))
      (assert (approx (. glyph-view 6) (/ 10 255)))
      (assert (approx (. glyph-view 10) (+ layout.depth-offset-index 1))))))

(fn underline-uses-font-metrics []
  (with-mock
    (fn [_mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local metrics {:ascender 12 :descender -3 :lineHeight 20})
      (local font (make-font 9 4 metrics))
      (local style (make-style {:font font}))
      (local cell {:codepoint (string.byte "A")
                   :fg-r 120 :fg-g 10 :fg-b 10
                   :bg-r 0 :bg-g 0 :bg-b 0
                   :bold false :underline true :italic false :reverse false})
      (local dirty {:regions [{:top 0 :left 0 :bottom 0 :right 0}]})
      (local [term _cleared?] (make-term [[cell]] dirty {:row 0 :col 0 :visible false :blinking false}))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 2 5)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 1)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (local handles (renderer:get-handles))
      (local underline-view (ctx.triangle-vector:view handles.underline))
      (local expected-thickness (math.max 1.0 (* 0.08 (TextUtils.line-height style))))
      (local expected-y0 (+ layout.position.y (math.max 0.0 (- 5 expected-thickness))))
      (local expected-y1 (+ expected-y0 expected-thickness))
      (assert (approx (. underline-view 2) expected-y0))
      (assert (approx (. underline-view 10) expected-y1)))))

(fn cursor-blink-removes-cursor-handle-when-off []
  (with-mock
    (fn [mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local style (make-style))
      (local cell {:codepoint (string.byte "B")
                   :fg-r 200 :fg-g 200 :fg-b 200
                   :bg-r 0 :bg-g 0 :bg-b 0
                   :bold false :underline false :italic false :reverse false})
      (var dirty {:regions [{:top 0 :left 0 :bottom 0 :right 1}]})
      (local cursor {:row 0 :col 1 :visible true :blinking true})
      (local [term _cleared?] (make-term [[cell cell]] dirty cursor))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 1 1)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 2)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (local initial-batches (ctx:get-triangle-batches))
      (assert (= (# initial-batches) 1))
      (local initial-batch (. initial-batches 1))
      (var initial-count 0)
      (each [_ count (ipairs initial-batch.counts)]
        (set initial-count (+ initial-count count)))
      (mock:reset)
      (set dirty.regions [])
      (renderer:update 0.7)
      (local later-batches (ctx:get-triangle-batches))
      (assert (= (# later-batches) 1))
      (local later-batch (. later-batches 1))
      (var later-count 0)
      (each [_ count (ipairs later-batch.counts)]
        (set later-count (+ later-count count)))
      (assert (< later-count initial-count))
      (local TriangleRenderer (reload "triangle-renderer"))
      (local tri (TriangleRenderer))
      (tri:render ctx.triangle-vector {:projection true} {:view true} later-batches)
      (local draw-calls (mock:get-gl-calls "glMultiDrawArrays"))
      (assert (= (# draw-calls) 1)))))

(fn renders-scrollback-when-offset []
  (with-mock
    (fn [_mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local style (make-style))
      (local history-cell {:codepoint (string.byte "H")
                           :fg-r 0 :fg-g 0 :fg-b 0
                           :bg-r 10 :bg-g 0 :bg-b 0
                           :bold false :underline false :italic false :reverse false})
      (local screen-cell {:codepoint (string.byte "S")
                          :fg-r 0 :fg-g 0 :fg-b 0
                          :bg-r 200 :bg-g 0 :bg-b 0
                          :bold false :underline false :italic false :reverse false})
      (local dirty {:regions []})
      (local scrollback {:lines [[history-cell]] :size 1})
      (local [term _cleared?] (make-term [[screen-cell] [screen-cell]] dirty {:row 0 :col 0 :visible false :blinking false} scrollback))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 1 1)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 2 1)
      (renderer:set-layout layout)
      (renderer:set-scroll-state {:offset 1 :alt-screen? false})
      (renderer:update 0)
      (local handles (renderer:get-handles))
      (local bg-view (ctx.triangle-vector:view handles.background))
      (assert (approx (. bg-view 4) (/ 10 255)))
      (assert (approx (. bg-view (+ 48 4)) (/ 200 255))))))

(fn clears-glyphs-when-cell-becomes-blank []
  (with-mock
    (fn [_mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local style (make-style))
      (local dirty {:regions [{:top 0 :left 0 :bottom 0 :right 0}]})
      (local filled-cell {:codepoint (string.byte "A")
                          :fg-r 255 :fg-g 255 :fg-b 255
                          :bg-r 0 :bg-g 0 :bg-b 0
                          :bold false :underline false :italic false :reverse false})
      (var cells [[filled-cell]])
      (local [term _cleared?] (make-term cells dirty {:row 0 :col 0 :visible true :blinking false}))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 1 1)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 1)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (local handles (renderer:get-handles))
      (local font-vector (. ctx.text-vectors style.font))
      (local glyph-handle (. handles.glyph style.font))
      (local initial-view (font-vector:view glyph-handle))
      (var wrote-glyph? false)
      (for [i 1 (# initial-view)]
        (when (not (approx (. initial-view i) 0))
          (set wrote-glyph? true)))
      (assert wrote-glyph?)
      (tset (. cells 1) 1 blank-cell)
      (set dirty.regions [{:top 0 :left 0 :bottom 0 :right 0}])
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (local cleared-view (font-vector:view glyph-handle))
      (for [i 0 5]
        (local base (* i 10))
        (for [j 0 3]
          (assert (approx (. cleared-view (+ base 5 j)) 0)))))))

(fn renderer-populates-palette-map []
  (with-mock
    (fn [_mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local palette {})
      (local style (make-style))
      (local cell {:codepoint (string.byte "P")
                   :fg-r 10 :fg-g 20 :fg-b 30
                   :bg-r 40 :bg-g 50 :bg-b 60
                   :bold false :underline false :italic false :reverse false})
      (local dirty {:regions [{:top 0 :left 0 :bottom 0 :right 0}]})
      (local [term _cleared?] (make-term [[cell]] dirty {:row 0 :col 0 :visible false :blinking false}))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 1 1) :palette palette}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 1)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (var entries 0)
      (each [_ _ (pairs palette)]
        (set entries (+ entries 1)))
      (assert (= entries 2))
      (assert (. palette "10:20:30"))
      (assert (. palette "40:50:60")))))

(fn terminal-widget-renders-glyphs-into-text-vector []
  (with-mock
    (fn [_mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local font (make-font 123 4))
      (local style (make-style {:font font}))
      (assert style.font "missing font")
      (assert style.font.texture "missing font texture")
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 2 3)}))
      (local layout (make-layout))
      (local term (terminal-native.Terminal 1 1))
      (renderer:set-term term)
      (renderer:set-grid-size 1 1)
      (renderer:set-layout layout)
      (term:inject-output "\27[38;2;80;90;100mG")
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (local handles (renderer:get-handles))
      (local glyph-table (or handles.glyph {}))
      (var glyph-handle (. glyph-table style.font))
      (when (not glyph-handle)
        (each [_ handle (pairs glyph-table)]
          (when (not glyph-handle)
            (set glyph-handle handle))))
      (assert glyph-handle)
      (local vector (ctx:get-text-vector style.font))
      (local view (vector:view glyph-handle))
      (assert (= glyph-handle.size (* 10 6)))
      (assert (> (length view) 0))
      (local r (. view 6))
      (local g (. view 7))
      (local b (. view 8))
      (assert (> r 0) (.. "r=" r " g=" g " b=" b))
      (assert (> g 0) (.. "r=" r " g=" g " b=" b))
      (assert (> b 0) (.. "r=" r " g=" g " b=" b))
      (renderer:drop)
      (term:clear-dirty-regions))))

(table.insert tests {:name "terminal renderer selects fonts for bold and italic cells" :fn uses-font-variants-for-bold-and-italic})
(table.insert tests {:name "terminal renderer repaints dirty cells and uploads GL buffers" :fn renders-dirty-cells-into-buffers})
(table.insert tests {:name "terminal renderer uses font metrics for underline positioning" :fn underline-uses-font-metrics})
(table.insert tests {:name "terminal cursor blink toggles overlay draw" :fn cursor-blink-removes-cursor-handle-when-off})
(table.insert tests {:name "terminal renderer draws scrollback when offset is set" :fn renders-scrollback-when-offset})
(table.insert tests {:name "terminal renderer clears glyphs for blank cells" :fn clears-glyphs-when-cell-becomes-blank})
(table.insert tests {:name "terminal renderer caches colors in provided palette map" :fn renderer-populates-palette-map})
(table.insert tests {:name "terminal widget renders glyphs into tracked text buffer" :fn terminal-widget-renders-glyphs-into-text-vector})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "terminal-renderer"
                       :tests tests})))

{:name "terminal-renderer"
 :tests tests
 :main main}
