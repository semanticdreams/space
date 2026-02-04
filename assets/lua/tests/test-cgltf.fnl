(local tests [])
(local fs (require :fs))
(local cgltf (require :cgltf))
(local GltfModel (require :gltf-model))

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

(fn cgltf-parse-glb []
  (local model-path (resolve-asset-path "models/BoxTextured.glb"))
  (local data (cgltf.parse-file {:type "glb"} model-path))
  (data:load-buffers {} model-path)
  (data:validate)
  (local info (data:to-table))
  (assert (= info.file-type "glb"))
  (assert (> (length info.meshes) 0))
  (assert (> (length info.accessors) 0))
  (assert (> (length info.buffers) 0))
  (assert (> (length info.buffer-views) 0))
  (assert (> (length info.images) 0))
  (local buf (data:buffer-data 1))
  (assert buf "expected buffer data")
  (local floats (data:accessor-unpack-floats 1))
  (assert (> (length floats) 0))
  (local node-matrix (data:node-transform-local 1))
  (assert (= (length node-matrix) 16))
  (data:drop))

(fn cgltf-parse-animated-gltf []
  (local model-path (resolve-asset-path "models/AnimatedUnlitTriangle.gltf"))
  (local data (cgltf.parse-file {:type "gltf"} model-path))
  (data:load-buffers {} model-path)
  (data:validate)
  (local info (data:to-table))
  (assert (= info.file-type "gltf"))
  (assert (= (length info.animations) 1))
  (local animation (. info.animations 1))
  (assert (= (length animation.samplers) 1))
  (assert (= (length animation.channels) 1))
  (local channel (. animation.channels 1))
  (assert (= channel.target-path "translation"))
  (local material (. info.materials 1))
  (var has-unlit material.unlit)
  (when (not has-unlit)
    (each [_ ext (ipairs material.extensions)]
      (when (= ext.name "KHR_materials_unlit")
        (set has-unlit true))))
  (assert has-unlit "expected KHR_materials_unlit material extension")
  (data:drop))

(fn cgltf-wrapper-model []
  (local model-path (resolve-asset-path "models/AnimatedUnlitTriangle.gltf"))
  (local model (GltfModel {:path model-path :type "gltf"}))
  (assert (= (length model.animations) 1))
  (assert (= (length model.materials) 1))
  (assert (= (length model.meshes) 1))
  (assert (= (. model.named.animations "MoveUp") 1))
  (local sampler (model:animation-sampler 1 1))
  (assert (= (length sampler.input) 2))
  (assert (= (length sampler.output) 6))
  (local primitive (model:primitive 1 1))
  (assert primitive.indices)
  (assert (= (length primitive.indices) 3))
  (assert primitive.attributes.position)
  (model:drop))

(fn cgltf-job-loads-model []
  (assert (and app.engine app.engine.jobs app.engine.jobs.submit)
          "cgltf job test requires app.engine.jobs")
  (local model-path (resolve-asset-path "models/BoxTextured.glb"))
  (local id (app.engine.jobs.submit "load_gltf" model-path))
  (local res (wait-for-job id))
  (assert res.ok res.error)
  (assert res.data "cgltf job should return data")
  (local data res.data)
  (local info (data:to-table))
  (assert (= info.file-type "glb"))
  (data:drop))

(fn cgltf-job-builds-batches []
  (assert (and app.engine app.engine.jobs app.engine.jobs.submit)
          "cgltf job test requires app.engine.jobs")
  (local model-path (resolve-asset-path "models/BoxTextured.glb"))
  (local id (app.engine.jobs.submit "build_gltf_batches" model-path))
  (local res (wait-for-job id))
  (assert res.ok res.error)
  (assert res.batches "gltf batch build should return batches")
  (assert (> (length res.batches) 0))
  (local batch (. res.batches 1))
  (assert (. batch "vertex_bytes"))
  (assert (= 0 (% (length (. batch "vertex_bytes")) 32)))
  (assert (or (. batch "image-uri") (. batch "image-bytes"))))

(table.insert tests {:name "cgltf parses glb models" :fn cgltf-parse-glb})
(table.insert tests {:name "cgltf parses animated gltf models" :fn cgltf-parse-animated-gltf})
(table.insert tests {:name "gltf-model wraps cgltf data" :fn cgltf-wrapper-model})
(table.insert tests {:name "cgltf job loads glb models" :fn cgltf-job-loads-model})
(table.insert tests {:name "cgltf job builds mesh batches" :fn cgltf-job-builds-batches})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "cgltf"
                       :tests tests})))

{:name "cgltf"
 :tests tests
 :main main}
