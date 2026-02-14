(local os os)
(local string string)
(local glm (require :glm))
(local Harness (require :tests.e2e.harness))
(local NextAppSubApp (require :next-app/sub-app))

(fn average [sum count]
  (if (= count 0) 0 (/ sum count)))

(fn run-phase [sub-app frames mode]
  (var total-submit-seconds 0.0)
  (var total-write-seconds 0.0)
  (var total-upload-seconds 0.0)
  (var total-write-count 0)
  (var total-upsert-count 0)

  (for [i 1 frames]
    (when (= mode :transform)
      (sub-app:set-root-transform (+ -0.91 (* i 0.0005)) -0.83 0 0))
    (local start (os.clock))
    (sub-app:prerender)
    (local elapsed (- (os.clock) start))
    (local stats (sub-app:get-submit-stats))
    (set total-submit-seconds (+ total-submit-seconds elapsed))
    (set total-write-seconds (+ total-write-seconds (or stats.write-seconds 0)))
    (set total-upload-seconds (+ total-upload-seconds (or stats.gl-upload-seconds 0)))
    (set total-write-count (+ total-write-count (or stats.write-count 0)))
    (set total-upsert-count (+ total-upsert-count (or stats.upsert-count 0))))

  {:mode mode
   :frames frames
   :submit-ms (* 1000 (average total-submit-seconds frames))
   :write-ms (* 1000 (average total-write-seconds frames))
   :upload-ms (* 1000 (average total-upload-seconds frames))
   :write-count (average total-write-count frames)
   :upsert-count (average total-upsert-count frames)})

(fn print-result [result]
  (print (.. "next-app-transform-idle mode=" (tostring result.mode)
             " frames=" result.frames))
  (print (.. "  render_submit_ms=" (string.format "%.4f" result.submit-ms)))
  (print (.. "  vector_write_ms=" (string.format "%.4f" result.write-ms)))
  (print (.. "  gl_upload_ms=" (string.format "%.4f" result.upload-ms)))
  (print (.. "  write_count_per_frame=" (string.format "%.2f" result.write-count)))
  (print (.. "  upsert_count_per_frame=" (string.format "%.2f" result.upsert-count))))

(fn run [ctx]
  (local sub-app
    (NextAppSubApp {:name "next-app-transform-idle"
                    :size (glm.vec2 640 360)
                    :sub-app-options {:renderer-options
                                      {:scenario :default
                                       :enable-focus true
                                       :root-width 1.82
                                       :root-height 1.66
                                       :root-position {:x -0.91 :y -0.83 :z 0 :rotation-z 0}}}}))
  (sub-app:set-size 640 360)

  ;; warm-up
  (for [_ 1 10]
    (sub-app:prerender))

  (local steady (run-phase sub-app 80 :steady))
  (print-result steady)
  (assert (= steady.write-count 0)
          (.. "steady write count should be zero, got " steady.write-count))
  (assert (= steady.upsert-count 0)
          (.. "steady upsert count should be zero, got " steady.upsert-count))

  (local transform (run-phase sub-app 80 :transform))
  (print-result transform)
  (assert (> transform.write-count 0)
          "transform phase should submit updated instances")
  (assert (> transform.upsert-count 0)
          "transform phase should upsert instances")

  (sub-app:drop)
  true)

(fn main []
  (Harness.with-app {:width 800 :height 450}
                    (fn [ctx]
                      (run ctx)))
  true)

{:main main}
