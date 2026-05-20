(local glm (require :glm))
(local WrappedText (require :wrapped-text))
(local MathUtils (require :math-utils))

(local tests [])
(local approx (. MathUtils :approx))

(fn make-test-font []
  {:metadata {:metrics {:ascender 1.0
                        :descender 0.0
                        :lineHeight 2.0}
              :atlas {:width 1 :height 1}}
   :glyph-map {32 {:advance 0.5}
               65 {:advance 1.0}
               65533 {:advance 1.0}}})

(fn make-text-style [font]
  {:font font
   :scale 1.0
   :color (glm.vec4 1 1 1 1)})

(fn make-text-context []
  (local batcher {})
  (set batcher.upsert-text (fn [_self _key _payload] nil))
  (set batcher.update-text-transform (fn [_self _key _payload] nil))
  (set batcher.remove-text (fn [_self _key] nil))
  {:get-text-ssbo-batcher (fn [_self] batcher)})

(fn count-newlines [codepoints]
  (var count 0)
  (local newline (string.byte "\n"))
  (each [_ codepoint (ipairs codepoints)]
    (when (= codepoint newline)
      (set count (+ count 1))))
  count)

(fn wrapped-text-remeasures-for-constrained-width []
  (local font (make-test-font))
  (local style (make-text-style font))
  (local text ((WrappedText {:text "AA AA AA"
                             :style style})
               (make-text-context)))
  (text.layout:measurer)
  (assert (approx text.layout.measure.x 7.0))
  (assert (approx text.layout.measure.y 2.0))

  (text.layout:measure-constrained {:max (glm.vec3 4.5 100000 0)})
  (assert (approx text.layout.measure.x 4.5))
  (assert (approx text.layout.measure.y 4.0))
  (assert (= (count-newlines (text:get-wrapped-codepoints)) 1))

  (text.layout:measure-constrained {:max (glm.vec3 10 100000 0)})
  (assert (approx text.layout.measure.x 7.0))
  (assert (approx text.layout.measure.y 2.0))
  (text:drop))

(fn wrapped-text-hard-wraps-long-words []
  (local font (make-test-font))
  (local style (make-text-style font))
  (local text ((WrappedText {:text "AAAAA"
                             :style style})
               (make-text-context)))
  (text.layout:measure-constrained {:max (glm.vec3 2 100000 0)})
  (assert (approx text.layout.measure.x 2.0))
  (assert (approx text.layout.measure.y 6.0))
  (assert (= (count-newlines (text:get-wrapped-codepoints)) 2))
  (text:drop))

(fn wrapped-text-preserves-unwrapped-spaces []
  (local font (make-test-font))
  (local style (make-text-style font))
  (local text ((WrappedText {:text "A  A"
                             :style style})
               (make-text-context)))
  (text.layout:measure-constrained {:max (glm.vec3 10 100000 0)})
  (local codepoints (text:get-wrapped-codepoints))
  (assert (= (length codepoints) 4))
  (assert (= (. codepoints 2) (string.byte " ")))
  (assert (= (. codepoints 3) (string.byte " ")))
  (text:drop))

(fn wrapped-text-treats-crlf-as-single-line-break []
  (local font (make-test-font))
  (local style (make-text-style font))
  (local text ((WrappedText {:text "A\r\nA"
                             :style style})
               (make-text-context)))
  (text.layout:measure-constrained {:max (glm.vec3 10 100000 0)})
  (assert (= (count-newlines (text:get-wrapped-codepoints)) 1))
  (assert (approx text.layout.measure.y 4.0))
  (text:drop))

(fn wrapped-text-zero-width-does-not-error []
  (local font (make-test-font))
  (local style (make-text-style font))
  (local text ((WrappedText {:text "AA"
                             :style style})
               (make-text-context)))
  (text.layout:measure-constrained {:max (glm.vec3 0 100000 0)})
  (assert (approx text.layout.measure.x 0))
  (assert (> text.layout.measure.y 0))
  (text:drop))

(table.insert tests {:name "WrappedText remeasures for constrained width"
                     :fn wrapped-text-remeasures-for-constrained-width})
(table.insert tests {:name "WrappedText hard-wraps long words"
                     :fn wrapped-text-hard-wraps-long-words})
(table.insert tests {:name "WrappedText preserves unwrapped spaces"
                     :fn wrapped-text-preserves-unwrapped-spaces})
(table.insert tests {:name "WrappedText treats CRLF as single line break"
                     :fn wrapped-text-treats-crlf-as-single-line-break})
(table.insert tests {:name "WrappedText zero width does not error"
                     :fn wrapped-text-zero-width-does-not-error})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "wrapped-text"
                       :tests tests})))

{:name "wrapped-text"
 :tests tests
 :main main}
