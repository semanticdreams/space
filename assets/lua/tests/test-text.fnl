(local glm (require :glm))
(local Text (require :text))
(local MathUtils (require :math-utils))

(local tests [])
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
  (local state {:upsert-count 0
                :update-count 0
                :remove-count 0
                :last-upsert nil
                :last-update nil
                :last-remove nil})
  (local batcher {})
  (set batcher.upsert-text
       (fn [_self key payload]
         (set state.upsert-count (+ state.upsert-count 1))
         (set state.last-upsert {:key key :payload payload})))
  (set batcher.update-text-transform
       (fn [_self key payload]
         (set state.update-count (+ state.update-count 1))
         (set state.last-update {:key key :payload payload})))
  (set batcher.remove-text
       (fn [_self key]
         (set state.remove-count (+ state.remove-count 1))
         (set state.last-remove key)))
  {:ctx {:get-text-ssbo-batcher (fn [_self] batcher)}
   :state state})

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

(fn layouter-upserts-ssbo-and-removes-when-culled []
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
  (set text.layout.size text.layout.measure)
  (local original-compute text.layout.compute-clip-visibility)
  (var force-culled false)
  (set text.layout.compute-clip-visibility
       (fn [self]
         (if force-culled :outside (original-compute self))))

  (text.layout:layouter)
  (assert (= builder-state.state.upsert-count 1))
  (assert (= builder-state.state.update-count 0))
  (local first-upsert builder-state.state.last-upsert)
  (assert first-upsert)
  (assert (= (. first-upsert.payload :font) font))
  (assert (= (. first-upsert.payload :clip) clip-region))
  (assert (= (. first-upsert.payload :depth-offset-index) 3.0))
  (assert (glm.is-mat4 (. first-upsert.payload :group-matrix)))

  (text.layout:layouter)
  (assert (= builder-state.state.upsert-count 1))
  (assert (= builder-state.state.update-count 1))
  (local update builder-state.state.last-update)
  (assert update)
  (assert (= (. update.payload :clip) clip-region))
  (assert (= (. update.payload :depth-offset-index) 3.0))
  (assert (glm.is-mat4 (. update.payload :group-matrix)))

  (text:set-text "B")
  (text.layout:measurer)
  (set text.layout.size text.layout.measure)
  (text.layout:layouter)
  (assert (= builder-state.state.upsert-count 2)
          "changing text should issue a fresh upsert")

  (set force-culled true)
  (text.layout:layouter)
  (assert (= builder-state.state.remove-count 1))
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

(fn layouter-skips-empty-text []
  (local font (make-test-font))
  (local style (make-text-style font 1.0))
  (local builder-state (make-text-context))
  (local text ((Text {:style style :text ""}) builder-state.ctx))
  (text.layout:measurer)
  (set text.layout.size text.layout.measure)
  (text.layout:layouter)
  (assert (= builder-state.state.upsert-count 0))
  (assert (= builder-state.state.remove-count 1))
  (text:drop))

(table.insert tests {:name "Text measurer respects glyph advances" :fn measurer-uses-glyph-advances})
(table.insert tests {:name "Text layouter emits SSBO updates and removes when culled"
                     :fn layouter-upserts-ssbo-and-removes-when-culled})
(table.insert tests {:name "Text measurer supports multi-line layout" :fn measurer-supports-multi-line-text})
(table.insert tests {:name "Text layouter skips empty text" :fn layouter-skips-empty-text})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "text"
                       :tests tests})))

{:name "text"
 :tests tests
 :main main}
