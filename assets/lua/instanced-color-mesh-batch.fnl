(local glm (require :glm))
(local DrawBatcher (require :draw-batcher))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))

(local vertex-stride 10)
(local instance-stride 16)

(fn write-vertex [vector handle offset vertex]
  (vector:set-glm-vec4 handle offset vertex.color)
  (vector:set-glm-vec3 handle (+ offset 4) vertex.normal)
  (vector:set-glm-vec3 handle (+ offset 7) vertex.position))

(fn InstancedColorMeshBatch [ctx opts]
  (local options (or opts {}))
  (assert (and ctx ctx.register-instanced-color-mesh-batch ctx.unregister-instanced-color-mesh-batch)
          "InstancedColorMeshBatch requires instanced color mesh batch registration in the build context")
  (local vertices (assert options.vertices "InstancedColorMeshBatch requires :vertices"))
  (local indices (assert options.indices "InstancedColorMeshBatch requires :indices"))

  (local vertex-vector (VectorBuffer))
  (local vertex-handle (vertex-vector:allocate (* (length vertices) vertex-stride)))
  (each [idx vertex (ipairs vertices)]
    (write-vertex vertex-vector vertex-handle (* (- idx 1) vertex-stride) vertex))

  (local instance-vector (VectorBuffer))
  (local instance-batcher (DrawBatcher {:stride instance-stride}))
  (var live-instance-count 0)
  (local batch {:vertex-vector vertex-vector
                :vertex-handle vertex-handle
                :vertex-count (length vertices)
                :indices indices
                :index-count (length indices)
                :instance-vector instance-vector
                :instance-stride instance-stride
                :visible? true
                :unlit (not (= options.unlit false))})
  (ctx:register-instanced-color-mesh-batch batch)

  (fn add-instance [self model]
    (local handle (self.instance-vector:allocate instance-stride))
    (self.instance-vector:set-glm-mat4 handle 0 (or model (glm.mat4 1)))
    (instance-batcher:track-handle handle nil nil)
    (set live-instance-count (+ live-instance-count 1))
    {:handle handle
     :visible? true})

  (fn update-instance-model [self instance model]
    (assert (and instance instance.handle) "InstancedColorMeshBatch instance requires a handle")
    (self.instance-vector:set-glm-mat4-diff instance.handle 0 (or model (glm.mat4 1))))

  (fn set-instance-visible [_self instance visible?]
    (assert (and instance instance.handle) "InstancedColorMeshBatch instance requires a handle")
    (local desired (not (not visible?)))
    (when (not (= desired instance.visible?))
      (set instance.visible? desired)
      (if desired
          (instance-batcher:track-handle instance.handle nil nil)
          (instance-batcher:untrack-handle instance.handle))))

  (fn remove-instance [self instance]
    (when (and instance instance.handle)
      (instance-batcher:untrack-handle instance.handle)
      (self.instance-vector:delete instance.handle)
      (set live-instance-count (- live-instance-count 1))
      (set instance.handle nil)
      (set instance.visible? false)))

  (fn get-instance-batches [_self]
    (instance-batcher:get-batches))

  (fn drop [self]
    (assert (= live-instance-count 0)
            (string.format "InstancedColorMeshBatch.drop requires all instances to be removed first; %d remain"
                           live-instance-count))
    (ctx:unregister-instanced-color-mesh-batch batch)
    (self.vertex-vector:delete vertex-handle))

  (set batch.add-instance add-instance)
  (set batch.update-instance-model update-instance-model)
  (set batch.set-instance-visible set-instance-visible)
  (set batch.remove-instance remove-instance)
  (set batch.get-instance-batches get-instance-batches)
  (set batch.get-live-instance-count (fn [_self] live-instance-count))
  (set batch.drop drop)
  batch)

InstancedColorMeshBatch
