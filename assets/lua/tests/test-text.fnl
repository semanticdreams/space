(local glm (require :glm))
(local Text (require :text))
(local MathUtils (require :math-utils))

(local tests [])

(local {:VectorBuffer VectorBuffer :VectorHandle VectorHandle} (require :vector-buffer))
(local approx (. MathUtils :approx))

(fn make-test-font []
  (local atlas {:width 100
                :height 50})
  {:metadata {:metrics {:ascender 1.5
                        :descender -0.5
                        :lineHeight 2.5}
              :atlas atlas}
   :glyph-map {65 {:advance 1.0
                   :planeBounds {:left -0.25 :right 0.75 :bottom -0.5 :top 0.5}
                   :atlasBounds {:left 10 :right 30 :bottom 5 :top 25}}
               66 {:advance 1.5
                   :planeBounds {:left -0.5 :right 0.5 :bottom -1.0 :top 0.0}
                   :atlasBounds {:left 40 :right 60 :bottom 10 :top 20}}
               65533 {:advance 0.5
                      :planeBounds {:left 0.0 :right 0.25 :bottom 0.0 :top 0.5}
                      :atlasBounds {:left 70 :right 80 :bottom 15 :top 35}}}})

(fn make-text-style [font scale]
  {:font font
   :scale (or scale 1.0)
   :color (glm.vec4 0.25 0.5 0.75 1.0)})

(fn make-text-context []
  (local vector (VectorBuffer))
  (local state {:track-count 0
                :untrack-count 0
                :last-font nil
                :last-handle nil
                :last-clip nil
                :last-untracked nil})
  (local ctx {})
  (set ctx.get-text-vector (fn [_self _font] vector))
  (set ctx.track-text-handle
       (fn [_self font handle clip-region]
         (set state.track-count (+ state.track-count 1))
         (set state.last-font font)
         (set state.last-handle handle)
         (set state.last-clip clip-region)))
  (set ctx.untrack-text-handle
       (fn [_self font handle]
         (set state.untrack-count (+ state.untrack-count 1))
         (set state.last-untracked {:font font :handle handle})))
  {:ctx ctx :vector vector :state state})

(fn measurer-uses-glyph-advances []
  (local font (make-test-font))
  (local style (make-text-style font 1.25))
  (local builder-state (make-text-context))
  (local text ((Text {:style style :text "A?"}) builder-state.ctx))
  (text.layout:measurer)
  (local codepoints (text:get-codepoints))
  (assert (= (# codepoints) 2))
  (assert (= (. codepoints 1) (string.byte "A")))
  (assert (= (. codepoints 2) (string.byte "?")))
  (local glyph (. font.glyph-map 65))
  (local fallback (. font.glyph-map 65533))
  (local expected-width (* style.scale (+ glyph.advance fallback.advance)))
  (assert (approx text.layout.measure.x expected-width))
  (local metrics font.metadata.metrics)
  (local expected-height (* style.scale metrics.lineHeight))
  (assert (approx text.layout.measure.y expected-height))
  (text:drop))

(fn vertex-base [glyph-index vertex-index]
  (+ 1 (* 60 (- glyph-index 1)) (* 10 (- vertex-index 1))))

(fn layouter-writes-glyph-quads-and-untracks-when-culled []
  (local font (make-test-font))
  (local style (make-text-style font 1.0))
  (local builder-state (make-text-context))
  (local clip-region {:name :test-clip})
  (local text ((Text {:style style :codepoints [65 66]}) builder-state.ctx))
  (set text.layout.position (glm.vec3 1 2 0.5))
  (set text.layout.rotation (glm.quat 1 0 0 0))
  (set text.layout.depth-offset-index 2.0)
  (set text.layout.clip-region clip-region)
  (text.layout:measurer)
  (local original-compute text.layout.compute-clip-visibility)
  (var force-culled false)
  (set text.layout.compute-clip-visibility
       (fn [self]
         (if force-culled :outside (original-compute self))))
  (text.layout:layouter)
  (assert (= builder-state.state.track-count 1))
  (assert (= builder-state.state.last-font font))
  (assert (= builder-state.state.last-clip clip-region))
  (local handle builder-state.state.last-handle)
  (assert handle)
  (local data (builder-state.vector:view handle))
  (assert (= (# data) (* 60 2)))
  (local first-base (vertex-base 1 1))
  (assert (approx (. data first-base) 0.75))
  (local metrics font.metadata.metrics)
  (local ascender (* style.scale metrics.ascender))
  (local measured-height text.layout.measure.y)
  (local baseline (- measured-height ascender))
  (local glyph (. font.glyph-map 65))
  (local first-bottom
    (+ text.layout.position.y
       baseline
       (* glyph.planeBounds.bottom style.scale)))
  (assert (approx (. data (+ first-base 1)) first-bottom))
  (assert (approx (. data (+ first-base 2)) 0.5))
  (assert (approx (. data (+ first-base 3)) 0.1))
  (assert (approx (. data (+ first-base 4)) 0.1))
  (assert (approx (. data (+ first-base 5)) 0.25))
  (assert (approx (. data (+ first-base 6)) 0.5))
  (assert (approx (. data (+ first-base 7)) 0.75))
  (assert (approx (. data (+ first-base 8)) 1.0))
  (assert (approx (. data (+ first-base 9)) 2.0))
  (local second-base (vertex-base 2 1))
  (assert (approx (. data second-base) 1.5))
  (local glyph-b (. font.glyph-map 66))
  (local second-bottom
    (+ text.layout.position.y
       baseline
       (* glyph-b.planeBounds.bottom style.scale)))
  (assert (approx (. data (+ second-base 1)) second-bottom))
  (assert (approx (. data (+ second-base 2)) 0.5))
  (assert (approx (. data (+ second-base 3)) 0.4))
  (assert (approx (. data (+ second-base 4)) 0.2))
  (assert (approx (. data (+ second-base 5)) 0.25))
  (assert (approx (. data (+ second-base 6)) 0.5))
  (assert (approx (. data (+ second-base 7)) 0.75))
  (assert (approx (. data (+ second-base 8)) 1.0))
  (assert (approx (. data (+ second-base 9)) 2.0))
  (set force-culled true)
  (text.layout:layouter)
  (assert (= builder-state.state.untrack-count 1))
  (assert (= builder-state.state.last-untracked.handle handle))
  (text:drop))

(fn measurer-supports-multi-line-text []
  (local font (make-test-font))
  (local style (make-text-style font 1.0))
  (local builder-state (make-text-context))
  (local text ((Text {:style style :text "AB\nA"}) builder-state.ctx))
  (text.layout:measurer)
  (local glyph-a (. font.glyph-map 65))
  (local glyph-b (. font.glyph-map 66))
  (local metrics font.metadata.metrics)
  (local expected-width (* style.scale (+ glyph-a.advance glyph-b.advance)))
  (local expected-height (* style.scale metrics.lineHeight 2))
  (assert (approx text.layout.measure.x expected-width))
  (assert (approx text.layout.measure.y expected-height))
  (text:drop))

(fn layouter-stacks-lines-downward []
  (local font (make-test-font))
  (local style (make-text-style font 1.0))
  (local builder-state (make-text-context))
  (local text ((Text {:style style :text "A\nB"}) builder-state.ctx))
  (set text.layout.position (glm.vec3 0 0 0))
  (set text.layout.rotation (glm.quat 1 0 0 0))
  (text.layout:measurer)
  (text.layout:layouter)
  (local handle builder-state.state.last-handle)
  (local data (builder-state.vector:view handle))
  (local glyph-a (. font.glyph-map 65))
  (local glyph-b (. font.glyph-map 66))
  (local metrics font.metadata.metrics)
  (local line-height (* style.scale metrics.lineHeight))
  (local ascender (* style.scale metrics.ascender))
  (local measured-height text.layout.measure.y)
  (local first-baseline (- measured-height ascender))
  (local first-line-y (. data (+ (vertex-base 1 1) 1)))
  (local second-line-y (. data (+ (vertex-base 2 1) 1)))
  (local expected-first
    (+ first-baseline (* glyph-a.planeBounds.bottom style.scale)))
  (local expected-second
    (+ (- first-baseline line-height)
       (* glyph-b.planeBounds.bottom style.scale)))
  (assert (approx first-line-y expected-first))
  (assert (approx second-line-y expected-second))
  (text:drop))

(table.insert tests {:name "Text measurer respects glyph advances" :fn measurer-uses-glyph-advances})
(table.insert tests {:name "Text layouter populates glyph quads and untracks on cull" :fn layouter-writes-glyph-quads-and-untracks-when-culled})
(table.insert tests {:name "Text measurer supports multi-line layout" :fn measurer-supports-multi-line-text})
(table.insert tests {:name "Text layouter stacks lines downward" :fn layouter-stacks-lines-downward})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "text"
                       :tests tests})))

{:name "text"
 :tests tests
 :main main}
