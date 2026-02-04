(local tests [])
(local fs (require :fs))
(local textures (require :textures))

(fn resolve-asset-path [relative-path]
  (if (and app.engine app.engine.get-asset-path)
      (app.engine.get-asset-path relative-path)
      (do
        (local assets-root (os.getenv "SPACE_ASSETS_PATH"))
        (assert assets-root "SPACE_ASSETS_PATH must be set for cgltf tests")
        (fs.join-path assets-root relative-path))))

(fn wait-for-job [job-id]
  (local deadline (+ (os.clock) 2))
  (var result nil)
  (while (and (not result) (< (os.clock) deadline))
    (each [_ entry (ipairs (app.engine.jobs.poll))]
      (when (= entry.id job-id)
        (set result entry))))
  (assert result (string.format "Timed out waiting for job %s" (tostring job-id)))
  result)

(fn decode-embedded-texture []
  (assert (and app.engine app.engine.jobs app.engine.jobs.submit)
          "embedded texture decode test requires app.engine.jobs")
  (local model-path (resolve-asset-path "models/BoxTextured.glb"))
  (local batch-id (app.engine.jobs.submit "build_gltf_batches" model-path))
  (local batch-res (wait-for-job batch-id))
  (assert batch-res.ok batch-res.error)
  (assert batch-res.batches "gltf batch build should return batches")
  (local batch (. batch-res.batches 1))
  (local image-bytes (. batch "image-bytes"))
  (assert image-bytes "expected embedded image bytes")

  (local payload (.. (string.char 0) image-bytes))
  (local decode-id (app.engine.jobs.submit "decode_texture_bytes" payload))
  (local decode-res (wait-for-job decode-id))
  (assert decode-res.ok decode-res.error)
  (local pixels (. decode-res "pixel-bytes"))
  (local width decode-res.width)
  (local height decode-res.height)
  (local channels decode-res.channels)
  (assert pixels "decode job should return pixel bytes")
  (assert (and width height channels) "decode job missing dimensions")
  (local expected (* width height channels))
  (assert (= (length pixels) expected) "decoded pixel bytes length mismatch")

  (local texture (textures.load-texture-from-pixels "decode-embedded-test"
                                                    width
                                                    height
                                                    channels
                                                    pixels
                                                    true))
  (assert texture.ready "texture should be ready after pixel upload"))

(table.insert tests {:name "decode embedded gltf texture bytes" :fn decode-embedded-texture})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "gltf-async-embedded-texture-decode"
                       :tests tests})))

{:name "gltf-async-embedded-texture-decode"
 :tests tests
 :main main}
