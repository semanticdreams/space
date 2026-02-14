(local glm (require :glm))
(local LightUtils (require :light-utils))
(local os os)

(local gl (require :gl))
(local shaders (require :shaders))

(local instance-stride 21)
(local stream-ring-size 3)
(local query-ring-size 4)

(fn make-buffer-ring []
  (local out [])
  (for [_ 1 stream-ring-size]
    (table.insert out (gl.glGenBuffers 1)))
  out)

(fn make-query-ring []
  (local out [])
  (for [_ 1 query-ring-size]
    (table.insert out (gl.glGenQueries 1)))
  out)

(fn QuadRenderer []
  (local shader
    (shaders.load-shader-from-files
      "quads"
      (app.engine.get-asset-path "shaders/quad.vert")
      (app.engine.get-asset-path "shaders/quad.frag")))

  (local vao (gl.glGenVertexArrays 1))
  (local quad-buffer (gl.glGenBuffers 1))
  (local instance-buffers (make-buffer-ring))
  (local clip-group-buffers (make-buffer-ring))
  (local clip-groups-ssbos (make-buffer-ring))

  (local gpu-query-supported?
    (and gl.glGenQueries
         gl.glBeginQuery
         gl.glEndQuery
         gl.glGetQueryObjectuiv
         gl.glGetQueryObjectui64v
         gl.GL_TIME_ELAPSED
         gl.GL_QUERY_RESULT_AVAILABLE
         gl.GL_QUERY_RESULT))
  (local upload-gpu-queries (if gpu-query-supported? (make-query-ring) nil))
  (local draw-gpu-queries (if gpu-query-supported? (make-query-ring) nil))
  (var upload-query-submitted {})
  (var draw-query-submitted {})

  (var active-query-slot 1)
  (var active-stream-slot 1)
  (var stream-frame-id 0)
  (var slot-last-frame {})
  (var active-instance-buffer (. instance-buffers active-stream-slot))
  (var active-clip-group-buffer (. clip-group-buffers active-stream-slot))
  (var active-clip-groups-ssbo (. clip-groups-ssbos active-stream-slot))

  (gl.glBindVertexArray vao)
  (gl.glBindBuffer gl.GL_ARRAY_BUFFER quad-buffer)
  (gl.glBufferData gl.GL_ARRAY_BUFFER
                   [0 0
                    1 0
                    0 1
                    1 1]
                   gl.GL_STATIC_DRAW)
  (gl.glEnableVertexAttribArray 0)
  (gl.glVertexAttribPointer 0 2 gl.GL_FLOAT gl.GL_FALSE (* 2 4) 0)

  (gl.glBindBuffer gl.GL_ARRAY_BUFFER active-instance-buffer)
  (local stride-bytes (* instance-stride 4))

  (gl.glEnableVertexAttribArray 1)
  (gl.glVertexAttribPointer 1 4 gl.GL_FLOAT gl.GL_FALSE stride-bytes 0)
  (gl.glVertexAttribDivisor 1 1)
  (gl.glEnableVertexAttribArray 2)
  (gl.glVertexAttribPointer 2 4 gl.GL_FLOAT gl.GL_FALSE stride-bytes (* 4 4))
  (gl.glVertexAttribDivisor 2 1)
  (gl.glEnableVertexAttribArray 3)
  (gl.glVertexAttribPointer 3 4 gl.GL_FLOAT gl.GL_FALSE stride-bytes (* 8 4))
  (gl.glVertexAttribDivisor 3 1)
  (gl.glEnableVertexAttribArray 4)
  (gl.glVertexAttribPointer 4 4 gl.GL_FLOAT gl.GL_FALSE stride-bytes (* 12 4))
  (gl.glVertexAttribDivisor 4 1)
  (gl.glEnableVertexAttribArray 5)
  (gl.glVertexAttribPointer 5 4 gl.GL_FLOAT gl.GL_FALSE stride-bytes (* 16 4))
  (gl.glVertexAttribDivisor 5 1)
  (gl.glEnableVertexAttribArray 6)
  (gl.glVertexAttribPointer 6 1 gl.GL_FLOAT gl.GL_FALSE stride-bytes (* 20 4))
  (gl.glVertexAttribDivisor 6 1)
  (gl.glBindBuffer gl.GL_ARRAY_BUFFER active-clip-group-buffer)
  (gl.glEnableVertexAttribArray 7)
  (gl.glVertexAttribIPointer 7 1 gl.GL_UNSIGNED_INT 4 0)
  (gl.glVertexAttribDivisor 7 1)
  (gl.glBindVertexArray 0)

  (fn resolve-batches [_self vector batches]
    (if (and batches (> (length batches) 0))
        batches
        (if (and vector (> (vector:length) 0))
            [{:model nil
              :firsts [0]
              :counts [(math.floor (/ (vector:length) instance-stride))]}]
            [])))

  (var uploaded-vectors {})
  (var uploaded-floats {})
  (var uploaded-clip-group-vectors {})
  (var uploaded-clip-group-counts {})
  (var uploaded-clip-vectors {})
  (var uploaded-clip-floats {})
  (var last-upload-seconds 0.0)
  (var last-draw-seconds 0.0)
  (var last-gpu-upload-seconds 0.0)
  (var last-gpu-draw-seconds 0.0)

  (fn rotate-query-slot [_self]
    (set active-query-slot (+ (% active-query-slot query-ring-size) 1)))

  (fn update-gpu-query-result [_self queries submitted slot setter]
    (when (and gpu-query-supported?
               (. submitted slot))
      (local query (. queries slot))
      (local available
        (gl.glGetQueryObjectuiv query gl.GL_QUERY_RESULT_AVAILABLE))
      (when (= available 1)
        (setter (* (gl.glGetQueryObjectui64v query gl.GL_QUERY_RESULT) 0.000000001)))))

  (fn upload-vector [_self vector stale-slot?]
    (local float-count (and vector (vector:length)))
    (when (and float-count (> float-count 0))
      (local slot active-stream-slot)
      (local uploaded-vector (. uploaded-vectors slot))
      (local uploaded-float-count (. uploaded-floats slot))
      (var dirty-from nil)
      (var dirty-to nil)
      (when (. vector :dirty-range)
        (local (from to) (vector:dirty-range))
        (set dirty-from from)
        (set dirty-to to))
      (local dirty? (and dirty-from dirty-to (> dirty-to dirty-from)))
      (local needs-full?
        (or (and stale-slot? dirty?)
            (not (= vector uploaded-vector))
            (not (= float-count uploaded-float-count))))
      (if needs-full?
          (do
            (gl.bufferDataFromVectorBuffer vector gl.GL_ARRAY_BUFFER gl.GL_STREAM_DRAW)
            (set (. uploaded-vectors slot) vector)
            (set (. uploaded-floats slot) float-count)
            (when (. vector :clear-dirty)
              (vector:clear-dirty)))
          (when dirty?
            (gl.bufferSubDataFromVectorBuffer
              vector
              gl.GL_ARRAY_BUFFER
              (* dirty-from 4)
              (* (- dirty-to dirty-from) 4))
            (when (. vector :clear-dirty)
              (vector:clear-dirty))))))

  (fn upload-clip-groups-index [_self clip-group-vector stale-slot?]
    (local element-count (and clip-group-vector (clip-group-vector:length)))
    (when (and element-count (> element-count 0))
      (local slot active-stream-slot)
      (local uploaded-clip-group-vector (. uploaded-clip-group-vectors slot))
      (local uploaded-clip-group-count (. uploaded-clip-group-counts slot))
      (var dirty-from nil)
      (var dirty-to nil)
      (when (. clip-group-vector :dirty-range)
        (local (from to) (clip-group-vector:dirty-range))
        (set dirty-from from)
        (set dirty-to to))
      (local dirty? (and dirty-from dirty-to (> dirty-to dirty-from)))
      (local needs-full?
        (or (and stale-slot? dirty?)
            (not (= clip-group-vector uploaded-clip-group-vector))
            (not (= element-count uploaded-clip-group-count))))
      (if needs-full?
          (do
            (gl.bufferDataUIntFromVectorBuffer clip-group-vector gl.GL_ARRAY_BUFFER gl.GL_STREAM_DRAW)
            (set (. uploaded-clip-group-vectors slot) clip-group-vector)
            (set (. uploaded-clip-group-counts slot) element-count)
            (when (. clip-group-vector :clear-dirty)
              (clip-group-vector:clear-dirty)))
          (when dirty?
            (gl.bufferSubDataUIntFromVectorBuffer
              clip-group-vector
              gl.GL_ARRAY_BUFFER
              dirty-from
              (- dirty-to dirty-from))
            (when (. clip-group-vector :clear-dirty)
              (clip-group-vector:clear-dirty))))))

  (fn upload-clip-groups [_self clip-vector stale-slot?]
    (if (and clip-vector (> (clip-vector:length) 0))
        (do
          (local slot active-stream-slot)
          (local float-count (clip-vector:length))
          (local uploaded-clip-vector (. uploaded-clip-vectors slot))
          (local uploaded-clip-float-count (. uploaded-clip-floats slot))
          (var dirty-from nil)
          (var dirty-to nil)
          (when (. clip-vector :dirty-range)
            (local (from to) (clip-vector:dirty-range))
            (set dirty-from from)
            (set dirty-to to))
          (local dirty? (and dirty-from dirty-to (> dirty-to dirty-from)))
          (local needs-full?
            (or (and stale-slot? dirty?)
                (not (= clip-vector uploaded-clip-vector))
                (not (= float-count uploaded-clip-float-count))))
          (if needs-full?
              (do
                (gl.bufferDataFromVectorBuffer clip-vector
                                               gl.GL_SHADER_STORAGE_BUFFER
                                               gl.GL_STREAM_DRAW)
                (set (. uploaded-clip-vectors slot) clip-vector)
                (set (. uploaded-clip-floats slot) float-count)
                (when (. clip-vector :clear-dirty)
                  (clip-vector:clear-dirty)))
              (when dirty?
                (gl.bufferSubDataFromVectorBuffer
                  clip-vector
                  gl.GL_SHADER_STORAGE_BUFFER
                  (* dirty-from 4)
                  (* (- dirty-to dirty-from) 4))
                (when (. clip-vector :clear-dirty)
                  (clip-vector:clear-dirty)))))
        (gl.glBufferData gl.GL_SHADER_STORAGE_BUFFER
                         [0 0 0 0
                          0 0 0 0
                          0 0 0 0
                          0 0 0 0]
                         gl.GL_STREAM_DRAW)))

  (var active-instance-first nil)

  (fn bind-instance-window [_self first]
    (when (not (= first active-instance-first))
      (set active-instance-first first)
      (local base-bytes (* first stride-bytes))
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER active-instance-buffer)
      (gl.glVertexAttribPointer 1 4 gl.GL_FLOAT gl.GL_FALSE stride-bytes base-bytes)
      (gl.glVertexAttribPointer 2 4 gl.GL_FLOAT gl.GL_FALSE stride-bytes (+ base-bytes (* 4 4)))
      (gl.glVertexAttribPointer 3 4 gl.GL_FLOAT gl.GL_FALSE stride-bytes (+ base-bytes (* 8 4)))
      (gl.glVertexAttribPointer 4 4 gl.GL_FLOAT gl.GL_FALSE stride-bytes (+ base-bytes (* 12 4)))
      (gl.glVertexAttribPointer 5 4 gl.GL_FLOAT gl.GL_FALSE stride-bytes (+ base-bytes (* 16 4)))
      (gl.glVertexAttribPointer 6 1 gl.GL_FLOAT gl.GL_FALSE stride-bytes (+ base-bytes (* 20 4)))
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER active-clip-group-buffer)
      (gl.glVertexAttribIPointer 7 1 gl.GL_UNSIGNED_INT 4 (* first 4))))

  (fn rotate-stream-slot [_self]
    (set active-stream-slot (+ (% active-stream-slot stream-ring-size) 1))
    (set active-instance-buffer (. instance-buffers active-stream-slot))
    (set active-clip-group-buffer (. clip-group-buffers active-stream-slot))
    (set active-clip-groups-ssbo (. clip-groups-ssbos active-stream-slot)))

  (fn draw-pass [self projection view vector batches]
    (local draw-start-local (os.clock))
    (when gpu-query-supported?
      (gl.glBeginQuery gl.GL_TIME_ELAPSED (. draw-gpu-queries active-query-slot)))
    (shader:use)
    (local lights (assert (and app app.lights)
                          "QuadRenderer requires app.lights; call AppBootstrap.init-lights"))
    (LightUtils.apply-lights shader lights)
    (shader:setMatrix4 "projection" projection)
    (shader:setMatrix4 "view" view)
    (shader:setVector3f "viewPos" (glm.vec3 0.0))
    (each [_ bucket (ipairs (self:resolve-batches vector batches))]
      (shader:setMatrix4 "model" (or bucket.model (glm.mat4 1)))
      (each [i first (ipairs bucket.firsts)]
        (local count (. bucket.counts i))
        (when (and count (> count 0))
          (self:bind-instance-window first)
          (gl.glDrawArraysInstanced gl.GL_TRIANGLE_STRIP 0 4 count))))
    (when gpu-query-supported?
      (gl.glEndQuery gl.GL_TIME_ELAPSED)
      (set (. draw-query-submitted active-query-slot) true))
    (- (os.clock) draw-start-local))

  (fn render [self vector projection view batches clip-vector clip-group-vector]
    (when (and vector (> (vector:length) 0))
      (set stream-frame-id (+ stream-frame-id 1))
      (self:rotate-query-slot)
      (self:update-gpu-query-result upload-gpu-queries
                                    upload-query-submitted
                                    active-query-slot
                                    (fn [value] (set last-gpu-upload-seconds value)))
      (self:update-gpu-query-result draw-gpu-queries
                                    draw-query-submitted
                                    active-query-slot
                                    (fn [value] (set last-gpu-draw-seconds value)))
      (self:rotate-stream-slot)
      (local upload-start (os.clock))
      (local last-frame (. slot-last-frame active-stream-slot))
      (local stale-slot?
        (or (= last-frame nil)
            (> (- stream-frame-id last-frame) 1)))
      (gl.glBindVertexArray vao)
      (when gpu-query-supported?
        (gl.glBeginQuery gl.GL_TIME_ELAPSED (. upload-gpu-queries active-query-slot)))
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER active-instance-buffer)
      (set active-instance-first nil)
      (self:upload-vector vector stale-slot?)
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER active-clip-group-buffer)
      (self:upload-clip-groups-index clip-group-vector stale-slot?)
      (gl.glBindBuffer gl.GL_SHADER_STORAGE_BUFFER active-clip-groups-ssbo)
      (self:upload-clip-groups clip-vector stale-slot?)
      (gl.glBindBufferBase gl.GL_SHADER_STORAGE_BUFFER 0 active-clip-groups-ssbo)
      (when gpu-query-supported?
        (gl.glEndQuery gl.GL_TIME_ELAPSED)
        (set (. upload-query-submitted active-query-slot) true))
      (set (. slot-last-frame active-stream-slot) stream-frame-id)
      (set last-upload-seconds (- (os.clock) upload-start))
      (set last-draw-seconds (self:draw-pass projection view vector batches))))

  {:shader shader
   :instance-stride instance-stride
   :resolve-batches resolve-batches
   :upload-vector upload-vector
   :upload-clip-groups-index upload-clip-groups-index
   :upload-clip-groups upload-clip-groups
   :draw-pass draw-pass
   :bind-instance-window bind-instance-window
   :rotate-query-slot rotate-query-slot
   :update-gpu-query-result update-gpu-query-result
   :rotate-stream-slot rotate-stream-slot
   :get-last-upload-seconds (fn [_self] last-upload-seconds)
   :get-last-draw-seconds (fn [_self] last-draw-seconds)
   :get-last-gpu-upload-seconds (fn [_self] last-gpu-upload-seconds)
   :get-last-gpu-draw-seconds (fn [_self] last-gpu-draw-seconds)
   :render render})

QuadRenderer
