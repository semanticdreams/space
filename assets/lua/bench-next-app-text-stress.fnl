(local os os)
(local string string)
(local TextSsboBatcher (require :text-ssbo-batcher))

(fn make-bench-font []
  {:metadata {:atlas {:distanceRange 3.5
                      :width 512
                      :height 512}
              :metrics {:ascender 1.0
                        :lineHeight 1.2}}
   :texture {:id 1 :ready true}
   :glyph-map {32 {:planeBounds {:left 0 :right 0.4 :bottom -0.2 :top 0.8}
                   :atlasBounds {:left 0 :right 40 :bottom 0 :top 80}
                   :advance 0.42}
               65 {:planeBounds {:left 0 :right 0.58 :bottom -0.2 :top 0.8}
                   :atlasBounds {:left 40 :right 98 :bottom 0 :top 80}
                   :advance 0.60}
               66 {:planeBounds {:left 0 :right 0.58 :bottom -0.2 :top 0.8}
                   :atlasBounds {:left 98 :right 156 :bottom 0 :top 80}
                   :advance 0.60}
               67 {:planeBounds {:left 0 :right 0.58 :bottom -0.2 :top 0.8}
                   :atlasBounds {:left 156 :right 214 :bottom 0 :top 80}
                   :advance 0.60}
               68 {:planeBounds {:left 0 :right 0.58 :bottom -0.2 :top 0.8}
                   :atlasBounds {:left 214 :right 272 :bottom 0 :top 80}
                   :advance 0.60}
               69 {:planeBounds {:left 0 :right 0.58 :bottom -0.2 :top 0.8}
                   :atlasBounds {:left 272 :right 330 :bottom 0 :top 80}
                   :advance 0.60}
               70 {:planeBounds {:left 0 :right 0.58 :bottom -0.2 :top 0.8}
                   :atlasBounds {:left 330 :right 388 :bottom 0 :top 80}
                   :advance 0.60}
               71 {:planeBounds {:left 0 :right 0.58 :bottom -0.2 :top 0.8}
                   :atlasBounds {:left 388 :right 446 :bottom 0 :top 80}
                   :advance 0.60}
               72 {:planeBounds {:left 0 :right 0.58 :bottom -0.2 :top 0.8}
                   :atlasBounds {:left 446 :right 504 :bottom 0 :top 80}
                   :advance 0.60}
               65533 {:planeBounds {:left 0 :right 0.5 :bottom -0.2 :top 0.8}
                      :atlasBounds {:left 0 :right 50 :bottom 0 :top 80}
                      :advance 0.52}}})

(fn make-lines [count]
  (local lines [])
  (for [i 1 count]
    (local len (+ 12 (% i 40)))
    (local cps [])
    (for [j 1 len]
      (local code (+ 65 (% (+ i j) 8)))
      (table.insert cps code))
    (table.insert lines cps))
  lines)

(fn mutate-lines [lines frame changes]
  (local total (length lines))
  (for [i 1 changes]
    (local idx (+ (% (+ frame (* i 31)) total) 1))
    (local line (. lines idx))
    (local pos (+ (% (+ frame (* i 17)) (length line)) 1))
    (set (. line pos) (+ 65 (% (+ frame i) 8)))))

(fn run-bench [line-count frames changes]
  (local font (make-bench-font))
  (local batcher (TextSsboBatcher {}))
  (local lines (make-lines line-count))

  ;; Initial build
  (batcher:begin-frame)
  (for [i 1 line-count]
    (batcher:upsert-text i {:font font
                            :scale 0.04
                            :codepoints (. lines i)
                            :x 0
                            :y (* -0.06 i)
                            :z 0}))
  (batcher:end-frame)

  (var total-seconds 0.0)
  (var total-write-seconds 0.0)
  (var total-write-count 0)
  (var total-glyph-writes 0)
  (var total-transform-writes 0)

  (for [frame 1 frames]
    (mutate-lines lines frame changes)
    (local start (os.clock))
    (batcher:begin-frame)
    (for [i 1 line-count]
      (batcher:upsert-text i {:font font
                              :scale 0.04
                              :codepoints (. lines i)
                              :x 0
                              :y (* -0.06 i)
                              :z 0}))
    (batcher:end-frame)
    (set total-seconds (+ total-seconds (- (os.clock) start)))
    (local stats (batcher:get-last-stats))
    (set total-write-seconds (+ total-write-seconds stats.write-seconds))
    (set total-write-count (+ total-write-count stats.write-count))
    (set total-glyph-writes (+ total-glyph-writes stats.glyph-write-count))
    (set total-transform-writes (+ total-transform-writes stats.transform-write-count)))

  {:lines line-count
   :frames frames
   :changes changes
   :submit-ms (* 1000 (/ total-seconds frames))
   :write-ms (* 1000 (/ total-write-seconds frames))
   :write-count (/ total-write-count frames)
   :glyph-write-count (/ total-glyph-writes frames)
   :transform-write-count (/ total-transform-writes frames)})

(fn print-result [result]
  (print (.. "next-app-text-stress lines=" result.lines
             " frames=" result.frames
             " changes=" result.changes))
  (print (.. "  submit_ms=" (string.format "%.4f" result.submit-ms)))
  (print (.. "  write_ms=" (string.format "%.4f" result.write-ms)))
  (print (.. "  write_count_per_frame=" (string.format "%.2f" result.write-count)))
  (print (.. "  glyph_write_count_per_frame=" (string.format "%.2f" result.glyph-write-count)))
  (print (.. "  transform_write_count_per_frame=" (string.format "%.2f" result.transform-write-count))))

(fn main []
  (print-result (run-bench 1000 220 32))
  (print-result (run-bench 2000 220 48))
  true)

{:main main}
