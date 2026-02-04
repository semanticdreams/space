(local _ (require :main))
(local MockOpenGL (require :mock-opengl))
(local package package)
(local table table)
(local ipairs ipairs)

(local tests [])

(local gl (require :gl))
(local glm (require :glm))
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
  (require module-name))

(fn collect-calls [calls method predicate]
  (local matches [])
  (each [_ call (ipairs calls)]
    (when (and (= call.name method) (predicate call.args))
      (table.insert matches call)))
  matches)

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
      (local vector (fake-vector 120))
      (local batches [{:clip nil :model nil :firsts [3] :counts [6]}
                      {:clip {:enabled true} :model nil :firsts [12] :counts [9]}])
      (renderer:render vector projection view batches)
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
      (local vector (VectorBuffer 0))
      (local handle (vector:allocate 24))
      (vector:set-glm-vec3 handle 0 (glm.vec3 1 2 3))
      (vector:set-glm-vec4 handle 3 (glm.vec4 0.1 0.2 0.3 0.4))
      (vector:set-float handle 7 1.0)
      (renderer:render vector projection view nil)
      (assert (= (# (mock:get-gl-calls "bufferDataFromVectorBuffer")) 1))
      (assert (= (# (mock:get-gl-calls "bufferSubDataFromVectorBuffer")) 0))

      (mock:reset)
      (renderer:render vector projection view nil)
      (assert (= (# (mock:get-gl-calls "bufferDataFromVectorBuffer")) 0))
      (assert (= (# (mock:get-gl-calls "bufferSubDataFromVectorBuffer")) 0))

      (vector:set-float handle 0 2.0)
      (mock:reset)
      (renderer:render vector projection view nil)
      (assert (= (# (mock:get-gl-calls "bufferDataFromVectorBuffer")) 0))
      (local sub (only (mock:get-gl-calls "bufferSubDataFromVectorBuffer")))
      (assert (= sub.args.target gl.GL_ARRAY_BUFFER))
      (assert (= sub.args.offset-bytes (* handle.index 4)))
      (assert (>= sub.args.size-bytes 4)))))

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
      (local vector (fake-vector 24))
      (renderer:render-lines vector {:projection true} {:view true})
      (local strip-a (fake-vector 18))
      (local strip-b (fake-vector 12))
      (renderer:render-line-strips [strip-a strip-b] {:projection true} {:view true})
      (local draw-calls (mock:get-gl-calls "glDrawArrays"))
      (assert (= (# draw-calls) 3))
      (assert (= (. (. draw-calls 1) :args :mode) gl.GL_LINES))
      (assert (= (. (. draw-calls 2) :args :mode) gl.GL_LINE_STRIP))
      (assert (= (. (. draw-calls 3) :args :mode) gl.GL_LINE_STRIP))
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

(fn mesh-renderer-draws-textured-triangles []
  (with-open-gl
    (fn [mock]
      (local MeshRenderer (reload "mesh-renderer"))
      (local renderer (MeshRenderer))
      (local vector (fake-vector 48))
      (local projection {:projection true})
      (local view {:view true})
      (local texture {:id 7})
      (renderer:render [{:vector vector :texture texture}] projection view)
      (local buffer-call (only (mock:get-gl-calls "bufferDataFromVectorBuffer")))
      (assert (= buffer-call.args.vector vector))
      (local bind-calls (mock:get-gl-calls "glBindTexture"))
      (assert (= (. (. bind-calls 1) :args :texture) 7))
      (local draw-call (only (mock:get-gl-calls "glDrawArrays")))
      (assert (= draw-call.args.mode gl.GL_TRIANGLES))
      (assert (= draw-call.args.count (/ (vector:length) 8))))))

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

(table.insert tests {:name "Triangle renderer falls back to default draw" :fn triangle-resolve-batches-falls-back})
(table.insert tests {:name "Triangle renderer uploads draw batches" :fn triangle-renderer-uploads-all-draws})
(table.insert tests {:name "Triangle renderer uploads dirty subdata" :fn triangle-renderer-uses-dirty-subdata})
(table.insert tests {:name "DrawBatcher batches by clip and model" :fn draw-batcher-batches-by-clip-and-model})
(table.insert tests {:name "DrawBatcher splits noncontiguous runs" :fn draw-batcher-splits-noncontiguous-runs})
(table.insert tests {:name "Line renderer draws lines and strips" :fn line-renderer-draws-lines-and-strips})
(table.insert tests {:name "Point renderer uses instanced quads" :fn point-renderer-uses-instanced-quads})
(table.insert tests {:name "Mesh renderer draws textured triangles" :fn mesh-renderer-draws-textured-triangles})
(table.insert tests {:name "Text renderer uploads font metadata and texture" :fn text-renderer-uploads-font-state})
(table.insert tests {:name "Image renderer uses draw batcher and fallback draws" :fn image-renderer-respects-draw-batcher})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "renderers"
                       :tests tests})))

{:name "renderers"
 :tests tests
 :main main}
