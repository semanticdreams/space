(local Harness (require :tests.e2e.harness))
(local glm (require :glm))
(local {: Layout} (require :layout))
(local TerminalRenderer (require :terminal-renderer))
(local {: resolve-style
        : fallback-glyph
        : line-height} (require :text-utils))

(fn make-cell [codepoint]
  {:codepoint codepoint
   :fg-r 220 :fg-g 230 :fg-b 255
   :bg-r 14 :bg-g 18 :bg-b 26
   :bold false :underline false :italic false :reverse false})

(fn make-row [text cols]
  (local row [])
  (for [col 0 (- cols 1)]
    (local codepoint
      (if (< col (length text))
          (string.byte (string.sub text (+ col 1) (+ col 1)))
          32))
    (table.insert row (make-cell codepoint)))
  row)

(local transcript-lines
  ["user@demo:~/space$ pwd"
   "/repo/space"
   "user@demo:~/space$ ls -1 | head -5"
   "assets"
   "build"
   "docs"
   "scripts"
   "src"
   "user@demo:~/space$ echo performance-ok"
   "performance-ok"
   "user@demo:~/space$"])

(fn make-term [rows cols]
  (local lines [])
  (for [row 1 rows]
    (local text (or (. transcript-lines row) ""))
    (table.insert lines (make-row text cols)))
  (local prompt-line (or (. transcript-lines rows) ""))
  (local cursor-col (math.min (- cols 1) (length prompt-line)))
  (var dirty [{:top 0 :left 0 :bottom (- rows 1) :right (- cols 1)}])
  (local term {})
  (set term.get-dirty-regions (fn [] dirty))
  (set term.clear-dirty-regions (fn [] (set dirty [])))
  (set term.get-row
       (fn [_self row]
         (or (. lines (+ row 1)) [])))
  (set term.get-cell
       (fn [_self row col]
         (or (and (. lines (+ row 1))
                  (. (. lines (+ row 1)) (+ col 1)))
             (make-cell 32))))
  (set term.get-cursor (fn [] {:row (- rows 1) :col cursor-col :visible true :blinking false}))
  (set term.get-size (fn [] {:rows rows :cols cols}))
  (set term.get-scrollback-size (fn [_] 0))
  (set term.get-scrollback-line (fn [_ _] []))
  (set term.update (fn [_self] nil))
  term)

(fn make-widget-builder []
  (fn [ctx]
    (local rows 11)
    (local cols 56)
    (local style (resolve-style ctx {}))
    (local space-glyph (fallback-glyph style.font 32))
    (local cell-size (glm.vec2 (* (or (and space-glyph space-glyph.advance) 1.0) style.scale)
                               (line-height style)))
    (local renderer (TerminalRenderer {:ctx ctx
                                       :style style
                                       :cell-size cell-size}))
    (local term (make-term rows cols))
    (renderer:set-term term)
    (renderer:set-grid-size rows cols)

    (local measurer
      (fn [self]
        (set self.measure (glm.vec3 (* cols cell-size.x)
                                    (* rows cell-size.y)
                                    0))))

    (local layouter
      (fn [self]
        (set self.size (or self.size self.measure))
        (renderer:set-layout self)))

    (local layout (Layout {:name "terminal-renderer-transform-e2e"
                           :measurer measurer
                           :layouter layouter}))
    (renderer:set-layout layout)

    {:layout layout
     :renderer renderer
     :term term
     :update (fn [_self delta]
               (term:update)
               (renderer:update delta))
     :drop (fn [self]
             (self.renderer:drop)
             (self.layout:drop))}))

(fn run [ctx]
  (local target
    (Harness.make-screen-target {:width ctx.width
                                 :height ctx.height
                                 :world-units-per-pixel ctx.units-per-pixel
                                 :builder (make-widget-builder)}))
  (when (and target.element target.element.update)
    (target.element:update 0))
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (local root-layout target.root-layout)
  (root-layout:set-position (+ root-layout.position (glm.vec3 2.2 0.8 0)))
  (when (and target.element target.element.update)
    (target.element:update 0))
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (Harness.capture-snapshot {:name "terminal-renderer-transform"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E terminal renderer transform snapshot complete"))

{:run run
 :main main}
