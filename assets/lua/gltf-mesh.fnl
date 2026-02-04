(local fs (require :fs))
(local glm (require :glm))
(local textures (require :textures))
(local {: Layout} (require :layout))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))

(fn resolve-glm-vec3 [value fallback]
    (if
      (= value nil) fallback
      (= (type value) :userdata) value
      (= (type value) :number) (glm.vec3 value value value)
      (= (type value) :table)
        (do
          (local x (or (. value 1) value.x (. value "x") (and fallback fallback.x) 0))
          (local y (or (. value 2) value.y (. value "y") (and fallback fallback.y) 0))
          (local z (or (. value 3) value.z (. value "z") (and fallback fallback.z) 0))
          (glm.vec3 x y z))
      fallback))

(fn resolve-glm-quat [value fallback]
    (if
      (= value nil) fallback
      (= (type value) :userdata) value
      fallback))

(fn axis-angle-from-quat [rotation]
    (local normalized (rotation:normalize))
    (local w (math.max -1 (math.min 1 normalized.w)))
    (local angle (* 2 (math.acos w)))
    (local s (math.sqrt (math.max 0 (- 1 (* w w)))))
    (if (< s 1e-6)
        (values angle (glm.vec3 1 0 0))
        (values angle (glm.vec3 (/ normalized.x s)
                            (/ normalized.y s)
                            (/ normalized.z s)))))

(fn model-matrix [position rotation scale local-offset]
    (local translate (glm.translate (glm.mat4 1) position))
    (local (angle axis) (axis-angle-from-quat rotation))
    (local rot (glm.rotate (glm.mat4 1) angle axis))
    (local scaled (glm.scale (glm.mat4 1) scale))
    (local offset (glm.translate (glm.mat4 1) (or local-offset (glm.vec3 0 0 0))))
    (* translate (* rot (* scaled offset))))

(fn is-absolute-path? [path]
    (or (= (string.sub path 1 1) "/")
        (and (> (# path) 1) (= (string.sub path 2 2) ":"))))

(fn resolve-path [path]
    (if (and app.engine app.engine.get-asset-path (not (fs.exists path)))
        (app.engine.get-asset-path path)
        path))

(fn resolve-texture-path [gltf-path uri]
    (if (is-absolute-path? uri)
        uri
        (fs.join-path (fs.parent gltf-path) uri)))

(fn resolve-texture-from-batch [gltf-path texture-cache name-prefix batch]
    (local image-index (. batch "image-index"))
    (assert image-index "mesh batch missing image index")
    (local cached (. texture-cache image-index))
    (if cached
        cached
        (do
          (local name (.. name-prefix "-" image-index))
          (if (. batch "image-uri")
              (do
                (local path (resolve-texture-path gltf-path (. batch "image-uri")))
                (local loader (or textures.load-texture-async textures.load-texture))
                (local texture (loader name path))
                (tset texture-cache image-index texture)
                texture)
              (do
                (assert (. batch "image-bytes") "image requires uri or bytes")
                (local loader (or textures.load-texture-from-bytes-async
                                  textures.load-texture-from-bytes))
                (assert loader
                        "textures.load-texture-from-bytes(-async) is required for gltf images")
                (local texture (loader name (. batch "image-bytes")))
                (tset texture-cache image-index texture)
                texture)))))

(fn RenderBuffer [ctx batches]
    (assert (and ctx ctx.register-mesh-batch ctx.unregister-mesh-batch)
            "GltfMesh requires mesh batch registration in the build context")

    (local renders [])

      (each [_ batch (ipairs batches)]
        (local vertex-count (or batch.vertex_count (/ (length batch.vertex_bytes) 32)))
        (local stride (* vertex-count 8))
        (local vector (VectorBuffer))
        (local handle (vector:allocate stride))
        (when (and batch.vertex_bytes (> (length batch.vertex_bytes) 0))
          (vector:set-floats-from-bytes handle 0 batch.vertex_bytes))
        (local batch-ref {:vector vector :texture batch.texture :visible? true :model nil})
        (local render {:vector vector
                       :handle handle
                       :texture batch.texture
                       :batch-ref batch-ref
                       :batch batch
                       :vertex-count vertex-count})
        (ctx:register-mesh-batch batch-ref)
        (table.insert renders render))

    (fn update [self args]
      (local rotation (or args.rotation (glm.quat 1 0 0 0)))
      (local position (or args.position (glm.vec3 0 0 0)))
      (local scale (or args.scale (glm.vec3 1 1 1)))
      (local bounds-offset (or args.bounds-offset (glm.vec3 0 0 0)))
      (local model (model-matrix position rotation scale bounds-offset))
      (each [_ render (ipairs renders)]
        (set render.batch-ref.visible? true)
        (set render.batch-ref.model model))
      )

    (fn drop [_self]
      (each [_ render (ipairs renders)]
        (ctx:unregister-mesh-batch render.batch-ref)
        (render.vector:delete render.handle)))

    {:update update
     :drop drop
     :renders renders})

(fn GltfMesh [opts]
    (local options (or opts {}))
    (local path (or options.path options.file options.filename))
    (assert path "GltfMesh requires :path")
    (local resolved (resolve-path path))
    (local name-prefix (or options.name "gltf-mesh"))
    (local position (resolve-glm-vec3 options.position (glm.vec3 0 0 0)))
    (local rotation (resolve-glm-quat options.rotation (glm.quat 1 0 0 0)))
    (local scale (resolve-glm-vec3 options.scale (glm.vec3 1 1 1)))

    (fn build [ctx]
      (assert (and app.engine app.engine.jobs app.engine.jobs.submit)
              "GltfMesh requires app.engine.jobs")
      (local state {:loaded? false
                    :dropped? false
                    :renderable nil
                    :size (glm.vec3 0 0 0)
                    :bounds-offset (glm.vec3 0 0 0)})

      (fn measurer [self]
        (local size state.size)
        (set self.measure (glm.vec3 (* size.x scale.x)
                                 (* size.y scale.y)
                                 (* size.z scale.z))))

      (fn layouter [self]
        (when state.loaded?
          (local culled? (self:effective-culled?))
          (when culled?
            (each [_ render (ipairs state.renderable.renders)]
              (set render.batch-ref.visible? false)))
          (when (not culled?)
            (state.renderable:update {:position self.position
                                      :rotation self.rotation
                                      :scale scale
                                      :bounds-offset state.bounds-offset}))))

      (local layout
        (Layout {:name name-prefix
                 :measurer measurer
                 :layouter layouter}))
      (layout:set-position position)
      (layout:set-rotation rotation)

      (fn apply-batches [payload]
        (local texture-cache {})
        (local batches [])
        (each [_ batch (ipairs payload.batches)]
          (local texture (resolve-texture-from-batch resolved texture-cache name-prefix batch))
          (table.insert batches {:vertex_bytes (. batch "vertex_bytes")
                                 :vertex_count (. batch "vertex_count")
                                 :texture texture}))
        (set state.renderable (RenderBuffer ctx batches))
        (local bounds payload.bounds)
        (if (and bounds bounds.min bounds.max)
            (set state.size (- (glm.vec3 bounds.max.x bounds.max.y bounds.max.z)
                            (glm.vec3 bounds.min.x bounds.min.y bounds.min.z)))
            (set state.size (glm.vec3 0 0 0)))
        (if (and bounds bounds.min)
            (set state.bounds-offset (glm.vec3 (- bounds.min.x)
                                               (- bounds.min.y)
                                               (- bounds.min.z)))
            (set state.bounds-offset (glm.vec3 0 0 0)))
        (set state.loaded? true)
        (layout:mark-measure-dirty))

      (app.engine.jobs.submit
        {:kind "build_gltf_batches"
         :payload resolved
         :callback (fn [res]
                     (when (not state.dropped?)
                       (assert res.ok (.. "gltf batch build failed: " (or res.error "unknown")))
                       (assert res.batches "gltf batch build did not return batches")
                       (apply-batches {:batches res.batches :bounds res.bounds})))})

      (fn drop [_self]
        (set state.dropped? true)
        (layout:drop)
        (when state.renderable
          (state.renderable:drop)))

      {:layout layout
       :drop drop}))

GltfMesh
