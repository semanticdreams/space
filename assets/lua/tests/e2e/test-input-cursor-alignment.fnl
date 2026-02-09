(local Harness (require :tests.e2e.harness))
(local glm (require :glm))
(local {: Layout} (require :layout))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Input (require :input))
(local Sized (require :sized))
(local {: Flex : FlexChild} (require :flex))

(fn cursor-index-for-line-col [model line col]
    (local lines (or model.lines []))
    (var index 0)
    (var i 0)
    (while (< i line)
        (local entry (. lines (+ i 1)))
        (local line-len (length (or (and entry entry.codepoints) [])))
        (local newline-len (or (and entry entry.newline-length) 0))
        (set index (+ index line-len newline-len))
        (set i (+ i 1)))
    (local entry (. lines (+ line 1)))
    (local line-len (length (or (and entry entry.codepoints) [])))
    (local clamped-col (math.max 0 (math.min col line-len)))
    (+ index clamped-col))

(fn make-input-row-builder [entries label-style]
    (fn [entry]
        (fn [ctx]
            (local label ((Text {:text entry.label
                                 :style label-style}) ctx))
            (local input ((Input entry.input-opts) ctx))
            (local input-element
                (if entry.wrap-size
                    ((Sized {:size entry.wrap-size
                             :child (fn [_] input)}) ctx)
                    input))
            (table.insert entries {:label entry.label
                                   :input input
                                   :cursor entry.cursor})
            (local spacing 0.6)

            (fn measurer [self]
                (label.layout:measurer)
                (input-element.layout:measurer)
                (set self.measure
                     (glm.vec3 (+ label.layout.measure.x spacing input-element.layout.measure.x)
                               (math.max label.layout.measure.y input-element.layout.measure.y)
                               0)))

            (fn layouter [self]
                (set self.size self.measure)
                (set label.layout.size label.layout.measure)
                (set label.layout.position self.position)
                (set label.layout.rotation self.rotation)
                (set label.layout.depth-offset-index self.depth-offset-index)
                (set label.layout.clip-region self.clip-region)
                (label.layout:layouter)
                (set input-element.layout.size input-element.layout.measure)
                (set input-element.layout.position
                     (+ self.position
                        (glm.vec3 (+ label.layout.measure.x spacing) 0 0)))
                (set input-element.layout.rotation self.rotation)
                (set input-element.layout.depth-offset-index (+ self.depth-offset-index 1))
                (set input-element.layout.clip-region self.clip-region)
                (input-element.layout:layouter))

            (local layout
                (Layout {:name "input-row"
                         :children [label.layout input-element.layout]
                         :measurer measurer
                         :layouter layouter}))

            (fn drop [self]
                (self.layout:drop)
                (label:drop)
                (input-element:drop))

            {:layout layout :drop drop})))

(fn apply-cursor-state [entry]
    (local input entry.input)
    (local cursor entry.cursor)
    (when (and input cursor)
        (input:set-mode :insert)
        (set input.focused? true)
        (input:update-focus-visual {:mark-layout-dirty? false})
        (local index (cursor-index-for-line-col input.model cursor.line cursor.col))
        (input:move-caret-to index)
        (input:update-caret-visual {:mark-layout-dirty? false})))

(fn run [ctx]
    (local label-style (TextStyle {:scale 1.1}))
    (local entries [])
    (local column-count 18)
    (local single-count 16)
  (local rows
        [{:label "Single: empty line"
          :input-opts {:text ""
                       :column-count single-count}
          :cursor {:line 0 :col 0}}
         {:label "Single: first char"
          :input-opts {:text "ABCDE"
                       :column-count single-count}
          :cursor {:line 0 :col 0}}
         {:label "Single: middle"
          :input-opts {:text "ABCDE"
                       :column-count single-count}
          :cursor {:line 0 :col 2}}
         {:label "Single: last char"
          :input-opts {:text "ABCDE"
                       :column-count single-count}
          :cursor {:line 0 :col 4}}
         {:label "Multi: empty line"
          :input-opts {:text "Line one\n\nLine three"
                       :multiline? true
                       :line-count 3
                       :column-count column-count}
          :cursor {:line 1 :col 0}}
         {:label "Multi: second line"
          :input-opts {:text "Line one\nLine two\nLine three"
                       :multiline? true
                       :line-count 3
                       :column-count column-count}
          :cursor {:line 1 :col 3}}
         {:label "Multi: extra height"
          :input-opts {:text "Line one\nLine two\nLine three"
                       :multiline? true
                       :line-count 3
                       :column-count column-count}
          :wrap-size (glm.vec3 16 6 0)
          :cursor {:line 0 :col 0}}])
    (local row-builder (make-input-row-builder entries label-style))
    (local column-builder
        (Flex {:axis :y
               :yspacing 0.8
               :xalign :start
               :children (icollect [_ entry (ipairs rows)]
                           (FlexChild (row-builder entry) 0))}))

    (local target
        (Harness.make-screen-target {:width ctx.width
                                     :height ctx.height
                                     :world-units-per-pixel ctx.units-per-pixel
                                     :builder column-builder}))

    (each [_ entry (ipairs entries)]
        (apply-cursor-state entry))

    (Harness.draw-targets ctx.width ctx.height [{:target target}])
    (Harness.capture-snapshot {:name "input-cursor-alignment"
                               :width ctx.width
                               :height ctx.height
                               :tolerance 2})
    (Harness.cleanup-target target))

(fn main []
    (Harness.with-app {:width 960 :height 720}
                     (fn [ctx]
                         (run ctx)))
    (print "E2E input cursor alignment snapshot complete"))

{:run run
 :main main}
