(local cgltf (require :cgltf))

(fn build-name-map [items]
    (local names {})
    (each [index item (ipairs items)]
        (when item.name
            (tset names item.name index)))
    names)

(fn attribute-key [attr]
    (if (= attr.type "custom")
        (if attr.name
            attr.name
            (if (> attr.index 0)
                (.. attr.type "-" attr.index)
                attr.type))
        (if (> attr.index 0)
            (.. attr.type "-" attr.index)
            attr.type)))

(fn read-indices [data accessor-index count]
    (local index-values [])
    (for [i 1 count]
        (table.insert index-values (+ 1 (data:accessor-read-index accessor-index i))))
    index-values)

(fn resolve-primitive-attributes [data primitive]
    (local attributes {})
    (each [_ attr (ipairs primitive.attributes)]
        (local key (attribute-key attr))
        (when key
            (tset attributes key
                  {:accessor attr.accessor
                   :type attr.type
                   :name attr.name
                   :values (data:accessor-unpack-floats attr.accessor)})))
    attributes)

(fn GltfModel [opts]
    (assert opts "GltfModel requires options")
    (local path (or opts.path opts.file opts.filename))
    (assert path "GltfModel requires :path")
    (local parse-options (if opts.type {:type opts.type} {}))
    (local data (if opts.data
                    opts.data
                    (cgltf.parse-file parse-options path)))
    (when (not opts.data)
      (data:load-buffers (or opts.load-options {}) path))
    (when (not (= opts.validate? false))
      (data:validate))
    (local info (data:to-table))
    (local nodes info.nodes)
    (local meshes info.meshes)
    (local materials info.materials)
    (local animations info.animations)
    (local scenes info.scenes)
    (local accessors info.accessors)
    {:data data
     :info info
     :path path
     :file-type info.file-type
     :scenes scenes
     :nodes nodes
     :meshes meshes
     :materials materials
     :animations animations
     :images info.images
     :textures info.textures
     :accessors accessors
     :buffers info.buffers
     :buffer-views info.buffer-views
     :named {:nodes (build-name-map nodes)
             :meshes (build-name-map meshes)
             :materials (build-name-map materials)
             :animations (build-name-map animations)
             :scenes (build-name-map scenes)}
     :drop (fn [self] (data:drop))
     :node-transform-local (fn [self node-index]
                             (data:node-transform-local node-index))
     :node-transform-world (fn [self node-index]
                             (data:node-transform-world node-index))
     :animation-sampler (fn [self animation-index sampler-index]
                          (local animation (. animations animation-index))
                          (assert animation "animation index out of range")
                          (local sampler (. animation.samplers sampler-index))
                          (assert sampler "sampler index out of range")
                          {:input (data:accessor-unpack-floats sampler.input)
                           :output (data:accessor-unpack-floats sampler.output)
                           :interpolation sampler.interpolation})
     :primitive (fn [self mesh-index primitive-index]
                  (local mesh (. meshes mesh-index))
                  (assert mesh "mesh index out of range")
                  (local primitive (. mesh.primitives primitive-index))
                  (assert primitive "primitive index out of range")
                  (var indices nil)
                  (when primitive.indices
                      (local accessor (. accessors primitive.indices))
                      (set indices (read-indices data primitive.indices accessor.count)))
                  {:type primitive.type
                   :material primitive.material
                   :attributes (resolve-primitive-attributes data primitive)
                   :indices indices
                   :targets primitive.targets
                   :mappings primitive.mappings})})

GltfModel
