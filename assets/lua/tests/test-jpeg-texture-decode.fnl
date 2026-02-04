(local tests [])

(local wait-for
  (fn [job-id]
    (local deadline (+ (os.clock) 2))
    (var result nil)
    (while (and (not result) (< (os.clock) deadline))
      (each [_ entry (ipairs (app.engine.jobs.poll))]
        (when (= entry.id job-id)
          (set result entry))))
    (assert result (string.format "Timed out waiting for job %s" (tostring job-id)))
    result))

(fn decode-jpeg-texture-bytes []
  (assert (and app.engine app.engine.jobs app.engine.jobs.submit)
          "JPEG decode test requires app.engine.jobs")
  (local path (app.engine.get-asset-path "skyboxes/lake/front.jpg"))
  (local file (io.open path "rb"))
  (assert file (.. "Missing JPEG fixture: " path))
  (local bytes (file:read "*all"))
  (file:close)
  (assert (> (string.len bytes) 0) "JPEG fixture should not be empty")
  (local payload (.. (string.char 0) bytes))
  (local id (app.engine.jobs.submit "decode_texture_bytes" payload))
  (local res (wait-for id))
  (assert res.ok (or res.error "JPEG decode job failed"))
  (local width (. res "width"))
  (local height (. res "height"))
  (local channels (. res "channels"))
  (local pixel-bytes (. res "pixel-bytes"))
  (assert (and width height channels pixel-bytes) "JPEG decode missing payload")
  (assert (> width 0) "JPEG width missing")
  (assert (> height 0) "JPEG height missing")
  (assert (or (= channels 3) (= channels 4)) "JPEG channels should be 3 or 4")
  (local expected (* width height channels))
  (assert (= (string.len pixel-bytes) expected)
          "JPEG pixel byte count mismatch"))

(table.insert tests {:name "jpeg decode texture bytes" :fn decode-jpeg-texture-bytes})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "jpeg-texture-decode"
                       :tests tests})))

{:name "jpeg-texture-decode"
 :tests tests
 :main main}
