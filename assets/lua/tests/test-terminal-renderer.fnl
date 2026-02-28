(local glm (require :glm))
(local _ (require :main))
(local BuildContext (require :build-context))
(local TerminalRenderer (require :terminal-renderer))
(local MockOpenGL (require :mock-opengl))
(local terminal-native (require :terminal))
(local MathUtils (require :math-utils))
(local package package)

(local blank-cell {:codepoint 32
                   :fg-r 255 :fg-g 255 :fg-b 255
                   :bg-r 0 :bg-g 0 :bg-b 0
                   :bold false :underline false :italic false :reverse false})

(local tests [])
(local approx (. MathUtils :approx))

(fn reload [module-name]
  (set (. package.loaded module-name) nil)
  (require module-name))

(fn with-mock [cb]
  (local mock (MockOpenGL))
  (mock:install)
  (local (ok result) (pcall cb mock))
  (mock:restore)
  (if ok
      result
      (error result)))

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
    (set (. font.glyph-map (string.byte "G")) glyph)
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
     :texture {:id id
               :ready true}
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

(fn draw-text-ssbo [ctx projection view]
  (local TextSsboRenderer (reload "text-ssbo-renderer"))
  (local text-ssbo (TextSsboRenderer))
  (local draw-list (ctx:get-text-ssbo-draw-list))
  (each [_ entry (ipairs draw-list)]
    (text-ssbo:render entry.glyph-vector
                      entry.glyph-group-vector
                      entry.group-vector
                      entry.group-clip-index-vector
                      entry.group-depth-index-vector
                      entry.clip-vector
                      entry.font
                      projection
                      view
                      entry.batches)))

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
      (local term-pair (make-term [row] dirty {:row 0 :col 0 :visible false :blinking false}))
      (local term (. term-pair 1))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 1 1)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 4)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (local draw-list (ctx:get-text-ssbo-draw-list))
      (assert (= (# draw-list) 4))
      (local per-font {})
      (each [_ entry (ipairs draw-list)]
        (set (. per-font entry.font) entry))
      (assert (. per-font fonts.regular))
      (assert (. per-font fonts.italic))
      (assert (. per-font fonts.bold))
      (assert (. per-font fonts.bold_italic))
      (each [_ entry (pairs per-font)]
        (assert (= (entry.glyph-group-vector:length) 4))
        (assert (= (entry.glyph-vector:length) (* 4 12)))))))

(fn renders-dirty-cells-into-buffers []
  (with-mock
    (fn [mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local style (make-style))
      (local cell {:codepoint (string.byte "A")
                   :fg-r 10 :fg-g 20 :fg-b 30
                   :bg-r 40 :bg-g 50 :bg-b 60
                   :bold false :underline true :italic false :reverse false})
      (local dirty {:regions [{:top 0 :left 0 :bottom 0 :right 0}]})
      (local term-pair (make-term [[cell]] dirty {:row 0 :col 0 :visible false :blinking false}))
      (local term (. term-pair 1))
      (local cleared? (. term-pair 2))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 2 3)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 1)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (assert (cleared?))
      (local QuadRenderer (reload "quad-renderer"))
      (local quad (QuadRenderer))
      (local quad-draw-list (ctx:get-quad-draw-list))
      (assert (= (# quad-draw-list) 2))
      (each [_ entry (ipairs quad-draw-list)]
        (quad:render entry.vector
                     {:projection true}
                     {:view true}
                     entry.batches
                     entry.clip-vector
                     entry.clip-group-vector))
      (draw-text-ssbo ctx {:projection true} {:view true})
      (local draw-calls (mock:get-gl-calls "glDrawArraysInstanced"))
      (assert (>= (# draw-calls) 3)))))

(fn underline-uses-font-metrics []
  (with-mock
    (fn [mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local metrics {:ascender 12 :descender -3 :lineHeight 20})
      (local font (make-font 9 4 metrics))
      (local style (make-style {:font font}))
      (local cell {:codepoint (string.byte "A")
                   :fg-r 120 :fg-g 10 :fg-b 10
                   :bg-r 0 :bg-g 0 :bg-b 0
                   :bold false :underline true :italic false :reverse false})
      (local dirty {:regions [{:top 0 :left 0 :bottom 0 :right 0}]})
      (local term-pair (make-term [[cell]] dirty {:row 0 :col 0 :visible false :blinking false}))
      (local term (. term-pair 1))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 2 5)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 1)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (local quad-draw-list (ctx:get-quad-draw-list))
      (assert (= (# quad-draw-list) 2))
      (local QuadRenderer (reload "quad-renderer"))
      (local quad (QuadRenderer))
      (each [_ entry (ipairs quad-draw-list)]
        (quad:render entry.vector
                     {:projection true}
                     {:view true}
                     entry.batches
                     entry.clip-vector
                     entry.clip-group-vector))
      (local draw-calls (mock:get-gl-calls "glDrawArraysInstanced"))
      (assert (= (# draw-calls) 2)))))

(fn layout-movement-does-not-repaint-cells []
  (with-mock
    (fn [_mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local style (make-style))
      (local dirty {:regions [{:top 0 :left 0 :bottom 0 :right 0}]})
      (var get-cell-count 0)
      (local term {})
      (set term.get-dirty-regions (fn [] dirty.regions))
      (set term.clear-dirty-regions (fn [] (set dirty.regions [])))
      (set term.get-row (fn [_self _row] []))
      (set term.get-cell
           (fn [_self _row _col]
             (set get-cell-count (+ get-cell-count 1))
             {:codepoint (string.byte "A")
              :fg-r 255 :fg-g 255 :fg-b 255
              :bg-r 0 :bg-g 0 :bg-b 0
              :bold false :underline false :italic false :reverse false}))
      (set term.get-cursor (fn [] {:row 0 :col 0 :visible false :blinking false}))
      (set term.get-size (fn [] {:rows 1 :cols 1}))
      (set term.get-scrollback-size (fn [_] 0))
      (set term.get-scrollback-line (fn [_ _] []))
      (set term.update (fn [_self] nil))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 1 1)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 1)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (local first-read-count get-cell-count)
      (assert (> first-read-count 0))
      (set layout.position (glm.vec3 5 6 0))
      (renderer:set-layout layout)
      (renderer:update 0)
      (assert (= get-cell-count first-read-count))
      (renderer:drop))))

(fn cursor-blink-removes-cursor-handle-when-off []
  (with-mock
    (fn [_mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local style (make-style))
      (local cell {:codepoint (string.byte "B")
                   :fg-r 200 :fg-g 200 :fg-b 200
                   :bg-r 0 :bg-g 0 :bg-b 0
                   :bold false :underline false :italic false :reverse false})
      (var dirty {:regions [{:top 0 :left 0 :bottom 0 :right 1}]})
      (local cursor {:row 0 :col 1 :visible true :blinking true})
      (local term-pair (make-term [[cell cell]] dirty cursor))
      (local term (. term-pair 1))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 1 1)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 2)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (local initial-draw-list (ctx:get-quad-draw-list))
      (assert (= (# initial-draw-list) 3))
      (set dirty.regions [])
      (renderer:update 0.7)
      (local later-draw-list (ctx:get-quad-draw-list))
      (assert (= (# later-draw-list) 2)))))

(fn renders-scrollback-when-offset []
  (with-mock
    (fn [mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local style (make-style))
      (local history-cell {:codepoint (string.byte "A")
                           :fg-r 0 :fg-g 0 :fg-b 0
                           :bg-r 10 :bg-g 0 :bg-b 0
                           :bold false :underline false :italic false :reverse false})
      (local screen-cell {:codepoint (string.byte "B")
                          :fg-r 0 :fg-g 0 :fg-b 0
                          :bg-r 200 :bg-g 0 :bg-b 0
                          :bold false :underline false :italic false :reverse false})
      (local dirty {:regions []})
      (local scrollback {:lines [[history-cell]] :size 1})
      (local term-pair (make-term [[screen-cell] [screen-cell]]
                                   dirty
                                   {:row 0 :col 0 :visible false :blinking false}
                                   scrollback))
      (local term (. term-pair 1))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 1 1)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 2 1)
      (renderer:set-layout layout)
      (renderer:set-scroll-state {:offset 1 :alt-screen? false})
      (renderer:update 0)
      (local quad-draw-list (ctx:get-quad-draw-list))
      (assert (= (# quad-draw-list) 2))
      (local QuadRenderer (reload "quad-renderer"))
      (local quad (QuadRenderer))
      (each [_ entry (ipairs quad-draw-list)]
        (quad:render entry.vector
                     {:projection true}
                     {:view true}
                     entry.batches
                     entry.clip-vector
                     entry.clip-group-vector))
      (local draw-calls (mock:get-gl-calls "glDrawArraysInstanced"))
      (assert (= (# draw-calls) 2)))))

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
      (local term-pair (make-term cells dirty {:row 0 :col 0 :visible true :blinking false}))
      (local term (. term-pair 1))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 1 1)}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 1)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (assert (> (# (ctx:get-text-ssbo-draw-list)) 0))
      (tset (. cells 1) 1 blank-cell)
      (set dirty.regions [{:top 0 :left 0 :bottom 0 :right 0}])
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (assert (= (# (ctx:get-text-ssbo-draw-list)) 0)))))

(fn renderer-populates-palette-map []
  (with-mock
    (fn [_mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local palette {})
      (local style (make-style))
      (local cell {:codepoint (string.byte "A")
                   :fg-r 10 :fg-g 20 :fg-b 30
                   :bg-r 40 :bg-g 50 :bg-b 60
                   :bold false :underline false :italic false :reverse false})
      (local dirty {:regions [{:top 0 :left 0 :bottom 0 :right 0}]})
      (local term-pair (make-term [[cell]] dirty {:row 0 :col 0 :visible false :blinking false}))
      (local term (. term-pair 1))
      (local renderer (TerminalRenderer {:ctx ctx :style style :cell-size (glm.vec2 1 1) :palette palette}))
      (local layout (make-layout))
      (renderer:set-term term)
      (renderer:set-grid-size 1 1)
      (renderer:set-layout layout)
      (renderer:mark-dirty {:full? true})
      (renderer:update 0)
      (assert (. palette "10:20:30"))
      (assert (. palette "40:50:60")))))

(fn terminal-widget-renders-glyphs-into-text-ssbo-source []
  (with-mock
    (fn [_mock]
      (local ctx (BuildContext {:theme (app.themes.get-active-theme)}))
      (local font (make-font 123 4))
      (local style (make-style {:font font}))
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
      (assert (= handles.glyph-count 1))
      (local draw-list (ctx:get-text-ssbo-draw-list))
      (assert (= (# draw-list) 1))
      (local entry (. draw-list 1))
      (assert (= entry.font style.font))
      (assert (>= (entry.glyph-vector:length) 12))
      (renderer:drop)
      (term:clear-dirty-regions))))

(table.insert tests {:name "terminal renderer selects fonts for bold and italic cells"
                     :fn uses-font-variants-for-bold-and-italic})
(table.insert tests {:name "terminal renderer repaints dirty cells and uploads GL buffers"
                     :fn renders-dirty-cells-into-buffers})
(table.insert tests {:name "terminal renderer uses font metrics for underline positioning"
                     :fn underline-uses-font-metrics})
(table.insert tests {:name "terminal renderer movement updates transform without repainting cells"
                     :fn layout-movement-does-not-repaint-cells})
(table.insert tests {:name "terminal cursor blink toggles overlay draw"
                     :fn cursor-blink-removes-cursor-handle-when-off})
(table.insert tests {:name "terminal renderer draws scrollback when offset is set"
                     :fn renders-scrollback-when-offset})
(table.insert tests {:name "terminal renderer clears glyphs for blank cells"
                     :fn clears-glyphs-when-cell-becomes-blank})
(table.insert tests {:name "terminal renderer caches colors in provided palette map"
                     :fn renderer-populates-palette-map})
(table.insert tests {:name "terminal widget renders glyphs into text ssbo draw source"
                     :fn terminal-widget-renders-glyphs-into-text-ssbo-source})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "terminal-renderer"
                       :tests tests})))

{:name "terminal-renderer"
 :tests tests
 :main main}
