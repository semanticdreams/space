(local _ (require :main))
(local MockOpenGL (require :mock-opengl))
(local package package)
(local table table)
(local ipairs ipairs)

(local tests [])

(local gl (require :gl))
(local glm (require :glm))
(local LightingViewState (require :lighting-view-state))
(local {:VectorBuffer VectorBuffer :VectorHandle VectorHandle} (require :vector-buffer))

(fn only [items]
  (assert (= (# items) 1) (.. "Expected exactly one entry, found " (# items)))
  (. items 1))

(fn fake-vector [float-count]
  (local vector {:_length float-count})
  (set vector.length (fn [self] self._length))
  vector)

(fn with-open-gl [cb]
  (local mock (MockOpenGL))
  (mock:install)
  (let [(ok result) (pcall cb mock)]
    (mock:restore)
    (if ok
        result
        (error result))))

(fn reload [module-name]
  (set (. package.loaded module-name) nil)
  (set (. package.loaded "vector-upload-cache") nil)
  (require module-name))

(fn reload-renderers-module []
  (each [_ module-name (ipairs [:renderers
                                :triangle-renderer
                                :vector-upload-cache
                                :line-renderer
                                :point-renderer
                                :image-renderer
                                :mesh-renderer
                                :instanced-color-mesh-renderer
                                :quad-renderer
                                :text-ssbo-renderer
                                :skybox-renderer
                                :fxaa
                                :lighting-view-state
                                :render-batch-predicates])]
    (set (. package.loaded module-name) nil))
  (require :renderers))

(fn with-renderers-constructor-deps [cb]
  (local textures (require :textures))
  (local original-load-cubemap textures.load-cubemap)
  (local original-load-cubemap-async textures.load-cubemap-async)
  (when (not (or original-load-cubemap original-load-cubemap-async))
    (set textures.load-cubemap
         (fn [_files]
           {:id 1
            :ready true
            :drop (fn [_self] nil)})))
  (let [(ok result) (pcall cb)]
    (set textures.load-cubemap original-load-cubemap)
    (set textures.load-cubemap-async original-load-cubemap-async)
    (if ok
        result
        (error result))))

(fn collect-calls [calls method predicate]
  (local matches [])
  (each [_ call (ipairs calls)]
    (when (and (= call.name method) (predicate call.args))
      (table.insert matches call)))
  matches)

(fn assert-perspective-lighting-uniforms [shader position]
  (local mode-call
    (only (collect-calls shader.calls "setInteger"
                         (fn [args] (= args.uniform "lightingViewMode")))))
  (assert (= mode-call.args.value LightingViewState.perspective-uniform-mode))
  (local pos-call
    (only (collect-calls shader.calls "setVector3f"
                         (fn [args] (= args.uniform "lightingViewPos")))))
  (assert (= (. pos-call.args.value 1) position.x))
  (assert (= (. pos-call.args.value 2) position.y))
  (assert (= (. pos-call.args.value 3) position.z)))

(fn assert-orthographic-lighting-uniforms [shader direction]
  (local mode-call
    (only (collect-calls shader.calls "setInteger"
                         (fn [args] (= args.uniform "lightingViewMode")))))
  (assert (= mode-call.args.value LightingViewState.orthographic-uniform-mode))
  (local dir-call
    (only (collect-calls shader.calls "setVector3f"
                         (fn [args] (= args.uniform "lightingViewDir")))))
  (assert (= (. dir-call.args.value 1) direction.x))
  (assert (= (. dir-call.args.value 2) direction.y))
  (assert (= (. dir-call.args.value 3) direction.z)))

(fn assert-unlit-uniform-enabled [shader]
  (local call
    (only (collect-calls shader.calls "setInteger"
                         (fn [args] (= args.uniform "unlit")))))
  (assert (= call.args.value 1)))

(fn triangle-resolve-batches-falls-back []
  (with-open-gl
    (fn [_mock]
      (local TriangleRenderer (reload "triangle-renderer"))
      (local renderer (TriangleRenderer))
      (local vector (fake-vector 80))
      (local batches (renderer:resolve-batches vector nil))
      (assert (= (# batches) 1))
      (local fallback (. batches 1))
      (assert (= fallback.clip nil))
      (assert (= fallback.model nil))
      (assert (= (# fallback.firsts) 1))
      (assert (= (# fallback.counts) 1))
      (assert (= (. fallback.firsts 1) 0))
      (assert (= (. fallback.counts 1) (math.floor (/ (vector:length) 8)))))))

(fn triangle-renderer-uploads-all-draws []
  (with-open-gl
    (fn [mock]
      (local TriangleRenderer (reload "triangle-renderer"))
      (local renderer (TriangleRenderer))
      (local projection {:type :projection})
      (local view {:type :view})
      (local camera-position (glm.vec3 7 8 9))
      (local lighting-view-state (LightingViewState.perspective camera-position))
      (local vector (fake-vector 120))
      (local batches [{:clip nil :model nil :firsts [3] :counts [6]}
                      {:clip {:enabled true} :model nil :firsts [12] :counts [9]}])
      (renderer:render vector projection view lighting-view-state batches)
      (local buffer-calls (mock:get-gl-calls "bufferDataFromVectorBuffer"))
      (assert (= (# buffer-calls) 1))
      (assert (= (. (. buffer-calls 1) :args :vector) vector))
      (local draw-calls (mock:get-gl-calls "glMultiDrawArrays"))
      (assert (= (# draw-calls) 2))
      (local first (. draw-calls 1))
      (assert (= first.args.mode gl.GL_TRIANGLES))
      (assert (= (. first.args.firsts 1) 3))
      (assert (= (. first.args.counts 1) 6))
      (local shader renderer.shader)
      (local projection-call (only (collect-calls shader.calls "setMatrix4"
                                                  (fn [args] (= args.uniform "projection")))))
      (assert (= projection-call.args.value projection))
      (local view-call (only (collect-calls shader.calls "setMatrix4"
                                            (fn [args] (= args.uniform "view")))))
      (assert (= view-call.args.value view))
      (assert-perspective-lighting-uniforms shader camera-position)
      (local clip-calls (collect-calls shader.calls "setMatrix4"
                                       (fn [args] (= args.uniform "uClipMatrix"))))
      (assert (= (# clip-calls) 2)))))

(fn triangle-renderer-uses-dirty-subdata []
  (with-open-gl
    (fn [mock]
      (local TriangleRenderer (reload "triangle-renderer"))
      (local renderer (TriangleRenderer))
      (local projection {:type :projection})
      (local view {:type :view})
      (local camera-position (glm.vec3 1 2 3))
      (local lighting-view-state (LightingViewState.perspective camera-position))
      (local vector (VectorBuffer 0))
      (local handle (vector:allocate 24))
      (vector:set-glm-vec3 handle 0 (glm.vec3 1 2 3))
      (vector:set-glm-vec4 handle 3 (glm.vec4 0.1 0.2 0.3 0.4))
      (vector:set-float handle 7 1.0)
      (renderer:render vector projection view lighting-view-state nil)
      (assert (= (# (mock:get-gl-calls "bufferDataFromVectorBuffer")) 1))
      (assert (= (# (mock:get-gl-calls "bufferSubDataFromVectorBuffer")) 0))

      (mock:reset)
      (renderer:render vector projection view lighting-view-state nil)
      (assert (= (# (mock:get-gl-calls "bufferDataFromVectorBuffer")) 0))
      (assert (= (# (mock:get-gl-calls "bufferSubDataFromVectorBuffer")) 0))

      (vector:set-float handle 0 2.0)
      (mock:reset)
      (renderer:render vector projection view lighting-view-state nil)
      (assert (= (# (mock:get-gl-calls "bufferDataFromVectorBuffer")) 0))
      (local sub (only (mock:get-gl-calls "bufferSubDataFromVectorBuffer")))
      (assert (= sub.args.target gl.GL_ARRAY_BUFFER))
      (assert (= sub.args.offset-bytes (* handle.index 4)))
      (assert (>= sub.args.size-bytes 4)))))

(fn triangle-renderer-caches-uploads-per-vector []
  (with-open-gl
    (fn [mock]
      (local TriangleRenderer (reload "triangle-renderer"))
      (local renderer (TriangleRenderer))
      (local projection {:type :projection})
      (local view {:type :view})
      (local camera-position (glm.vec3 1 2 3))
      (local lighting-view-state (LightingViewState.perspective camera-position))
      (local vector-a (VectorBuffer 0))
      (local vector-b (VectorBuffer 0))
      (local handle-a (vector-a:allocate 24))
      (local handle-b (vector-b:allocate 24))
      (vector-a:set-glm-vec3 handle-a 0 (glm.vec3 1 2 3))
      (vector-a:set-glm-vec4 handle-a 3 (glm.vec4 0.1 0.2 0.3 0.4))
      (vector-a:set-float handle-a 7 1.0)
      (vector-b:set-glm-vec3 handle-b 0 (glm.vec3 4 5 6))
      (vector-b:set-glm-vec4 handle-b 3 (glm.vec4 0.5 0.6 0.7 0.8))
      (vector-b:set-float handle-b 7 2.0)

      (mock:reset)
      (renderer:render vector-a projection view lighting-view-state nil)
      (renderer:render vector-b projection view lighting-view-state nil)
      (assert (= (# (mock:get-gl-calls "bufferDataFromVectorBuffer")) 2))
      (assert (= (# (mock:get-gl-calls "bufferSubDataFromVectorBuffer")) 0))

      (mock:reset)
      (renderer:render vector-a projection view lighting-view-state nil)
      (renderer:render vector-b projection view lighting-view-state nil)
      (assert (= (# (mock:get-gl-calls "bufferDataFromVectorBuffer")) 0))
      (assert (= (# (mock:get-gl-calls "bufferSubDataFromVectorBuffer")) 0))

      (vector-a:set-float handle-a 0 9.0)
      (mock:reset)
      (renderer:render vector-a projection view lighting-view-state nil)
      (assert (= (# (mock:get-gl-calls "bufferDataFromVectorBuffer")) 0))
      (local sub (only (mock:get-gl-calls "bufferSubDataFromVectorBuffer")))
      (assert (= sub.args.vector vector-a))
      (assert (= sub.args.offset-bytes (* handle-a.index 4))))))

(fn vector-upload-cache-evicts-oldest-entry []
  (with-open-gl
    (fn [mock]
      (local VectorUploadCache (reload "vector-upload-cache"))
      (local cache (VectorUploadCache {:usage gl.GL_STREAM_DRAW
                                       :max-entries 1
                                       :evict-per-upload 1}))
      (local vector-a (VectorBuffer 0))
      (local vector-b (VectorBuffer 0))
      (local handle-a (vector-a:allocate 8))
      (local handle-b (vector-b:allocate 8))
      (vector-a:set-float handle-a 0 1.0)
      (vector-b:set-float handle-b 0 2.0)

      (cache:upload vector-a nil)
      (local first-buffer (only (mock:get-gl-calls "glGenBuffers")))
      (assert (= (. (cache:stats) :entries) 1))

      (mock:reset)
      (cache:upload vector-b nil)
      (assert (= (# (mock:get-gl-calls "bufferDataFromVectorBuffer")) 1))
      (local deleted (only (mock:get-gl-calls "glDeleteBuffers")))
      (assert (= deleted.args.buffer first-buffer.args.handle))
      (assert (= (. (cache:stats) :entries) 1))

      (mock:reset)
      (cache:upload vector-a nil)
      (assert (= (# (mock:get-gl-calls "glGenBuffers")) 1))
      (assert (= (# (mock:get-gl-calls "bufferDataFromVectorBuffer")) 1))
      (assert (= (# (mock:get-gl-calls "bufferSubDataFromVectorBuffer")) 0))
      (assert (= (. (cache:stats) :entries) 1)))))

(fn vector-upload-cache-drop-deletes-live-entries []
  (with-open-gl
    (fn [mock]
      (local VectorUploadCache (reload "vector-upload-cache"))
      (local cache (VectorUploadCache {:usage gl.GL_STREAM_DRAW
                                       :max-entries 4
                                       :evict-per-upload 1}))
      (local vector-a (VectorBuffer 0))
      (local vector-b (VectorBuffer 0))
      (local handle-a (vector-a:allocate 8))
      (local handle-b (vector-b:allocate 8))
      (vector-a:set-float handle-a 0 1.0)
      (vector-b:set-float handle-b 0 2.0)

      (cache:upload vector-a nil)
      (cache:upload vector-b nil)
      (assert (= (. (cache:stats) :entries) 2))

      (mock:reset)
      (cache:drop)
      (assert (= (# (mock:get-gl-calls "glDeleteBuffers")) 2))
      (assert (= (. (cache:stats) :entries) 0)))))

(fn vector-upload-cache-rejects-invalid-limits []
  (with-open-gl
    (fn [_mock]
      (local VectorUploadCache (reload "vector-upload-cache"))
      (local (ok-max err-max)
        (pcall VectorUploadCache {:max-entries 0
                                  :evict-per-upload 1}))
      (assert (not ok-max))
      (assert (string.find err-max "positive integer" 1 true))
      (local (ok-evict err-evict)
        (pcall VectorUploadCache {:max-entries 1
                                  :evict-per-upload 0}))
      (assert (not ok-evict))
      (assert (string.find err-evict "positive integer" 1 true)))))

(fn triangle-renderer-drop-releases-cache-and-vao []
  (with-open-gl
    (fn [mock]
      (local TriangleRenderer (reload "triangle-renderer"))
      (local renderer (TriangleRenderer))
      (local vector (VectorBuffer 0))
      (local handle (vector:allocate 8))
      (local projection {:type :projection})
      (local view {:type :view})
      (local lighting-view-state (LightingViewState.perspective (glm.vec3 1 2 3)))
      (vector:set-float handle 0 1.0)

      (renderer:render vector projection view lighting-view-state nil)

      (mock:reset)
      (renderer:drop)
      (assert (= (# (mock:get-gl-calls "glDeleteBuffers")) 1))
      (assert (= (# (mock:get-gl-calls "glDeleteVertexArrays")) 1)))))

(fn line-renderer-drop-releases-cache-and-vao []
  (with-open-gl
    (fn [mock]
      (local LineRenderer (reload "line-renderer"))
      (local renderer (LineRenderer))
      (local vector (VectorBuffer 0))
      (local handle (vector:allocate 14))
      (vector:set-float handle 0 1.0)
      (renderer:render-lines vector {:projection true} {:view true})

      (mock:reset)
      (renderer:drop)
      (assert (= (# (mock:get-gl-calls "glDeleteBuffers")) 1))
      (assert (= (# (mock:get-gl-calls "glDeleteVertexArrays")) 1)))))

(fn point-renderer-drop-releases-both-buffers-and-vao []
  (with-open-gl
    (fn [mock]
      (local PointRenderer (reload "point-renderer"))
      (local renderer (PointRenderer))
      (local vector (VectorBuffer 0))
      (local handle (vector:allocate 9))
      (vector:set-float handle 0 1.0)
      (renderer:render vector {:projection true} {:view true})

      (mock:reset)
      (renderer:drop)
      (assert (= (# (mock:get-gl-calls "glDeleteBuffers")) 2))
      (assert (= (# (mock:get-gl-calls "glDeleteVertexArrays")) 1)))))

(fn image-renderer-drop-releases-cache-and-vao []
  (with-open-gl
    (fn [mock]
      (local ImageRenderer (reload "image-renderer"))
      (local renderer (ImageRenderer))
      (local vector (VectorBuffer 0))
      (local handle (vector:allocate 10))
      (vector:set-float handle 0 1.0)
      (renderer:render-texture-batch {:vector vector
                                      :texture {:id 7 :ready true}}
                                     {:projection true}
                                     {:view true}
                                     nil)

      (mock:reset)
      (renderer:drop)
      (assert (= (# (mock:get-gl-calls "glDeleteBuffers")) 1))
      (assert (= (# (mock:get-gl-calls "glDeleteVertexArrays")) 1)))))

(fn draw-batcher-batches-by-clip-and-model []
  (local DrawBatcher (reload "draw-batcher"))
  (local batcher (DrawBatcher {:stride 8}))
  (local vector (VectorBuffer 0))
  (local h1 (vector:allocate 24))
  (local h2 (vector:allocate 24))
  (local clip {:enabled true})
  (local model {:id 1})
  (batcher:track-handle h1 clip model)
  (batcher:track-handle h2 clip model)
  (local batches (batcher:get-batches))
  (assert (= (# batches) 1))
  (local batch (. batches 1))
  (assert (= batch.clip clip))
  (assert (= batch.model model))
  (assert (= (# batch.firsts) 1))
  (assert (= (# batch.counts) 1))
  (assert (= (. batch.firsts 1) 0))
  (assert (= (. batch.counts 1) 6)))

(fn draw-batcher-splits-noncontiguous-runs []
  (local DrawBatcher (reload "draw-batcher"))
  (local batcher (DrawBatcher {:stride 8}))
  (local vector (VectorBuffer 0))
  (local h1 (vector:allocate 24))
  (local _gap (vector:allocate 8))
  (local h2 (vector:allocate 24))
  (local clip {:enabled true})
  (batcher:track-handle h1 clip nil)
  (batcher:track-handle h2 clip nil)
  (local batches (batcher:get-batches))
  (assert (= (# batches) 1))
  (local batch (. batches 1))
  (assert (= (# batch.firsts) 2))
  (assert (= (# batch.counts) 2))
  (assert (= (. batch.firsts 1) 0))
  (assert (= (. batch.counts 1) 3))
  (assert (= (. batch.firsts 2) 4))
  (assert (= (. batch.counts 2) 3)))

(fn line-renderer-draws-lines-and-strips []
  (with-open-gl
    (fn [mock]
      (local LineRenderer (reload "line-renderer"))
      (local renderer (LineRenderer))
      (mock:reset)
      (local vector (fake-vector 28))
      (renderer:render-lines vector {:projection true} {:view true})
      (local strip-a (fake-vector 21))
      (local strip-b (fake-vector 14))
      (renderer:render-line-strips [strip-a strip-b] {:projection true} {:view true})
      (local attrib-calls (mock:get-gl-calls "glVertexAttribPointer"))
      (assert (= (# attrib-calls) 6))
      (local attrib-position (. attrib-calls 1))
      (local attrib-color (. attrib-calls 2))
      (assert (= attrib-position.args.index 0))
      (assert (= attrib-position.args.size 3))
      (assert (= attrib-position.args.stride (* 7 4)))
      (assert (= attrib-color.args.index 1))
      (assert (= attrib-color.args.size 4))
      (assert (= attrib-color.args.stride (* 7 4)))
      (assert (= attrib-color.args.offset (* 4 3)))
      (local draw-calls (mock:get-gl-calls "glDrawArrays"))
      (assert (= (# draw-calls) 3))
      (assert (= (. (. draw-calls 1) :args :mode) gl.GL_LINES))
      (assert (= (. (. draw-calls 2) :args :mode) gl.GL_LINE_STRIP))
      (assert (= (. (. draw-calls 3) :args :mode) gl.GL_LINE_STRIP))
      (assert (= (. (. draw-calls 1) :args :count) 4))
      (assert (= (. (. draw-calls 2) :args :count) 3))
      (assert (= (. (. draw-calls 3) :args :count) 2))
      (local buffer-calls (mock:get-gl-calls "bufferDataFromVectorBuffer"))
      (assert (= (# buffer-calls) 3)))))

(fn point-renderer-uses-instanced-quads []
  (with-open-gl
    (fn [mock]
      (local PointRenderer (reload "point-renderer"))
      (local renderer (PointRenderer))
      (local vector (fake-vector 36))
      (renderer:render vector {:projection true} {:view true})
      (local buffer-call (only (mock:get-gl-calls "bufferDataFromVectorBuffer")))
      (assert (= buffer-call.args.vector vector))
      (local divisor-calls (mock:get-gl-calls "glVertexAttribDivisor"))
      (assert (= (# divisor-calls) 4))
      (each [_ call (ipairs divisor-calls)]
        (assert (= call.args.divisor 1)))
      (local draw-call (only (mock:get-gl-calls "glDrawArraysInstanced")))
      (assert (= draw-call.args.mode gl.GL_TRIANGLE_STRIP))
      (assert (= draw-call.args.count 4))
      (assert (= draw-call.args.instances (/ (vector:length) 9))))))

(fn quad-renderer-base-strip-has-positive-local-winding []
  (with-open-gl
    (fn [mock]
      (local QuadRenderer (reload "quad-renderer"))
      (QuadRenderer)
      (local upload (only (mock:get-gl-calls "glBufferData")))
      (local data upload.args.data)
      (assert (= (# data) 8))
      (local v0 (glm.vec3 (. data 1) (. data 2) 0))
      (local v1 (glm.vec3 (. data 3) (. data 4) 0))
      (local v2 (glm.vec3 (. data 5) (. data 6) 0))
      (local v3 (glm.vec3 (. data 7) (. data 8) 0))
      (local tri0-normal (glm.cross (- v1 v0) (- v2 v0)))
      (local tri1-normal (glm.cross (- v3 v1) (- v2 v1)))
      (assert (> tri0-normal.z 0) "Quad strip first triangle should face local +Z")
      (assert (> tri1-normal.z 0) "Quad strip second triangle should face local +Z"))))

(fn quad-renderer-draws-instanced-batches-with-clipping-and-lighting []
  (with-open-gl
    (fn [mock]
      (local QuadRenderer (reload "quad-renderer"))
      (local renderer (QuadRenderer))
      (local camera-position (glm.vec3 7 8 9))
      (local lighting-view-state (LightingViewState.perspective camera-position))
      (mock:reset)
      (local vector (fake-vector (* 21 8)))
      (local clip-vector (fake-vector (* 16 3)))
      (local clip-group-vector (fake-vector 8))
      (local model-a {:id :a})
      (renderer:render vector
                       {:projection true}
                       {:view true}
                       lighting-view-state
                       [{:model model-a
                         :firsts [0 3]
                         :counts [2 1]}
                       {:model nil
                         :firsts [4]
                         :counts [4]}]
                       clip-vector
                       clip-group-vector
                       false)
      (local draw-calls (mock:get-gl-calls "glDrawArraysInstanced"))
      (assert (= (# draw-calls) 3))
      (assert (= (. (. draw-calls 1) :args :mode) gl.GL_TRIANGLE_STRIP))
      (assert (= (. (. draw-calls 1) :args :instances) 2))
      (assert (= (. (. draw-calls 2) :args :instances) 1))
      (assert (= (. (. draw-calls 3) :args :instances) 4))
      (local bind-buffer-calls (mock:get-gl-calls "glBindBuffer"))
      (var instance-bind-count 0)
      (each [_ call (ipairs bind-buffer-calls)]
        (when (= call.args.target gl.GL_ARRAY_BUFFER)
          (set instance-bind-count (+ instance-bind-count 1))))
      (assert (> instance-bind-count 1)
              "quad renderer should rebind instance buffer when changing instance windows")
      (local bind-base-call (only (mock:get-gl-calls "glBindBufferBase")))
      (assert (= bind-base-call.args.target 0x90D2))
      (assert (= bind-base-call.args.index 0))
      (local shader renderer.shader)
      (local model-calls (collect-calls shader.calls "setMatrix4"
                                        (fn [args] (= args.uniform "model"))))
      (assert (= (# model-calls) 2))
      (assert (= (. (. model-calls 1) :args :value) model-a))
      (assert-perspective-lighting-uniforms shader camera-position)
      (local ambient-call (only (collect-calls shader.calls "setVector3f"
                                               (fn [args] (= args.uniform "ambientLight")))))
      (assert ambient-call "quad renderer should upload lighting uniforms")
      (assert (>= (renderer:get-last-upload-seconds) 0)
              "quad renderer should expose upload timing"))))

(fn quad-renderer-uploads-orthographic-lighting-direction []
  (with-open-gl
    (fn [_mock]
      (local QuadRenderer (reload "quad-renderer"))
      (local renderer (QuadRenderer))
      (local direction (glm.vec3 0 0 1))
      (local lighting-view-state (LightingViewState.orthographic direction))
      (local vector (fake-vector (* 21 2)))
      (local clip-vector (fake-vector 16))
      (local clip-group-vector (fake-vector 2))
      (renderer:render vector
                       {:projection true}
                       {:view true}
                       lighting-view-state
                       [{:model nil
                         :firsts [0]
                         :counts [2]}]
                       clip-vector
                       clip-group-vector
                       false)
      (assert-orthographic-lighting-uniforms renderer.shader direction))))

(fn quad-renderer-skips-lighting-for-unlit-quads []
  (with-open-gl
    (fn [_mock]
      (local QuadRenderer (reload "quad-renderer"))
      (local renderer (QuadRenderer))
      (local vector (fake-vector (* 21 2)))
      (local clip-vector (fake-vector 16))
      (local clip-group-vector (fake-vector 2))
      (renderer:render vector
                       {:projection true}
                       {:view true}
                       nil
                       [{:model nil
                         :firsts [0]
                         :counts [2]}]
                       clip-vector
                       clip-group-vector
                       true)
      (assert-unlit-uniform-enabled renderer.shader)
      (assert (= (# (collect-calls renderer.shader.calls "setVector3f"
                                   (fn [args] (= args.uniform "ambientLight"))))
                 0)
              "unlit quad renderer path should skip light uniform uploads")
      (assert (= (# (collect-calls renderer.shader.calls "setInteger"
                                   (fn [args] (= args.uniform "lightingViewMode"))))
                 0)
              "unlit quad renderer path should skip lighting view uniforms"))))

(fn quad-renderer-updates-dirty-instance-window []
  (with-open-gl
    (fn [mock]
      (local QuadRenderer (reload "quad-renderer"))
      (local renderer (QuadRenderer))
      (local vector (VectorBuffer 0))
      (local handle (vector:allocate (* 21 2)))
      (vector:set-glm-mat4 handle 0 (glm.mat4 1))
      (vector:set-glm-vec4 handle 16 (glm.vec4 1 1 1 1))
      (vector:set-float handle 20 0)
      (local camera-position (glm.vec3 2 3 4))
      (local lighting-view-state (LightingViewState.perspective camera-position))
      (local clip-vector (fake-vector 16))
      (local clip-group-vector (fake-vector 2))
      (local batches [{:model nil :firsts [0] :counts [2]}])
      (renderer:render vector
                       {:projection true}
                       {:view true}
                       lighting-view-state
                       batches
                       clip-vector
                       clip-group-vector
                       false)

      (mock:reset)
      (vector:set-float handle 0 2.0)
      (renderer:render vector
                       {:projection true}
                       {:view true}
                       lighting-view-state
                       batches
                       clip-vector
                       clip-group-vector
                       false)

      (local sub-updates
        (collect-calls (mock:get-gl-calls "bufferSubDataFromVectorBuffer")
                       "bufferSubDataFromVectorBuffer"
                       (fn [args] (= args.target gl.GL_ARRAY_BUFFER))))
      (assert (= (# sub-updates) 1)
              "quad renderer should issue one dirty subdata update for instance data changes"))))

(fn mesh-renderer-draws-textured-triangles []
  (with-open-gl
    (fn [mock]
      (local MeshRenderer (reload "mesh-renderer"))
      (local renderer (MeshRenderer))
      (local vector (fake-vector 48))
      (local projection {:projection true})
      (local view {:view true})
      (local camera-position (glm.vec3 3 4 5))
      (local lighting-view-state (LightingViewState.perspective camera-position))
      (local texture {:id 7})
      (renderer:render [{:vector vector :texture texture}] projection view lighting-view-state)
      (local buffer-call (only (mock:get-gl-calls "bufferDataFromVectorBuffer")))
      (assert (= buffer-call.args.vector vector))
      (local bind-calls (mock:get-gl-calls "glBindTexture"))
      (assert (= (. (. bind-calls 1) :args :texture) 7))
      (local draw-call (only (mock:get-gl-calls "glDrawArrays")))
      (assert (= draw-call.args.mode gl.GL_TRIANGLES))
      (assert (= draw-call.args.count (/ (vector:length) 8)))
      (assert-perspective-lighting-uniforms renderer.shader camera-position))))

(fn instanced-color-mesh-renderer-draws-instanced-and-updates-dirty-instance-window []
  (with-open-gl
    (fn [mock]
      (local InstancedColorMeshRenderer (reload "instanced-color-mesh-renderer"))
      (local renderer (InstancedColorMeshRenderer))
      (local vertex-vector (fake-vector 60))
      (local instance-vector (VectorBuffer 0))
      (local handle (instance-vector:allocate 32))
      (instance-vector:set-glm-mat4 handle 0 (glm.mat4 1))
      (instance-vector:set-glm-mat4 handle 16 (glm.translate (glm.mat4 1) (glm.vec3 2 0 0)))
      (local batch {:vertex-vector vertex-vector
                    :indices [0 1 2 0 2 3]
                    :index-count 6
                    :instance-vector instance-vector
                    :visible? true
                    :unlit false
                    :get-instance-batches (fn [_self]
                                            [{:firsts [0]
                                              :counts [2]}])})
      (local camera-position (glm.vec3 5 6 7))
      (local lighting-view-state (LightingViewState.perspective camera-position))
      (renderer:render [batch] {:projection true} {:view true} lighting-view-state)
      (local index-upload (only (mock:get-gl-calls "glBufferDataUInt")))
      (assert (= index-upload.args.target 0x8893))
      (local draw-call (only (mock:get-gl-calls "glDrawElementsInstanced")))
      (assert (= draw-call.args.mode gl.GL_TRIANGLES))
      (assert (= draw-call.args.count 6))
      (assert (= draw-call.args.type gl.GL_UNSIGNED_INT))
      (assert (= draw-call.args.instances 2))
      (assert-perspective-lighting-uniforms renderer.shader camera-position)

      (mock:reset)
      (instance-vector:set-glm-mat4-diff handle 16 (glm.translate (glm.mat4 1) (glm.vec3 4 0 0)))
      (renderer:render [batch] {:projection true} {:view true} lighting-view-state)
      (local sub-updates
        (collect-calls (mock:get-gl-calls "bufferSubDataFromVectorBuffer")
                       "bufferSubDataFromVectorBuffer"
                       (fn [args] (= args.target gl.GL_ARRAY_BUFFER))))
      (assert (= (# sub-updates) 1)
              "instanced color mesh renderer should issue one dirty subdata update for instance changes"))))

(fn renderers-draw-target-skips-lighting-state-for-empty-lit-geometry []
  (with-open-gl
    (fn [_mock]
      (with-renderers-constructor-deps
        (fn []
          (local Renderers (reload-renderers-module))
          (local renderers (Renderers))
          (renderers:draw-target
            {:projection {:projection true}
             :get-view-matrix (fn [_self] {:view true})
             :get-triangle-vector (fn [_self] (fake-vector 0))
             :get-mesh-batches (fn [_self] [{:vector (fake-vector 0)}])
             :get-instanced-color-mesh-batches
             (fn [_self] [{:vertex-vector (fake-vector 0)
                           :instance-vector (fake-vector 0)}])
             :get-quad-draw-list
             (fn [_self] [{:vector (fake-vector 0)
                           :batches []
                           :clip-vector (fake-vector 0)
                           :clip-group-vector (fake-vector 0)}])})))))) 

(fn renderers-draw-target-skips-lighting-state-for-unlit-quads []
  (with-open-gl
    (fn [_mock]
      (with-renderers-constructor-deps
        (fn []
          (local Renderers (reload-renderers-module))
          (local renderers (Renderers))
          (renderers:draw-target
            {:projection {:projection true}
             :get-view-matrix (fn [_self] {:view true})
             :get-quad-draw-list
             (fn [_self] [{:vector (fake-vector 21)
                           :unlit true
                           :batches [{:model nil
                                      :firsts [0]
                                      :counts [1]}]
                           :clip-vector (fake-vector 16)
                           :clip-group-vector (fake-vector 1)}])}))))))

(fn renderers-draw-target-requires-lighting-state-for-lit-geometry []
  (with-open-gl
    (fn [_mock]
      (with-renderers-constructor-deps
        (fn []
          (local Renderers (reload-renderers-module))
          (local renderers (Renderers))
          (local (ok err)
            (pcall (fn []
                     (renderers:draw-target
                       {:projection {:projection true}
                        :get-view-matrix (fn [_self] {:view true})
                        :get-triangle-vector (fn [_self] (fake-vector 8))}))))
          (assert (not ok))
          (assert err)
          (assert (string.find (tostring err) "lighting")))))))

(fn renderers-update-uses-background-clear-color []
  (with-open-gl
    (fn [mock]
      (with-renderers-constructor-deps
        (fn []
          (local Renderers (reload-renderers-module))
          (local renderers (Renderers))
          (local previous-app app)
          (global app {})
          (renderers:set-background-state {:color [0.1 0.2 0.3]})
          (renderers:update)
          (local clear-call (only (mock:get-gl-calls "glClearColor")))
          (assert (= clear-call.args.r 0.1))
          (assert (= clear-call.args.g 0.2))
          (assert (= clear-call.args.b 0.3))
          (assert (= clear-call.args.a 1.0))
          (global app previous-app))))))

(fn instanced-color-mesh-batch-drop-requires-removed-instances []
  (local InstancedColorMeshBatch (reload "instanced-color-mesh-batch"))
  (local batches [])
  (local ctx {:register-instanced-color-mesh-batch (fn [_self batch]
                                                     (table.insert batches batch)
                                                     batch)
              :unregister-instanced-color-mesh-batch (fn [_self batch]
                                                       (for [idx 1 (length batches)]
                                                         (when (= (. batches idx) batch)
                                                           (table.remove batches idx)
                                                           (lua "break")))
                                                       nil)})
  (local batch (InstancedColorMeshBatch ctx {:vertices [{:color (glm.vec4 1 1 1 1)
                                                         :normal (glm.vec3 0 1 0)
                                                         :position (glm.vec3 0 0 0)}]
                                            :indices [0]}))
  (local instance (batch:add-instance (glm.mat4 1)))
  (local ok (pcall (fn [] (batch:drop))))
  (assert (not ok) "Dropping a batch with live instances should fail loudly")
  (batch:remove-instance instance)
  (batch:drop)
  (assert (= (length batches) 0)))

(fn text-renderer-uploads-font-state []
  (with-open-gl
    (fn [mock]
      (local TextRenderer (reload "text-renderer"))
      (local renderer (TextRenderer))
      (local vector (fake-vector 40))
      (local font {:metadata {:atlas {:distanceRange 3.5}}
                   :texture {:id 77 :ready true}})
      (renderer:render vector font {:projection true} {:view true} nil)
      (local shader renderer.shader)
      (local px-range (only (collect-calls shader.calls "setFloat"
                                           (fn [args] (= args.uniform "pxRange")))))
      (assert (= px-range.args.value 3.5))
      (local bind-call (only (mock:get-gl-calls "glBindTexture")))
      (assert (= bind-call.args.target gl.GL_TEXTURE_2D))
      (assert (= bind-call.args.texture font.texture.id))
      (local active-call (only (mock:get-gl-calls "glActiveTexture")))
      (assert (= active-call.args.slot gl.GL_TEXTURE0)))))

(fn image-renderer-respects-draw-batcher []
  (with-open-gl
    (fn [mock]
      (local ImageRenderer (reload "image-renderer"))
      (local renderer (ImageRenderer))
      (local vector (fake-vector 50))
      (local batch {:vector vector
                    :texture {:id 19 :ready true}
                    :draw-batcher {:get-batches (fn [_] [{:clip {:foo true}
                                                          :model nil
                                                          :firsts [2]
                                                          :counts [3]}] )}})
      (renderer:render-texture-batch batch {:projection true} {:view true} nil)
      (local clip-calls (collect-calls renderer.shader.calls "setMatrix4"
                                       (fn [args] (= args.uniform "uClipMatrix"))))
      (assert (= (# clip-calls) 1))
      (local bind-call (only (mock:get-gl-calls "glBindTexture")))
      (assert (= bind-call.args.texture batch.texture.id))
      (local fallback-vector (fake-vector 60))
      (local fallback (renderer:resolve-draw-batches {:vector fallback-vector
                                                      :texture {:id 20}}
                                                     nil))
      (assert (= (# fallback) 1))
      (local default (. fallback 1))
      (local expected (math.floor (/ (fallback-vector:length) 10)))
      (assert (= (. default.counts 1) expected)))))

(fn skybox-renderer-loads-initial-cubemap []
  (with-open-gl
    (fn [_mock]
      (local textures (require :textures))
      (local original-load-cubemap textures.load-cubemap)
      (local original-load-cubemap-async textures.load-cubemap-async)
      (local calls [])
      (set textures.load-cubemap-async nil)
      (set textures.load-cubemap
           (fn [files]
             (table.insert calls files)
             {:id 99
              :ready true
              :drop (fn [_self] nil)}))
      (let [(ok result)
            (pcall
              (fn []
                (local SkyboxRenderer (reload "skybox-renderer"))
                (local renderer (SkyboxRenderer {}))
                (assert (= (# calls) 1)
                        "SkyboxRenderer should load the initial cubemap during construction")
                (local files (. calls 1))
                (assert (= (# files) 6) "SkyboxRenderer cubemap should include all six faces")
                (renderer:drop)))]
        (set textures.load-cubemap original-load-cubemap)
        (set textures.load-cubemap-async original-load-cubemap-async)
        (if ok
            result
            (error result))))))

(fn text-ssbo-renderer-uses-ssbo-groups-and-instanced-draws []
  (with-open-gl
    (fn [mock]
      (local TextSsboRenderer (reload "text-ssbo-renderer"))
      (local renderer (TextSsboRenderer))
      (local glyph-vector (fake-vector (* 8 12)))
      (local glyph-group-vector (fake-vector 12))
      (local group-vector (fake-vector (* 16 3)))
      (local group-clip-index-vector (fake-vector 3))
      (local group-depth-index-vector (fake-vector 3))
      (local clip-vector (fake-vector (* 16 2)))
      (local font {:metadata {:atlas {:distanceRange 3.5}}
                   :texture {:id 42 :ready true}})
      (renderer:render glyph-vector
                       glyph-group-vector
                       group-vector
                       group-clip-index-vector
                       group-depth-index-vector
                       clip-vector
                       font
                       {:projection true}
                       {:view true}
                       [{:firsts [0 4]
                         :counts [3 2]}])
      (local bind-base-calls (mock:get-gl-calls "glBindBufferBase"))
      (assert (= (# bind-base-calls) 4))
      (assert (= (. (. bind-base-calls 1) :args :target) 0x90D2))
      (assert (= (. (. bind-base-calls 1) :args :index) 0))
      (assert (= (. (. bind-base-calls 2) :args :index) 1))
      (assert (= (. (. bind-base-calls 3) :args :index) 2))
      (assert (= (. (. bind-base-calls 4) :args :index) 3))
      (local buffer-calls (mock:get-gl-calls "bufferDataFromVectorBuffer"))
      (assert (= (# buffer-calls) 4))
      (local uint-buffer-calls (mock:get-gl-calls "bufferDataUIntFromVectorBuffer"))
      (assert (= (# uint-buffer-calls) 2))
      (local int-pointer-calls (mock:get-gl-calls "glVertexAttribIPointer"))
      (assert (> (# int-pointer-calls) 0))
      (local draw-calls (mock:get-gl-calls "glDrawArraysInstanced"))
      (assert (= (# draw-calls) 2))
      (assert (= (. (. draw-calls 1) :args :instances) 3))
      (assert (= (. (. draw-calls 2) :args :instances) 2))
      (local shader renderer.shader)
      (local px-range (only (collect-calls shader.calls "setFloat"
                                           (fn [args] (= args.uniform "pxRange")))))
      (assert (= px-range.args.value 3.5))
      (assert (>= (renderer:get-last-upload-seconds) 0)
              "text ssbo renderer should expose upload timing"))))

(table.insert tests {:name "Triangle renderer falls back to default draw" :fn triangle-resolve-batches-falls-back})
(table.insert tests {:name "Triangle renderer uploads draw batches" :fn triangle-renderer-uploads-all-draws})
(table.insert tests {:name "Triangle renderer uploads dirty subdata" :fn triangle-renderer-uses-dirty-subdata})
(table.insert tests {:name "Triangle renderer caches uploads per vector"
                     :fn triangle-renderer-caches-uploads-per-vector})
(table.insert tests {:name "Vector upload cache evicts oldest entry"
                     :fn vector-upload-cache-evicts-oldest-entry})
(table.insert tests {:name "Vector upload cache drop deletes live entries"
                     :fn vector-upload-cache-drop-deletes-live-entries})
(table.insert tests {:name "Vector upload cache rejects invalid limits"
                     :fn vector-upload-cache-rejects-invalid-limits})
(table.insert tests {:name "Triangle renderer drop releases cache and vao"
                     :fn triangle-renderer-drop-releases-cache-and-vao})
(table.insert tests {:name "Line renderer drop releases cache and vao"
                     :fn line-renderer-drop-releases-cache-and-vao})
(table.insert tests {:name "Point renderer drop releases both buffers and vao"
                     :fn point-renderer-drop-releases-both-buffers-and-vao})
(table.insert tests {:name "Image renderer drop releases cache and vao"
                     :fn image-renderer-drop-releases-cache-and-vao})
(table.insert tests {:name "DrawBatcher batches by clip and model" :fn draw-batcher-batches-by-clip-and-model})
(table.insert tests {:name "DrawBatcher splits noncontiguous runs" :fn draw-batcher-splits-noncontiguous-runs})
(table.insert tests {:name "Line renderer draws lines and strips" :fn line-renderer-draws-lines-and-strips})
(table.insert tests {:name "Point renderer uses instanced quads" :fn point-renderer-uses-instanced-quads})
(table.insert tests {:name "Quad renderer base strip has positive local winding"
                     :fn quad-renderer-base-strip-has-positive-local-winding})
(table.insert tests {:name "Quad renderer draws instanced batches with clipping and lighting"
                     :fn quad-renderer-draws-instanced-batches-with-clipping-and-lighting})
(table.insert tests {:name "Quad renderer uploads orthographic lighting view direction"
                     :fn quad-renderer-uploads-orthographic-lighting-direction})
(table.insert tests {:name "Quad renderer updates dirty instance window"
                     :fn quad-renderer-updates-dirty-instance-window})
(table.insert tests {:name "Mesh renderer draws textured triangles" :fn mesh-renderer-draws-textured-triangles})
(table.insert tests {:name "Instanced color mesh renderer draws instanced meshes and updates dirty instances"
                     :fn instanced-color-mesh-renderer-draws-instanced-and-updates-dirty-instance-window})
(table.insert tests {:name "Instanced color mesh batch drop requires removed instances"
                     :fn instanced-color-mesh-batch-drop-requires-removed-instances})
(table.insert tests {:name "Text renderer uploads font metadata and texture" :fn text-renderer-uploads-font-state})
(table.insert tests {:name "Image renderer uses draw batcher and fallback draws" :fn image-renderer-respects-draw-batcher})
(table.insert tests {:name "Skybox renderer loads initial cubemap" :fn skybox-renderer-loads-initial-cubemap})
(table.insert tests {:name "Text SSBO renderer uses group SSBO and instanced draws"
                     :fn text-ssbo-renderer-uses-ssbo-groups-and-instanced-draws})
(table.insert tests {:name "Renderers draw-target skips lighting state for empty lit geometry"
                     :fn renderers-draw-target-skips-lighting-state-for-empty-lit-geometry})
(table.insert tests {:name "Renderers draw-target skips lighting state for unlit quads"
                     :fn renderers-draw-target-skips-lighting-state-for-unlit-quads})
(table.insert tests {:name "Renderers draw-target requires lighting state for lit geometry"
                     :fn renderers-draw-target-requires-lighting-state-for-lit-geometry})
(table.insert tests {:name "Renderers update uses background clear color"
                     :fn renderers-update-uses-background-clear-color})

(fn draw-target-uses-only-active-slot-draw-source []
  ;; Regression: renderers:draw-target must only consume data from the active
  ;; slot source. When the target exposes slot-gated getters that switch which
  ;; internal data is served, draw-target must not read from inactive slots.
  ;; Slot-a and slot-b use distinct-length vectors; the draw call counts must
  ;; match the active slot's vector and never the inactive one.
  (with-open-gl
    (fn [mock]
      (with-renderers-constructor-deps
        (fn []
          (local Renderers (reload-renderers-module))
          (local renderers (Renderers))
          (var active-slot nil)
          ;; Slot-a: 64 floats -> 64/8 = 8 triangle vertices -> 1 draw call with count=8
          (local slot-a {:vector (fake-vector 64)
                         :id "slot-a"})
          ;; Slot-b: 160 floats -> 160/8 = 20 triangle vertices -> 1 draw call with count=20
          (local slot-b {:vector (fake-vector 160)
                         :id "slot-b"})
          (set active-slot slot-a)
          (local target
            {:projection {:projection true}
             :get-view-matrix (fn [_self] {:view true})
             :get-lighting-view-state (fn [_self] {:kind :perspective :position (glm.vec3 1 2 3)})
             :get-triangle-vector (fn [_self] active-slot.vector)
             :get-mesh-batches (fn [_self] [{:vector (fake-vector 0)}])
             :get-instanced-color-mesh-batches
             (fn [_self] [{:vertex-vector (fake-vector 0)
                           :instance-vector (fake-vector 0)}])
             :get-quad-draw-list
             (fn [_self] [{:vector (fake-vector 0)
                           :batches []
                           :clip-vector (fake-vector 0)
                           :clip-group-vector (fake-vector 0)}])})
          ;; First draw with slot-a active
          (renderers:draw-target target)
          (local draw-a (mock:get-gl-calls "glMultiDrawArrays"))
          (assert draw-a "Expected draw calls for slot-a")
          (local draw-a-counts (or (and (. draw-a 1) (. (. draw-a 1) :args :counts)) []))
          (assert (= (or (. draw-a-counts 1) 0) 8)
                  (.. "slot-a draw should render 8 triangles, got "
                      (tostring (or (. draw-a-counts 1) 0))))
          ;; Switch to slot-b and draw again
          (set active-slot slot-b)
          (mock:reset)
          (renderers:draw-target target)
          (local draw-b (mock:get-gl-calls "glMultiDrawArrays"))
          (assert draw-b "Expected draw calls for slot-b")
          (local draw-b-counts (or (and (. draw-b 1) (. (. draw-b 1) :args :counts)) []))
          (assert (= (or (. draw-b-counts 1) 0) 20)
                  (.. "slot-b draw should render 20 triangles, not stale slot-a count, got "
                      (tostring (or (. draw-b-counts 1) 0))))
          true)))))

(table.insert tests {:name "Renderers draw-target uses only active slot draw source"
                     :fn draw-target-uses-only-active-slot-draw-source})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "renderers"
                       :tests tests})))

{:name "renderers"
 :tests tests
 :main main}
