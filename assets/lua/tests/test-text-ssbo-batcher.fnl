(local TextSsboBatcher (require :text-ssbo-batcher))
(local glm (require :glm))

(local tests [])

(fn make-font []
  {:metadata {:atlas {:distanceRange 3.5
                      :width 512
                      :height 512}
              :metrics {:ascender 1.0
                        :lineHeight 1.2}}
   :texture {:id 1 :ready true}
   :glyph-map {(string.byte "A") {:planeBounds {:left 0 :right 0.6 :bottom -0.2 :top 0.8}
                                  :atlasBounds {:left 0 :right 60 :bottom 0 :top 80}
                                  :advance 0.65}
               (string.byte "B") {:planeBounds {:left 0 :right 0.7 :bottom -0.2 :top 0.8}
                                  :atlasBounds {:left 60 :right 130 :bottom 0 :top 80}
                                  :advance 0.72}
               65533 {:planeBounds {:left 0 :right 0.5 :bottom -0.2 :top 0.8}
                      :atlasBounds {:left 130 :right 180 :bottom 0 :top 80}
                      :advance 0.6}}})

(fn text-ssbo-batcher-builds-shared-buffers-per-font []
  (local font (make-font))
  (local batcher (TextSsboBatcher {}))
  (batcher:add-text {:font font
                     :text "AB"
                     :x 2
                     :y 4})
  (batcher:add-text {:font font
                     :text "BA"
                     :x 8
                     :y 1
                     :clip {:bounds {:position (glm.vec3 0 0 0)
                                     :size (glm.vec3 10 10 0.1)}}})
  (local draws (batcher:get-draw-list))
  (assert (= (# draws) 1))
  (local entry (. draws 1))
  (assert (= entry.font font))
  ;; 4 glyph instances, each 12 floats
  (assert (= (entry.glyph-vector:length) 48))
  ;; 4 glyph group indices
  (assert (= (entry.glyph-group-vector:length) 4))
  ;; 2 group matrices
  (assert (= (entry.group-vector:length) 32))
  ;; two unique clip matrices (no-clip + explicit clip)
  (assert (or (= (entry.clip-vector:length) 16)
              (= (entry.clip-vector:length) 32)))
  ;; 2 group->clip index entries
  (assert (= (entry.group-clip-index-vector:length) 2))
  ;; 2 group depth-offset index entries
  (assert (= (entry.group-depth-index-vector:length) 2))
  ;; clip is handled per-group; draws stay contiguous
  (assert (= (# entry.batches) 1)))

(fn text-ssbo-batcher-render-delegates-entries []
  (local font (make-font))
  (local batcher (TextSsboBatcher {}))
  (batcher:add-text {:font font :text "AB"})
  (var calls 0)
  (local renderer
    {:render (fn [_self glyph-vector glyph-group-vector group-vector group-clip-index-vector group-depth-index-vector clip-vector passed-font projection view batches]
               (set calls (+ calls 1))
               (assert (> (glyph-vector:length) 0))
               (assert (> (glyph-group-vector:length) 0))
               (assert (> (group-vector:length) 0))
               (assert (> (group-clip-index-vector:length) 0))
               (assert (> (group-depth-index-vector:length) 0))
               (assert (> (clip-vector:length) 0))
               (assert (= passed-font font))
               (assert projection)
               (assert view)
               (assert (> (# batches) 0)))})
  (batcher:render renderer {:projection true} {:view true})
  (assert (= calls 1)))

(fn text-ssbo-batcher-clear-drops-active-data []
  (local font (make-font))
  (local batcher (TextSsboBatcher {}))
  (batcher:add-text {:font font :text "AB"})
  (assert (= (# (batcher:get-draw-list)) 1))
  (batcher:clear)
  (assert (= (# (batcher:get-draw-list)) 0)))

(fn text-ssbo-batcher-keyed-upsert-updates-existing-entry []
  (local font (make-font))
  (local batcher (TextSsboBatcher {}))
  (batcher:begin-frame)
  (batcher:upsert-text :row-1 {:font font :text "AB"})
  (batcher:end-frame)
  (local first (batcher:get-last-stats))
  (assert (> first.write-count 0))
  (assert (= first.upsert-count 1))

  (batcher:begin-frame)
  (batcher:upsert-text :row-1 {:font font :text "AB"})
  (batcher:end-frame)
  (local second (batcher:get-last-stats))
  (assert (= second.write-count 0))
  (assert (= second.upsert-count 1))
  (local draws (batcher:get-draw-list))
  (local entry (. draws 1))
  (assert (= (# draws) 1))
  (assert (= (entry.glyph-group-vector:length) 2)))

(fn text-ssbo-batcher-dedups-identical-clip-matrices []
  (local font (make-font))
  (local batcher (TextSsboBatcher {}))
  (local clip
    [1 0 0 0
     0 1 0 0
     0 0 1 0
     2 3 0 1])
  (batcher:begin-frame)
  (batcher:upsert-text :a {:font font :text "AB" :clip-matrix clip})
  (batcher:upsert-text :b {:font font :text "BA" :clip-matrix clip})
  (batcher:end-frame)
  (local draws (batcher:get-draw-list))
  (assert (= (# draws) 1))
  (local entry (. draws 1))
  (assert (= (entry.clip-vector:length) 16)
          "identical clip matrices should be deduped"))

(fn text-ssbo-batcher-remove-text-hides-entry []
  (local font (make-font))
  (local batcher (TextSsboBatcher {}))
  (batcher:begin-frame)
  (batcher:upsert-text :row-1 {:font font :text "AB"})
  (batcher:end-frame)
  (assert (= (# (batcher:get-draw-list)) 1))
  (batcher:remove-text :row-1)
  (assert (= (# (batcher:get-draw-list)) 0)))

(fn text-ssbo-batcher-reuses-pooled-handles-after-remove []
  (local font (make-font))
  (local batcher (TextSsboBatcher {}))
  (batcher:begin-frame)
  (batcher:upsert-text :a {:font font :text "AB"})
  (batcher:end-frame)
  (local entry-a (. (batcher:get-draw-list) 1))
  (local first-length (entry-a.glyph-vector:length))
  (batcher:remove-text :a)
  (batcher:begin-frame)
  (batcher:upsert-text :b {:font font :text "AB"})
  (batcher:end-frame)
  (local entry-b (. (batcher:get-draw-list) 1))
  (assert (= (entry-b.glyph-vector:length) first-length)
          "pooled handles should prevent vector growth for same capacity"))

(fn text-ssbo-batcher-updates-dirty-subrange-for-content-edits []
  (local font (make-font))
  (local batcher (TextSsboBatcher {}))
  (batcher:begin-frame)
  (batcher:upsert-text :row-1 {:font font :text "AB"})
  (batcher:end-frame)

  (batcher:begin-frame)
  (batcher:upsert-text :row-1 {:font font :text "AA"})
  (batcher:end-frame)
  (local edited (batcher:get-last-stats))
  (assert (> edited.glyph-write-count 0))
  (assert (< edited.glyph-write-count 24)
          "single glyph edit should not rewrite full 2-glyph payload"))

(fn text-ssbo-batcher-uses-multi-span-diffs-for-disjoint-edits []
  (local font (make-font))
  ;; Add a glyph variant with same advance as A so distant edits stay disjoint.
  (set (. font.glyph-map (string.byte "C"))
       {:planeBounds {:left 0 :right 0.6 :bottom -0.2 :top 0.8}
        :atlasBounds {:left 180 :right 240 :bottom 0 :top 80}
        :advance 0.65})

  (local batcher (TextSsboBatcher {}))
  (batcher:begin-frame)
  (batcher:upsert-text :row-1 {:font font :text "ABBA"})
  (batcher:end-frame)

  (batcher:begin-frame)
  (batcher:upsert-text :row-1 {:font font :text "CBBC"})
  (batcher:end-frame)
  (local edited (batcher:get-last-stats))
  ;; Only UV fields change for first/last glyphs, so writes should stay very small.
  (assert (> edited.glyph-write-count 0))
  (assert (<= edited.glyph-write-count 8))
  ;; Old one-span diff would upload from first changed float to last changed float:
  ;; index 5 (glyph1 UV) .. index 43 (glyph4 UV) => 39 floats.
  (assert (< edited.glyph-write-count 39)))

(table.insert tests {:name "TextSsboBatcher builds shared buffers per font"
                     :fn text-ssbo-batcher-builds-shared-buffers-per-font})
(table.insert tests {:name "TextSsboBatcher render delegates entries"
                     :fn text-ssbo-batcher-render-delegates-entries})
(table.insert tests {:name "TextSsboBatcher clear drops active data"
                     :fn text-ssbo-batcher-clear-drops-active-data})
(table.insert tests {:name "TextSsboBatcher keyed upsert updates existing entry"
                     :fn text-ssbo-batcher-keyed-upsert-updates-existing-entry})
(table.insert tests {:name "TextSsboBatcher dedups identical clip matrices"
                     :fn text-ssbo-batcher-dedups-identical-clip-matrices})
(table.insert tests {:name "TextSsboBatcher remove-text hides entry"
                     :fn text-ssbo-batcher-remove-text-hides-entry})
(table.insert tests {:name "TextSsboBatcher reuses pooled handles after remove"
                     :fn text-ssbo-batcher-reuses-pooled-handles-after-remove})
(table.insert tests {:name "TextSsboBatcher updates dirty subrange for content edits"
                     :fn text-ssbo-batcher-updates-dirty-subrange-for-content-edits})
(table.insert tests {:name "TextSsboBatcher uses multi-span diffs for disjoint edits"
                     :fn text-ssbo-batcher-uses-multi-span-diffs-for-disjoint-edits})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "text-ssbo-batcher"
                       :tests tests})))

{:name "text-ssbo-batcher"
 :tests tests
 :main main}
